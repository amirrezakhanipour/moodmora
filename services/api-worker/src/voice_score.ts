// services/api-worker/src/voice_score.ts
import type { Suggestion } from "./types";
import type { VoiceInput } from "./prompt_builder";

function clamp01(n: number): number {
  return Math.max(0, Math.min(1, n));
}

function clampInt(n: number, min: number, max: number): number {
  return Math.max(min, Math.min(max, Math.round(n)));
}

// Rough emoji detector (good enough for score heuristic)
function countEmojis(s: string): number {
  try {
    // Extended_Pictographic exists in modern JS engines
    const m = s.match(/\p{Extended_Pictographic}/gu);
    return m ? m.length : 0;
  } catch {
    // Fallback: naive (won't catch all)
    const m = s.match(/[\u2600-\u27BF\uD83C-\uDBFF\uDC00-\uDFFF]/g);
    return m ? m.length : 0;
  }
}

function countWords(s: string): number {
  const t = (s ?? "").trim();
  if (!t) return 0;
  return t.split(/\s+/).filter(Boolean).length;
}

function containsPhrase(text: string, phrase: string): boolean {
  const t = (text ?? "").toLowerCase();
  const p = (phrase ?? "").toLowerCase().trim();
  if (!p) return false;
  return t.includes(p);
}

function avg(numbers: number[]): number {
  if (numbers.length === 0) return 0;
  return numbers.reduce((a, b) => a + b, 0) / numbers.length;
}

function measuredBrevity(avgWords: number): number {
  // Map avgWords -> 0..1 (higher means shorter)
  if (avgWords <= 8) return 1.0;
  if (avgWords <= 14) return 0.7;
  if (avgWords <= 22) return 0.4;
  return 0.2;
}

function measuredEmojiRate(avgEmojiPerMsg: number): number {
  // Map 0..2 emojis/msg -> 0..1
  return clamp01(avgEmojiPerMsg / 2);
}

function tokenHitRate(texts: string[], tokens: string[]): number {
  if (texts.length === 0) return 0;
  const hits = texts.reduce((acc, t) => {
    const low = t.toLowerCase();
    const any = tokens.some((k) => low.includes(k));
    return acc + (any ? 1 : 0);
  }, 0);
  return clamp01(hits / texts.length);
}

export function computeVoiceMatchScore(voice: VoiceInput | undefined, suggestions: Suggestion[]): number {
  // Contract requires an int. If voice is off/not present, return a neutral baseline.
  if (!voice || voice.enabled !== true) return 50;

  const profile = voice.profile ?? {};
  const targetWarmth = typeof profile.warmth === "number" ? clamp01(profile.warmth) : undefined;
  const targetDirectness = typeof profile.directness === "number" ? clamp01(profile.directness) : undefined;
  const targetBrevity = typeof profile.brevity === "number" ? clamp01(profile.brevity) : undefined;
  const targetFormality = typeof profile.formality === "number" ? clamp01(profile.formality) : undefined;
  const targetEmoji = typeof profile.emoji_rate === "number" ? clamp01(profile.emoji_rate) : undefined;
  const doNotUse = Array.isArray(profile.do_not_use) ? profile.do_not_use.filter((x) => typeof x === "string") : [];

  const texts = suggestions.map((s) => String(s?.text ?? ""));

  // --- measurements ---
  const wordCounts = texts.map(countWords);
  const avgWords = avg(wordCounts);
  const brevityNorm = measuredBrevity(avgWords);

  const emojiCounts = texts.map(countEmojis);
  const avgEmoji = avg(emojiCounts);
  const emojiNorm = measuredEmojiRate(avgEmoji);

  // proxies (simple + language-agnostic-ish)
  const formalTokens = ["please", "kindly", "regards", "sincerely", "dear", "with respect", "ba ehteram", "lotfan"];
  const hedgeTokens = ["maybe", "if you want", "up to you", "no worries if", "whenever you can", "agar ok", "age ok", "har vaght"];
  const warmTokens = ["thanks", "thank you", "appreciate", "khoshal", "mersi", "mamnoon", "dost", "❤️", "🙏"];

  const formalHit = tokenHitRate(texts, formalTokens);
  const hedgeHit = tokenHitRate(texts, hedgeTokens);
  const warmHit = tokenHitRate(texts, warmTokens);

  const directnessNorm = clamp01(1 - hedgeHit);

  // --- components (0..1) ---
  const compBrevity = targetBrevity === undefined ? 0.7 : clamp01(1 - Math.abs(brevityNorm - targetBrevity));
  const compEmoji = targetEmoji === undefined ? 0.7 : clamp01(1 - Math.abs(emojiNorm - targetEmoji));
  const compFormality = targetFormality === undefined ? 0.7 : clamp01(1 - Math.abs(formalHit - targetFormality));
  const compDirectness = targetDirectness === undefined ? 0.7 : clamp01(1 - Math.abs(directnessNorm - targetDirectness));
  const compWarmth = targetWarmth === undefined ? 0.7 : clamp01(1 - Math.abs(warmHit - targetWarmth));

  // Weighted average -> 0..1
  const score01 =
    compBrevity * 0.25 +
    compEmoji * 0.15 +
    compFormality * 0.20 +
    compDirectness * 0.20 +
    compWarmth * 0.20;

  let score = score01 * 100;

  // do_not_use penalty (strong)
  if (doNotUse.length > 0) {
    let penalty = 0;
    for (const phrase of doNotUse) {
      if (typeof phrase !== "string") continue;
      const p = phrase.trim();
      if (!p) continue;
      const hit = texts.some((t) => containsPhrase(t, p));
      if (hit) penalty += 20;
      if (penalty >= 60) break;
    }
    score -= penalty;
  }

  return clampInt(score, 0, 100);
}