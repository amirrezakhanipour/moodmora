// services/api-worker/src/index.ts
import { groqChatCompletion, type GroqMessage } from "./groq";
import { buildMessages } from "./prompt_builder";
import { parseAndValidateLlmOutput } from "./llm_output";
import { validateEnvelopeContract } from "./contract_validate";
import { classifyInput } from "./safety_min";
import type { Suggestion } from "./types";

type Status = "ok" | "blocked" | "error";

type Envelope = {
  status: Status;
  request_id: string;
  timestamp_ms: number;
  data: Record<string, any> | null;
  error: { code: string; message: string; details?: any } | null;
  meta: Record<string, any>;
};

// NOTE: tests may call fetch(req, undefined), so env must be optional-safe everywhere.
type WorkerEnv = {
  GROQ_API_KEY?: string;
  GROQ_MODEL?: string;
  PROMPT_VERSION?: string;
  BUILD_SHA?: string;
  ENVIRONMENT?: string; // dev | prod | preview
};

function nowMs(): number {
  return Date.now();
}

function requestId(): string {
  return `req_${Math.random().toString(16).slice(2)}_${Date.now().toString(16)}`;
}

function jsonResponse(body: any, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "content-type": "application/json; charset=utf-8",
      "cache-control": "no-store",
    },
  });
}

function ok(data: any, meta: Record<string, any>): Envelope {
  return {
    status: "ok",
    request_id: requestId(),
    timestamp_ms: nowMs(),
    data,
    error: null,
    meta,
  };
}

function blocked(code: string, message: string, details: any, meta: Record<string, any>): Envelope {
  return {
    status: "blocked",
    request_id: requestId(),
    timestamp_ms: nowMs(),
    data: null,
    error: { code, message, details },
    meta,
  };
}

function err(code: string, message: string, details: any, meta: Record<string, any>): Envelope {
  return {
    status: "error",
    request_id: requestId(),
    timestamp_ms: nowMs(),
    data: null,
    error: { code, message, details },
    meta,
  };
}

async function readJson(request: Request): Promise<any> {
  const ct = request.headers.get("content-type") || "";
  if (!ct.toLowerCase().includes("application/json")) {
    throw new Error("INVALID_CONTENT_TYPE");
  }
  return await request.json();
}

function modelForEnv(env?: WorkerEnv): string {
  return env?.GROQ_MODEL?.trim() || "llama-3.1-70b-versatile";
}

function timeoutMsForEnv(env?: WorkerEnv): number {
  const e = (env?.ENVIRONMENT || "").trim().toLowerCase();
  return e === "prod" ? 12_000 : 25_000;
}

