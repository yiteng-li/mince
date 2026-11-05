// One structured-output call to Claude. Model and effort are per-call; JSON is schema-constrained.
import Anthropic from "@anthropic-ai/sdk";
import { HttpError } from "./http.ts";

const client = new Anthropic({ apiKey: Deno.env.get("ANTHROPIC_API_KEY"), maxRetries: 2, timeout: 60_000 });
const MODEL = Deno.env.get("CLAUDE_MODEL") ?? "claude-opus-5-5";

type Content = Anthropic.Beta.Messages.BetaContentBlockParam[];

export async function structured<T>(opts: {
  system: string;
  content: Content;
  schema: Record<string, unknown>;
  effort?: "low" | "medium" | "high";
  maxTokens?: number;
}): Promise<T> {
  let response: Anthropic.Beta.Messages.BetaMessage;
  try {
    response = await client.beta.messages.create({
      model: MODEL,
      max_tokens: opts.maxTokens ?? 8000,
      betas: ["server-side-fallback-2026-07-01"],
      fallbacks: "default",
      system: opts.system,
      output_config: { effort: opts.effort ?? "medium", format: { type: "json_schema", schema: opts.schema } },
      messages: [{ role: "user", content: opts.content }],
    });
  } catch (e) {
    if (e instanceof Anthropic.RateLimitError) throw new HttpError(503, "Our AI is busy. Try again in a minute.");
    if (e instanceof Anthropic.BadRequestError) throw new HttpError(400, "That input couldn't be processed.");
    throw e;
  }
  if (response.stop_reason === "refusal") throw new HttpError(422, "We couldn't process that. Try different wording or another photo.");
  if (response.stop_reason === "max_tokens") throw new HttpError(422, "That was too long to process in one go.");
  const text = response.content.flatMap((b) => (b.type === "text" ? [b.text] : [])).join("");
  try {
    return JSON.parse(text) as T;
  } catch {
    throw new HttpError(502, "The AI reply was malformed. Try again.");
  }
}

const itemSchema = {
  type: "object",
  additionalProperties: false,
  required: ["name", "grams", "search_query"],
  properties: {
    name: { type: "string", description: "Short display name, e.g. 'Scrambled eggs'" },
    grams: { type: "number", description: "Estimated edible weight in grams" },
    search_query: { type: "string", description: "Generic food-database search terms, e.g. 'egg scrambled'" },
    note: { type: "string", description: "Optional caveat, e.g. 'portion hard to judge'" },
  },
};

/** JSON schema for a list of foods with gram amounts (photo log and voice log). */
export const itemsSchema = {
  type: "object",
  additionalProperties: false,
  required: ["items", "suggestions"],
  properties: {
    items: { type: "array", items: itemSchema },
    suggestions: { type: "array", items: itemSchema },
  },
};

export type Item = { name: string; grams: number; search_query: string; note?: string };
