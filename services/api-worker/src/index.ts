// services/api-worker/src/index.ts
import { groqChatCompletion, type GroqMessage } from "./groq";
import { buildMessages, type VoiceInput, type VoiceProfile } from "./prompt_builder";
import { computeVoiceMatchScore } from "./voice_score";
import { parseAndValidateLlmOutput } from "./llm_output";
import { validateEnvelopeContract } from "./contract_validate";
import { classifyInput } from "./safety_min";
import { precheckText } from "./risk/precheck";
import type { Suggestion } from "./types";
import { applyContactToVoice, parseContact, styleAppliedSummary, type ContactSnapshot } from "./contact_style";

type Status = "ok" | "blocked" | "error";
type ErrorCode = "NOT_FOUND" | "VALIDATION_ERROR" | "INTERNAL_ERROR" | "SAFETY_BLOCK" | "CONTRACT_ERROR";

type WorkerEnv = {
  GROQ_API_KEY?: string;
  GROQ_MODEL?: string;
  ENVIRONMENT?: string;
  BUILD_SHA?: string;
  PROMPT_VERSION?: string;
};

function nowMs(): number {
  return Date.now();
}

function clampSuggestionCount(hardModeApplied: boolean): number {
  // Contract allows 2..3. Hard Mode must be 2.
  return hardModeApplied ? 2 : 3;
}

function modelForEnv(env?: WorkerEnv): string {
  return env?.GROQ_MODEL?.trim() || "llama-3.1-70b-versatile";
}

function timeoutMsForEnv(env?: WorkerEnv): number {
  const e = (env?.ENVIRONMENT || "dev").toString();
  return e === "prod" ? 12_000 : 20_000;
}

function jsonResponse(body: any, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "content-type": "application/json",
      "cache-control": "no-store",
    },
  });
}

function ok(data: any, meta?: Record<string, any>) {
  return { status: "ok" as Status, data, error: null, meta: meta ?? {} };
}

function blocked(code: ErrorCode, message: string, details?: any, meta?: Record<string, any>) {
  return {
    status: "blocked" as Status,
    data: null,
    error: { code, message, details: details ?? null },
    meta: meta ?? {},
  };
}

function err(code: ErrorCode, message: string, details?: any, meta?: Record<string, any>) {
  return { status: "error" as Status, data: null, error: { code, message, details: details ?? null }, meta: meta ?? {} };
}

async function parseJsonBody(request: Request): Promise<any> {
  const ct = request.headers.get("content-type") || "";
  if (!ct.toLowerCase().includes("application/json")) {
    throw new Error("INVALID_CONTENT_TYPE");
  }
  return await request.json();
}

function sanitizeEnum<T extends string>(value: unknown, allowed: readonly T[]): T | undefined {
  if (typeof value !== "string") return undefined;
  const v = value.trim() as T;
  return (allowed as readonly string[]).includes(v) ? v : undefined;
}

function clamp01(n: unknown): number | undefined {
  if (typeof n !== "number" || Number.isNaN(n)) return undefined;
  return Math.max(0, Math.min(1, n));
}

function safeStrList(v: unknown, max = 50): string[] {
  if (!Array.isArray(v)) return [];
  const out: string[] = [];
  for (const x of v) {
    if (typeof x === "string") {
      const s = x.trim();
      if (s) out.push(s);
    }
    if (out.length >= max) break;
  }
  return out;
}

function parseVoice(body: any): VoiceInput | undefined {
  const v = body?.voice;
  if (!v || typeof v !== "object") return undefined;

  const enabled = v.enabled === true;

  const variant = typeof v.variant === "string" ? v.variant.trim() : undefined;

  const profRaw = v.profile;
  let profile: VoiceProfile | undefined = undefined;
  if (profRaw && typeof profRaw === "object") {
    profile = {
      warmth: clamp01(profRaw.warmth),
      directness: clamp01(profRaw.directness),
      brevity: clamp01(profRaw.brevity),
      formality: clamp01(profRaw.formality),
      emoji_rate: clamp01(profRaw.emoji_rate),
      do_not_use: safeStrList(profRaw.do_not_use),
    };
  }

  // Only return object if enabled or profile/variant is present (still additive)
  if (!enabled && !variant && !profile) return undefined;
  return { enabled, variant, profile };
}

