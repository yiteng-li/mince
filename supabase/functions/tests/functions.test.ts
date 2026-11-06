// End-to-end tests for every Edge Function: real handlers, network stubbed in fake.ts.
// Run: deno test --allow-env supabase/functions/tests/
import { assert, assertEquals, assertMatch, assertRejects, assertThrows } from "jsr:@std/assert@1";
import { decodeBase64Url } from "jsr:@std/encoding@1/base64url";
import { call, message, reset, SB, setup, state, UID } from "./fake.ts";

const publicKey = await setup();
const load = async (fn: string) => (await import(`../${fn}/index.ts`)).default as (r: Request) => Promise<Response>;
const [voice, photo, recipe, coach, verify, notify, del] = await Promise.all(
  ["voice-parse", "photo-log", "recipe-import", "coach", "verify-purchase", "appstore-notifications", "delete-account"].map(load));
const { handle, HttpError } = await import("../_shared/http.ts");
const { safeURL, findRecipe, recipeText, visibleText } = await import("../_shared/recipe.ts");
const { apiToken, subscriptionRow, unverifiedPayload } = await import("../_shared/appstore.ts");
const { jws } = await import("./fake.ts");

const claudeCalls = () => state.requests.filter((r) => r.url.host === "api.anthropic.com");
const sb = (path: string, method?: string) => state.requests.filter((r) => r.url.origin === SB && r.url.pathname.startsWith(path) && (!method || r.method === method));
const json = async (r: Response) => ({ status: r.status, body: await r.json() });
const test = (name: string, fn: () => Promise<void> | void) => Deno.test({ name, fn: async () => { reset(); await fn(); }, sanitizeOps: false, sanitizeResources: false });

// ───────── request wrapper

test("wrapper: non-POST is 405", async () => {
  const h = handle(async () => new Response("x"));
  assertEquals((await h(new Request("https://x/", { method: "GET" }))).status, 405);
});
test("wrapper: HttpError keeps its status, other errors become a generic 500", async () => {
  assertEquals((await json(await handle(async () => { throw new HttpError(418, "teapot"); })(new Request("https://x/", { method: "POST", body: "{}" })))).body.error, "teapot");
  const r = await json(await handle(async () => { throw new Error("secret detail"); })(new Request("https://x/", { method: "POST", body: "{}" })));
  assertEquals(r.status, 500);
  assert(!JSON.stringify(r.body).includes("secret"), "internal error text must not leak");
});
test("wrapper: array and invalid JSON bodies are treated as {}", async () => {
  let seen: unknown;
  const h = handle(async (_r, b) => { seen = b; return new Response("ok"); });
  await h(new Request("https://x/", { method: "POST", body: "[1,2]" }));
  assertEquals(seen, {});
  await h(new Request("https://x/", { method: "POST", body: "not json" }));
  assertEquals(seen, {});
});

// ───────── auth, Gold, quota (shared by every AI function)

test("auth: a bad token is 401 and nothing else runs", async () => {
  const r = await call(voice, { text: "eggs" }, "bad-token");
  assertEquals(r.status, 401);
  assertEquals(claudeCalls().length, 0);
});
test("gold: Basic users get 402 before any quota or AI call", async () => {
  state.gold = false;
  assertEquals((await call(voice, { text: "two eggs" })).status, 402);
  assertEquals(claudeCalls().length, 0);
  assertEquals(sb("/rest/v1/ai_usage").length, 0);
});
test("quota: at the daily limit it's 429 and Claude isn't called", async () => {
  state.usageCount = 100;
  assertEquals((await call(voice, { text: "two eggs" })).status, 429);
  assertEquals(claudeCalls().length, 0);
});
test("quota: first call of the day (no row yet) is allowed and counted", async () => {
  state.usageCount = null;
  state.claude = () => message(JSON.stringify({ items: [], suggestions: [] }));
  assertEquals((await call(voice, { text: "eggs" })).status, 200);
  const up = sb("/rest/v1/ai_usage", "POST");
  assertEquals(up.length, 1);
  assertEquals(JSON.parse(up[0].body).count, 1);
});

// ───────── voice-parse

