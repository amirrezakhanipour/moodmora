// services/api-worker/src/index.ts
import { groqChatCompletion } from "./groq";
import { buildMessages } from "./prompt_builder";

type Status = "ok" | "blocked" | "error";

type Envelope = {
  status: Status;
  request_id: string;
  timestamp_ms: number;
  data: Record<string, unknown> | null;
  error: { code: string; message: string; details?: Record<string, unknown> | null } | null;
  meta: { contract_version: "1.0.0" } & Record<string, unknown>;
};

type Suggestion = {
  label: string;
  text: string;
  why_it_works: string;
  emotion_preview: string[];
};

type WorkerEnv = {
  GROQ_API_KEY?: string;
  GROQ_MODEL?: string;
  PROMPT_VERSION?: string;
  LLM_TIMEOUT_MS?: string;
};

function jsonResponse(body: unknown, status = 200): Response {
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

// --- MOCK fallback (ta vaghti parse/repair va structured outputs ro nayavordim) ---
function makeMockSuggestions(count: number, variant: string | undefined) {
  const isFinglish = variant === "FINGLISH";
  const base = isFinglish
    ? {
        s1: "Hey, man mikhastam ye chizi ro clear konam. tone-am diruz ok نبود، sorry.",
        s2: "Mifahmam ke in barat sakht bood. mikhay ye vaght koochik gap bezanim?",
        s3: "Hag dari. az in be bad say mikonam zودتر coordination konam.",
      }
    : {
        s1: "Hey, I wanted to clear something up. My tone wasn’t great—sorry.",
        s2: "I get that this was stressful. Want to talk for a few minutes and align?",
        s3: "You’re right. I’ll coordinate earlier next time.",
      };

  const texts = [base.s1, base.s2, base.s3].slice(0, count);
  const labels = count === 2 ? ["Calm & clear", "Short"] : ["Calm & clear", "Short", "Warm"];

  return texts.map((text, i) => ({
    label: labels[i] ?? `Option ${i + 1}`,
    text,
    why_it_works: "Mock suggestion: simple, respectful, low pressure.",
    emotion_preview: ["calm"],
  })) satisfies Suggestion[];
}

function clampSuggestionCount(hardMode: boolean): number {
  return hardMode ? 2 : 3;
}

function modelForEnv(env: WorkerEnv): string {
  return env?.GROQ_MODEL?.trim() || "llama-3.3-70b-versatile";
}

function timeoutMsForEnv(env: WorkerEnv): number {
  const raw = env?.LLM_TIMEOUT_MS?.trim();
  const n = raw ? Number(raw) : 20000;
  if (!Number.isFinite(n) || n <= 0) return 20000;
  return Math.min(Math.max(1000, n), 60000);
}

function promptVersion(env: WorkerEnv): string {
  return env?.PROMPT_VERSION?.trim() || "3.2.0";
}

async function generateSuggestionsWithGroq(args: {
  env: WorkerEnv;
  mode: "IMPROVE" | "REPLY";
  variant?: string;
  hardMode: boolean;
  inputText: string;
}): Promise<{ suggestions: Suggestion[]; usage: unknown }> {
  const apiKey = args.env.GROQ_API_KEY?.trim();
  if (!apiKey) {
    throw new Error("MISSING_GROQ_API_KEY");
  }

  const count = clampSuggestionCount(args.hardMode);

  const messages = buildMessages({
    mode: args.mode,
    inputText: args.inputText,
    suggestionCount: count,
    outputVariant: args.variant,
  });

  const t0 = nowMs();
  const { content, usage } = await groqChatCompletion({
    apiKey,
    model: modelForEnv(args.env),
    messages,
    temperature: 0.4,
    maxTokens: 700,
    timeoutMs: timeoutMsForEnv(args.env),
  });
  const latencyMs = nowMs() - t0;

  // Best-effort parse (Step 3.6 repair comes later)
  let parsed: any;
  try {
    parsed = JSON.parse(content);
  } catch {
    throw new Error(`GROQ_BAD_JSON: ${content.slice(0, 200)}`);
  }

  const suggestions = Array.isArray(parsed?.suggestions) ? (parsed.suggestions as any[]) : [];
  if (suggestions.length !== count) {
    throw new Error(`GROQ_BAD_SHAPE: expected ${count} suggestions, got ${suggestions.length}`);
  }

  const normalized: Suggestion[] = suggestions.map((s, i) => ({
    label: typeof s?.label === "string" ? s.label : `Option ${i + 1}`,
    text: typeof s?.text === "string" ? s.text : "",
    why_it_works: typeof s?.why_it_works === "string" ? s.why_it_works : "Clear, respectful, and low pressure.",
    emotion_preview: Array.isArray(s?.emotion_preview) ? s.emotion_preview.map(String).slice(0, 3) : ["calm"],
  }));

  // quick sanity
  if (normalized.some((x) => !x.text.trim())) {
    throw new Error("GROQ_EMPTY_TEXT");
  }

  return { suggestions: normalized, usage: { ...(usage as any), latency_ms: latencyMs } };
}

export default {
  async fetch(request: Request, env: WorkerEnv = {} as WorkerEnv): Promise<Response> {
    const url = new URL(request.url);

    // GET /health
    if (request.method === "GET" && url.pathname === "/health") {
      return jsonResponse(
        ok(
          { service: "api-worker", ok: true },
          {
            prompt_version: promptVersion(env),
            model: modelForEnv(env),
          }
        ),
        200
      );
    }

    // POST /v1/improve
    if (request.method === "POST" && url.pathname === "/v1/improve") {
      let body: any;
      try {
        body = await readJson(request);
      } catch {
        return jsonResponse(err("VALIDATION_ERROR", "Invalid JSON body"), 400);
      }

      const draftText = body?.input?.draft_text;
      if (typeof draftText !== "string" || draftText.trim().length === 0) {
        return jsonResponse(err("VALIDATION_ERROR", "input.draft_text is required", { path: "input.draft_text" }), 400);
      }

      const hardMode = Boolean(body?.input?.hard_mode);
      const variant = body?.input?.output_variant as string | undefined;

      try {
        const { suggestions, usage } = await generateSuggestionsWithGroq({
          env,
          mode: "IMPROVE",
          variant,
          hardMode,
          inputText: draftText,
        });

        return jsonResponse(
          ok(
            {
              mode: "IMPROVE",
              voice_match_score: 80, // mock for now (Phase 5)
              risk: { level: "green", score: 20, reasons: ["Mock risk: low"] }, // real in Phase 4
              suggestions,
            },
            {
              model: modelForEnv(env),
              prompt_version: promptVersion(env),
              usage,
            }
          ),
          200
        );
      } catch (e: any) {
        // fallback to mock so app doesn't break while we iterate
        const suggestions = makeMockSuggestions(clampSuggestionCount(hardMode), variant);
        return jsonResponse(
          ok(
            {
              mode: "IMPROVE",
              voice_match_score: 80,
              risk: { level: "yellow", score: 35, reasons: ["LLM failed; served mock suggestions"] },
              suggestions,
            },
            {
              model: modelForEnv(env),
              prompt_version: promptVersion(env),
              llm_error: String(e?.message ?? e),
            }
          ),
          200
        );
      }
    }

    // POST /v1/reply
    if (request.method === "POST" && url.pathname === "/v1/reply") {
      let body: any;
      try {
        body = await readJson(request);
      } catch {
        return jsonResponse(err("VALIDATION_ERROR", "Invalid JSON body"), 400);
      }

      const receivedText = body?.input?.received_text;
      if (typeof receivedText !== "string" || receivedText.trim().length === 0) {
        return jsonResponse(err("VALIDATION_ERROR", "input.received_text is required", { path: "input.received_text" }), 400);
      }

      const hardMode = Boolean(body?.input?.hard_mode);
      const variant = body?.input?.output_variant as string | undefined;

      try {
        const { suggestions, usage } = await generateSuggestionsWithGroq({
          env,
          mode: "REPLY",
          variant,
          hardMode,
          inputText: receivedText,
        });

        return jsonResponse(
          ok(
            {
              mode: "REPLY",
              voice_match_score: 78,
              risk: { level: "yellow", score: 45, reasons: ["Mock risk: medium (receiver stressed)"] },
              suggestions,
            },
            {
              model: modelForEnv(env),
              prompt_version: promptVersion(env),
              usage,
            }
          ),
          200
        );
      } catch (e: any) {
        const suggestions = makeMockSuggestions(clampSuggestionCount(hardMode), variant);
        return jsonResponse(
          ok(
            {
              mode: "REPLY",
              voice_match_score: 78,
              risk: { level: "yellow", score: 55, reasons: ["LLM failed; served mock suggestions"] },
              suggestions,
            },
            {
              model: modelForEnv(env),
              prompt_version: promptVersion(env),
              llm_error: String(e?.message ?? e),
            }
          ),
          200
        );
      }
    }

    return jsonResponse(err("NOT_FOUND", "Route not found", { path: url.pathname }), 404);
  },
};
