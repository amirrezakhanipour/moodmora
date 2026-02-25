import { describe, expect, test } from "vitest";
import { computeVoiceMatchScore } from "../src/voice_score";

describe("voice_score", () => {
  test("returns baseline when voice disabled", () => {
    const score = computeVoiceMatchScore({ enabled: false }, [
      { label: "A", text: "Hello", why_it_works: "x", emotion_preview: ["calm"] },
    ]);
    expect(score).toBe(50);
  });

  test("penalizes do_not_use hits strongly", () => {
    const score = computeVoiceMatchScore(
      { enabled: true, profile: { do_not_use: ["lotfan"] } },
      [{ label: "A", text: "lotfan in ro anjam bede", why_it_works: "x", emotion_preview: ["calm"] }]
    );
    expect(score).toBeLessThan(70);
  });

  test("higher brevity target prefers shorter messages", () => {
    const shortScore = computeVoiceMatchScore(
      { enabled: true, profile: { brevity: 0.9 } },
      [{ label: "A", text: "Ok. Thanks!", why_it_works: "x", emotion_preview: ["calm"] }]
    );

    const longScore = computeVoiceMatchScore(
      { enabled: true, profile: { brevity: 0.9 } },
      [
        {
          label: "A",
          text: "Hey, I just wanted to say I really appreciate you and I hope we can talk about this when you have time, no pressure at all.",
          why_it_works: "x",
          emotion_preview: ["calm"],
        },
      ]
    );

    expect(shortScore).toBeGreaterThan(longScore);
  });
});