import { describe, it, expect } from "vitest";
import worker from "../src/index";

describe("api-worker", () => {
  it("GET /health returns envelope ok with service + ok:true", async () => {
    const req = new Request("http://example.com/health", { method: "GET" });
    const res = await worker.fetch(req);

    expect(res.status).toBe(200);

    const body = await res.json();

    expect(body.status).toBe("ok");
    expect(body.meta?.contract_version).toBe("1.0.0");
    expect(body.data).toEqual({ service: "api-worker", ok: true });
    expect(body.error).toBeNull();

    // observability meta
    expect(body.meta?.request_path).toBe("/health");
    expect(body.meta?.mode).toBe("HEALTH");
    expect(body.meta?.runtime).toBe("worker");
    expect(typeof body.meta?.request_latency_ms).toBe("number");
  });

  it("unknown route returns 404 with NOT_FOUND envelope", async () => {
    const req = new Request("http://example.com/nope", { method: "GET" });
    const res = await worker.fetch(req);

    expect(res.status).toBe(404);

    const body = await res.json();

    expect(body.status).toBe("error");
    expect(body.meta?.contract_version).toBe("1.0.0");
    expect(body.data).toBeNull();
    expect(body.error?.code).toBe("NOT_FOUND");
    expect(body.error?.details?.path).toBe("/nope");

    // observability meta
    expect(body.meta?.request_path).toBe("/nope");
    expect(body.meta?.mode).toBe("UNKNOWN");
    expect(body.meta?.runtime).toBe("worker");
    expect(typeof body.meta?.request_latency_ms).toBe("number");
  });

  it("POST /v1/reply blocks obvious self-harm signals", async () => {
    const payload = {
      input: {
        received_text: "man mikhayam khodkoshi konam",
        hard_mode: true,
        output_variant: "FINGLISH",
      },
    };

    const req = new Request("http://example.com/v1/reply", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(payload),
    });

    const res = await worker.fetch(req);
    expect(res.status).toBe(200);

    const body = await res.json();
    expect(body.status).toBe("blocked");
    expect(body.error?.code).toBe("SAFETY_BLOCK");

    // observability meta
    expect(body.meta?.request_path).toBe("/v1/reply");
    expect(body.meta?.mode).toBe("REPLY");
    expect(body.meta?.hard_mode).toBe(true);
    expect(body.meta?.output_variant).toBe("FINGLISH");
    expect(body.meta?.runtime).toBe("worker");
    expect(body.meta?.safety_blocked).toBe(true);
    expect(typeof body.meta?.request_latency_ms).toBe("number");
  });

  it("POST /v1/coach/message returns 404 when feature is disabled", async () => {
    const payload = {
      user_message: "salam",
      output_variant: "FINGLISH",
    };

    const req = new Request("http://example.com/v1/coach/message", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(payload),
    });

    // FEATURE_COACH is not set in tests => disabled by default
    const res = await worker.fetch(req, {});
    expect(res.status).toBe(404);

    const body = await res.json();
    expect(body.status).toBe("error");
    expect(body.error?.code).toBe("NOT_FOUND");

    // observability meta
    expect(body.meta?.request_path).toBe("/v1/coach/message");
    expect(body.meta?.mode).toBe("COACH");
    expect(body.meta?.runtime).toBe("worker");
    expect(typeof body.meta?.request_latency_ms).toBe("number");
  });

  it("POST /v1/coach/message returns 400 when enabled but user_message is missing", async () => {
    const payload = {
      output_variant: "FINGLISH",
    };

    const req = new Request("http://example.com/v1/coach/message", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(payload),
    });

    const res = await worker.fetch(req, { FEATURE_COACH: "1" });
    expect(res.status).toBe(400);

    const body = await res.json();
    expect(body.status).toBe("error");
    expect(body.error?.code).toBe("VALIDATION_ERROR");

    // observability meta
    expect(body.meta?.request_path).toBe("/v1/coach/message");
    expect(body.meta?.mode).toBe("COACH");
    expect(body.meta?.runtime).toBe("worker");
    expect(typeof body.meta?.request_latency_ms).toBe("number");
  });
});