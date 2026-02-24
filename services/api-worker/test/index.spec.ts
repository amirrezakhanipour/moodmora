import { describe, it, expect } from "vitest";
import worker from "../src/index";

async function readJson(res: Response): Promise<any> {
  return (await res.json()) as any;
}

describe("api-worker", () => {
  it("GET /health returns envelope ok with service + ok:true", async () => {
    const req = new Request("http://example.com/health", { method: "GET" });
    const res = await worker.fetch(req);

    expect(res.status).toBe(200);

    const body = await readJson(res);

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

    const body = await readJson(res);

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

    const body = await readJson(res);
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

  it("POST /v1/reply auto hard-mode severe escalation is blocked before LLM (precheck)", async () => {
    // Intentionally extreme to trigger precheckText() severe rule (red + score>=80)
    const payload = {
      input: {
        received_text: "YOU ALWAYS DO THIS!!! YOU'LL REGRET THIS!!! YOU ARE DONE. YOU IDIOT!!! OR ELSE!!!",
        hard_mode: false,
        output_variant: "EN",
      },
    };

    const req = new Request("http://example.com/v1/reply", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(payload),
    });

    const res = await worker.fetch(req);
    expect(res.status).toBe(200);

    const body = await readJson(res);

    // precheck blocks before LLM
    expect(body.status).toBe("blocked");
    expect(body.error?.code).toBe("SAFETY_BLOCK");

    // should include risk details (from precheck)
    expect(body.meta?.risk).toBeDefined();
    expect(body.meta?.risk?.level).toBe("red");
    expect(typeof body.meta?.risk?.score).toBe("number");
    expect(Array.isArray(body.meta?.risk?.reasons)).toBe(true);

    // observability meta
    expect(body.meta?.request_path).toBe("/v1/reply");
    expect(body.meta?.mode).toBe("REPLY");
    expect(body.meta?.hard_mode).toBe(true);
    expect(body.meta?.output_variant).toBe("EN");
    expect(body.meta?.runtime).toBe("worker");
    expect(body.meta?.safety_blocked).toBe(true);
    expect(typeof body.meta?.request_latency_ms).toBe("number");
  });
});