const ALLOWED_FLIRT_MODE = ["off", "subtle", "playful", "direct"] as const;
const ALLOWED_DATING_STAGE = ["first_msg", "early_chat", "planning", "reconnect", "post_date"] as const;
const ALLOWED_DATING_VIBE = ["fun", "classy", "direct", "shy", "friendly"] as const;

function promptVersion(env?: WorkerEnv): string {
  return env?.PROMPT_VERSION?.trim() || "3.2.0";
}

function buildBaseMeta(args: {
  env?: WorkerEnv;
  requestPath: string;
  mode: "IMPROVE" | "REPLY" | "HEALTH" | "UNKNOWN";
  hardMode?: boolean;
  outputVariant?: string;
  requestLatencyMs: number;
  safetyBlocked?: boolean;
}): Record<string, any> {
  return {
    contract_version: "1.0.0",
    request_path: args.requestPath,
    mode: args.mode,
    hard_mode: args.hardMode ?? false,
    output_variant: args.outputVariant ?? "AUTO",
    prompt_version: promptVersion(args.env),
    env: (args.env?.ENVIRONMENT || "dev").toString(),
    runtime: "worker",
    build: args.env?.BUILD_SHA?.trim() || null,
    request_latency_ms: args.requestLatencyMs,
    safety_blocked: args.safetyBlocked ?? false,
  };
}

function normalizeSuggestions(suggestions: any[]): Suggestion[] {
  return suggestions.map((s, i) => ({
    label: typeof s?.label === "string" ? s.label : `Option ${i + 1}`,
    text: typeof s?.text === "string" ? s.text : "",
    why_it_works: typeof s?.why_it_works === "string" ? s.why_it_works : "Clear, respectful, and low pressure.",
    emotion_preview: Array.isArray(s?.emotion_preview) ? s.emotion_preview.map(String).slice(0, 3) : ["calm"],
  }));
}

function ensureNonEmptyText(suggestions: Suggestion[]) {
  if (suggestions.some((x) => !x.text.trim())) {
    throw new Error("LLM_EMPTY_TEXT");
  }
}

function addStrictJsonReminder(base: GroqMessage[], count: number, hardModeApplied: boolean): GroqMessage[] {
  const reminderLines = [
    "IMPORTANT: Your previous output did NOT match the required JSON shape.",
    "Return ONLY one valid JSON object, nothing else.",
    `It MUST include "suggestions" with exactly ${count} items.`,
    "Root keys allowed: suggestions, hard_mode_applied, safety_line, best_question.",
    'Each suggestion must have ONLY keys: label, text, why_it_works, emotion_preview.',
    'emotion_preview MUST be an array of 1-3 non-empty strings.',
  ];

  if (hardModeApplied) {
    reminderLines.push('Hard mode is ON: "hard_mode_applied" MUST be true.');
    reminderLines.push('"safety_line" MUST be a non-empty string.');
    reminderLines.push('"best_question" MUST be a non-empty string and end with a "?".');
  }

  reminderLines.push("Do NOT include markdown or commentary. Do NOT wrap in code fences.");

  const reminder: GroqMessage = {
    role: "system",
    content: reminderLines.join("\n"),
  };
  return [reminder, ...base];
}

