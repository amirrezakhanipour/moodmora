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
  data: Record<string, unknown> | null;
  error: { code: string; message: string; details?: Record<string, unknown> | null } | null;
  meta: { contract_version: "1.0.0" } & Record<string, unknown>;
};

type WorkerEnv = {
  GROQ_API_KEY?: string;
  GROQ_MODEL?: string;
  PROMPT_VERSION?: string;
  LLM_TIMEOUT_MS?: string;
  BUILD_SHA?: string; // optional: short git sha for observability
};

async function jsonResponse(body: unknown, status = 200): Promise<Response> {
  // Optional contract validation in Node (tests/CI). Never block response unless strict is enabled.
  try {
    const strict =
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      String(((globalThis as any).process?.env?.MOODMORA_STRICT_CONTRACTS ?? "")).toLowerCase() === "true";

    if (strict) {
      const r = await validateEnvelopeContract(body);
      if (!r.ok) {
        return new Response(
          JSON.stringify(
            err("CONTRACT_VALIDATION_ERROR", "Envelope failed contract validation", {
              schema_id: r.schema_id,
              errors: r.errors,
            })
          ),
          {
            status: 500,
            headers: {
              "content-type": "application/json; charset=utf-8",
              "cache-control": "no-store",
            },
          }
        );
      }
    } else {
      // warn-only / best-effort
      await validateEnvelopeContract(body);
    }
  } catch {
    // ignore
  }

  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "content-type": "application/json; charset=utf-8",
      "cache-control": "no-store",
    },
  });
}

function nowMs(): number {
  return Date.now();
}

function requestId(): string {
  return `req_${nowMs()}_${Math.floor(Math.random() * 100000)}`;
}

function ok(data: Envelope["data"], meta?: Record<string, unknown>): Envelope {
  return {
    status: "ok",
    request_id: requestId(),
    timestamp_ms: nowMs(),
    data,
    error: null,
    meta: { contract_version: "1.0.0", ...(meta ?? {}) },
  };
}

function blocked(code: string, message: string, details?: Record<string, unknown> | null, meta?: Record<string, unknown>): Envelope {
  return {
    status: "blocked",
    request_id: requestId(),
    timestamp_ms: nowMs(),
    data: null,
    error: { code, message, details: details ?? null },
    meta: { contract_version: "1.0.0", ...(meta ?? {}) },
  };
}

function err(code: string, message: string, details?: Record<string, unknown> | null, meta?: Record<string, unknown>): Envelope {
  return {
    status: "error",
    request_id: requestId(),
    timestamp_ms: nowMs(),
    data: null,
    error: { code, message, details: details ?? null },
    meta: { contract_version: "1.0.0", ...(meta ?? {}) },
  };
}

async function readJson(request: Request): Promise<unknown> {
  const txt = await request.text();
  if (!txt) return null;
  return JSON.parse(txt);
}

function clampSuggestionCount(hardMode: boolean): number {
  return hardMode ? 2 : 3;
}

function modelForEnv(env: WorkerEnv): string {
  return env.GROQ_MODEL?.trim() || "llama-3.3-70b-versatile";
}

function timeoutMsForEnv(env: WorkerEnv): number {
  const raw = env.LLM_TIMEOUT_MS?.trim();
  const n = raw ? Number(raw) : 20000;
  if (!Number.isFinite(n) || n <= 0) return 20000;
  return Math.min(Math.max(1000, n), 60000);
}

function promptVersion(env: WorkerEnv): string {
  return env.PROMPT_VERSION?.trim() || "3.2.0";
}