function clampSuggestionCount(hardMode: boolean): number {
  return hardMode ? 2 : 3;
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
}): Promise<{
  suggestions: Suggestion[];
  usage: unknown;
  parse_ok: boolean;
  schema_ok: boolean;
  extracted_from_raw: boolean;
  repair_attempted: boolean;
}> {
  const apiKey = args.env?.GROQ_API_KEY?.trim();
  if (!apiKey) throw new Error("MISSING_GROQ_API_KEY");

  const count = clampSuggestionCount(args.hardMode);

  const baseMessages = buildMessages({
    mode: args.mode,
    inputText: args.inputText,
    suggestionCount: count,
    outputVariant: args.variant,
    flirtMode: args.flirtMode,
    datingStage: args.datingStage,
    datingVibe: args.datingVibe,
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

export default {
  async fetch(request: Request, env?: WorkerEnv): Promise<Response> {
    const safeEnv = env ?? {};
    const url = new URL(request.url);
    const tReq0 = nowMs();

    if (request.method === "GET" && url.pathname === "/health") {
      const baseMeta = buildBaseMeta({
        env: safeEnv,
        requestPath: url.pathname,
        mode: "HEALTH",
        requestLatencyMs: nowMs() - tReq0,
      });
      return await jsonResponse(ok({ service: "api-worker", ok: true }, baseMeta), 200);
    }

    if (request.method === "POST" && url.pathname === "/v1/improve") {
      let body: any;
      try {
        body = await readJson(request);
      } catch {
        const baseMeta = buildBaseMeta({
          env: safeEnv,
          requestPath: url.pathname,
          mode: "IMPROVE",
          requestLatencyMs: nowMs() - tReq0,
        });
        return await jsonResponse(err("VALIDATION_ERROR", "Invalid JSON body", null, baseMeta), 400);
      }

      const draftText = body?.input?.draft_text;
      if (typeof draftText !== "string" || draftText.trim().length === 0) {
        const baseMeta = buildBaseMeta({
          env: safeEnv,
          requestPath: url.pathname,
          mode: "IMPROVE",
          requestLatencyMs: nowMs() - tReq0,
        });
        return await jsonResponse(
          err("VALIDATION_ERROR", "input.draft_text is required", { path: "input.draft_text" }, baseMeta),
          400
        );
      }

      const hardMode = Boolean(body?.input?.hard_mode);
      const variant = body?.input?.output_variant as string | undefined;

      const flirtMode = sanitizeEnum(body?.input?.flirt_mode, ALLOWED_FLIRT_MODE) ?? "off";
      const datingStage = sanitizeEnum(body?.input?.dating_stage, ALLOWED_DATING_STAGE);
      const datingVibe = sanitizeEnum(body?.input?.dating_vibe, ALLOWED_DATING_VIBE);

      const safety = classifyInput(draftText);
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
        return await jsonResponse(
          blocked(
            "SAFETY_BLOCK",
            "Input was blocked by minimal safety gate.",
            { reasons: safety.reasons },
            { ...baseMeta, safety: safety.reasons }
          ),
          200
        );
      }

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
        });

        const baseMeta = buildBaseMeta({
          env: safeEnv,
          requestPath: url.pathname,
          mode: "IMPROVE",
          hardMode,
          outputVariant: variant,
          requestLatencyMs: nowMs() - tReq0,
        });

        return await jsonResponse(
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
        return await jsonResponse(
          err(
            "LLM_ERROR",
            "LLM generation failed",
            { message: String(e?.message ?? e) },
            {
              ...baseMeta,
              model: modelForEnv(safeEnv),
              llm_error: String(e?.message ?? e),
            }
          ),
          200
        );
      }
    }

    if (request.method === "POST" && url.pathname === "/v1/reply") {
      let body: any;
      try {
        body = await readJson(request);
      } catch {
        const baseMeta = buildBaseMeta({
          env: safeEnv,
          requestPath: url.pathname,
          mode: "REPLY",
          requestLatencyMs: nowMs() - tReq0,
        });
        return await jsonResponse(err("VALIDATION_ERROR", "Invalid JSON body", null, baseMeta), 400);
      }

      const receivedText = body?.input?.received_text;
      if (typeof receivedText !== "string" || receivedText.trim().length === 0) {
        const baseMeta = buildBaseMeta({
          env: safeEnv,
          requestPath: url.pathname,
          mode: "REPLY",
          requestLatencyMs: nowMs() - tReq0,
        });
        return await jsonResponse(
          err("VALIDATION_ERROR", "input.received_text is required", { path: "input.received_text" }, baseMeta),
          400
        );
      }

      const hardMode = Boolean(body?.input?.hard_mode);
      const variant = body?.input?.output_variant as string | undefined;

      const flirtMode = sanitizeEnum(body?.input?.flirt_mode, ALLOWED_FLIRT_MODE) ?? "off";
      const datingStage = sanitizeEnum(body?.input?.dating_stage, ALLOWED_DATING_STAGE);
      const datingVibe = sanitizeEnum(body?.input?.dating_vibe, ALLOWED_DATING_VIBE);

      const safety = classifyInput(receivedText);
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
        return await jsonResponse(
          blocked(
            "SAFETY_BLOCK",
            "Input was blocked by minimal safety gate.",
            { reasons: safety.reasons },
            { ...baseMeta, safety: safety.reasons }
          ),
          200
        );
      }

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
        });

        const baseMeta = buildBaseMeta({
          env: safeEnv,
          requestPath: url.pathname,
          mode: "REPLY",
          hardMode,
          outputVariant: variant,
          requestLatencyMs: nowMs() - tReq0,
        });

        return await jsonResponse(
          ok(
            {
              mode: "REPLY",
              voice_match_score: 78,
              risk: { level: "yellow", score: 45, reasons: ["Mock risk: medium (receiver stressed)"] },
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
        return await jsonResponse(
          err(
            "LLM_ERROR",
            "LLM generation failed",
            { message: String(e?.message ?? e) },
            {
              ...baseMeta,
              model: modelForEnv(safeEnv),
              llm_error: String(e?.message ?? e),
            }
          ),
          200
        );
      }
    }

    const baseMeta = buildBaseMeta({
      env: safeEnv,
      requestPath: url.pathname,
      mode: "UNKNOWN",
      requestLatencyMs: nowMs() - tReq0,
    });
    return await jsonResponse(err("NOT_FOUND", "Route not found", { path: url.pathname }, baseMeta), 404);
  },
};

// Dev guard (import side effects)
validateEnvelopeContract;
