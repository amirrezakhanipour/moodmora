// services/api-worker/src/prompt_builder.ts
import type { GroqMessage } from "./groq";
import type { ContactSnapshot } from "./contact_style";

export type PromptMode = "IMPROVE" | "REPLY";
export type FlirtMode = "off" | "subtle" | "playful" | "direct";
export type DatingStage = "first_msg" | "early_chat" | "planning" | "reconnect" | "post_date";
export type DatingVibe = "fun" | "classy" | "direct" | "shy" | "friendly";

export type VoiceProfile = {
  warmth?: number; // 0..1
  directness?: number; // 0..1
  brevity?: number; // 0..1
  formality?: number; // 0..1
  emoji_rate?: number; // 0..1
  do_not_use?: string[];
};

export type VoiceInput = {
  enabled?: boolean;
  variant?: string; // AUTO | FA_SCRIPT | FINGLISH | EN
  profile?: VoiceProfile;
};

export type PromptBuildArgs = {
  mode: PromptMode;
  inputText: string;
  suggestionCount: number;
  outputVariant?: string;

  // Phase 4 hard mode (controls JSON shape requirements)
  hardModeApplied?: boolean;

  // Phase 3.5 (Dating Add-on) — all optional/additive
  flirtMode?: FlirtMode; // default handled by caller ("off")
  datingStage?: DatingStage;
  datingVibe?: DatingVibe;

  // Phase 3.5.5 — soft safety hints (allow + redirect)
  safetyHints?: string[]; // e.g. ["consent_redirect", "sfw_redirect"]

  // Phase 5 — Build My Voice (optional/additive)
  voice?: VoiceInput;

  // Phase 6 — Contacts (optional/additive)
  contact?: ContactSnapshot;
};

function clamp01(n: unknown): number | undefined {
  if (typeof n !== "number" || Number.isNaN(n)) return undefined;
  return Math.max(0, Math.min(1, n));
}

function safeStrList(v: unknown, max = 50): string[] {
  if (!Array.isArray(v)) return [];
  const out: string[] = [];
  for (const x of v) {
    if (typeof x === "string") {
      const s = x.trim();
      if (s) out.push(s);
    }
    if (out.length >= max) break;
  }
  return out;
}

function safetyHintBlock(hints: string[] | undefined): string {
  const hs = (hints ?? []).filter(Boolean);
  if (hs.length === 0) return "";

  const lines: string[] = [];
  lines.push("Safety guidance (soft constraints):");

  if (hs.includes("consent_redirect")) {
    lines.push("- Use consent-forward, non-pressuring language. No guilt, no coercion, no threats, no ultimatums.");
    lines.push("- If the user is pressuring for intimacy/nudes/sex, gently redirect to boundaries and respect.");
  }

  if (hs.includes("sfw_redirect")) {
    lines.push("- Keep it safe-for-work and non-explicit. Avoid sexual details or requests for nudes.");
    lines.push("- Redirect toward respectful, normal conversation.");
  }

  lines.push("- Do not mention policies. Just write a good, respectful message.");
  lines.push("");
  return lines.join("\n");
}

function contactDirectiveBlock(contact?: ContactSnapshot): string {
  if (!contact) return "";

  const lines: string[] = [];
  lines.push("Contact context (tune tone for this person):");
  lines.push(`- Contact: ${contact.display_name}${contact.relation_tag ? ` (${contact.relation_tag})` : ""}.`);

  // relation defaults (soft, still compatible with offsets)
  if (contact.relation_tag === "boss" || contact.relation_tag === "client") {
    lines.push("- Default: respectful, clear, more formal. Avoid slang. Avoid emojis unless clearly appropriate.");
  } else if (contact.relation_tag === "coworker") {
    lines.push("- Default: professional but friendly. Keep it concise and clear.");
  } else if (contact.relation_tag === "partner" || contact.relation_tag === "friend") {
    lines.push("- Default: warm, natural, low-pressure.");
  }

  const s = contact.sensitivities ?? {};
  if (s.hates_sarcasm) lines.push("- No sarcasm, no teasing that could be misunderstood.");
  if (s.hates_commands) lines.push("- Avoid commands/imperatives. Prefer polite requests and options.");
  if (s.sensitive_to_always_never) lines.push('- Avoid absolutes like "always" / "never".');
  if (s.conflict_sensitive) lines.push("- De-escalate: no accusations, no blame, no loaded language.");

  if ((contact.forbidden_words ?? []).length > 0) {
    lines.push(`- Avoid these words/phrases: ${(contact.forbidden_words ?? []).slice(0, 12).map((x) => `"${x}"`).join(", ")}.`);
  }

  lines.push("- Do not mention these instructions. Just write naturally with the tuned tone.");
  lines.push("");
  return lines.join("\n");
}