async function generateSuggestionsWithGroq(args: {
  env?: WorkerEnv;
  mode: "IMPROVE" | "REPLY";
  variant?: string;
  hardModeApplied: boolean;
  inputText: string;

  // Phase 3.5 (Dating Add-on) — additive/optional
  flirtMode?: "off" | "subtle" | "playful" | "direct";
  datingStage?: "first_msg" | "early_chat" | "planning" | "reconnect" | "post_date";
  datingVibe?: "fun" | "classy" | "direct" | "shy" | "friendly";

  // Phase 3.5.5 — soft safety hints (allow + redirect)
  safetyHints?: string[];

  // Phase 5 — Build My Voice (optional/additive)
  voice?: VoiceInput;

  // Phase 6 — Contact snapshot (optional/additive)
  contact?: ContactSnapshot;
}): Promise<{
  suggestions: Suggestion[];
  safety_line?: string;
  best_question?: string;
  usage: unknown;
  parse_ok: boolean;
  schema_ok: boolean;
  extracted_from_raw: boolean;
  repair_attempted: boolean;
}> {
  const apiKey = args.env?.GROQ_API_KEY?.trim();
  if (!apiKey) throw new Error("MISSING_GROQ_API_KEY");

  const count = clampSuggestionCount(args.hardModeApplied);

  // Phase 4 rule: when hard mode is applied, suppress flirt ladder
  const flirtMode = args.hardModeApplied ? "off" : args.flirtMode;

  const baseMessages = buildMessages({
    mode: args.mode,
    inputText: args.inputText,
    suggestionCount: count,
    outputVariant: args.variant,
    hardModeApplied: args.hardModeApplied,
    flirtMode,
    datingStage: args.datingStage,
    datingVibe: args.datingVibe,
    safetyHints: args.safetyHints,
    voice: args.voice,
    contact: args.contact,
  });

  const t0 = nowMs();
  const first = await groqChatCompletion({
    apiKey,
    model: modelForEnv(args.env),
    messages: baseMessages,
    temperature: 0.4,
    maxTokens: 700,
    timeoutMs: timeoutMsForEnv(args.env),
    responseFormat: { type: "json_object" },
  });
  const latency1 = nowMs() - t0;

  const r1 = parseAndValidateLlmOutput(first.content, count, { requireHardModeFields: args.hardModeApplied });
  if (r1.ok) {
    const normalized = normalizeSuggestions(r1.parsed.suggestions);
    ensureNonEmptyText(normalized);
    return {
      suggestions: normalized,
      safety_line: r1.parsed.safety_line,
      best_question: r1.parsed.best_question,
      usage: { ...(first.usage as any), latency_ms: latency1 },
      parse_ok: true,
      schema_ok: true,
      extracted_from_raw: r1.extracted_from_raw,
      repair_attempted: false,
    };
  }

  const t1 = nowMs();
  const second = await groqChatCompletion({
    apiKey,
    model: modelForEnv(args.env),
    messages: addStrictJsonReminder(baseMessages, count, args.hardModeApplied),
    temperature: 0.2,
    maxTokens: 700,
    timeoutMs: timeoutMsForEnv(args.env),
    responseFormat: { type: "json_object" },
  });
  const latency2 = nowMs() - t1;

  const r2 = parseAndValidateLlmOutput(second.content, count, { requireHardModeFields: args.hardModeApplied });
  if (r2.ok) {
    const normalized = normalizeSuggestions(r2.parsed.suggestions);
    ensureNonEmptyText(normalized);
    return {
      suggestions: normalized,
      safety_line: r2.parsed.safety_line,
      best_question: r2.parsed.best_question,
      usage: { ...(second.usage as any), latency_ms: latency2 },
      parse_ok: true,
      schema_ok: true,
      extracted_from_raw: r2.extracted_from_raw,
      repair_attempted: true,
    };
  }

  // Third attempt (hard mode only): ultra-strict repair
  if (args.hardModeApplied) {
    const t2 = nowMs();
    const third = await groqChatCompletion({
      apiKey,
      model: modelForEnv(args.env),
      messages: addStrictJsonReminder(addStrictJsonReminder(baseMessages, count, true), count, true),
      temperature: 0.0,
      maxTokens: 500,
      timeoutMs: timeoutMsForEnv(args.env),
      responseFormat: { type: "json_object" },
    });
    const latency3 = nowMs() - t2;

    const r3 = parseAndValidateLlmOutput(third.content, count, { requireHardModeFields: true });
    if (r3.ok) {
      const normalized = normalizeSuggestions(r3.parsed.suggestions);
      ensureNonEmptyText(normalized);
      return {
        suggestions: normalized,
        safety_line: r3.parsed.safety_line,
        best_question: r3.parsed.best_question,
        usage: { ...(third.usage as any), latency_ms: latency3 },
        parse_ok: true,
        schema_ok: true,
        extracted_from_raw: r3.extracted_from_raw,
        repair_attempted: true,
      };
    }
  }

  throw new Error(
    `LLM_OUTPUT_INVALID: ${r2.error} extracted=${r2.extracted_from_raw} preview=${(r2.raw_preview ?? "").toString()}`
  );
}

function appliedContactPayload(contact?: ContactSnapshot): any | undefined {
  if (!contact) return undefined;
  return {
    id: contact.id,
    display_name: contact.display_name,
    relation_tag: contact.relation_tag,
  };
}

