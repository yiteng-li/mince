// Test doubles: one fetch stub standing in for Supabase (auth, PostgREST, storage), the Claude API,
// the App Store Server API and recipe websites. Every request is recorded; unknown hosts throw.
import { encodeBase64, } from "jsr:@std/encoding@1/base64";
import { encodeBase64Url } from "jsr:@std/encoding@1/base64url";

export const UID = "00000000-0000-0000-0000-00000000000a";
export const SB = "https://proj.supabase.co";

export type Rec = { method: string; url: URL; body: string; headers: Headers };
export const state = {
  gold: true,
  usageCount: 0 as number | null,
  requests: [] as Rec[],
  claude: (_body: Record<string, unknown>): Record<string, unknown> => message(JSON.stringify({ items: [], suggestions: [] })),
  apple: new Map<string, Record<string, unknown>>(),
  pages: new Map<string, string>(),
  seenEvents: new Set<string>(),
  subscriptionOwner: null as string | null,
  storageFiles: [] as string[],
  totals: [] as Record<string, unknown>[],
};

export function reset() {
  state.gold = true; state.usageCount = 0; state.requests = []; state.apple.clear(); state.pages.clear();
  state.seenEvents.clear(); state.subscriptionOwner = null; state.storageFiles = []; state.totals = [];
  state.claude = () => message(JSON.stringify({ items: [], suggestions: [] }));
}

export function message(text: string, stop_reason = "end_turn") {
  return { id: "msg_test", type: "message", role: "assistant", model: "claude-opus-5-5", stop_reason, stop_sequence: null,
    content: stop_reason === "refusal" ? [] : [{ type: "text", text }], usage: { input_tokens: 10, output_tokens: 10 } };
}

const res = (body: unknown, status = 200, headers: Record<string, string> = {}) =>
  new Response(body === undefined || status === 204 ? null : typeof body === "string" ? body : JSON.stringify(body),
    { status, headers: { "content-type": "application/json", ...headers } });

export function jws(payload: unknown) {
  const b = (o: unknown) => encodeBase64Url(new TextEncoder().encode(JSON.stringify(o)));
  return `${b({ alg: "ES256" })}.${b(payload)}.sig`;
}

