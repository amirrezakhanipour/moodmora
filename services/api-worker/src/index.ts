type Status = "ok" | "blocked" | "error";

type Envelope = {
  status: Status;
  request_id: string;
  timestamp_ms: number;
  data: Record<string, unknown> | null;
  error: { code: string; message: string; details?: Record<string, unknown> | null } | null;
  meta: { contract_version: "1.0.0" };
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
  // simple deterministic-ish id for mock
  return `req_${nowMs()}_${Math.floor(Math.random() * 100000)}`;
}

function ok(data: Envelope["data"]): Envelope {
  return {
    status: "ok",
    request_id: requestId(),
    timestamp_ms: nowMs(),
    data,
    error: null,
    meta: { contract_version: "1.0.0" },
  };
}

function err(code: string, message: string, details?: Record<string, unknown> | null): Envelope {
  return {
    status: "error",
    request_id: requestId(),
    timestamp_ms: nowMs(),
    data: null,
    error: { code, message, details: details ?? null },
    meta: { contract_version: "1.0.0" },
  };
}

function makeSuggestions(count: number, variant: string | undefined, mode: "IMPROVE" | "REPLY") {
  const isFinglish = variant === "FINGLISH";
  const base = isFinglish
    ? {
        s1: "Hey, man mikhastam ye chizi ro clear کنم. tone-am diruz ok نبود، sorry.",
        s2: "Mifahmam ke in barat sakht بوده. mikhay ye vaght koochik gap bezanim?",
        s3: "Hag dari. az in be bad say mikonam zودتر coordination کنم.",
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
    text: mode === "IMPROVE" ? text : text, // same for mock
    why_it_works: "Mock suggestion: simple, respectful, low pressure.",
    emotion_preview: ["calm"],
  }));
}

async function readJson(request: Request): Promise<any> {
  const txt = await request.text();
  if (!txt) return null;
  return JSON.parse(txt);
}

export default {
  async fetch(request: Request): Promise<Response> {
    const url = new URL(request.url);

    // GET /health
    if (request.method === "GET" && url.pathname === "/health") {
      // Keep it simple + compatible
      return jsonResponse(ok({ service: "api-worker", ok: true }), 200);
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
        return jsonResponse(
          err("VALIDATION_ERROR", "input.draft_text is required", { path: "input.draft_text" }),
          400
        );
      }

      const hardMode = Boolean(body?.input?.hard_mode);
      const variant = body?.input?.output_variant;

      const suggestions = makeSuggestions(hardMode ? 2 : 3, variant, "IMPROVE");

      return jsonResponse(
        ok({
          mode: "IMPROVE",
          voice_match_score: 80,
          risk: {
            level: "green",
            score: 20,
            reasons: ["Mock risk: low"],
          },
          suggestions,
        }),
        200
      );
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
        return jsonResponse(
          err("VALIDATION_ERROR", "input.received_text is required", { path: "input.received_text" }),
          400
        );
      }

      const hardMode = Boolean(body?.input?.hard_mode);
      const variant = body?.input?.output_variant;

      const suggestions = makeSuggestions(hardMode ? 2 : 3, variant, "REPLY");

      return jsonResponse(
        ok({
          mode: "REPLY",
          voice_match_score: 78,
          risk: {
            level: "yellow",
            score: 45,
            reasons: ["Mock risk: medium (receiver stressed)"],
          },
          suggestions,
        }),
        200
      );
    }

    // Default 404
    return jsonResponse(err("NOT_FOUND", "Route not found", { path: url.pathname }), 404);
  },
};