export default {
  async fetch(request: Request, env?: WorkerEnv): Promise<Response> {
    const safeEnv = env ?? {};
    const tReq0 = nowMs();

    const url = new URL(request.url);

    // health
    if (request.method === "GET" && url.pathname === "/health") {
      const baseMeta = buildBaseMeta({
        env: safeEnv,
        requestPath: url.pathname,
        mode: "HEALTH",
        requestLatencyMs: nowMs() - tReq0,
      });
      return jsonResponse(ok({ service: "api-worker", ok: true }, baseMeta), 200);
    }

    // contract validation endpoint (dev-only convenience)
    if (request.method === "POST" && url.pathname === "/v1/contracts/validate") {
      try {
        const body = await parseJsonBody(request);
        const result = await validateEnvelopeContract(body);
        const baseMeta = buildBaseMeta({
          env: safeEnv,
          requestPath: url.pathname,
          mode: "UNKNOWN",
          requestLatencyMs: nowMs() - tReq0,
        });

        const errors = result.ok ? [] : result.errors;
        return jsonResponse(ok({ valid: result.ok, errors }, baseMeta), 200);
      } catch (e: any) {
        const baseMeta = buildBaseMeta({
          env: safeEnv,
          requestPath: url.pathname,
          mode: "UNKNOWN",
          requestLatencyMs: nowMs() - tReq0,
        });
        return jsonResponse(err("VALIDATION_ERROR", "Invalid JSON body", String(e?.message ?? e), baseMeta), 400);
      }
    }

    // IMPROVE
    if (request.method === "POST" && url.pathname === "/v1/improve") {
      let body: any;
      try {
        body = await parseJsonBody(request);
      } catch (e) {
        const baseMeta = buildBaseMeta({
          env: safeEnv,
          requestPath: url.pathname,
          mode: "IMPROVE",
          requestLatencyMs: nowMs() - tReq0,
        });
        return jsonResponse(err("VALIDATION_ERROR", "Invalid JSON body", null, baseMeta), 400);
      }

      const draftText = body?.input?.draft_text;
      if (typeof draftText !== "string" || draftText.trim().length === 0) {
        const baseMeta = buildBaseMeta({
          env: safeEnv,
          requestPath: url.pathname,
          mode: "IMPROVE",
          requestLatencyMs: nowMs() - tReq0,
        });
        return jsonResponse(err("VALIDATION_ERROR", "input.draft_text is required", { path: "input.draft_text" }, baseMeta), 400);
      }

      const requestedHardMode = Boolean(body?.input?.hard_mode);
      const variant = body?.input?.output_variant as string | undefined;

      // Phase 5: voice (optional/additive)
      const voice = parseVoice(body);

      // Phase 6: contact snapshot (optional/additive)
      const contact = parseContact(body);
      const { effectiveVoice } = applyContactToVoice({ voice, contact });

      // Phase 3.5: smart defaults
      const flirtModeRaw = sanitizeEnum(body?.input?.flirt_mode, ALLOWED_FLIRT_MODE) ?? "off";
      const datingStage = sanitizeEnum(body?.input?.dating_stage, ALLOWED_DATING_STAGE);
      const datingVibe = sanitizeEnum(body?.input?.dating_vibe, ALLOWED_DATING_VIBE);

      // Phase 4: precheck (block severe escalation before LLM)
      const pre = precheckText(draftText);
      const risk = pre.risk;
      const hardModeApplied = requestedHardMode || risk.hard_mode_recommended;

      if (pre.action === "block") {
        const baseMeta = buildBaseMeta({
          env: safeEnv,
          requestPath: url.pathname,
          mode: "IMPROVE",
          hardMode: true,
          outputVariant: variant,
          requestLatencyMs: nowMs() - tReq0,
          safetyBlocked: true,
        });

        return jsonResponse(blocked("SAFETY_BLOCK", pre.message, pre.details, { ...baseMeta, risk }), 200);
      }

      const safety = classifyInput(draftText);
      if (safety.action === "block") {
        const baseMeta = buildBaseMeta({
          env: safeEnv,
          requestPath: url.pathname,
          mode: "IMPROVE",
          hardMode: hardModeApplied,
          outputVariant: variant,
          requestLatencyMs: nowMs() - tReq0,
          safetyBlocked: true,
        });
        return jsonResponse(
          blocked(
            "SAFETY_BLOCK",
            "Input was blocked by minimal safety gate.",
            { reasons: safety.reasons },
            { ...baseMeta, safety: safety.reasons, risk }
          ),
          200
        );
      }

      // Phase 3.5.5: soft redirects (only pass *_redirect hints into prompt)
      const safetyHints = (safety.reasons ?? []).filter((r) => r.endsWith("_redirect"));

      try {
        const out = await generateSuggestionsWithGroq({
          env: safeEnv,
          mode: "IMPROVE",
          variant,
          hardModeApplied,
          inputText: draftText,
          flirtMode: flirtModeRaw,
          datingStage,
          datingVibe,
          safetyHints,
          voice: effectiveVoice ?? voice,
          contact,
        });

        // Voice score uses EFFECTIVE voice (contact offsets + forbidden merge) when voice enabled
        const voiceScore = computeVoiceMatchScore(effectiveVoice ?? voice, out.suggestions);

        const baseMeta = buildBaseMeta({
          env: safeEnv,
          requestPath: url.pathname,
          mode: "IMPROVE",
          hardMode: hardModeApplied,
          outputVariant: variant,
          requestLatencyMs: nowMs() - tReq0,
        });

        const data: any = {
          mode: "IMPROVE",
          voice_match_score: voiceScore,
          risk: { level: risk.level, score: risk.score, reasons: risk.reasons },
          suggestions: out.suggestions,
        };

        const applied = appliedContactPayload(contact);
        const summary = styleAppliedSummary(contact);
        if (applied) data.applied_contact = applied;
        if (summary) data.style_applied_summary = summary;

        if (hardModeApplied) {
          data.hard_mode_applied = true;
          data.safety_line = String(out.safety_line ?? "").trim() || "Let’s keep this respectful and slow things down.";
          data.best_question = String(out.best_question ?? "").trim() || "What would help you feel heard right now?";
        }

        return jsonResponse(
          ok(data, {
            ...baseMeta,
            model: modelForEnv(safeEnv),
            usage: out.usage,
            parse_ok: out.parse_ok,
            schema_ok: out.schema_ok,
            extracted_from_raw: out.extracted_from_raw,
            repair_attempted: out.repair_attempted,
            hard_mode_requested: requestedHardMode,
          }),
          200
        );
      } catch (e: any) {
        const baseMeta = buildBaseMeta({
          env: safeEnv,
          requestPath: url.pathname,
          mode: "IMPROVE",
          hardMode: hardModeApplied,
          outputVariant: variant,
          requestLatencyMs: nowMs() - tReq0,
        });
        return jsonResponse(err("INTERNAL_ERROR", "Failed to generate suggestions", String(e?.message ?? e), baseMeta), 500);
      }
    }

    // REPLY
    if (request.method === "POST" && url.pathname === "/v1/reply") {
      let body: any;
      try {
        body = await parseJsonBody(request);
      } catch (e) {
        const baseMeta = buildBaseMeta({
          env: safeEnv,
          requestPath: url.pathname,
          mode: "REPLY",
          requestLatencyMs: nowMs() - tReq0,
        });
        return jsonResponse(err("VALIDATION_ERROR", "Invalid JSON body", null, baseMeta), 400);
      }

      const receivedText = body?.input?.received_text;
      if (typeof receivedText !== "string" || receivedText.trim().length === 0) {
        const baseMeta = buildBaseMeta({
          env: safeEnv,
          requestPath: url.pathname,
          mode: "REPLY",
          requestLatencyMs: nowMs() - tReq0,
        });
        return jsonResponse(
          err("VALIDATION_ERROR", "input.received_text is required", { path: "input.received_text" }, baseMeta),
          400
        );
      }

      const requestedHardMode = Boolean(body?.input?.hard_mode);
      const variant = body?.input?.output_variant as string | undefined;

      // Phase 5: voice (optional/additive)
      const voice = parseVoice(body);

      // Phase 6: contact snapshot (optional/additive)
      const contact = parseContact(body);
      const { effectiveVoice } = applyContactToVoice({ voice, contact });

      // Phase 3.5: smart defaults
      const flirtModeRaw = sanitizeEnum(body?.input?.flirt_mode, ALLOWED_FLIRT_MODE) ?? "off";
      const datingStage = sanitizeEnum(body?.input?.dating_stage, ALLOWED_DATING_STAGE);
      const datingVibe = sanitizeEnum(body?.input?.dating_vibe, ALLOWED_DATING_VIBE);

      // Phase 4: precheck (block severe escalation before LLM)
      const pre = precheckText(receivedText);
      const risk = pre.risk;
      const hardModeApplied = requestedHardMode || risk.hard_mode_recommended;

      if (pre.action === "block") {
        const baseMeta = buildBaseMeta({
          env: safeEnv,
          requestPath: url.pathname,
          mode: "REPLY",
          hardMode: true,
          outputVariant: variant,
          requestLatencyMs: nowMs() - tReq0,
          safetyBlocked: true,
        });

        return jsonResponse(blocked("SAFETY_BLOCK", pre.message, pre.details, { ...baseMeta, risk }), 200);
      }

      const safety = classifyInput(receivedText);
      if (safety.action === "block") {
        const baseMeta = buildBaseMeta({
          env: safeEnv,
          requestPath: url.pathname,
          mode: "REPLY",
          hardMode: hardModeApplied,
          outputVariant: variant,
          requestLatencyMs: nowMs() - tReq0,
          safetyBlocked: true,
        });
        return jsonResponse(
          blocked(
            "SAFETY_BLOCK",
            "Input was blocked by minimal safety gate.",
            { reasons: safety.reasons },
            { ...baseMeta, safety: safety.reasons, risk }
          ),
          200
        );
      }

      // Phase 3.5.5: soft redirects (only pass *_redirect hints into prompt)
      const safetyHints = (safety.reasons ?? []).filter((r) => r.endsWith("_redirect"));

      try {
        const out = await generateSuggestionsWithGroq({
          env: safeEnv,
          mode: "REPLY",
          variant,
          hardModeApplied,
          inputText: receivedText,
          flirtMode: flirtModeRaw,
          datingStage,
          datingVibe,
          safetyHints,
          voice: effectiveVoice ?? voice,
          contact,
        });

        const voiceScore = computeVoiceMatchScore(effectiveVoice ?? voice, out.suggestions);

        const baseMeta = buildBaseMeta({
          env: safeEnv,
          requestPath: url.pathname,
          mode: "REPLY",
          hardMode: hardModeApplied,
          outputVariant: variant,
          requestLatencyMs: nowMs() - tReq0,
        });

        const data: any = {
          mode: "REPLY",
          voice_match_score: voiceScore,
          risk: { level: risk.level, score: risk.score, reasons: risk.reasons },
          suggestions: out.suggestions,
        };

        const applied = appliedContactPayload(contact);
        const summary = styleAppliedSummary(contact);
        if (applied) data.applied_contact = applied;
        if (summary) data.style_applied_summary = summary;

        if (hardModeApplied) {
          data.hard_mode_applied = true;
          data.safety_line = String(out.safety_line ?? "").trim() || "Let’s keep this respectful and slow things down.";
          data.best_question = String(out.best_question ?? "").trim() || "What would help you feel heard right now?";
        }

        return jsonResponse(
          ok(data, {
            ...baseMeta,
            model: modelForEnv(safeEnv),
            usage: out.usage,
            parse_ok: out.parse_ok,
            schema_ok: out.schema_ok,
            extracted_from_raw: out.extracted_from_raw,
            repair_attempted: out.repair_attempted,
            hard_mode_requested: requestedHardMode,
          }),
          200
        );
      } catch (e: any) {
        const baseMeta = buildBaseMeta({
          env: safeEnv,
          requestPath: url.pathname,
          mode: "REPLY",
          hardMode: hardModeApplied,
          outputVariant: variant,
          requestLatencyMs: nowMs() - tReq0,
        });
        return jsonResponse(err("INTERNAL_ERROR", "Failed to generate suggestions", String(e?.message ?? e), baseMeta), 500);
      }
    }

    // unknown route
    const baseMeta = buildBaseMeta({
      env: safeEnv,
      requestPath: url.pathname,
      mode: "UNKNOWN",
      requestLatencyMs: nowMs() - tReq0,
    });
    return jsonResponse(err("NOT_FOUND", "Route not found", { path: url.pathname }, baseMeta), 404);
  },
};