async function route(req: Request): Promise<Response> {
  const url = new URL(req.url);
  const body = req.method === "GET" || req.method === "HEAD" ? "" : await req.clone().text();
  state.requests.push({ method: req.method, url, body, headers: req.headers });
  const p = url.pathname;

  if (url.origin === SB) {
    if (p === "/auth/v1/user") {
      return req.headers.get("authorization") === "Bearer good-token"
        ? res({ id: UID, aud: "authenticated", role: "authenticated", email: "t@example.com", app_metadata: {}, user_metadata: {}, created_at: "2026-01-01T00:00:00Z" })
        : res({ code: 401, msg: "invalid JWT" }, 401);
    }
    if (p.startsWith("/auth/v1/admin/users/") && req.method === "DELETE") return res({});
    if (p === "/rest/v1/rpc/is_gold") return res(state.gold);
    if (p === "/rest/v1/rpc/search_foods") {
      const q = JSON.parse(body).q as string;
      return res(q.includes("unknown") ? [] : [{ id: `food-${q.split(" ")[0]}` }]);
    }
    if (p === "/rest/v1/rpc/nutrient_totals") return res(state.totals);
    if (p === "/rest/v1/ai_usage") {
      if (req.method === "GET") {
        const single = (req.headers.get("accept") ?? "").includes("vnd.pgrst.object");
        if (state.usageCount === null) return single ? res({ code: "PGRST116", message: "0 rows" }, 406) : res([]);
        return single ? res({ count: state.usageCount }) : res([{ count: state.usageCount }]);
      }
      return res("", 201);
    }
    if (p === "/rest/v1/profiles") return res({ sex: "female", goal_kg_per_week: -0.25 }, 200);
    if (p === "/rest/v1/nutrient_targets") return res([]);
    if (p === "/rest/v1/subscriptions") {
      if (req.method === "GET") {
        const single = (req.headers.get("accept") ?? "").includes("vnd.pgrst.object");
        if (!state.subscriptionOwner) return single ? res({ code: "PGRST116", message: "0 rows" }, 406) : res([]);
        return single ? res({ user_id: state.subscriptionOwner }) : res([{ user_id: state.subscriptionOwner }]);
      }
      return res("", 201);
    }
    if (p === "/rest/v1/app_store_events") {
      if (req.method === "DELETE") { state.seenEvents.delete(url.searchParams.get("notification_uuid")?.replace("eq.", "") ?? ""); return res("", 204); }
      const id = JSON.parse(body).notification_uuid;
      if (state.seenEvents.has(id)) return res({ code: "23505", message: "duplicate key" }, 409);
      state.seenEvents.add(id);
      return res("", 201);
    }
    if (p.startsWith("/storage/v1/object/list/")) {
      const files = state.storageFiles.map((name) => ({ name, id: name }));
      state.storageFiles = [];
      return res(files);
    }
    if (p.startsWith("/storage/v1/object/meal-photos/") && req.method === "GET") {
      return new Response(new Uint8Array([0xff, 0xd8, 0xff, 0xe0, 1, 2, 3]), { headers: { "content-type": "image/jpeg" } });
    }
    if (p.startsWith("/storage/v1/object/") && req.method === "DELETE") return res([]);
  }
  if (url.host === "api.anthropic.com" && p === "/v1/messages") return res(state.claude(JSON.parse(body)));
  if (url.host === "api.storekit.itunes.apple.com" || url.host === "api.storekit-sandbox.itunes.apple.com") {
    const id = p.split("/").pop()!;
    const t = state.apple.get(`${url.host}:${id}`);
    return t ? res({ signedTransactionInfo: jws(t) }) : res({ errorCode: 4040010 }, 404);
  }
  const page = state.pages.get(url.href);
  if (page !== undefined) {
    const r = new Response(page, { headers: { "content-type": "text/html" } });
    Object.defineProperty(r, "url", { value: url.href }); // real fetch responses carry their final URL
    return r;
  }
  throw new Error(`unexpected request ${req.method} ${req.url}`);
}

export async function setup() {
  const pair = await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"]);
  const pkcs8 = new Uint8Array(await crypto.subtle.exportKey("pkcs8", pair.privateKey));
  const pem = `-----BEGIN PRIVATE KEY-----\n${encodeBase64(pkcs8)}\n-----END PRIVATE KEY-----`;
  for (const [k, v] of Object.entries({
    MINCE_TEST: "1", SUPABASE_URL: SB, SUPABASE_ANON_KEY: "anon", SUPABASE_SERVICE_ROLE_KEY: "service", ANTHROPIC_API_KEY: "test-key",
    APPSTORE_ISSUER_ID: "issuer-1", APPSTORE_KEY_ID: "KEY123", APPSTORE_PRIVATE_KEY: pem, APPSTORE_BUNDLE_ID: "yell0.mince",
  })) Deno.env.set(k, v);
  // Hermetic: ignore any Anthropic endpoint/credentials configured in the developer's shell.
  for (const k of ["ANTHROPIC_BASE_URL", "ANTHROPIC_AUTH_TOKEN", "ANTHROPIC_PROFILE"]) Deno.env.delete(k);
  globalThis.fetch = (async (input: Request | URL | string, init?: RequestInit) => {
    try { return await route(new Request(input, init)); } catch (e) { console.log("fake fetch:", (e as Error).message); throw e; }
  }) as typeof fetch;
  return pair.publicKey;
}

export function call(handler: (r: Request) => Promise<Response>, body: unknown, token = "good-token", method = "POST") {
  return handler(new Request("https://fn.test/", {
    method, headers: { "content-type": "application/json", authorization: `Bearer ${token}` },
    body: method === "GET" ? undefined : JSON.stringify(body),
  }));
}
