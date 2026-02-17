// services/api-worker/src/contract_validate.ts
import Ajv from "ajv";

type ValidateResult =
  | { ok: true }
  | { ok: false; errors: unknown; schema_id: string; data_preview: unknown };

function isNodeRuntime(): boolean {
  // Workers/workerd: `process` usually undefined
  // Node/Vitest: present with versions.node
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const p = (globalThis as any).process;
  return Boolean(p && p.versions && p.versions.node);
}

let cached:
  | {
      ajv: Ajv;
      validateEnvelope: (data: unknown) => boolean;
      envelopeId: string;
    }
  | null = null;

let warnedOnce = false;

async function existsDir(pathStr: string): Promise<boolean> {
  const fsMod = await import("node:fs/promises");
  try {
    const st = await fsMod.stat(pathStr);
    return st.isDirectory();
  } catch {
    return false;
  }
}

async function findSchemasDir(): Promise<string | null> {
  const pathMod = await import("node:path");
  const urlMod = await import("node:url");

  // 1) explicit override (best for CI/edge cases)
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const env = ((globalThis as any).process?.env ?? {}) as Record<string, string | undefined>;
  const override = (env.MOODMORA_SCHEMAS_DIR || env.CONTRACTS_SCHEMAS_DIR || "").trim();
  if (override && (await existsDir(override))) return override;

  // 2) try from process.cwd()
  const cwd = (env.PWD || "").trim() || (globalThis as any).process?.cwd?.() || "";
  if (cwd) {
    const candidatesFromCwd = [
      // if cwd is repo root
      pathMod.resolve(cwd, "packages", "contracts", "schemas"),
      // if cwd is services/api-worker
      pathMod.resolve(cwd, "..", "..", "packages", "contracts", "schemas"),
      // if cwd is services/api-worker/src
      pathMod.resolve(cwd, "..", "..", "..", "packages", "contracts", "schemas"),
    ];

    for (const c of candidatesFromCwd) {
      if (await existsDir(c)) return c;
    }
  }

  // 3) fallback: walk up from this file location
  let dir = pathMod.dirname(urlMod.fileURLToPath(import.meta.url));
  for (let i = 0; i < 12; i++) {
    const candidate = pathMod.resolve(dir, "..", "..", "..", "packages", "contracts", "schemas");
    if (await existsDir(candidate)) return candidate;

    const parent = pathMod.resolve(dir, "..");
    if (parent === dir) break;
    dir = parent;
  }

  return null;
}

async function loadSchemas(): Promise<any[] | null> {
  const fsMod = await import("node:fs/promises");
  const pathMod = await import("node:path");

  const schemasDir = await findSchemasDir();
  if (!schemasDir) return null;

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

async function bootAjv(): Promise<NonNullable<typeof cached> | null> {
  const schemas = await loadSchemas();
  if (!schemas) return null;

  const ajv = new Ajv({ allErrors: true, strict: false });

  for (const s of schemas) {
    if (s && typeof s === "object" && typeof s.$id === "string") {
      ajv.addSchema(s, s.$id);
    }
  }

  const envelopeId = "moodmora://schemas/envelope.schema.json";
  const validateEnvelope = ajv.getSchema(envelopeId);
  if (!validateEnvelope) {
    throw new Error(
      `CONTRACT_BOOT_ERROR: could not find schema ${envelopeId}. Check $id in packages/contracts/schemas/envelope.schema.json`
    );
  }

  return { ajv, validateEnvelope, envelopeId };
}

export async function validateEnvelopeContract(envelope: unknown): Promise<ValidateResult> {
  // only validate in Node runtime (tests/CI). In Workers, no-op.
  if (!isNodeRuntime()) return { ok: true };

  if (!cached) {
    try {
      const booted = await bootAjv();
      if (!booted) {
        if (!warnedOnce) {
          warnedOnce = true;
          // eslint-disable-next-line no-console
          console.warn(
            "[contract_validate] schemas dir not found; skipping contract validation (set MOODMORA_SCHEMAS_DIR to enable)."
          );
        }
        return { ok: true };
      }
      cached = booted;
    } catch (e) {
      if (!warnedOnce) {
        warnedOnce = true;
        // eslint-disable-next-line no-console
        console.warn(
          `[contract_validate] failed to boot AJV; skipping contract validation. err=${String(
            (e as any)?.message ?? e
          )}`
        );
      }
      return { ok: true };
    }
  }

  const ok = cached.validateEnvelope(envelope);
  if (ok) return { ok: true };

  return {
    ok: false,
    errors: cached.validateEnvelope.errors ?? null,
    schema_id: cached.envelopeId,
    data_preview: envelope,
  };
}
