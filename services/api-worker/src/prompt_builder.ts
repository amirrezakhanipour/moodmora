// services/api-worker/src/prompt_builder.ts
import type { GroqMessage } from "./groq";

export type PromptMode = "IMPROVE" | "REPLY";

export type FlirtMode = "off" | "subtle" | "playful" | "direct";

export type DatingStage = "first_msg" | "early_chat" | "planning" | "reconnect" | "post_date";

export type DatingVibe = "fun" | "classy" | "direct" | "shy" | "friendly";

export type PromptBuildArgs = {
  mode: PromptMode;
  inputText: string;
  suggestionCount: number;
  outputVariant?: string;

  // Phase 3.5 (Dating Add-on) — all optional/additive
  flirtMode?: FlirtMode; // default handled by caller ("off")
  datingStage?: DatingStage;
  datingVibe?: DatingVibe;

  // Phase 3.5.5 — soft safety hints (allow + redirect)
  safetyHints?: string[]; // e.g. ["consent_redirect", "sfw_redirect"]
};

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

export function buildMessages(args: PromptBuildArgs): GroqMessage[] {
  const languageHint =
    args.outputVariant === "FINGLISH"
      ? "Write the suggested messages in Finglish (Persian written with Latin letters). Do NOT use Persian script."
      : args.outputVariant === "FA_SCRIPT"
      ? "Write the suggested messages in Persian script (Farsi)."
      : args.outputVariant === "EN"
      ? "Write the suggested messages in English."
      : "Auto-detect: if the input text is Persian, answer in Persian; otherwise English. If Persian, prefer Finglish.";

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

  const system = [
    "You are MoodMora, an assistant that drafts emotionally intelligent, low-conflict messages.",
    "IMPORTANT OUTPUT RULES:",
    "- Return ONLY one valid JSON object.",
    "- No markdown, no code fences, no extra commentary.",
    `- You must return exactly ${args.suggestionCount} suggestions.`,
    "- Keep the messages short, calm, and low-pressure.",
    languageHint,
    datingHint,
    safetyBlock,
    "JSON Schema (shape):",
    `{
      "suggestions": [
        {
          "label": "short label",
          "text": "the message to send",
          "why_it_works": "1 sentence",
          "emotion_preview": ["calm" | "warm" | "confident" | "friendly" | "neutral"]
        }
      ]
    }`,
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
