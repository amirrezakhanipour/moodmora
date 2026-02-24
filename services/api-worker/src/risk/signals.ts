// services/api-worker/src/risk/signals.ts

export type RiskSignal = {
  id: string;
  reason: string;
  // weight contributes to score (0..100 total)
  weight: number;
  // if true, this signal is considered a hint to recommend hard mode
  hard_mode_hint?: boolean;
  // pattern to detect
  pattern: RegExp;
};

export const RISK_SIGNALS: RiskSignal[] = [
  // --- Conflict / aggression ---
  {
    id: "insult_basic",
    reason: "insults_or_namecalling",
    weight: 20,
    hard_mode_hint: true,
    pattern: /\b(stupid|idiot|moron|loser|pathetic)\b/i,
  },
  {
    id: "accusation_you_always",
    reason: "accusations_or_blame",
    weight: 15,
    hard_mode_hint: true,
    pattern: /\byou (always|never)\b/i,
  },
  {
    id: "absolute_words",
    reason: "absolutes_escalate_conflict",
    weight: 10,
    pattern: /\b(always|never|everyone|no one|nothing|everything)\b/i,
  },
  {
    id: "threat_or_ultimatum",
    reason: "threats_or_ultimatums",
    weight: 35,
    hard_mode_hint: true,
    pattern: /\b(or else|you'll regret|i swear|i will ruin|i'll ruin|i'll make sure|you are done)\b/i,
  },
  {
    id: "excessive_punctuation",
    reason: "high_emotional_intensity",
    weight: 8,
    pattern: /[!?]{3,}/,
  },
  {
    id: "all_caps_shouting",
    reason: "shouting_all_caps",
    weight: 10,
    hard_mode_hint: true,
    pattern: /\b[A-Z]{6,}\b/,
  },
  {
    id: "jealousy_possessive",
    reason: "possessive_or_controlling_tone",
    weight: 12,
    hard_mode_hint: true,
    pattern: /\b(you can't|you are not allowed|don't talk to|i forbid)\b/i,
  },
  {
    id: "high_stakes_work",
    reason: "high_stakes_context",
    weight: 10,
    pattern: /\b(hr|human resources|boss|manager|lawsuit|legal|court)\b/i,
  },

  // --- Sexual explicit / NSFW ---
  {
    id: "sexual_explicit",
    reason: "sexual_explicit",
    weight: 60,
    hard_mode_hint: true,
    pattern: /\b(fuck|fucking|blowjob|bj|nudes?|naked|pussy|dick|cock|cum|sex|horny)\b/i,
  },
  {
    id: "sexual_slur",
    reason: "sexual_profanity_or_slur",
    weight: 15,
    hard_mode_hint: true,
    pattern: /\b(bitch|slut|whore)\b/i,
  },
];