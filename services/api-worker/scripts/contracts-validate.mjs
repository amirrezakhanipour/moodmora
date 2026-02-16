import fs from "fs";
import path from "path";
import Ajv2020 from "ajv/dist/2020.js";

function readJson(p) {
  return JSON.parse(fs.readFileSync(p, "utf8"));
}

function listJsonFiles(dir) {
  return fs
    .readdirSync(dir)
    .filter((f) => f.endsWith(".json"))
    .map((f) => path.join(dir, f));
}

const repoRoot = path.resolve(process.cwd(), "..", "..");
const schemasDir = path.join(repoRoot, "packages", "contracts", "schemas");
const examplesDir = path.join(repoRoot, "packages", "contracts", "examples");

const ajv = new Ajv2020({ allErrors: true, strict: false });

// Load all schemas
for (const file of listJsonFiles(schemasDir)) {
  const schema = readJson(file);
  ajv.addSchema(schema, schema.$id);
}

function validateAgainst(schemaId, payload, label) {
  const validate = ajv.getSchema(schemaId);
  if (!validate) {
    console.error(`❌ Missing schema in AJV: ${schemaId}`);
    process.exit(1);
  }
  const ok = validate(payload);
  if (!ok) {
    console.error(`❌ Validation failed: ${label} against ${schemaId}`);
    console.error(validate.errors);
    process.exit(1);
  }
  console.log(`✅ OK: ${label} -> ${schemaId}`);
}

function validateFile(schemaId, fileName) {
  const p = path.join(examplesDir, fileName);
  const payload = readJson(p);
  validateAgainst(schemaId, payload, fileName);
  return payload;
}

// 1) Requests
validateFile("moodmora://schemas/improve.request.schema.json", "improve.request.sample.json");
validateFile("moodmora://schemas/reply.request.schema.json", "reply.request.sample.json");

// 2) Improve response: envelope + data
{
  const env = validateFile("moodmora://schemas/envelope.schema.json", "improve.response.sample.json");
  validateAgainst("moodmora://schemas/improve.response.schema.json", env.data, "improve.response.sample.json (data)");
}

// 3) Reply response: envelope + data
{
  const env = validateFile("moodmora://schemas/envelope.schema.json", "reply.response.sample.json");
  validateAgainst("moodmora://schemas/reply.response.schema.json", env.data, "reply.response.sample.json (data)");
}

// 4) Error response: envelope + error object
{
  const env = validateFile("moodmora://schemas/envelope.schema.json", "error.response.sample.json");
  validateAgainst("moodmora://schemas/error.schema.json", env.error, "error.response.sample.json (error)");
}

console.log("🎉 All contract samples validated successfully.");
