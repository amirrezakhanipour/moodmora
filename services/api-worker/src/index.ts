// services/api-worker/src/index.ts
import { groqChatCompletion, type GroqMessage } from "./groq";
import { buildMessages } from "./prompt_builder";
import { parseAndValidateLlmOutput } from "./llm_output";
import { validateEnvelopeContract } from "./contract_validate";
import { classifyInput } from "./safety_min";
import type { Suggestion } from "./types";

type Status = "ok" | "blocked" | "error";
type ErrorCode = "NOT_FOUND" | "VALIDATION_ERROR" | "INTERNAL_ERROR" | "SAFETY_BLOCK" | "CONTRACT_ERROR";

type WorkerEnv = {
  GROQ_API_KEY?: string;
  GROQ_MODEL?: string;
  ENVIRONMENT?: string;
  BUILD_SHA?: string;
  PROMPT_VERSION?: string;

  // Phase 3.6: feature flags
  FEATURE_COACH?: string;
};

function nowMs(): number {
  return Date.now();
}

function clampSuggestionCount(hardMode: boolean): number {
  return hardMode ? 5 : 3;
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

const ALLOWED_FLIRT_MODE = ["off", "subtle", "playful", "direct"] as const;
const ALLOWED_DATING_STAGE = ["first_msg", "early_chat", "planning", "reconnect", "post_date"] as const;
const ALLOWED_DATING_VIBE = ["fun", "classy", "direct", "shy", "friendly"] as const;

function promptVersion(env?: WorkerEnv): string {
  return env?.PROMPT_VERSION?.trim() || "3.2.0";
}

function isEnabled(v: unknown): boolean {
  if (typeof v !== "string") return false;
  const x = v.trim().toLowerCase();
  return x === "1" || x === "true" || x === "yes" || x === "on" || x === "enabled";
}

function buildBaseMeta(args: {
  env?: WorkerEnv;
  requestPath: string;
  mode: "IMPROVE" | "REPLY" | "COACH" | "HEALTH" | "UNKNOWN";
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

function addStrictJsonReminder(base: GroqMessage[], count: number): GroqMessage[] {
  const reminder: GroqMessage = {
    role: "system",
    content: [
      "IMPORTANT: Your previous output did NOT match the required JSON shape.",
      "Return ONLY one valid JSON object, nothing else.",
      `It MUST include "suggestions" with exactly ${count} items.`,
      'Do NOT include markdown or commentary. Do NOT wrap in code fences.',
    ].join("\n"),
  };
  return [reminder, ...base];
}

function addStrictJsonReminderCoach(base: GroqMessage[]): GroqMessage[] {
  const reminder: GroqMessage = {
    role: "system",
    content: [
      "IMPORTANT: Your previous output did NOT match the required JSON shape.",
      "Return ONLY one valid JSON object, nothing else.",
      'It MUST include: "assistant_message", "action_steps" (exactly 3 strings), and "best_next_message".',
      'Do NOT include markdown or commentary. Do NOT wrap in code fences.',
    ].join("\n"),
  };
  return [reminder, ...base];
}

async function generateSuggestionsWithGroq(args: {
  env?: WorkerEnv;
  mode: "IMPROVE" | "REPLY";
  variant?: string;
  hardMode: boolean;
  inputText: string;

  // Phase 3.5 (Dating Add-on) — additive/optional
  flirtMode?: "off" | "subtle" | "playful" | "direct";
  datingStage?: "first_msg" | "early_chat" | "planning" | "reconnect" | "post_date";
  datingVibe?: "fun" | "classy" | "direct" | "shy" | "friendly";

  // Phase 3.5.5 — soft safety hints (allow + redirect)
  safetyHints?: string[];

  // Phase 3.6 — screenshot context
  contextExtractedText?: string;
}): Promise<{
  suggestions: Suggestion[];
  usage: unknown;
  parse_ok: boolean;
  schema_ok: boolean;
  extracted_from_raw: boolean;
  repair_attempted: boolean;
  context_summary?: string[];
}> {
  const apiKey = args.env?.GROQ_API_KEY?.trim();
  if (!apiKey) throw new Error("MISSING_GROQ_API_KEY");

  const count = clampSuggestionCount(args.hardMode);

  const inputTextWithContext =
    args.contextExtractedText && args.contextExtractedText.trim()
      ? [
          args.inputText,
          "",
          "=== CONTEXT (extracted from screenshots) ===",
          args.contextExtractedText.trim(),
          "=== END CONTEXT ===",
        ].join("\n")
      : args.inputText;

  const baseMessages = buildMessages({
    mode: args.mode,
    inputText: inputTextWithContext,
    suggestionCount: count,
    outputVariant: args.variant,
    flirtMode: args.flirtMode,
    datingStage: args.datingStage,
    datingVibe: args.datingVibe,
    safetyHints: args.safetyHints,
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

  const r1 = parseAndValidateLlmOutput(first.content, count);
  if (r1.ok) {
    const normalized = normalizeSuggestions(r1.parsed.suggestions);
    ensureNonEmptyText(normalized);
    return {
      suggestions: normalized,
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
    messages: addStrictJsonReminder(baseMessages, count),
    temperature: 0.2,
    maxTokens: 700,
    timeoutMs: timeoutMsForEnv(args.env),
    responseFormat: { type: "json_object" },
  });
  const latency2 = nowMs() - t1;

  const r2 = parseAndValidateLlmOutput(second.content, count);
  if (!r2.ok) {
    throw new Error(
      `LLM_OUTPUT_INVALID: ${r2.error} extracted=${r2.extracted_from_raw} preview=${(r2.raw_preview ?? "").toString()}`
    );
  }

  const normalized = normalizeSuggestions(r2.parsed.suggestions);
  ensureNonEmptyText(normalized);
  return {
    suggestions: normalized,
    usage: { ...(second.usage as any), latency_ms: latency2 },
    parse_ok: true,
    schema_ok: true,
    extracted_from_raw: r2.extracted_from_raw,
    repair_attempted: true,
  };
}

type CoachReq = {
  goal_text?: string;
  situation_text?: string;
  user_message: string;
  chat_history?: Array<{ role: "user" | "assistant"; content: string }>;
  context_extracted_text?: string;
  output_variant?: "AUTO" | "FA_SCRIPT" | "FINGLISH" | "EN";
  hard_mode_requested?: boolean;
};

type CoachRisk = { level: "low" | "medium" | "high"; score: number; reasons: string[] };
type CoachUiHints = { collapse_context_card?: boolean; show_pinned_summary?: boolean };

type CoachData = {
  assistant_message: string;
  action_steps: [string, string, string];
  best_next_message: string;
  best_question?: string;
  safety_line?: string;
  risk?: CoachRisk;
  ui_hints?: CoachUiHints;
};

function safeString(x: unknown): string | undefined {
  return typeof x === "string" && x.trim().length ? x : undefined;
}

function tryExtractJsonObject(text: string): string {
  const t = text.trim();
  if (t.startsWith("{") && t.endsWith("}")) return t;

  const m = t.match(/\{[\s\S]*\}/);
  return m ? m[0] : t;
}

function parseCoachData(raw: string): CoachData {
  const extracted = tryExtractJsonObject(raw);
  let obj: any;
  try {
    obj = JSON.parse(extracted);
  } catch {
    throw new Error("COACH_JSON_PARSE_FAILED");
  }

  const assistant_message = safeString(obj?.assistant_message);
  const best_next_message = safeString(obj?.best_next_message);

  const steps = Array.isArray(obj?.action_steps) ? obj.action_steps : null;

  // ✅ FIX: filter param typed to avoid TS7006 (implicit any)
  const action_steps: string[] = steps
    ? steps
        .map((s: any) => (typeof s === "string" ? s : ""))
        .filter((s: string) => s.trim())
    : [];

  if (!assistant_message || !best_next_message) throw new Error("COACH_MISSING_REQUIRED_FIELDS");
  if (action_steps.length !== 3) throw new Error("COACH_ACTION_STEPS_INVALID");

  const data: CoachData = {
    assistant_message,
    best_next_message,
    action_steps: [action_steps[0], action_steps[1], action_steps[2]],
  };

  const bq = safeString(obj?.best_question);
  const sl = safeString(obj?.safety_line);
  if (bq) data.best_question = bq;
  if (sl) data.safety_line = sl;

  if (obj?.risk && typeof obj.risk === "object") {
    const level = safeString(obj.risk.level) as any;
    const score = typeof obj.risk.score === "number" ? obj.risk.score : undefined;
    const reasons = Array.isArray(obj.risk.reasons) ? obj.risk.reasons.map(String).slice(0, 6) : undefined;
    if ((level === "low" || level === "medium" || level === "high") && typeof score === "number" && reasons) {
      data.risk = { level, score: Math.max(0, Math.min(1, score)), reasons };
    }
  }

  if (obj?.ui_hints && typeof obj.ui_hints === "object") {
    const h: CoachUiHints = {};
    if (typeof obj.ui_hints.collapse_context_card === "boolean") h.collapse_context_card = obj.ui_hints.collapse_context_card;
    if (typeof obj.ui_hints.show_pinned_summary === "boolean") h.show_pinned_summary = obj.ui_hints.show_pinned_summary;
    if (Object.keys(h).length) data.ui_hints = h;
  }

  return data;
}

function buildCoachMessages(args: { req: CoachReq }): GroqMessage[] {
  const v = args.req.output_variant ?? "AUTO";
  const langHint =
    v === "EN"
      ? "Write in English."
      : v === "FA_SCRIPT"
      ? "Write in Persian script."
      : v === "FINGLISH"
      ? "Write in Finglish (Persian written with Latin letters)."
      : "Choose the best language based on the user's message; default to Finglish if unclear.";

  const system = [
    "You are MoodMora Coach (Moshaver).",
    "You help the user craft the best next message and a small plan.",
    "Be concise, actionable, and emotionally intelligent. Avoid moralizing.",
    "",
    "Return ONLY one JSON object with this exact shape:",
    "{",
    '  "assistant_message": string,',
    '  "action_steps": [string,string,string],',
    '  "best_next_message": string,',
    '  "best_question"?: string,',
    '  "safety_line"?: string,',
    '  "risk"?: {"level":"low"|"medium"|"high","score":0..1,"reasons": string[]},',
    '  "ui_hints"?: {"collapse_context_card"?: boolean, "show_pinned_summary"?: boolean}',
    "}",
    "",
    'Rules: action_steps MUST be exactly 3 short items. No markdown. No code fences.',
    langHint,
  ].join("\n");

  const parts: string[] = [];

  const goal = safeString(args.req.goal_text);
  const sit = safeString(args.req.situation_text);
  const ctx = safeString(args.req.context_extracted_text);

  if (goal) parts.push(`GOAL:\n${goal}`);
  if (sit) parts.push(`SITUATION:\n${sit}`);

  if (Array.isArray(args.req.chat_history) && args.req.chat_history.length) {
    const last = args.req.chat_history.slice(-8);
    const transcript = last.map((m) => `${m.role.toUpperCase()}: ${m.content}`).join("\n");
    parts.push(`CHAT HISTORY (recent):\n${transcript}`);
  }

  if (ctx) parts.push(["CONTEXT (extracted from screenshots):", ctx].join("\n"));

  parts.push(`USER MESSAGE:\n${args.req.user_message}`);

  const user = parts.join("\n\n");

  return [
    { role: "system", content: system },
    { role: "user", content: user },
  ];
}

async function generateCoachWithGroq(args: {
  env?: WorkerEnv;
  req: CoachReq;
}): Promise<{ data: CoachData; usage: unknown; repair_attempted: boolean }> {
  const apiKey = args.env?.GROQ_API_KEY?.trim();
  if (!apiKey) throw new Error("MISSING_GROQ_API_KEY");

  const baseMessages = buildCoachMessages({ req: args.req });

  const t0 = nowMs();
  const first = await groqChatCompletion({
    apiKey,
    model: modelForEnv(args.env),
    messages: baseMessages,
    temperature: 0.35,
    maxTokens: 900,
    timeoutMs: timeoutMsForEnv(args.env),
    responseFormat: { type: "json_object" },
  });
  const latency1 = nowMs() - t0;

  try {
    const parsed = parseCoachData(first.content);
    return { data: parsed, usage: { ...(first.usage as any), latency_ms: latency1 }, repair_attempted: false };
  } catch {
    // one repair attempt
  }

  const t1 = nowMs();
  const second = await groqChatCompletion({
    apiKey,
    model: modelForEnv(args.env),
    messages: addStrictJsonReminderCoach(baseMessages),
    temperature: 0.2,
    maxTokens: 900,
    timeoutMs: timeoutMsForEnv(args.env),
    responseFormat: { type: "json_object" },
  });
  const latency2 = nowMs() - t1;

  const parsed2 = parseCoachData(second.content);
  return { data: parsed2, usage: { ...(second.usage as any), latency_ms: latency2 }, repair_attempted: true };
}

export default {
  async fetch(request: Request, env?: WorkerEnv): Promise<Response> {
    const safeEnv = env ?? {};
    const tReq0 = nowMs();

    const url = new URL(request.url);

    if (request.method === "GET" && url.pathname === "/health") {
      const baseMeta = buildBaseMeta({
        env: safeEnv,
        requestPath: url.pathname,
        mode: "HEALTH",
        requestLatencyMs: nowMs() - tReq0,
      });
      return jsonResponse(ok({ service: "api-worker", ok: true }, baseMeta), 200);
    }

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

    if (request.method === "POST" && url.pathname === "/v1/coach/message") {
      if (!isEnabled(safeEnv.FEATURE_COACH)) {
        const baseMeta = buildBaseMeta({
          env: safeEnv,
          requestPath: url.pathname,
          mode: "COACH",
          requestLatencyMs: nowMs() - tReq0,
        });
        return jsonResponse(err("NOT_FOUND", "Route not found", { path: url.pathname }, baseMeta), 404);
      }

      let body: any;
      try {
        body = await parseJsonBody(request);
      } catch {
        const baseMeta = buildBaseMeta({
          env: safeEnv,
          requestPath: url.pathname,
          mode: "COACH",
          requestLatencyMs: nowMs() - tReq0,
        });
        return jsonResponse(err("VALIDATION_ERROR", "Invalid JSON body", null, baseMeta), 400);
      }

      const userMsg = body?.user_message;
      if (typeof userMsg !== "string" || userMsg.trim().length === 0) {
        const baseMeta = buildBaseMeta({
          env: safeEnv,
          requestPath: url.pathname,
          mode: "COACH",
          requestLatencyMs: nowMs() - tReq0,
        });
        return jsonResponse(err("VALIDATION_ERROR", "user_message is required", { path: "user_message" }, baseMeta), 400);
      }

      const req: CoachReq = {
        goal_text: typeof body?.goal_text === "string" ? body.goal_text : undefined,
        situation_text: typeof body?.situation_text === "string" ? body.situation_text : undefined,
        user_message: userMsg,
        chat_history: Array.isArray(body?.chat_history)
          ? body.chat_history
              .slice(-16)
              .map((m: any) => ({
                role: m?.role === "assistant" ? "assistant" : "user",
                content: typeof m?.content === "string" ? m.content : "",
              }))
              .filter((m: any) => m.content.trim().length > 0)
          : undefined,
        context_extracted_text: typeof body?.context_extracted_text === "string" ? body.context_extracted_text : undefined,
        output_variant: sanitizeEnum(body?.output_variant, ["AUTO", "FA_SCRIPT", "FINGLISH", "EN"] as const),
        hard_mode_requested: Boolean(body?.hard_mode_requested),
      };

      const combinedForSafety = [req.goal_text ?? "", req.situation_text ?? "", req.user_message, req.context_extracted_text ?? ""]
        .join("\n")
        .trim();

      const safety = classifyInput(combinedForSafety);
      if (safety.action === "block") {
        const baseMeta = buildBaseMeta({
          env: safeEnv,
          requestPath: url.pathname,
          mode: "COACH",
          hardMode: req.hard_mode_requested ?? false,
          outputVariant: req.output_variant ?? "AUTO",
          requestLatencyMs: nowMs() - tReq0,
          safetyBlocked: true,
        });
        return jsonResponse(
          blocked("SAFETY_BLOCK", "Input was blocked by minimal safety gate.", { reasons: safety.reasons }, { ...baseMeta, safety: safety.reasons }),
          200
        );
      }

      try {
        const out = await generateCoachWithGroq({ env: safeEnv, req });

        if (req.hard_mode_requested) {
          if (!out.data.best_question || !out.data.safety_line) {
            out.data.best_question = out.data.best_question ?? "Mikhay aheste aheste behem begi alan chi hess mikoni?";
            out.data.safety_line =
              out.data.safety_line ??
              "Agar alan hess mikoni to khatar hasti, lotfan az yek nafar moteber komak begir ya ba emergency tamas begir.";
          }
        }

        const baseMeta = buildBaseMeta({
          env: safeEnv,
          requestPath: url.pathname,
          mode: "COACH",
          hardMode: req.hard_mode_requested ?? false,
          outputVariant: req.output_variant ?? "AUTO",
          requestLatencyMs: nowMs() - tReq0,
        });

        return jsonResponse(
          ok(out.data, {
            ...baseMeta,
            model: modelForEnv(safeEnv),
            usage: out.usage,
            repair_attempted: out.repair_attempted,
          }),
          200
        );
      } catch (e: any) {
        const baseMeta = buildBaseMeta({
          env: safeEnv,
          requestPath: url.pathname,
          mode: "COACH",
          hardMode: req.hard_mode_requested ?? false,
          outputVariant: req.output_variant ?? "AUTO",
          requestLatencyMs: nowMs() - tReq0,
        });
        return jsonResponse(err("INTERNAL_ERROR", "Failed to generate coach response", String(e?.message ?? e), baseMeta), 500);
      }
    }

    // IMPROVE
    if (request.method === "POST" && url.pathname === "/v1/improve") {
      let body: any;
      try {
        body = await parseJsonBody(request);
      } catch {
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

      const hardMode = Boolean(body?.input?.hard_mode);
      const variant = body?.input?.output_variant as string | undefined;
      const contextExtractedText = typeof body?.input?.context_extracted_text === "string" ? body.input.context_extracted_text : undefined;

      const flirtMode = sanitizeEnum(body?.input?.flirt_mode, ALLOWED_FLIRT_MODE) ?? "off";
      const datingStage = sanitizeEnum(body?.input?.dating_stage, ALLOWED_DATING_STAGE);
      const datingVibe = sanitizeEnum(body?.input?.dating_vibe, ALLOWED_DATING_VIBE);

      const safety = classifyInput([draftText, contextExtractedText ?? ""].join("\n"));
      if (safety.action === "block") {
        const baseMeta = buildBaseMeta({
          env: safeEnv,
          requestPath: url.pathname,
          mode: "IMPROVE",
          hardMode,
          outputVariant: variant,
          requestLatencyMs: nowMs() - tReq0,
          safetyBlocked: true,
        });
        return jsonResponse(
          blocked("SAFETY_BLOCK", "Input was blocked by minimal safety gate.", { reasons: safety.reasons }, { ...baseMeta, safety: safety.reasons }),
          200
        );
      }

      const safetyHints = (safety.reasons ?? []).filter((r) => r.endsWith("_redirect"));

      try {
        const out = await generateSuggestionsWithGroq({
          env: safeEnv,
          mode: "IMPROVE",
          variant,
          hardMode,
          inputText: draftText,
          flirtMode,
          datingStage,
          datingVibe,
          safetyHints,
          contextExtractedText,
        });

        const baseMeta = buildBaseMeta({
          env: safeEnv,
          requestPath: url.pathname,
          mode: "IMPROVE",
          hardMode,
          outputVariant: variant,
          requestLatencyMs: nowMs() - tReq0,
        });

        return jsonResponse(
          ok(
            {
              mode: "IMPROVE",
              voice_match_score: 80,
              risk: { level: "green", score: 20, reasons: ["Mock risk: low"] },
              suggestions: out.suggestions,
            },
            {
              ...baseMeta,
              model: modelForEnv(safeEnv),
              usage: out.usage,
              parse_ok: out.parse_ok,
              schema_ok: out.schema_ok,
              extracted_from_raw: out.extracted_from_raw,
              repair_attempted: out.repair_attempted,
            }
          ),
          200
        );
      } catch (e: any) {
        const baseMeta = buildBaseMeta({
          env: safeEnv,
          requestPath: url.pathname,
          mode: "IMPROVE",
          hardMode,
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
      } catch {
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
        return jsonResponse(err("VALIDATION_ERROR", "input.received_text is required", { path: "input.received_text" }, baseMeta), 400);
      }

      const hardMode = Boolean(body?.input?.hard_mode);
      const variant = body?.input?.output_variant as string | undefined;
      const contextExtractedText = typeof body?.input?.context_extracted_text === "string" ? body.input.context_extracted_text : undefined;

      const flirtMode = sanitizeEnum(body?.input?.flirt_mode, ALLOWED_FLIRT_MODE) ?? "off";
      const datingStage = sanitizeEnum(body?.input?.dating_stage, ALLOWED_DATING_STAGE);
      const datingVibe = sanitizeEnum(body?.input?.dating_vibe, ALLOWED_DATING_VIBE);

      const safety = classifyInput([receivedText, contextExtractedText ?? ""].join("\n"));
      if (safety.action === "block") {
        const baseMeta = buildBaseMeta({
          env: safeEnv,
          requestPath: url.pathname,
          mode: "REPLY",
          hardMode,
          outputVariant: variant,
          requestLatencyMs: nowMs() - tReq0,
          safetyBlocked: true,
        });
        return jsonResponse(
          blocked("SAFETY_BLOCK", "Input was blocked by minimal safety gate.", { reasons: safety.reasons }, { ...baseMeta, safety: safety.reasons }),
          200
        );
      }

      const safetyHints = (safety.reasons ?? []).filter((r) => r.endsWith("_redirect"));

      try {
        const out = await generateSuggestionsWithGroq({
          env: safeEnv,
          mode: "REPLY",
          variant,
          hardMode,
          inputText: receivedText,
          flirtMode,
          datingStage,
          datingVibe,
          safetyHints,
          contextExtractedText,
        });

        const baseMeta = buildBaseMeta({
          env: safeEnv,
          requestPath: url.pathname,
          mode: "REPLY",
          hardMode,
          outputVariant: variant,
          requestLatencyMs: nowMs() - tReq0,
        });

        return jsonResponse(
          ok(
            {
              mode: "REPLY",
              voice_match_score: 80,
              risk: { level: "green", score: 20, reasons: ["Mock risk: low"] },
              suggestions: out.suggestions,
            },
            {
              ...baseMeta,
              model: modelForEnv(safeEnv),
              usage: out.usage,
              parse_ok: out.parse_ok,
              schema_ok: out.schema_ok,
              extracted_from_raw: out.extracted_from_raw,
              repair_attempted: out.repair_attempted,
            }
          ),
          200
        );
      } catch (e: any) {
        const baseMeta = buildBaseMeta({
          env: safeEnv,
          requestPath: url.pathname,
          mode: "REPLY",
          hardMode,
          outputVariant: variant,
          requestLatencyMs: nowMs() - tReq0,
        });
        return jsonResponse(err("INTERNAL_ERROR", "Failed to generate suggestions", String(e?.message ?? e), baseMeta), 500);
      }
    }

    const baseMeta = buildBaseMeta({
      env: safeEnv,
      requestPath: url.pathname,
      mode: "UNKNOWN",
      requestLatencyMs: nowMs() - tReq0,
    });
    return jsonResponse(err("NOT_FOUND", "Route not found", { path: url.pathname }, baseMeta), 404);
  },
};