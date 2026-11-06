// Coach (Gold): 3-5 short suggestions from the user's own averages vs their targets. Sends numbers only, no names.
import { caller, HttpError, json, requireGold, serve, takeQuota } from "../_shared/http.ts";
import { structured } from "../_shared/claude.ts";

export default serve(async (req, body) => {
  const { user, db } = await caller(req);
  const days = Math.min(Math.max(Number(body.days) || 7, 3), 30);
  await requireGold(db);
  await takeQuota(user.id, "coach");

  const to = new Date();
  const from = new Date(to.getTime() - (days - 1) * 86_400_000);
  const iso = (d: Date) => d.toISOString().slice(0, 10);
  const [{ data: rows, error }, { data: profile }, { data: targets }] = await Promise.all([
    db.rpc("nutrient_totals", { p_from: iso(from), p_to: iso(to) }),
    db.from("profiles").select("sex, date_of_birth, goal_kg_per_week, macro_mode, diet_preset, activity_level").eq("id", user.id).single(),
    db.from("nutrient_targets").select("nutrient_key, min_amount, max_amount"),
  ]);
  if (error) throw error;

  const totals = (rows ?? []) as { day: string; nutrient_key: string; amount: number }[];
  const loggedDays = new Set(totals.filter((r) => r.nutrient_key === "energy" && r.amount > 0).map((r) => r.day)).size;
  if (loggedDays < 2) throw new HttpError(422, "Log at least two days first.");
  const avg: Record<string, number> = {};
  for (const r of totals) avg[r.nutrient_key] = (avg[r.nutrient_key] ?? 0) + r.amount / loggedDays;

  const result = await structured<{ tips: string[] }>({
    system:
      "You are a supportive nutrition coach in a food-tracking app. From the user's daily averages, give 3 to 5 specific, practical suggestions " +
      "(one sentence each, under 25 words), naming foods where useful. Use typical adult reference intakes when no custom target is given. " +
      "Don't diagnose or mention medical conditions; suggest seeing a professional only for clearly extreme numbers.",
    content: [{ type: "text", text: JSON.stringify({ days_logged: loggedDays, profile, custom_targets: targets ?? [], daily_averages: avg }) }],
    schema: {
      type: "object", additionalProperties: false, required: ["tips"],
      properties: { tips: { type: "array", items: { type: "string" } } },
    },
    effort: "low",
  });
  return json({ tips: result.tips.slice(0, 5) });
});
