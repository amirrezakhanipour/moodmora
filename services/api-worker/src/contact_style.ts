// services/api-worker/src/contact_style.ts

import type { VoiceInput, VoiceProfile } from "./prompt_builder";

export type ContactRelationTag = "boss" | "coworker" | "friend" | "family" | "partner" | "client" | "other";

export type ContactStyleOffsets = {
  warmth_offset?: number; // -30..+30
  directness_offset?: number; // -30..+30
  brevity_offset?: number; // -30..+30
  formality_offset?: number; // -30..+30
  emoji_rate_offset?: number; // -30..+30
};

export type ContactSensitivities = {
  hates_sarcasm?: boolean;
  hates_commands?: boolean;
  sensitive_to_always_never?: boolean;
  conflict_sensitive?: boolean;
};

export type ContactSnapshot = {
  id: string;
  display_name: string;
  relation_tag?: ContactRelationTag;
  style_offsets?: ContactStyleOffsets;
  sensitivities?: ContactSensitivities;
  forbidden_words?: string[];
};

function clamp01(n: number): number {
  return Math.max(0, Math.min(1, n));
}

function clampInt(n: unknown, min: number, max: number): number | undefined {
  if (typeof n !== "number" || Number.isNaN(n)) return undefined;
  const x = Math.round(n);
  return Math.max(min, Math.min(max, x));
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

function mergeUnique(a: string[], b: string[], max = 50): string[] {
  const seen = new Set<string>();
  const out: string[] = [];
  for (const x of [...a, ...b]) {
    const s = (x ?? "").toString().trim();
    if (!s) continue;
    const key = s.toLowerCase();
    if (seen.has(key)) continue;
    seen.add(key);
    out.push(s);
    if (out.length >= max) break;
  }
  return out;
}

function baseOrMid(n: unknown): number {
  if (typeof n !== "number" || Number.isNaN(n)) return 0.5;
  return clamp01(n);
}

function deltaFromOffsetInt(off?: number): number {
  // -30..+30 -> -0.30..+0.30
  if (typeof off !== "number" || Number.isNaN(off)) return 0;
  return Math.max(-30, Math.min(30, Math.round(off))) / 100;
}

export function parseContact(body: any): ContactSnapshot | undefined {
  const c = body?.contact;
  if (!c || typeof c !== "object") return undefined;

  const id = typeof c.id === "string" ? c.id.trim() : "";
  const display = typeof c.display_name === "string" ? c.display_name.trim() : "";
  if (!id || !display) return undefined;

  const relation = typeof c.relation_tag === "string" ? (c.relation_tag.trim() as ContactRelationTag) : undefined;

  const so = c.style_offsets;
  const style_offsets: ContactStyleOffsets | undefined =
    so && typeof so === "object"
      ? {
          warmth_offset: clampInt(so.warmth_offset, -30, 30),
          directness_offset: clampInt(so.directness_offset, -30, 30),
          brevity_offset: clampInt(so.brevity_offset, -30, 30),
          formality_offset: clampInt(so.formality_offset, -30, 30),
          emoji_rate_offset: clampInt(so.emoji_rate_offset, -30, 30),
        }
      : undefined;

  const sens = c.sensitivities;
  const sensitivities: ContactSensitivities | undefined =
    sens && typeof sens === "object"
      ? {
          hates_sarcasm: sens.hates_sarcasm === true,
          hates_commands: sens.hates_commands === true,
          sensitive_to_always_never: sens.sensitive_to_always_never === true,
          conflict_sensitive: sens.conflict_sensitive === true,
        }
      : undefined;

  const forbidden_words = safeStrList(c.forbidden_words);

  return {
    id,
    display_name: display,
    relation_tag: relation,
    style_offsets,
    sensitivities,
    forbidden_words,
  };
}

export function applyContactToVoice(args: {
  voice?: VoiceInput;
  contact?: ContactSnapshot;
}): { effectiveVoice?: VoiceInput; mergedDoNotUse: string[] } {
  const voice = args.voice;
  const contact = args.contact;

  const baseProfile: VoiceProfile = voice?.profile ?? {};
  const baseDoNotUse = safeStrList(baseProfile.do_not_use);

  const contactForbidden = safeStrList(contact?.forbidden_words);
  const mergedDoNotUse = mergeUnique(baseDoNotUse, contactForbidden, 50);

  // If neither voice nor contact exists, return undefined (no directives)
  if (!voice && !contact) return { effectiveVoice: undefined, mergedDoNotUse: [] };

  const enabled = voice?.enabled === true; // keep semantics: only "voice enabled" means scoring is meaningful
  const variant = typeof voice?.variant === "string" ? voice!.variant!.trim() : undefined;

  const so = contact?.style_offsets ?? {};

  const warmth = clamp01(baseOrMid(baseProfile.warmth) + deltaFromOffsetInt(so.warmth_offset));
  const directness = clamp01(baseOrMid(baseProfile.directness) + deltaFromOffsetInt(so.directness_offset));
  const brevity = clamp01(baseOrMid(baseProfile.brevity) + deltaFromOffsetInt(so.brevity_offset));
  const formality = clamp01(baseOrMid(baseProfile.formality) + deltaFromOffsetInt(so.formality_offset));
  const emoji_rate = clamp01(baseOrMid(baseProfile.emoji_rate) + deltaFromOffsetInt(so.emoji_rate_offset));

  const effectiveProfile: VoiceProfile = {
    warmth,
    directness,
    brevity,
    formality,
    emoji_rate,
    do_not_use: mergedDoNotUse,
  };

  const effectiveVoice: VoiceInput = {
    enabled,
    variant,
    profile: effectiveProfile,
  };

  return { effectiveVoice, mergedDoNotUse };
}

export function styleAppliedSummary(contact?: ContactSnapshot): string | undefined {
  if (!contact) return undefined;

  const bits: string[] = [];
  const so = contact.style_offsets ?? {};

  const pushIf = (cond: boolean, s: string) => {
    if (cond) bits.push(s);
  };

  const w = so.warmth_offset ?? 0;
  const d = so.directness_offset ?? 0;
  const b = so.brevity_offset ?? 0;
  const f = so.formality_offset ?? 0;
  const e = so.emoji_rate_offset ?? 0;

  pushIf(f >= 10, "More formal");
  pushIf(f <= -10, "More casual");

  pushIf(w >= 10, "Warmer");
  pushIf(w <= -10, "More neutral");

  pushIf(d >= 10, "More direct");
  pushIf(d <= -10, "Softer");

  pushIf(b >= 10, "Shorter");
  pushIf(b <= -10, "More detailed");

  pushIf(e >= 10, "More emoji");
  pushIf(e <= -10, "Less emoji");

  // Relation tag defaults (soft)
  if (bits.length === 0 && contact.relation_tag) {
    if (contact.relation_tag === "boss" || contact.relation_tag === "client") return "Respectful, clear";
    if (contact.relation_tag === "partner" || contact.relation_tag === "friend") return "Warm, relaxed";
  }

  if (bits.length === 0) return undefined;
  return bits.slice(0, 4).join(", ");
}