test("voice: empty text is 400", async () => {
  assertEquals((await call(voice, { text: "   " })).status, 400);
});
test("voice: items are matched to foods, grams clamped, and the request is well formed", async () => {
  state.claude = () => message(JSON.stringify({ items: [
    { name: "Scrambled eggs", grams: 100, search_query: "egg scrambled" },
    { name: "Mystery stew", grams: 99999, search_query: "unknown stew" },
  ], suggestions: [] }));
  const { status, body } = await json(await call(voice, { text: "two scrambled eggs and some stew" }));
  assertEquals(status, 200);
  assertEquals(body.items, [
    { name: "Scrambled eggs", grams: 100, food_id: "food-egg" },
    { name: "Mystery stew", grams: 5000, food_id: null },
  ]);
  const [c] = claudeCalls();
  const req = JSON.parse(c.body);
  assertEquals(req.model, "claude-opus-5-5");
  assertEquals(req.fallbacks, "default");
  assertEquals(req.output_config.effort, "low");
  assertEquals(req.output_config.format.type, "json_schema");
  assertMatch(c.headers.get("anthropic-beta") ?? "", /server-side-fallback-2026-07-01/);
  assertMatch(req.messages[0].content[0].text, /<meal>two scrambled eggs and some stew<\/meal>/);
});
test("voice: a refusal is a friendly 422", async () => {
  state.claude = () => message("", "refusal");
  assertEquals((await call(voice, { text: "eggs" })).status, 422);
});
test("voice: truncated output is 422, malformed JSON is 502", async () => {
  state.claude = () => message('{"items": [', "max_tokens");
  assertEquals((await call(voice, { text: "eggs" })).status, 422);
  state.claude = () => message("not json");
  assertEquals((await call(voice, { text: "eggs" })).status, 502);
});
test("voice: very long text is cut to 2000 characters", async () => {
  await call(voice, { text: "a".repeat(5000) });
  const text = JSON.parse(claudeCalls()[0].body).messages[0].content[0].text as string;
  assert(text.length < 2100);
});

// ───────── photo-log

test("photo: someone else's path or path traversal is 400 and nothing is downloaded", async () => {
  for (const path of ["11111111-1111-1111-1111-111111111111/x.jpg", `${UID}/../other/x.jpg`, "", 42]) {
    assertEquals((await call(photo, { path })).status, 400);
  }
  assertEquals(sb("/storage/v1/object/meal-photos/").length, 0);
});
test("photo: image sent to Claude, items and extras matched, photo deleted afterwards", async () => {
  state.claude = () => message(JSON.stringify({
    items: [{ name: "Grilled salmon", grams: 150, search_query: "salmon baked" }],
    suggestions: [{ name: "Olive oil", grams: 10, search_query: "oil olive" }],
  }));
  const { status, body } = await json(await call(photo, { path: `${UID}/meal.jpg` }));
  assertEquals(status, 200);
  assertEquals(body.items[0].food_id, "food-salmon");
  assertEquals(body.suggestions[0].food_id, "food-oil");
  const img = JSON.parse(claudeCalls()[0].body).messages[0].content[0];
  assertEquals(img.type, "image");
  assertEquals(img.source.media_type, "image/jpeg");
  assert(img.source.data.length > 0);
  assertEquals(sb("/storage/v1/object/meal-photos", "DELETE").length, 1);
});
test("photo: deleted even when the AI call fails", async () => {
  state.claude = () => message("", "refusal");
  assertEquals((await call(photo, { path: `${UID}/meal.jpg` })).status, 422);
  assertEquals(sb("/storage/v1/object/meal-photos", "DELETE").length, 1);
});

// ───────── recipe-import

