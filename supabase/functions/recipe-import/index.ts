// Recipe Importer (mince+): a URL (schema.org Recipe JSON-LD, else page text) or pasted text -> recipe draft with matched ingredients.
import { caller, HttpError, json, requirePlus, serve, str, takeQuota } from "../_shared/http.ts";
import { structured } from "../_shared/claude.ts";
import { matchFood } from "../_shared/match.ts";
import { fetchPage, findRecipe, recipeText, safeURL, visibleText } from "../_shared/recipe.ts";

type Parsed = { name: string; servings: number; instructions: string; ingredients: { line: string; name: string; grams: number; search_query: string }[] };

export default serve(async (req, body) => {
  const { user, db } = await caller(req);
  const url = str(body.url, 2000);
  const pasted = str(body.text, 40_000);
  if (!url && !pasted) throw new HttpError(400, "Add a link or paste a recipe.");
  await requirePlus(db);
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
