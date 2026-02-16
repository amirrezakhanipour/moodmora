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
  });
});
