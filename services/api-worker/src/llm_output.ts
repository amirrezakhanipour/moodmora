// services/api-worker/src/llm_output.ts
import Ajv from "ajv";
import type { Suggestion } from "./types";

const ajv = new Ajv({
  allErrors: true,
  strict: false,
});

function schemaForCount(count: number) {
  return {
    type: "object",
    additionalProperties: false,
    required: ["suggestions"],
    properties: {
      suggestions: {
        type: "array",
        minItems: count,
        maxItems: count,
        items: {
          type: "object",
          additionalProperties: false,
          required: ["label", "text", "why_it_works", "emotion_preview"],
          properties: {
            label: { type: "string", minLength: 1, maxLength: 60 },
            text: { type: "string", minLength: 1, maxLength: 900 },
            why_it_works: { type: "string", minLength: 1, maxLength: 220 },
            emotion_preview: {
              type: "array",
              minItems: 1,
              maxItems: 3,
              items: { type: "string", enum: ["calm", "warm", "confident", "friendly", "neutral"] },
            },
          },
        },
      },
    },
  } as const;
}

function tryExtractJSONObject(raw: string): string | null {
  const s = raw.indexOf("{");
  const e = raw.lastIndexOf("}");
  if (s === -1 || e === -1 || e <= s) return null;
  return raw.slice(s, e + 1);
}

export type ParseValidateResult =
  | { ok: true; parsed: { suggestions: Suggestion[] }; extracted_from_raw: boolean }
  | {
      ok: false;
      error: "PARSE_ERROR" | "SCHEMA_ERROR";
      extracted_from_raw: boolean;
      details: unknown;
      raw_preview: string;
    };

export function parseAndValidateLlmOutput(raw: string, count: number): ParseValidateResult {
  let extracted = false;
  let parsed: any;

  try {
    parsed = JSON.parse(raw);
  } catch {
    const maybe = tryExtractJSONObject(raw);
    if (!maybe) {
      return { ok: false, error: "PARSE_ERROR", extracted_from_raw: false, details: null, raw_preview: raw.slice(0, 240) };
    }
    extracted = true;
    try {
      parsed = JSON.parse(maybe);
    } catch {
      return { ok: false, error: "PARSE_ERROR", extracted_from_raw: true, details: null, raw_preview: raw.slice(0, 240) };
    }
  }

  const validate = ajv.compile(schemaForCount(count));
  const ok = validate(parsed);

  if (!ok) {
    return {
      ok: false,
      error: "SCHEMA_ERROR",
      extracted_from_raw: extracted,
      details: validate.errors ?? null,
      raw_preview: raw.slice(0, 240),
    };
  }

  return { ok: true, parsed: parsed as { suggestions: Suggestion[] }, extracted_from_raw: extracted };
}
