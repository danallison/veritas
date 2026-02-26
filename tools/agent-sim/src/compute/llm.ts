import type { ComputationSpec } from "./simulated.js";

/**
 * Real LLM computation: calls the specified provider API.
 * Requires ANTHROPIC_API_KEY or OPENAI_API_KEY env var.
 */
export async function llmCompute(
  spec: ComputationSpec
): Promise<Uint8Array> {
  if (spec.provider === "anthropic") {
    return anthropicCompute(spec);
  } else if (spec.provider === "openai") {
    return openaiCompute(spec);
  } else {
    throw new Error(`Unknown provider: ${spec.provider}`);
  }
}

async function anthropicCompute(spec: ComputationSpec): Promise<Uint8Array> {
  const apiKey = process.env.ANTHROPIC_API_KEY;
  if (!apiKey) throw new Error("ANTHROPIC_API_KEY env var required");

  const body = {
    model: spec.model,
    max_tokens: spec.max_tokens ?? 1024,
    temperature: spec.temperature,
    system: spec.system_prompt,
    messages: [{ role: "user", content: spec.user_prompt }],
  };

  const response = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "x-api-key": apiKey,
      "anthropic-version": "2023-06-01",
    },
    body: JSON.stringify(body),
  });

  if (!response.ok) {
    const text = await response.text();
    throw new Error(`Anthropic API error (${response.status}): ${text}`);
  }

  const result = (await response.json()) as {
    content: Array<{ type: string; text: string }>;
  };
  const text =
    result.content.find((c) => c.type === "text")?.text ?? "";
  return new TextEncoder().encode(text);
}

async function openaiCompute(spec: ComputationSpec): Promise<Uint8Array> {
  const apiKey = process.env.OPENAI_API_KEY;
  if (!apiKey) throw new Error("OPENAI_API_KEY env var required");

  const body = {
    model: spec.model,
    max_tokens: spec.max_tokens ?? 1024,
    temperature: spec.temperature,
    messages: [
      { role: "system", content: spec.system_prompt },
      { role: "user", content: spec.user_prompt },
    ],
  };

  const response = await fetch("https://api.openai.com/v1/chat/completions", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${apiKey}`,
    },
    body: JSON.stringify(body),
  });

  if (!response.ok) {
    const text = await response.text();
    throw new Error(`OpenAI API error (${response.status}): ${text}`);
  }

  const result = (await response.json()) as {
    choices: Array<{ message: { content: string } }>;
  };
  const text = result.choices[0]?.message?.content ?? "";
  return new TextEncoder().encode(text);
}
