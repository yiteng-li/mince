// Recipe Importer (Gold): a URL (schema.org Recipe JSON-LD, else page text) or pasted text -> recipe draft with matched ingredients.
import { caller, HttpError, json, requireGold, serve, str, takeQuota } from "../_shared/http.ts";
import { structured } from "../_shared/claude.ts";
import { matchFood } from "../_shared/match.ts";

const MAX_PAGE = 2 * 1024 * 1024;

/** Only public http(s) hosts: no IP literals, localhost or internal names (avoids reaching private networks). */
function safeURL(raw: string): URL {
  let u: URL;
  try { u = new URL(raw); } catch { throw new HttpError(400, "That doesn't look like a link."); }
  const h = u.hostname.toLowerCase();
  const ipLike = /^[\d.]+$/.test(h) || h.includes(":");
  if (!["http:", "https:"].includes(u.protocol) || ipLike || !h.includes(".") || h.endsWith(".local") || h.endsWith(".internal") || h === "localhost") {
    throw new HttpError(400, "Use a public recipe link.");
  }
  return u;
}

async function fetchPage(url: URL): Promise<string> {
  const res = await fetch(url, { redirect: "follow", signal: AbortSignal.timeout(10_000), headers: { "user-agent": "mince-recipe-import/1.0" } });
  if (!res.ok) throw new HttpError(422, "That site wouldn't share the recipe. Paste the text instead.");
  safeURL(res.url); // re-check after redirects
  const buf = await res.arrayBuffer();
  if (buf.byteLength > MAX_PAGE) throw new HttpError(413, "That page is too large.");
  return new TextDecoder().decode(buf);
}

type JsonLd = Record<string, unknown>;

/** Finds a schema.org Recipe object in the page's JSON-LD, if any. */
function findRecipe(html: string): JsonLd | null {
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

function recipeText(r: JsonLd): string {
  const lines = (v: unknown): string[] =>
    Array.isArray(v) ? v.flatMap((x) => typeof x === "string" ? [x] : x && typeof x === "object" ? lines((x as JsonLd).text ?? (x as JsonLd).itemListElement) : []) : typeof v === "string" ? [v] : [];
  return [`Title: ${r.name ?? ""}`, `Yield: ${JSON.stringify(r.recipeYield ?? "")}`, "Ingredients:", ...lines(r.recipeIngredient), "Instructions:", ...lines(r.recipeInstructions)].join("\n");
}

function visibleText(html: string): string {
  return html.replace(/<(script|style|noscript)[\s\S]*?<\/\1>/gi, " ").replace(/<[^>]+>/g, " ").replace(/\s+/g, " ").slice(0, 40_000);
}

type Parsed = { name: string; servings: number; instructions: string; ingredients: { line: string; name: string; grams: number; search_query: string }[] };

serve(async (req, body) => {
  const { user, db } = await caller(req);
  const url = str(body.url, 2000);
  const pasted = str(body.text, 40_000);
  if (!url && !pasted) throw new HttpError(400, "Add a link or paste a recipe.");
  await requireGold(db);
  await takeQuota(user.id, "recipe_import");

  let source = pasted ?? "";
  if (url) {
    const html = await fetchPage(safeURL(url));
    const r = findRecipe(html);
    source = r ? recipeText(r) : visibleText(html);
  }

  const parsed = await structured<Parsed>({
    system:
      "Extract a recipe for a nutrition app. Keep each ingredient's original line. Give its weight in grams for the whole recipe, converting " +
      "volumes and counts with typical densities and sizes. `search_query` is a generic food-database search (e.g. 'flour wheat all-purpose'). " +
      "Skip water, salt to taste and garnishes without an amount. `servings` is how many servings it makes (1 if unknown). " +
      "Summarise the method in `instructions` in at most 8 short steps, in your own words.",
    content: [{ type: "text", text: `<recipe>\n${source}\n</recipe>` }],
    schema: {
      type: "object",
      additionalProperties: false,
      required: ["name", "servings", "instructions", "ingredients"],
      properties: {
        name: { type: "string" },
        servings: { type: "number" },
        instructions: { type: "string" },
        ingredients: {
          type: "array",
          items: {
            type: "object",
            additionalProperties: false,
            required: ["line", "name", "grams", "search_query"],
            properties: { line: { type: "string" }, name: { type: "string" }, grams: { type: "number" }, search_query: { type: "string" } },
          },
        },
      },
    },
  });
  if (parsed.ingredients.length === 0) throw new HttpError(422, "No ingredients found. Paste the recipe text instead.");

  const ingredients = await Promise.all(parsed.ingredients.slice(0, 60).map(async (i) => ({
    line: i.line, name: i.name, grams: i.grams > 0 ? i.grams : null, food_id: await matchFood(db, i.search_query || i.name),
  })));
  return json({ name: parsed.name, servings: Math.max(1, parsed.servings || 1), instructions: parsed.instructions, ingredients });
});
