// App Store Server API: the source of truth for subscription state.
// We never trust a JWS sent by the device or the notification body on its own: we take the transaction id from it
// and re-fetch the transaction from Apple over TLS with our own API key, then store what Apple says.
import { admin, HttpError } from "./http.ts";
import { decodeBase64Url, encodeBase64Url } from "jsr:@std/encoding@1/base64url";
import { decodeBase64 } from "jsr:@std/encoding@1/base64";

const env = (n: string) => {
  const v = Deno.env.get(n);
  if (!v) throw new Error(`missing env ${n}`);
  return v;
};

/** Reads a JWS payload WITHOUT verifying it. Only for picking ids to re-fetch from Apple. */
export function unverifiedPayload<T>(jws: string): T {
  const part = jws.split(".")[1];
  if (!part) throw new HttpError(400, "Malformed transaction.");
  return JSON.parse(new TextDecoder().decode(decodeBase64Url(part))) as T;
}

export async function apiToken(): Promise<string> {
  const pem = env("APPSTORE_PRIVATE_KEY").replace(/-----[^-]+-----|\s/g, "");
  const key = await crypto.subtle.importKey("pkcs8", decodeBase64(pem), { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
  const enc = (o: unknown) => encodeBase64Url(new TextEncoder().encode(JSON.stringify(o)));
  const now = Math.floor(Date.now() / 1000);
  const signingInput = `${enc({ alg: "ES256", kid: env("APPSTORE_KEY_ID"), typ: "JWT" })}.${enc({
    iss: env("APPSTORE_ISSUER_ID"), iat: now, exp: now + 1200, aud: "appstoreconnect-v1", bid: env("APPSTORE_BUNDLE_ID"),
  })}`;
  // WebCrypto ECDSA returns r||s (IEEE P1363), which is exactly the JWS ES256 signature format.
  const sig = await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, new TextEncoder().encode(signingInput));
  return `${signingInput}.${encodeBase64Url(new Uint8Array(sig))}`;
}

export type AppleTransaction = {
  transactionId: string;
  originalTransactionId: string;
  productId: string;
  bundleId: string;
  appAccountToken?: string;
  expiresDate?: number;
  revocationDate?: number;
  environment: "Production" | "Sandbox" | "Xcode";
};

/** Fetches a transaction from Apple, trying Production then Sandbox. */
export async function fetchTransaction(transactionId: string): Promise<AppleTransaction> {
  if (!/^\d+$/.test(transactionId)) throw new HttpError(400, "Malformed transaction id.");
  const token = await apiToken();
  for (const host of ["api.storekit.itunes.apple.com", "api.storekit-sandbox.itunes.apple.com"]) {
    const res = await fetch(`https://${host}/inApps/v1/transactions/${transactionId}`, { headers: { Authorization: `Bearer ${token}` } });
    if (res.status === 404) continue;
    if (!res.ok) throw new Error(`App Store API ${res.status}`);
    const { signedTransactionInfo } = await res.json() as { signedTransactionInfo: string };
    return unverifiedPayload<AppleTransaction>(signedTransactionInfo); // came straight from Apple over TLS
  }
  throw new HttpError(404, "Apple doesn't know that purchase.");
}

const GOLD_PRODUCTS = new Set(["mince.gold.monthly", "mince.gold.annual"]);

/** The subscriptions row for Apple's view of a transaction. Pure, for tests. */
export function subscriptionRow(t: AppleTransaction, userId: string, bundleId: string, grace = false, now = Date.now()) {
  if (t.bundleId !== bundleId || !GOLD_PRODUCTS.has(t.productId)) throw new HttpError(400, "Not a mince Gold purchase.");
  const expires = t.expiresDate ?? 0;
  const status = t.revocationDate ? "revoked" : grace ? "grace" : expires > now ? "active" : "expired";
  return {
    original_transaction_id: t.originalTransactionId,
    user_id: userId,
    product_id: t.productId,
    status,
    // Grace period: keep access for Apple's billing grace window even though expiresDate has passed.
    expires_at: new Date(grace ? Math.max(expires, now + 16 * 86_400_000) : expires).toISOString(),
    environment: t.environment === "Production" ? "Production" : "Sandbox",
    updated_at: new Date(now).toISOString(),
  };
}

/** Writes Apple's view of a subscription. Returns whether it currently grants Gold. */
export async function storeSubscription(t: AppleTransaction, userId: string, grace = false): Promise<boolean> {
  const row = subscriptionRow(t, userId, env("APPSTORE_BUNDLE_ID"), grace);
  const { error } = await admin().from("subscriptions").upsert(row);
  if (error) throw error;
  return row.status === "active" || row.status === "grace";
}
