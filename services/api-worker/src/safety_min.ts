// services/api-worker/src/safety_min.ts
export type SafetyAction = "allow" | "block";

export type SafetyResult = {
  action: SafetyAction;
  reasons: string[];
};

// super-minimal MVP gate (Phase 4 will replace this with Risk Radar)
const SELF_HARM_PATTERNS: RegExp[] = [
  /\b(khodkoshi|khod koshi|khodam ro mikosham|mikosham khodam ro)\b/i,
  /\b(suicide|kill myself|end my life|self harm|self-harm)\b/i,
];

const VIOLENCE_PATTERNS: RegExp[] = [
  /\b(mikoshamet|to ro mikosham|mikosham to ro)\b/i,
  /\b(kill you|murder you|shoot you)\b/i,
];

export function classifyInput(text: string): SafetyResult {
  const t = (text ?? "").toString();

  const reasons: string[] = [];

  for (const re of SELF_HARM_PATTERNS) {
    if (re.test(t)) {
      reasons.push("self_harm_signal");
      break;
    }
  }

  for (const re of VIOLENCE_PATTERNS) {
    if (re.test(t)) {
      reasons.push("violence_signal");
      break;
    }
  }

  if (reasons.length > 0) {
    return { action: "block", reasons };
  }

  return { action: "allow", reasons: [] };
}
