// services/api-worker/src/risk/score.ts
import { RISK_SIGNALS, type RiskSignal } from "./signals";

export type RiskLevel = "green" | "yellow" | "red";

export type RiskResult = {
  level: RiskLevel;
  score: number; // 0..100
  reasons: string[]; // keep <=3
  hard_mode_recommended: boolean;
};

function clamp(n: number, min: number, max: number): number {
  return Math.max(min, Math.min(max, n));
}

function uniq(arr: string[]): string[] {
  return Array.from(new Set(arr));
}

function baseLevelFromScore(score: number): RiskLevel {
  if (score >= 60) return "red";
  if (score >= 30) return "yellow";
  return "green";
}

function matchSignals(text: string, signals: RiskSignal[]) {
  const matches: { signal: RiskSignal }[] = [];
  for (const s of signals) {
    if (s.pattern.test(text)) matches.push({ signal: s });
  }
  return matches;
}

function bumpAtLeast(current: RiskLevel, target: RiskLevel): RiskLevel {
  const rank: Record<RiskLevel, number> = { green: 0, yellow: 1, red: 2 };
  return rank[current] >= rank[target] ? current : target;
}

export function scoreRisk(text: string): RiskResult {
  const input = (text ?? "").toString();
  if (!input.trim()) {
    return { level: "green", score: 0, reasons: [], hard_mode_recommended: false };
  }

  const matches = matchSignals(input, RISK_SIGNALS);

  const raw = matches.reduce((acc, m) => acc + (m.signal.weight || 0), 0);
  const score = clamp(raw, 0, 100);

  const reasons = uniq(
    matches
      .sort((a, b) => (b.signal.weight ?? 0) - (a.signal.weight ?? 0))
      .map((m) => m.signal.reason)
  ).slice(0, 3);

  let level = baseLevelFromScore(score);

  // Human-friendly overrides
  if (reasons.includes("insults_or_namecalling")) {
    level = bumpAtLeast(level, "yellow");
  }
  if (reasons.includes("sexual_explicit") || reasons.includes("sexual_profanity_or_slur")) {
    level = bumpAtLeast(level, "red");
  }
  if (reasons.includes("threats_or_ultimatums")) {
    level = bumpAtLeast(level, "red");
  }

  const hard_mode_recommended =
    level === "red" || matches.some((m) => Boolean(m.signal.hard_mode_hint));

  return { level, score, reasons, hard_mode_recommended };
}