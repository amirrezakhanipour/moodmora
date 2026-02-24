// services/api-worker/src/risk/precheck.ts
import { scoreRisk } from "./score";

export type PrecheckDecision =
  | { action: "allow"; risk: ReturnType<typeof scoreRisk> }
  | { action: "block"; risk: ReturnType<typeof scoreRisk>; message: string; details: any };

export function precheckText(text: string): PrecheckDecision {
  const risk = scoreRisk(text);

  // v1 severe rule: very high escalation -> block before LLM
  const severe = risk.level === "red" && risk.score >= 80;

  if (severe) {
    return {
      action: "block",
      risk,
      message: "Message looks highly escalated. Hard stop before generating replies.",
      details: {
        reasons: risk.reasons,
        score: risk.score,
        level: risk.level,
      },
    };
  }

  return { action: "allow", risk };
}