test("recipe: only public http(s) links are accepted", () => {
  safeURL("https://www.example.com/recipes/bread");
  for (const bad of ["http://localhost/x", "http://127.0.0.1/", "http://10.0.0.5/", "http://[::1]/", "http://0x7f000001/",
    "http://2130706433/", "ftp://example.com/r", "http://intranet/", "http://printer.local/", "http://metadata.google.internal/", "not a url"]) {
    assertThrows(() => safeURL(bad), HttpError, undefined, bad);
  }
});
test("recipe: finds a Recipe inside @graph and flattens HowTo steps", () => {
  const html = `<script type="application/ld+json">{"@context":"https://schema.org","@graph":[{"@type":"WebPage"},
    {"@type":["Recipe"],"name":"Bread","recipeYield":"1 loaf","recipeIngredient":["500 g flour","10 g salt"],
     "recipeInstructions":[{"@type":"HowToStep","text":"Mix."},{"@type":"HowToSection","itemListElement":[{"@type":"HowToStep","text":"Bake."}]}]}]}</script>`;
  const r = findRecipe(html)!;
  const text = recipeText(r);
  for (const s of ["Title: Bread", "500 g flour", "10 g salt", "Mix.", "Bake."]) assertMatch(text, new RegExp(s.replace(".", "\\.")));
  assertEquals(findRecipe("<html>no data</html>"), null);
  assertEquals(findRecipe(`<script type="application/ld+json">{broken</script>`), null);
});
test("recipe: visible text drops scripts and styles", () => {
  assertEquals(visibleText("<style>x{}</style><p>Hi <b>there</b></p><script>alert(1)</script>").trim(), "Hi there");
});
test("recipe: URL import sends the JSON-LD recipe, matches ingredients, keeps unmatched lines", async () => {
  state.pages.set("https://cook.example.com/bread", `<html><script type="application/ld+json">{"@type":"Recipe","name":"Bread",
    "recipeIngredient":["500 g flour","a pinch of unknown spice"]}</script><p>Long story about my grandmother...</p></html>`);
  state.claude = () => message(JSON.stringify({ name: "Bread", servings: 0, instructions: "Mix and bake.", ingredients: [
    { line: "500 g flour", name: "Flour", grams: 500, search_query: "flour wheat" },
    { line: "a pinch of unknown spice", name: "Spice", grams: 0, search_query: "unknown spice" },
  ] }));
  const { status, body } = await json(await call(recipe, { url: "https://cook.example.com/bread" }));
  assertEquals(status, 200);
  assertEquals(body.servings, 1);
  assertEquals(body.ingredients, [
    { line: "500 g flour", name: "Flour", grams: 500, food_id: "food-flour" },
    { line: "a pinch of unknown spice", name: "Spice", grams: null, food_id: null },
  ]);
  const sent = JSON.parse(claudeCalls()[0].body).messages[0].content[0].text as string;
  assertMatch(sent, /Ingredients:\n500 g flour/);
  assert(!sent.includes("grandmother"), "with JSON-LD present, page prose isn't sent");
});
test("recipe: a redirect to a private address is refused", async () => {
  const realFetch = globalThis.fetch;
  globalThis.fetch = (async (input: Request | URL | string, init?: RequestInit) => {
    const url = String(input instanceof Request ? input.url : input);
    if (url === "https://short.example.com/r") {
      const r = new Response("<html></html>");
      Object.defineProperty(r, "url", { value: "http://169.254.169.254/latest/meta-data" });
      return r;
    }
    return realFetch(input, init);
  }) as typeof fetch;
  try {
    assertEquals((await call(recipe, { url: "https://short.example.com/r" })).status, 400);
    assertEquals(claudeCalls().length, 0);
  } finally { globalThis.fetch = realFetch; }
});
test("recipe: private link is refused without fetching it", async () => {
  assertEquals((await call(recipe, { url: "http://192.168.1.1/admin" })).status, 400);
  assertEquals(state.requests.filter((r) => r.url.host === "192.168.1.1").length, 0);
});
test("recipe: nothing given is 400; no ingredients found is 422", async () => {
  assertEquals((await call(recipe, {})).status, 400);
  state.claude = () => message(JSON.stringify({ name: "", servings: 1, instructions: "", ingredients: [] }));
  assertEquals((await call(recipe, { text: "just a story" })).status, 422);
});

// ───────── coach

test("coach: needs two logged days", async () => {
  state.totals = [{ day: "2026-11-05", nutrient_key: "energy", amount: 1800 }];
  assertEquals((await call(coach, { days: 7 })).status, 422);
  assertEquals(claudeCalls().length, 0);
});
test("coach: averages over logged days, sends numbers only, returns at most 5 tips", async () => {
  state.totals = [
    { day: "2026-11-04", nutrient_key: "energy", amount: 2000 }, { day: "2026-11-05", nutrient_key: "energy", amount: 1000 },
    { day: "2026-11-05", nutrient_key: "fiber", amount: 10 },
  ];
  state.claude = () => message(JSON.stringify({ tips: ["a", "b", "c", "d", "e", "f"] }));
  const { status, body } = await json(await call(coach, { days: 99 }));
  assertEquals(status, 200);
  assertEquals(body.tips.length, 5);
  const sent = JSON.parse(JSON.parse(claudeCalls()[0].body).messages[0].content[0].text);
  assertEquals(sent.daily_averages.energy, 1500);
  assertEquals(sent.daily_averages.fiber, 5);
  assert(!JSON.stringify(sent).includes("t@example.com"), "no email sent to the model");
});

// ───────── App Store

