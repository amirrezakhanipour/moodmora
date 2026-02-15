import { describe, it, expect } from "vitest";
import worker from "../src/index";

describe("api-worker", () => {
  it("GET /health returns ok:true", async () => {
    const req = new Request("http://example.com/health", { method: "GET" });
    const res = await worker.fetch(req);
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ ok: true });
  });

  it("unknown route returns 404 not_found", async () => {
    const req = new Request("http://example.com/nope", { method: "GET" });
    const res = await worker.fetch(req);
    expect(res.status).toBe(404);
    expect(await res.json()).toEqual({ error: "not_found" });
  });
});
