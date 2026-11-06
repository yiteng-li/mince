// Photo Log (Gold): identify foods and portions in a meal photo the app uploaded to meal-photos/<uid>/.
import { caller, HttpError, json, requireGold, serve, str, takeQuota } from "../_shared/http.ts";
import { type Item, itemsSchema, structured } from "../_shared/claude.ts";
import { matchItems } from "../_shared/match.ts";
import { encodeBase64 } from "jsr:@std/encoding@1/base64";

export default serve(async (req, body) => {
  const { user, db } = await caller(req);
  const path = str(body.path, 200);
  if (!path || !path.startsWith(`${user.id}/`) || path.includes("..")) throw new HttpError(400, "Bad photo path.");
  await requireGold(db);
  await takeQuota(user.id, "photo");

  const { data: blob, error } = await db.storage.from("meal-photos").download(path);
  if (error || !blob) throw new HttpError(404, "Photo not found.");
  if (blob.size > 5 * 1024 * 1024) throw new HttpError(413, "Photo is too large.");
  const media = blob.type === "image/png" ? "image/png" : "image/jpeg";
  const data = encodeBase64(new Uint8Array(await blob.arrayBuffer()));

  try {
    const result = await structured<{ items: Item[]; suggestions: Item[] }>({
      system:
        "You estimate what is on a plate for a nutrition diary. List each distinct food or drink you can see with its edible weight in grams, " +
        "judged from plate size, utensils and typical portions. Split mixed dishes into their main components only when they are visibly separate. " +
        "In `suggestions`, list easy-to-miss extras this kind of dish usually contains but the photo can't show (cooking oil, butter, dressing, sugar), " +
        "with typical amounts. If the photo shows no food, return empty lists.",
      content: [
        { type: "image", source: { type: "base64", media_type: media, data } },
        { type: "text", text: "What's in this meal?" },
      ],
      schema: itemsSchema,
    });
    return json({ items: await matchItems(db, result.items), suggestions: await matchItems(db, result.suggestions) });
  } finally {
    await db.storage.from("meal-photos").remove([path]); // photos are only kept long enough to analyse
  }
});
