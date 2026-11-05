// Matches free-text food names to the food database, as the caller (RLS: shared foods + their own).
import type { SupabaseClient } from "@supabase/supabase-js";
import type { Item } from "./claude.ts";

export async function matchFood(db: SupabaseClient, query: string): Promise<string | null> {
  const { data, error } = await db.rpc("search_foods", { q: query, lim: 1, off: 0 });
  if (error) throw error;
  return (data as { id: string }[] | null)?.[0]?.id ?? null;
}

export async function matchItems(db: SupabaseClient, items: Item[]) {
  return await Promise.all(items.slice(0, 25).map(async (i) => ({
    name: i.name,
    grams: Math.max(1, Math.min(i.grams, 5000)),
    note: i.note,
    food_id: await matchFood(db, i.search_query || i.name),
  })));
}
