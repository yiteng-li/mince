// Voice Log / Siri (Gold): "two eggs and a slice of toast" -> foods with gram amounts.
import { caller, HttpError, json, requireGold, serve, str, takeQuota } from "../_shared/http.ts";
import { type Item, itemsSchema, structured } from "../_shared/claude.ts";
import { matchItems } from "../_shared/match.ts";

serve(async (req, body) => {
  const { user, db } = await caller(req);
  const text = str(body.text, 2000);
  if (!text) throw new HttpError(400, "Say or type what you ate.");
  await requireGold(db);
  await takeQuota(user.id, "voice");

  const result = await structured<{ items: Item[]; suggestions: Item[] }>({
    system:
      "Turn a spoken description of a meal into diary items. One item per food or drink, with the edible weight in grams " +
      "(convert counts and household measures using typical sizes, e.g. one large egg = 50 g, one slice of bread = 30 g). " +
      "Ignore words that aren't food. Leave `suggestions` empty.",
    content: [{ type: "text", text: `<meal>${text}</meal>` }],
    schema: itemsSchema,
    effort: "low",
  });
  return json({ items: await matchItems(db, result.items) });
});
