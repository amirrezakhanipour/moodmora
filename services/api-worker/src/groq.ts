// services/api-worker/src/groq.ts
type GroqRole = "system" | "user" | "assistant";

export type GroqMessage = {
  role: GroqRole;
  content: string;
};

export type GroqChatOptions = {
  apiKey: string;
  model: string;
  messages: GroqMessage[];
  temperature?: number;
  maxTokens?: number;
  timeoutMs?: number;
};

type GroqChatResponse = {
  choices?: Array<{
    message?: { content?: string | null };
  }>;
  usage?: unknown;
};

function withTimeout(ms: number, signal?: AbortSignal): { controller: AbortController; signal: AbortSignal } {
  const controller = new AbortController();

  const timeout = setTimeout(() => controller.abort(), ms);
  const anySignal = signal;

  if (anySignal) {
    if (anySignal.aborted) controller.abort();
    else anySignal.addEventListener("abort", () => controller.abort(), { once: true });
  }

  controller.signal.addEventListener("abort", () => clearTimeout(timeout), { once: true });

  return { controller, signal: controller.signal };
}

export async function groqChatCompletion(opts: GroqChatOptions): Promise<{
  content: string;
  usage: unknown;
}> {
  const timeoutMs = Math.max(1000, opts.timeoutMs ?? 20000);
  const { signal } = withTimeout(timeoutMs);

  const res = await fetch("https://api.groq.com/openai/v1/chat/completions", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      authorization: `Bearer ${opts.apiKey}`,
    },
    body: JSON.stringify({
      model: opts.model,
      messages: opts.messages,
      temperature: opts.temperature ?? 0.4,
      max_tokens: opts.maxTokens ?? 700,
    }),
    signal,
  });

  if (!res.ok) {
    const txt = await res.text().catch(() => "");
    throw new Error(`GROQ_HTTP_${res.status}: ${txt || res.statusText}`);
  }

  const data = (await res.json()) as GroqChatResponse;

  const content = data?.choices?.[0]?.message?.content ?? "";
  return { content, usage: data?.usage ?? null };
}
