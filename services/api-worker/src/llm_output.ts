// services/api-worker/src/llm_output.ts
import type { Suggestion } from "./types";

type ValidationIssue = {
  path: string;
  message: string;
};

export type LlmParsedOutput = {
  suggestions: Suggestion[];
  // Phase 4 Hard Mode (optional unless expected)
  hard_mode_applied?: boolean;
  safety_line?: string;
  best_question?: string;
};

function preview(s: string, n = 240): string {
  const t = String(s ?? "");
  return t.length <= n ? t : t.slice(0, n) + "…";
}

function isPlainObject(x: unknown): x is Record<string, unknown> {
  return typeof x === "object" && x !== null && !Array.isArray(x);
}

function hasOnlyKeys(obj: Record<string, unknown>, allowed: string[]): boolean {
  for (const k of Object.keys(obj)) {
    if (!allowed.includes(k)) return false;
  }
  return true;
}

function extractFirstJSONObject(raw: string): string | null {
  const s = String(raw ?? "");
  const start = s.indexOf("{");
  if (start < 0) return null;

  let depth = 0;
  for (let i = start; i < s.length; i++) {
    const ch = s[i];
    if (ch === "{") depth++;
    else if (ch === "}") depth--;

    if (depth === 0) return s.slice(start, i + 1);
  }
  return null;
}

function validateParsedOutput(
  parsed: unknown,
  count: number,
  opts: { requireHardModeFields: boolean }
): { ok: true } | { ok: false; errors: ValidationIssue[] } {
  const errors: ValidationIssue[] = [];

  if (!isPlainObject(parsed)) {
    return { ok: false, errors: [{ path: "", message: "root must be an object" }] };
  }

  const allowedRootKeys = ["suggestions", "hard_mode_applied", "safety_line", "best_question"];
  if (!hasOnlyKeys(parsed, allowedRootKeys)) {
    errors.push({
      path: "",
      message: `additional properties are not allowed (only: ${allowedRootKeys.join(", ")})`,
    });
  }

  const suggestions = (parsed as any).suggestions;
  if (!Array.isArray(suggestions)) {
    errors.push({ path: "/suggestions", message: "must be an array" });
    return { ok: false, errors };
  }

  if (suggestions.length !== count) {
    errors.push({ path: "/suggestions", message: `must have exactly ${count} items` });
  }

  for (let i = 0; i < suggestions.length; i++) {
    const s = suggestions[i];
    const base = `/suggestions/${i}`;

    if (!isPlainObject(s)) {
      errors.push({ path: base, message: "must be an object" });
      continue;
    }

    if (!hasOnlyKeys(s, ["label", "text", "why_it_works", "emotion_preview"])) {
      errors.push({ path: base, message: "additional properties are not allowed" });
    }

    const label = (s as any).label;
    const text = (s as any).text;
    const why = (s as any).why_it_works;
    const emo = (s as any).emotion_preview;

    if (typeof label !== "string" || !label.trim()) errors.push({ path: `${base}/label`, message: "must be a non-empty string" });
    if (typeof text !== "string" || !text.trim()) errors.push({ path: `${base}/text`, message: "must be a non-empty string" });
    if (typeof why !== "string" || !why.trim()) errors.push({ path: `${base}/why_it_works`, message: "must be a non-empty string" });

    if (!Array.isArray(emo)) {
      errors.push({ path: `${base}/emotion_preview`, message: "must be an array of strings" });
    } else {
      const emoStrings = emo.map((x: any) => String(x)).filter((x: string) => x.trim().length > 0);
      if (emoStrings.length === 0) errors.push({ path: `${base}/emotion_preview`, message: "must contain at least 1 non-empty string" });
    }
  }

  // Hard mode fields validation (only when required by caller)
  if (opts.requireHardModeFields) {
    const hm = (parsed as any).hard_mode_applied;
    const safetyLine = (parsed as any).safety_line;
    const bestQ = (parsed as any).best_question;

    if (hm !== true) {
      errors.push({ path: "/hard_mode_applied", message: "must be true in hard mode" });
    }
    if (typeof safetyLine !== "string" || !safetyLine.trim()) {
      errors.push({ path: "/safety_line", message: "must be a non-empty string in hard mode" });
    }
    if (typeof bestQ !== "string" || !bestQ.trim()) {
      errors.push({ path: "/best_question", message: "must be a non-empty string in hard mode" });
    }
  } else {
    // If present, still type-check lightly
    const hm = (parsed as any).hard_mode_applied;
    if (hm !== undefined && typeof hm !== "boolean") {
      errors.push({ path: "/hard_mode_applied", message: "must be a boolean" });
    }
    const safetyLine = (parsed as any).safety_line;
    if (safetyLine !== undefined && (typeof safetyLine !== "string" || !safetyLine.trim())) {
      errors.push({ path: "/safety_line", message: "must be a non-empty string" });
    }
    const bestQ = (parsed as any).best_question;
    if (bestQ !== undefined && (typeof bestQ !== "string" || !bestQ.trim())) {
      errors.push({ path: "/best_question", message: "must be a non-empty string" });
    }
  }

  return errors.length ? { ok: false, errors } : { ok: true };
}

export type ParseValidateResult =
  | { ok: true; parsed: LlmParsedOutput; extracted_from_raw: boolean }
  | {
      ok: false;
      error: "PARSE_ERROR" | "SCHEMA_ERROR";
      extracted_from_raw: boolean;
      details: unknown;
      raw_preview: string;
    };

export function parseAndValidateLlmOutput(
  raw: string,
  count: number,
  opts?: { requireHardModeFields?: boolean }
): ParseValidateResult {
  let extracted = false;
  let parsed: any;

  try {
    parsed = JSON.parse(raw);
  } catch {
    const maybe = extractFirstJSONObject(raw);
    if (!maybe) {
      return {
        ok: false,
        error: "PARSE_ERROR",
        extracted_from_raw: false,
        details: null,
        raw_preview: preview(raw),
      };
    }
    extracted = true;
    try {
      parsed = JSON.parse(maybe);
    } catch {
      return {
        ok: false,
        error: "PARSE_ERROR",
        extracted_from_raw: true,
        details: null,
        raw_preview: preview(raw),
      };
    }
  }

  const v = validateParsedOutput(parsed, count, { requireHardModeFields: Boolean(opts?.requireHardModeFields) });
  if (!v.ok) {
    return {
      ok: false,
      error: "SCHEMA_ERROR",
      extracted_from_raw: extracted,
      details: v.errors,
      raw_preview: preview(raw),
    };
  }

  return {
    ok: true,
    parsed: parsed as LlmParsedOutput,
    extracted_from_raw: extracted,
  };
}