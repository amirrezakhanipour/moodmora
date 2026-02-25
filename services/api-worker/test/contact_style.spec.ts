import { describe, expect, it } from "vitest";
import { applyContactToVoice, styleAppliedSummary, type ContactSnapshot } from "../src/contact_style";

describe("contact_style", () => {
  it("merges forbidden_words into do_not_use (dedupe, case-insensitive)", () => {
    const contact: ContactSnapshot = {
      id: "c1",
      display_name: "Sara",
      forbidden_words: ["Lotfan", "ba ehteram", "  "],
      style_offsets: { formality_offset: 10 },
    };

    const { effectiveVoice, mergedDoNotUse } = applyContactToVoice({
      voice: { enabled: true, profile: { do_not_use: ["lotfan"] } },
      contact,
    });

    expect(mergedDoNotUse).toEqual(["lotfan", "ba ehteram"]);
    expect(effectiveVoice?.profile?.do_not_use).toEqual(["lotfan", "ba ehteram"]);
  });

  it("applies offsets and clamps to 0..1", () => {
    const contact: ContactSnapshot = {
      id: "c1",
      display_name: "Sara",
      style_offsets: { emoji_rate_offset: -30 },
    };

    const { effectiveVoice } = applyContactToVoice({
      voice: { enabled: true, profile: { emoji_rate: 0.1 } },
      contact,
    });

    // 0.1 - 0.3 => clamp to 0
    expect(effectiveVoice?.profile?.emoji_rate).toBe(0);
  });

  it("summary reflects large offsets", () => {
    const contact: ContactSnapshot = {
      id: "c1",
      display_name: "Sara",
      style_offsets: { formality_offset: 15, emoji_rate_offset: -15 },
    };

    expect(styleAppliedSummary(contact)).toContain("More formal");
    expect(styleAppliedSummary(contact)).toContain("Less emoji");
  });
});