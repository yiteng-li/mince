// App Store Server Notifications V2 (renewals, expiry, refunds, billing problems). Set this URL in App Store Connect.
// Deploy with --no-verify-jwt: Apple doesn't send a Supabase token. Authenticity comes from re-fetching each transaction from Apple.
import { admin, json, serve } from "../_shared/http.ts";
import { fetchTransaction, storeSubscription, unverifiedPayload } from "../_shared/appstore.ts";

type Notification = {
  notificationType: string;
  subtype?: string;
  notificationUUID: string;
  data?: { signedTransactionInfo?: string; bundleId?: string };
};

export default serve(async (_req, body) => {
  if (typeof body.signedPayload !== "string") return json({ error: "missing signedPayload" }, 400);
  const n = unverifiedPayload<Notification>(body.signedPayload);
  const svc = admin();

  // Idempotent: Apple retries until it gets a 200, and may deliver the same notification twice.
  const { error: dup } = await svc.from("app_store_events").insert({ notification_uuid: n.notificationUUID });
  if (dup) return json({ ok: true, duplicate: true });

  try {
    const signed = n.data?.signedTransactionInfo;
    if (!signed) return json({ ok: true }); // e.g. TEST notifications carry no transaction
    const t = await fetchTransaction(unverifiedPayload<{ transactionId: string }>(signed).transactionId);

    // Find the user: the token set at purchase, else the account that already owns this subscription.
    let userId = t.appAccountToken?.toLowerCase();
    if (!userId) {
      const { data } = await svc.from("subscriptions").select("user_id").eq("original_transaction_id", t.originalTransactionId).maybeSingle();
      userId = data?.user_id;
    }
    if (!userId) return json({ ok: true, unmatched: true });

    const grace = n.notificationType === "DID_FAIL_TO_RENEW" && n.subtype === "GRACE_PERIOD";
    await storeSubscription(t, userId, grace);
    return json({ ok: true });
  } catch (e) {
    // Let Apple retry: forget the event id so the retry isn't treated as a duplicate.
    await svc.from("app_store_events").delete().eq("notification_uuid", n.notificationUUID);
    throw e;
  }
});
