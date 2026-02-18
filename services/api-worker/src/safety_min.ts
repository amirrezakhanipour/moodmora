// services/api-worker/src/safety_min.ts
export type SafetyAction = "allow" | "block";

export type SafetyResult = {
  action: SafetyAction;
  reasons: string[];
};

// super-minimal MVP gate (Phase 4 will replace this with Risk Radar)

// --- Hard blocks ---
const SELF_HARM_PATTERNS: RegExp[] = [
  /\b(khodkoshi|khod koshi|khodam ro mikosham|mikosham khodam ro)\b/i,
  /\b(suicide|kill myself|end my life|self harm|self-harm)\b/i,
];

const VIOLENCE_PATTERNS: RegExp[] = [
  /\b(mikoshamet|to ro mikosham|mikosham to ro)\b/i,
  /\b(kill you|murder you|shoot you)\b/i,
];

// Underage / minor signals (hard block)
const UNDERAGE_PATTERNS: RegExp[] = [
  /\b(im|i\s*am|i'?m)\s*(1[0-7])\b/i, // I'm 17
  /\b(i\s*am|im|i'?m)\s*under\s*18\b/i,
  /\b(under\s*18|minor|underage)\b/i,
  /\b(1[0-7])\s*(years?\s*old|yo)\b/i, // 17 years old
  /\b(1[0-7])\s*sal(e|eh)?\b/i, // 17 sale
  /\b(dabirestan|high\s*school)\b/i,
];

// --- Soft redirects (allow, but add guidance reasons) ---
const PRESSURE_COERCION_PATTERNS: RegExp[] = [
  /\b(if\s+you\s+don'?t|unless\s+you)\b/i,
  /\b(you\s+owe\s+me|prove\s+you\s+love\s+me)\b/i,
  /\b(send\s+me\s+nudes?|nudes?|sext)\b/i,
  /\b(pressur(e|ing)|coerc(e|ion)|blackmail)\b/i,
  /\b(majboor(et)?\s*mikonam|majboori|bede\s*be\s*man)\b/i,
];

const EXPLICIT_SEXUAL_PATTERNS: RegExp[] = [
  /\b(sex|seks|hook\s*up|one\s*night\s*stand)\b/i,
  /\b(nudes?|naked|porn|blowjob|oral|anal)\b/i,
  /\b(les|lakh?t|lokat|aks\s*lakh?t)\b/i,
];

function matchesAny(text: string, patterns: RegExp[]): boolean {
  for (const re of patterns) {
    if (re.test(text)) return true;
  }
  return false;
}

export function classifyInput(text: string): SafetyResult {
  const t = (text ?? "").toString();

  const reasons: string[] = [];

  // hard blocks first
  if (matchesAny(t, SELF_HARM_PATTERNS)) reasons.push("self_harm_signal");
  if (matchesAny(t, VIOLENCE_PATTERNS)) reasons.push("violence_signal");
  if (matchesAny(t, UNDERAGE_PATTERNS)) reasons.push("underage_signal");

  if (reasons.includes("underage_signal")) {
    return { action: "block", reasons };
  }

  if (reasons.includes("self_harm_signal") || reasons.includes("violence_signal")) {
    return { action: "block", reasons };
  }

  // soft redirects (allow)
  if (matchesAny(t, PRESSURE_COERCION_PATTERNS)) reasons.push("consent_redirect");
  if (matchesAny(t, EXPLICIT_SEXUAL_PATTERNS)) reasons.push("sfw_redirect");

  return { action: "allow", reasons };
}
