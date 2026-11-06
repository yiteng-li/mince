// Called by the app after a StoreKit 2 purchase or restore. Confirms the purchase with Apple and records it.
import { caller, HttpError, json, serve, str } from "../_shared/http.ts";
import { type AppleTransaction, fetchTransaction, storeSubscription, unverifiedPayload } from "../_shared/appstore.ts";

export default serve(async (req, body) => {
  const { user } = await caller(req);
  const jws = str(body.jws, 20_000);
  if (!jws) throw new HttpError(400, "Missing transaction.");
  const claimed = unverifiedPayload<AppleTransaction>(jws);

  // Local StoreKit testing in Xcode signs with a local certificate Apple's servers don't know. Dev projects only.
  if (claimed.environment === "Xcode") {
    if (Deno.env.get("ALLOW_XCODE_STOREKIT") !== "true") throw new HttpError(400, "Test purchases aren't accepted here.");
    if (claimed.appAccountToken?.toLowerCase() !== user.id) throw new HttpError(403, "That purchase belongs to another account.");
    return json({ gold: await storeSubscription(claimed, user.id) });
  }

  const t = await fetchTransaction(claimed.transactionId);
  // The app sets appAccountToken = user id on purchase; refuse to attach someone else's purchase to this account.
  if (t.appAccountToken && t.appAccountToken.toLowerCase() !== user.id) throw new HttpError(403, "That purchase belongs to another account.");
  return json({ gold: await storeSubscription(t, user.id) });
});