type Tx = Parameters<typeof subscriptionRow>[0];
const tx = (over: Record<string, unknown> = {}): Tx => ({
  transactionId: "2000000001", originalTransactionId: "2000000000", productId: "mince.gold.annual", bundleId: "yell0.mince",
  appAccountToken: UID, expiresDate: Date.now() + 30 * 86_400_000, environment: "Production", ...over,
} as Tx);
const upserts = () => sb("/rest/v1/subscriptions", "POST").map((r) => JSON.parse(r.body));

test("apple token: ES256 JWT signed with our key, for our bundle", async () => {
  const token = await apiToken();
  const [h, p, s] = token.split(".");
  const header = JSON.parse(new TextDecoder().decode(decodeBase64Url(h)));
  const payload = JSON.parse(new TextDecoder().decode(decodeBase64Url(p)));
  assertEquals(header, { alg: "ES256", kid: "KEY123", typ: "JWT" });
  assertEquals([payload.iss, payload.aud, payload.bid], ["issuer-1", "appstoreconnect-v1", "yell0.mince"]);
  assert(payload.exp - payload.iat <= 1200);
  const ok = await crypto.subtle.verify({ name: "ECDSA", hash: "SHA-256" }, publicKey, decodeBase64Url(s), new TextEncoder().encode(`${h}.${p}`));
  assert(ok, "signature verifies with the public key");
});
test("apple: subscription status from Apple's data", () => {
  const now = Date.now();
  assertEquals(subscriptionRow(tx(), UID, "yell0.mince", false, now).status, "active");
  assertEquals(subscriptionRow(tx({ expiresDate: now - 1 }), UID, "yell0.mince", false, now).status, "expired");
  assertEquals(subscriptionRow(tx({ revocationDate: now }), UID, "yell0.mince", false, now).status, "revoked");
  const grace = subscriptionRow(tx({ expiresDate: now - 1 }), UID, "yell0.mince", true, now);
  assertEquals(grace.status, "grace");
  assert(Date.parse(grace.expires_at) > now, "grace keeps access open");
  assertEquals(subscriptionRow(tx({ environment: "Sandbox" }), UID, "yell0.mince").environment, "Sandbox");
  assertThrows(() => subscriptionRow(tx({ bundleId: "com.other" }), UID, "yell0.mince"));
  assertThrows(() => subscriptionRow(tx({ productId: "other.product" }), UID, "yell0.mince"));
});
test("verify: missing or malformed transaction is 400", async () => {
  assertEquals((await call(verify, {})).status, 400);
  assertEquals((await call(verify, { jws: "garbage" })).status, 400);
  assertEquals((await call(verify, { jws: jws({ transactionId: "../../etc" }) })).status, 400);
});
test("verify: re-fetches from Apple and stores what Apple says, not what the device sent", async () => {
  state.apple.set("api.storekit.itunes.apple.com:2000000001", tx());
  const claimed = jws(tx({ expiresDate: Date.now() + 10 * 365 * 86_400_000, productId: "mince.gold.monthly" }));
  const { status, body } = await json(await call(verify, { jws: claimed }));
  assertEquals([status, body.gold], [200, true]);
  const [row] = upserts();
  assertEquals([row.user_id, row.product_id, row.status, row.environment], [UID, "mince.gold.annual", "active", "Production"]);
  const appleCall = state.requests.find((r) => r.url.host === "api.storekit.itunes.apple.com")!;
  assertMatch(appleCall.headers.get("authorization") ?? "", /^Bearer ey/);
});
test("verify: falls back to the sandbox API", async () => {
  state.apple.set("api.storekit-sandbox.itunes.apple.com:2000000001", tx({ environment: "Sandbox" }));
  assertEquals((await json(await call(verify, { jws: jws(tx()) }))).body.gold, true);
  assertEquals(upserts()[0].environment, "Sandbox");
});
test("verify: someone else's purchase is 403 and not stored", async () => {
  state.apple.set("api.storekit.itunes.apple.com:2000000001", tx({ appAccountToken: "99999999-9999-9999-9999-999999999999" }));
  assertEquals((await call(verify, { jws: jws(tx()) })).status, 403);
  assertEquals(upserts().length, 0);
});
test("verify: expired and refunded purchases don't grant Gold", async () => {
  state.apple.set("api.storekit.itunes.apple.com:2000000001", tx({ expiresDate: Date.now() - 1000 }));
  assertEquals((await json(await call(verify, { jws: jws(tx()) }))).body.gold, false);
  state.apple.set("api.storekit.itunes.apple.com:2000000001", tx({ revocationDate: Date.now() }));
  assertEquals((await json(await call(verify, { jws: jws(tx()) }))).body.gold, false);
});
test("verify: unknown to Apple is 404", async () => {
  assertEquals((await call(verify, { jws: jws(tx()) })).status, 404);
});
test("verify: Xcode test purchases only when the dev flag is on", async () => {
  const xcode = jws(tx({ environment: "Xcode" }));
  assertEquals((await call(verify, { jws: xcode })).status, 400);
  Deno.env.set("ALLOW_XCODE_STOREKIT", "true");
  try {
    assertEquals((await json(await call(verify, { jws: xcode }))).body.gold, true);
    assertEquals((await call(verify, { jws: jws(tx({ environment: "Xcode", appAccountToken: "99999999-9999-9999-9999-999999999999" })) })).status, 403);
    assertEquals(state.requests.filter((r) => r.url.host.includes("storekit")).length, 0, "Xcode purchases never reach Apple");
  } finally { Deno.env.delete("ALLOW_XCODE_STOREKIT"); }
});

