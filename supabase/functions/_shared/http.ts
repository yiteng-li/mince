// Request plumbing shared by every function: auth, Gold check, daily quota, JSON responses.
import { createClient, type SupabaseClient, type User } from "@supabase/supabase-js";

export class HttpError extends Error {
  constructor(public status: number, message: string) {
    super(message);
  }
}

export function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });
}

function env(name: string): string {
  const v = Deno.env.get(name);
  if (!v) throw new Error(`missing env ${name}`);
  return v;
}

/** Service-role client: bypasses RLS. Only for writes the client must never make itself. */
export function admin(): SupabaseClient {
  return createClient(env("SUPABASE_URL"), env("SUPABASE_SERVICE_ROLE_KEY"), { auth: { persistSession: false } });
}

/** The caller, plus a client that acts as them (RLS applies). */
export async function caller(req: Request): Promise<{ user: User; db: SupabaseClient }> {
  const authorization = req.headers.get("Authorization") ?? "";
  const db = createClient(env("SUPABASE_URL"), env("SUPABASE_ANON_KEY"), {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false },
  });
  const { data, error } = await db.auth.getUser(authorization.replace(/^Bearer /, ""));
  if (error || !data.user) throw new HttpError(401, "Sign in again.");
  return { user: data.user, db };
}

export async function requireGold(db: SupabaseClient): Promise<void> {
  const { data, error } = await db.rpc("is_gold");
  if (error) throw error;
  if (data !== true) throw new HttpError(402, "This needs mince Gold.");
}

export const DAILY_LIMITS = { photo: 30, voice: 100, recipe_import: 30, coach: 10 } as const;

/** Counts one paid AI call; refuses past the daily limit. */
export async function takeQuota(userId: string, kind: keyof typeof DAILY_LIMITS): Promise<void> {
  const day = new Date().toISOString().slice(0, 10);
  const svc = admin();
  const { data } = await svc.from("ai_usage").select("count").match({ user_id: userId, day, kind }).maybeSingle();
  const count = data?.count ?? 0;
  if (count >= DAILY_LIMITS[kind]) throw new HttpError(429, "You've hit today's limit for this. It resets tomorrow (UTC).");
  // ponytail: read-then-write can let two simultaneous calls both pass at the limit; an increment RPC fixes that if it matters.
  const { error } = await svc.from("ai_usage").upsert({ user_id: userId, day, kind, count: count + 1 });
  if (error) throw error;
}

/** Wraps a handler: POST only, JSON body, errors mapped to {error} responses. */
export function serve(handler: (req: Request, body: Record<string, unknown>) => Promise<Response>) {
  Deno.serve(async (req) => {
    if (req.method !== "POST") return json({ error: "POST only" }, 405);
    try {
      const body = await req.json().catch(() => ({}));
      return await handler(req, body && typeof body === "object" ? body as Record<string, unknown> : {});
    } catch (e) {
      if (e instanceof HttpError) return json({ error: e.message }, e.status);
      console.error(e instanceof Error ? e.message : e); // never log request bodies: they hold user data
      return json({ error: "Something went wrong. Try again." }, 500);
    }
  });
}

export function str(v: unknown, max: number): string | undefined {
  if (typeof v !== "string") return undefined;
  const t = v.trim();
  return t.length === 0 ? undefined : t.slice(0, max);
}
