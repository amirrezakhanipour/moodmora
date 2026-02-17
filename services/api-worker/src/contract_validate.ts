// services/api-worker/src/contract_validate.ts
import type Ajv from "ajv";
import type { ValidateFunction } from "ajv";

type ValidateResult =
  | { ok: true }
  | { ok: false; errors: unknown; schema_id: string; data_preview: unknown };

function isNodeRuntime(): boolean {
  // Workers: `process` is typically undefined.
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const p = (globalThis as any).process;
  return Boolean(p && p.versions && p.versions.node);
}

/**
 * Contract validation is a DEV/TEST helper.
 * We must never run AJV compilation inside the Worker runtime,
 * because it relies on codegen that is disallowed in this context.
 */
function shouldValidateContracts(): boolean {
  if (!isNodeRuntime()) return false;
  // Allow enabling explicitly in Node (tests/local tooling)
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const env = (globalThis as any).process?.env as Record<string, string | undefined> | undefined;
  return (env?.MOODMORA_VALIDATE_CONTRACTS ?? "0") === "1";
}

let cached:
  | {
      ajv: Ajv;
      validateEnvelope: ValidateFunction;
      envelopeId: string;
    }
  | null = null;

async function findSchemasDir(): Promise<string | null> {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const env = (globalThis as any).process?.env as Record<string, string | undefined> | undefined;
  const explicit = env?.MOODMORA_SCHEMAS_DIR?.trim();
  if (explicit) return explicit;

  const pathMod = await import("node:path");
  const urlMod = await import("node:url");
  const fsMod = await import("node:fs/promises");

  let dir = pathMod.dirname(urlMod.fileURLToPath(import.meta.url));

  for (let i = 0; i < 10; i++) {
    const candidate = pathMod.resolve(dir, "..", "..", "..", "packages", "contracts", "schemas");
    try {
      const st = await fsMod.stat(candidate);
      if (st.isDirectory()) return candidate;
    } catch {
      // keep walking up
    }
    const parent = pathMod.resolve(dir, "..");
    if (parent === dir) break;
    dir = parent;
  }

  return null;
}

async function loadAllSchemasFromPackagesContracts(): Promise<any[]> {
  const fsMod = await import("node:fs/promises");
  const pathMod = await import("node:path");

  const schemasDir = await findSchemasDir();
  if (!schemasDir) return [];

  const entries = await fsMod.readdir(schemasDir, { withFileTypes: true });
  const jsonFiles = entries
    .filter((e) => e.isFile() && e.name.toLowerCase().endsWith(".json"))
    .map((e) => pathMod.join(schemasDir, e.name));

  const loaded: any[] = [];
  for (const fp of jsonFiles) {
    const raw = await fsMod.readFile(fp, "utf-8");
    loaded.push(JSON.parse(raw));
  }
  return loaded;
}

export async function validateEnvelopeContract(envelope: unknown): Promise<ValidateResult> {
  if (!shouldValidateContracts()) return { ok: true };

  if (!cached) {
    const AjvMod = await import("ajv");
    const ajv = new AjvMod.default({ allErrors: true, strict: false });

    const schemas = await loadAllSchemasFromPackagesContracts();
    for (const s of schemas) {
      if (s && typeof s === "object" && typeof s.$id === "string") {
        ajv.addSchema(s, s.$id);
      }
    }

    const envelopeId = "moodmora://schemas/envelope.schema.json";
    const validateEnvelope = ajv.getSchema(envelopeId) as ValidateFunction | undefined;
    if (!validateEnvelope) {
      return { ok: true }; // don't break runtime because of contracts
    }

    cached = { ajv: ajv as unknown as Ajv, validateEnvelope, envelopeId };
  }

  const ok = cached.validateEnvelope(envelope) as boolean;
  if (ok) return { ok: true };

  return {
    ok: false,
    errors: cached.validateEnvelope.errors ?? null,
    schema_id: cached.envelopeId,
    data_preview: envelope,
  };
}