function buildBaseMeta(args: {
  env: WorkerEnv;
  requestPath: string;
  mode?: "IMPROVE" | "REPLY" | "HEALTH" | "UNKNOWN";
  hardMode?: boolean;
  outputVariant?: string;
  requestLatencyMs: number;
  safetyBlocked?: boolean;
}): Record<string, unknown> {
  return {
    request_path: args.requestPath,
    mode: args.mode ?? "UNKNOWN",
    hard_mode: args.hardMode ?? null,
    output_variant: args.outputVariant ?? null,
    runtime: "worker",
    build: args.env.BUILD_SHA?.trim() || null,
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
  env: WorkerEnv;
  mode: "IMPROVE" | "REPLY";
  variant?: string;
  hardMode: boolean;
  inputText: string;
}): Promise<{
  suggestions: Suggestion[];
  usage: unknown;
  parse_ok: boolean;
  schema_ok: boolean;
  extracted_from_raw: boolean;
  repair_attempted: boolean;
}> {
  const apiKey = args.env.GROQ_API_KEY?.trim();
  if (!apiKey) throw new Error("MISSING_GROQ_API_KEY");

  const count = clampSuggestionCount(args.hardMode);

  const baseMessages = buildMessages({
    mode: args.mode,
    inputText: args.inputText,
    suggestionCount: count,
    outputVariant: args.variant,
  });

  // Attempt #1 (JSON mode)
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

  // Attempt #2 (repair)
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
  async fetch(request: Request, env: WorkerEnv = {} as WorkerEnv): Promise<Response> {
    const tReq0 = nowMs();
    const url = new URL(request.url);

    if (request.method === "GET" && url.pathname === "/health") {
      const baseMeta = buildBaseMeta({
        env,
        requestPath: url.pathname,
        mode: "HEALTH",
        requestLatencyMs: nowMs() - tReq0,
      });

      return await jsonResponse(
        ok(
          { service: "api-worker", ok: true },
          {
            ...baseMeta,
            prompt_version: promptVersion(env),
            model: modelForEnv(env),
          }
        ),
        200
      );
    }

    if (request.method === "POST" && url.pathname === "/v1/improve") {
      let body: any;
      try {
        body = await readJson(request);
      } catch {
        const baseMeta = buildBaseMeta({
          env,
          requestPath: url.pathname,
          mode: "IMPROVE",
          requestLatencyMs: nowMs() - tReq0,
        });
        return await jsonResponse(err("VALIDATION_ERROR", "Invalid JSON body", null, baseMeta), 400);
      }

      const draftText = body?.input?.draft_text;
      if (typeof draftText !== "string" || draftText.trim().length === 0) {
        const baseMeta = buildBaseMeta({
          env,
          requestPath: url.pathname,
          mode: "IMPROVE",
          requestLatencyMs: nowMs() - tReq0,
        });
        return await jsonResponse(err("VALIDATION_ERROR", "input.draft_text is required", { path: "input.draft_text" }, baseMeta), 400);
      }

      const hardMode = Boolean(body?.input?.hard_mode);
      const variant = body?.input?.output_variant as string | undefined;

      // minimal safety gate
      const safety = classifyInput(draftText);
      if (safety.action === "block") {
        const baseMeta = buildBaseMeta({
          env,
          requestPath: url.pathname,
          mode: "IMPROVE",
          hardMode,
          outputVariant: variant,
          requestLatencyMs: nowMs() - tReq0,
          safetyBlocked: true,
        });
        return await jsonResponse(
          blocked("SAFETY_BLOCK", "Input was blocked by minimal safety gate.", { reasons: safety.reasons }, { ...baseMeta, safety: safety.reasons }),
          200
        );
      }

      try {
        const out = await generateSuggestionsWithGroq({
          env,
          mode: "IMPROVE",
          variant,
          hardMode,
          inputText: draftText,
        });

        const baseMeta = buildBaseMeta({
          env,
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
              model: modelForEnv(env),
              prompt_version: promptVersion(env),
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
          env,
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
              risk: { level: "yellow", score: 35, reasons: ["LLM failed; served mock suggestions"] },
              suggestions: [
                {
                  label: "Calm & clear",
                  text: "Hey, man mikhastam ye chizi ro clear konam. tone-am ok نبود، sorry.",
                  why_it_works: "Simple, respectful, low pressure.",
                  emotion_preview: ["calm"],
                },
                ...(hardMode
                  ? []
                  : [
                      {
                        label: "Warm",
                        text: "Mifahmam ke in barat sakht bood. mikhay ye vaght koochik gap bezanim?",
                        why_it_works: "Gentle, collaborative, lowers tension.",
                        emotion_preview: ["warm"],
                      },
                    ]),
              ].slice(0, clampSuggestionCount(hardMode)) as any,
            },
            {
              ...baseMeta,
              model: modelForEnv(env),
              prompt_version: promptVersion(env),
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
          env,
          requestPath: url.pathname,
          mode: "REPLY",
          requestLatencyMs: nowMs() - tReq0,
        });
        return await jsonResponse(err("VALIDATION_ERROR", "Invalid JSON body", null, baseMeta), 400);
      }

      const receivedText = body?.input?.received_text;
      if (typeof receivedText !== "string" || receivedText.trim().length === 0) {
        const baseMeta = buildBaseMeta({
          env,
          requestPath: url.pathname,
          mode: "REPLY",
          requestLatencyMs: nowMs() - tReq0,
        });
        return await jsonResponse(err("VALIDATION_ERROR", "input.received_text is required", { path: "input.received_text" }, baseMeta), 400);
      }

      const hardMode = Boolean(body?.input?.hard_mode);
      const variant = body?.input?.output_variant as string | undefined;

      // minimal safety gate
      const safety = classifyInput(receivedText);
      if (safety.action === "block") {
        const baseMeta = buildBaseMeta({
          env,
          requestPath: url.pathname,
          mode: "REPLY",
          hardMode,
          outputVariant: variant,
          requestLatencyMs: nowMs() - tReq0,
          safetyBlocked: true,
        });
        return await jsonResponse(
          blocked("SAFETY_BLOCK", "Input was blocked by minimal safety gate.", { reasons: safety.reasons }, { ...baseMeta, safety: safety.reasons }),
          200
        );
      }

      try {
        const out = await generateSuggestionsWithGroq({
          env,
          mode: "REPLY",
          variant,
          hardMode,
          inputText: receivedText,
        });

        const baseMeta = buildBaseMeta({
          env,
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
              model: modelForEnv(env),
              prompt_version: promptVersion(env),
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
          env,
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
              risk: { level: "yellow", score: 55, reasons: ["LLM failed; served mock suggestions"] },
              suggestions: [
                {
                  label: "Short",
                  text: "Ok, mifahmam. mikhay ye kam aram-tar harf bezanim ta behtar ham-o befahmim?",
                  why_it_works: "Short, calm, invites alignment.",
                  emotion_preview: ["calm"],
                },
                ...(hardMode
                  ? []
                  : [
                      {
                        label: "Friendly",
                        text: "Mersy gofti. manam dost daram be shive-ye aram-tar pish berim. mikhay alan 2 daghighe gap bezanim?",
                        why_it_works: "Friendly + specific next step reduces friction.",
                        emotion_preview: ["friendly"],
                      },
                    ]),
              ].slice(0, clampSuggestionCount(hardMode)) as any,
            },
            {
              ...baseMeta,
              model: modelForEnv(env),
              prompt_version: promptVersion(env),
              llm_error: String(e?.message ?? e),
            }
          ),
          200
        );
      }
    }

    const baseMeta = buildBaseMeta({
      env,
      requestPath: url.pathname,
      mode: "UNKNOWN",
      requestLatencyMs: nowMs() - tReq0,
    });

    return await jsonResponse(err("NOT_FOUND", "Route not found", { path: url.pathname }, baseMeta), 404);
  },
};