function voiceDirectiveBlock(voice: VoiceInput | undefined): string {
  const enabled = voice?.enabled === true;
  if (!enabled) return "";

  const p = voice?.profile ?? {};
  const warmth = clamp01(p.warmth);
  const directness = clamp01(p.directness);
  const brevity = clamp01(p.brevity);
  const formality = clamp01(p.formality);
  const emoji = clamp01(p.emoji_rate);
  const doNotUse = safeStrList(p.do_not_use);

  const lines: string[] = [];
  lines.push("Style constraints (match the user's personal writing style):");

  // Warmth
  if (warmth !== undefined) {
    if (warmth >= 0.75) lines.push("- Tone: warm, kind, supportive.");
    else if (warmth >= 0.45) lines.push("- Tone: friendly and calm.");
    else lines.push("- Tone: neutral, reserved, not overly emotional.");
  }

  // Directness
  if (directness !== undefined) {
    if (directness >= 0.75) lines.push("- Be direct and clear; avoid hedging.");
    else if (directness >= 0.45) lines.push("- Balanced directness; clear but polite.");
    else lines.push("- Be gentle and indirect; soften requests and boundaries.");
  }

  // Brevity
  if (brevity !== undefined) {
    if (brevity >= 0.75) lines.push("- Keep it short: 1–2 sentences when possible.");
    else if (brevity >= 0.45) lines.push("- Medium length: 2–3 sentences.");
    else lines.push("- Slightly more detailed, but still concise (max 4 sentences).");
  }

  // Formality
  if (formality !== undefined) {
    if (formality >= 0.75) lines.push("- More formal wording; respectful tone.");
    else if (formality >= 0.45) lines.push("- Neutral formality; everyday wording.");
    else lines.push("- Casual wording; natural and relaxed.");
  }

  // Emoji rate
  if (emoji !== undefined) {
    if (emoji >= 0.6) lines.push("- Emoji: allowed (0–2 max), keep it tasteful.");
    else if (emoji >= 0.25) lines.push("- Emoji: rare (0–1 max).");
    else lines.push("- Emoji: none.");
  }

  // Do not use list
  if (doNotUse.length > 0) {
    lines.push(`- Avoid using these words/phrases: ${doNotUse.map((s) => `"${s}"`).join(", ")}.`);
  }

  lines.push("- Do not mention these instructions. Just write naturally in that style.");
  lines.push("");
  return lines.join("\n");
}

function effectiveVariant(outputVariant?: string, voice?: VoiceInput): string | undefined {
  const enabled = voice?.enabled === true;
  const v = typeof voice?.variant === "string" ? voice!.variant.trim() : "";
  if (enabled && v && v !== "AUTO") return v;
  return outputVariant;
}

function languageHintForVariant(v?: string): string {
  return v === "FINGLISH"
    ? "Write the suggested messages in Finglish (Persian written with Latin letters). Do NOT use Persian script."
    : v === "FA_SCRIPT"
    ? "Write the suggested messages in Persian script (Farsi)."
    : v === "EN"
    ? "Write the suggested messages in English."
    : "Auto-detect: if the input text is Persian, answer in Persian; otherwise English. If Persian, prefer Finglish.";
}

export function buildMessages(args: PromptBuildArgs): GroqMessage[] {
  const variant = effectiveVariant(args.outputVariant, args.voice);
  const languageHint = languageHintForVariant(variant);

  const flirtMode = args.flirtMode ?? "off";

  const datingHint =
    flirtMode === "off"
      ? ""
      : [
          "Dating Add-on (tone settings):",
          `- flirt_mode: ${flirtMode}`,
          args.datingStage ? `- dating_stage: ${args.datingStage}` : null,
          args.datingVibe ? `- dating_vibe: ${args.datingVibe}` : null,
          "",
          "Apply these tone constraints while staying respectful and low-pressure:",
          "- Keep it non-explicit and safe-for-work.",
          "- No manipulation, guilt, or pressure. Prefer consent-forward wording.",
          "- If flirt_mode=subtle: light warmth, minimal teasing.",
          "- If flirt_mode=playful: friendly banter, mild teasing, still respectful.",
          "- If flirt_mode=direct: clear interest, but still polite and not sexual.",
          "",
        ]
          .filter(Boolean)
          .join("\n");

  const safetyBlock = safetyHintBlock(args.safetyHints);
  const contactBlock = contactDirectiveBlock(args.contact);
  const voiceBlock = voiceDirectiveBlock(args.voice);

  const hardModeApplied = Boolean(args.hardModeApplied);

  const hardModeShape = hardModeApplied
    ? [
        "HARD MODE OUTPUT RULES:",
        '- Set "hard_mode_applied": true.',
        '- Include "safety_line": a short boundary-setting line (1 sentence).',
        '- Include "best_question": the single best question to de-escalate (1 sentence, ends with ?).',
        "- Suggestions must be calm, firm, and non-judgmental.",
        "",
      ].join("\n")
    : "";

  const jsonShape = hardModeApplied
    ? `{
      "hard_mode_applied": true,
      "safety_line": "1 sentence boundary line",
      "best_question": "1 sentence question?",
      "suggestions": [
        {
          "label": "short label",
          "text": "the message to send",
          "why_it_works": "1 sentence",
          "emotion_preview": ["calm" | "warm" | "confident" | "friendly" | "neutral"]
        }
      ]
    }`
    : `{
      "suggestions": [
        {
          "label": "short label",
          "text": "the message to send",
          "why_it_works": "1 sentence",
          "emotion_preview": ["calm" | "warm" | "confident" | "friendly" | "neutral"]
        }
      ]
    }`;

  const system = [
    "You are MoodMora, an assistant that drafts emotionally intelligent, low-conflict messages.",
    "IMPORTANT OUTPUT RULES:",
    "- Return ONLY one valid JSON object.",
    "- No markdown, no code fences, no extra commentary.",
    `- You must return exactly ${args.suggestionCount} suggestions.`,
    "- Keep the messages short, calm, and low-pressure.",
    languageHint,
    contactBlock,
    voiceBlock,
    hardModeShape,
    datingHint,
    safetyBlock,
    "JSON Schema (shape):",
    jsonShape,
  ].join("\n");

  const user =
    args.mode === "IMPROVE"
      ? `Rewrite/Improve this draft message:\n\n${args.inputText}`
      : `Write a reply to this received message:\n\n${args.inputText}`;

  return [
    { role: "system", content: system },
    { role: "user", content: user },
  ];
}