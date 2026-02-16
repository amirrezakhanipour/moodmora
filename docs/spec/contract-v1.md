\# MoodMora Contract v1 (Freeze)

contract\_version: 1.0.0



\## Endpoints

1\) GET /health

2\) POST /v1/improve

3\) POST /v1/reply



\## Response Envelope (for ALL endpoints)

status: "ok" | "blocked" | "error"

request\_id: string

timestamp\_ms: int

data: object | null

error: object | null

meta.contract\_version: "1.0.0"



\## POST /v1/improve

\### Request fields

\- input.draft\_text (required, string)

\- input.context (optional, string)

\- input.output\_variant (optional: AUTO | FA\_SCRIPT | FINGLISH | EN)

\- input.hard\_mode (optional, boolean)

\- input.contact\_id (optional, string)



\### Response data

\- mode: "IMPROVE"

\- suggestions: array (3 items normally, 2 items in hard\_mode)

\- risk: { level: green|yellow|red, score: 0..100, reasons: string\[] }

\- voice\_match\_score: 0..100



\## POST /v1/reply

\### Request fields

\- input.received\_text (required, string)

\- input.context (optional, string)

\- input.output\_variant (optional: AUTO | FA\_SCRIPT | FINGLISH | EN)

\- input.hard\_mode (optional, boolean)

\- input.contact\_id (optional, string)



\### Response data

\- mode: "REPLY"

\- suggestions: array (3 items normally, 2 items in hard\_mode)

\- risk: { level: green|yellow|red, score: 0..100, reasons: string\[] }

\- voice\_match\_score: 0..100



\## GET /health

\### Response data

\- service: "api-worker"

\- ok: true