const notification = (over: Record<string, unknown> = {}) => ({
  signedPayload: jws({ notificationType: "DID_RENEW", notificationUUID: "n-1", data: { signedTransactionInfo: jws(tx()) }, ...over }),
});
test("notify: renewal re-fetched from Apple and stored", async () => {
  state.apple.set("api.storekit.itunes.apple.com:2000000001", tx());
  assertEquals((await json(await call(notify, notification(), ""))).body, { ok: true });
  assertEquals(upserts()[0].status, "active");
});
test("notify: the same notification twice is processed once", async () => {
  state.apple.set("api.storekit.itunes.apple.com:2000000001", tx());
  await call(notify, notification(), "");
  const second = await json(await call(notify, notification(), ""));
  assertEquals(second.body.duplicate, true);
  assertEquals(upserts().length, 1);
});
test("notify: billing grace period keeps Gold", async () => {
  state.apple.set("api.storekit.itunes.apple.com:2000000001", tx({ expiresDate: Date.now() - 1000 }));
  await call(notify, notification({ notificationType: "DID_FAIL_TO_RENEW", subtype: "GRACE_PERIOD" }), "");
  assertEquals(upserts()[0].status, "grace");
});
test("notify: no account token falls back to the existing owner, else is skipped", async () => {
  state.apple.set("api.storekit.itunes.apple.com:2000000001", tx({ appAccountToken: undefined }));
  assertEquals((await json(await call(notify, notification({ notificationUUID: "n-2" }), ""))).body.unmatched, true);
  state.subscriptionOwner = UID;
  await call(notify, notification({ notificationUUID: "n-3" }), "");
  assertEquals(upserts()[0].user_id, UID);
});
test("notify: if Apple can't be reached the event is forgotten so Apple's retry is processed", async () => {
  const r = await call(notify, notification({ notificationUUID: "n-4" }), "");
  assertEquals(r.status, 404);
  assert(!state.seenEvents.has("n-4"));
});
test("notify: test notifications without a transaction are acknowledged", async () => {
  assertEquals((await json(await call(notify, { signedPayload: jws({ notificationType: "TEST", notificationUUID: "t" }) }, ""))).body, { ok: true });
  assertEquals((await call(notify, {}, "")).status, 400);
});

// ───────── delete-account

test("delete: needs explicit confirmation", async () => {
  assertEquals((await call(del, {})).status, 400);
  assertEquals(state.requests.filter((r) => r.url.pathname.startsWith("/auth/v1/admin")).length, 0);
});
test("delete: empties both storage folders, then deletes the auth user", async () => {
  state.storageFiles = ["a.jpg", "b.jpg"];
  assertEquals((await json(await call(del, { confirm: "delete" }))).body, { ok: true });
  const removed = sb("/storage/v1/object/", "DELETE").map((r) => JSON.parse(r.body).prefixes).flat();
  assertEquals(removed, [`${UID}/a.jpg`, `${UID}/b.jpg`]);
  const adminCall = state.requests.find((r) => r.url.pathname === `/auth/v1/admin/users/${UID}`)!;
  assertEquals(adminCall.method, "DELETE");
  assertEquals(adminCall.headers.get("authorization"), "Bearer service");
});

// ───────── payload decoding

test("unverifiedPayload rejects non-JWS input", () => {
  assertThrows(() => unverifiedPayload("nodots"));
  assertEquals(unverifiedPayload<{ a: number }>(jws({ a: 1 })).a, 1);
});
void assertRejects;
