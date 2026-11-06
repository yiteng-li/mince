// Recipe page handling for recipe-import: URL safety, fetching, schema.org Recipe extraction.
import { HttpError } from "./http.ts";

const MAX_PAGE = 2 * 1024 * 1024;

/** Only public http(s) hosts: no IP literals, localhost or internal names (avoids reaching private networks). */
export function safeURL(raw: string): URL {
  let u: URL;
  try { u = new URL(raw); } catch { throw new HttpError(400, "That doesn't look like a link."); }
  const h = u.hostname.toLowerCase();
  const ipLike = /^[\d.]+$/.test(h) || h.includes(":");
  if (!["http:", "https:"].includes(u.protocol) || ipLike || !h.includes(".") || h.endsWith(".local") || h.endsWith(".internal") || h === "localhost") {
    throw new HttpError(400, "Use a public recipe link.");
  }
  return u;
}

export async function fetchPage(url: URL): Promise<string> {
  const res = await fetch(url, { redirect: "follow", signal: AbortSignal.timeout(10_000), headers: { "user-agent": "mince-recipe-import/1.0" } });
  if (!res.ok) throw new HttpError(422, "That site wouldn't share the recipe. Paste the text instead.");
  if (res.url) safeURL(res.url); // re-check where redirects ended up
  const buf = await res.arrayBuffer();
  if (buf.byteLength > MAX_PAGE) throw new HttpError(413, "That page is too large.");
  return new TextDecoder().decode(buf);
}

export type JsonLd = Record<string, unknown>;

/** Finds a schema.org Recipe object in the page's JSON-LD, if any. */
export function findRecipe(html: string): JsonLd | null {
  for (const m of html.matchAll(/<script[^>]+application\/ld\+json[^>]*>([\s\S]*?)<\/script>/gi)) {
    let parsed: unknown;
    try { parsed = JSON.parse(m[1]); } catch { continue; }
    const stack = [parsed];
    while (stack.length) {
      const node = stack.pop();
      if (Array.isArray(node)) { stack.push(...node); continue; }
      if (node && typeof node === "object") {
        const o = node as JsonLd;
        const t = o["@type"];
        if (t === "Recipe" || (Array.isArray(t) && t.includes("Recipe"))) return o;
        if (o["@graph"]) stack.push(o["@graph"]);
      }
    }
  }
  return null;
}

export function recipeText(r: JsonLd): string {
  const lines = (v: unknown): string[] =>
    Array.isArray(v) ? v.flatMap((x) => typeof x === "string" ? [x] : x && typeof x === "object" ? lines((x as JsonLd).text ?? (x as JsonLd).itemListElement) : []) : typeof v === "string" ? [v] : [];
  return [`Title: ${r.name ?? ""}`, `Yield: ${JSON.stringify(r.recipeYield ?? "")}`, "Ingredients:", ...lines(r.recipeIngredient), "Instructions:", ...lines(r.recipeInstructions)].join("\n");
}

export function visibleText(html: string): string {
  return html.replace(/<(script|style|noscript)[\s\S]*?<\/\1>/gi, " ").replace(/<[^>]+>/g, " ").replace(/\s+/g, " ").slice(0, 40_000);
}

