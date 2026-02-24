// services/api-worker/test/risk_score.spec.ts
import { describe, it, expect } from "vitest";
import { scoreRisk } from "../src/risk/score";

describe("risk score", () => {
  it("returns green for calm text", () => {
    const r = scoreRisk("Hey, can we talk later? I want to understand you better.");
    expect(r.level).toBe("green");
    expect(r.score).toBeGreaterThanOrEqual(0);
    expect(r.score).toBeLessThan(30);
  });

  it("returns yellow for medium escalation", () => {
    const r = scoreRisk("You always do this!!!");
    expect(["yellow", "red"]).toContain(r.level);
    expect(r.reasons.length).toBeGreaterThan(0);
  });

  it("returns red for threats/insults", () => {
    const r = scoreRisk("YOU'LL REGRET THIS, you idiot!!!");
    expect(r.level).toBe("red");
    expect(r.score).toBeGreaterThanOrEqual(60);
    expect(r.hard_mode_recommended).toBe(true);
  });
});