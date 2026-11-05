# Backend: mince

Supabase (Postgres + Auth + Storage + Edge Functions), StoreKit 2 with App Store Server API, Claude API.
Everything below is in the repo; the steps marked **you** need your accounts and keys (Claude never creates accounts or handles live keys).

## What's built

| piece | where | verified by |
| --- | --- | --- |
| Schema, RLS, RPCs (25 tables) | `supabase/migrations/20261105000000_schema.sql` | `replica/schema-check` (`npm i && npm test`): second user sees nothing, Gold gates, repeats, recipes, totals |
| Storage buckets + owner-only policies | `supabase/migrations/20261105000001_storage.sql` | Supabase-specific (not runnable in PGlite); review before push |
| Reference data: 84 nutrients, DRI defaults, 85 exercises, 34 biometrics | `supabase/migrations/20261105000002_reference_data.sql` | loaded by schema-check |
| USDA food import (SR Legacy + Foundation) | `supabase/seed/usda_import.py` | fixture zip -> SQL -> loaded twice (idempotent) -> `search_foods` finds it |
| `photo-log`, `voice-parse`, `recipe-import`, `coach` | `supabase/functions/*` | `deno check` passes; not called live (needs your API key) |
| `verify-purchase`, `appstore-notifications` | `supabase/functions/*`, `_shared/appstore.ts` | `deno check` passes; needs App Store Connect setup to run |
| `delete-account` | `supabase/functions/delete-account` | `deno check` passes |
| StoreKit local testing | `Products.storekit` + scheme reference | builds; purchase flow not exercised (needs Xcode run) |

AI calls: `claude-opus-5-5` (override with `CLAUDE_MODEL`), JSON-schema structured output, `fallbacks: "default"` for safety-classifier declines,
refusals mapped to a friendly 422, effort `low` for voice parsing and coaching, `medium` for photos and recipes.
Per-user daily limits in `ai_usage`: 30 photos, 100 voice, 30 imports, 10 coach. Meal photos are deleted right after analysis.

Subscriptions: the device sends its StoreKit JWS; the server takes only the transaction id from it and re-fetches the transaction from
Apple's App Store Server API with your key, checks bundle id, product and `appAccountToken` (= user id), then writes `subscriptions`.
Notifications are handled the same way (re-fetched, deduped on `notificationUUID`, retried by Apple on failure). `is_gold()` reads that table;
RLS, the RPCs and every Edge Function call it, so a modified app can't unlock Gold.

## Deploy (you)

```bash
supabase login
supabase link --project-ref yobeigyeotsifsvxlpwz
supabase db reset --linked            # DESTROYS the existing tables and data, then applies the 3 migrations
# download SR Legacy + Foundation CSV zips from https://fdc.nal.usda.gov/download-datasets
python3 supabase/seed/usda_import.py ~/Downloads/FoodData_Central_sr_legacy_food_csv_*.zip ~/Downloads/FoodData_Central_foundation_food_csv_*.zip
psql "$(supabase status --linked -o env | grep DB_URL | cut -d= -f2-)" -f supabase/seed/usda_foods.sql   # or paste the DB URL from the dashboard
cp supabase/functions/.env.example supabase/functions/.env   # fill it in
supabase secrets set --env-file supabase/functions/.env
supabase functions deploy photo-log voice-parse recipe-import coach verify-purchase delete-account
supabase functions deploy appstore-notifications --no-verify-jwt
```

Then:
- **Auth > Providers > Apple**: enable, client id = `yell0.mince`. **Auth > SMTP**: use Resend or Postmark from your own domain before launch (Supabase's built-in sender is rate-limited).
- **App Store Connect**: create the subscription group and products `mince.gold.monthly`, `mince.gold.annual`; create an In-App Purchase key (issuer id, key id, .p8);
  set the Server Notifications V2 URL (production and sandbox) to `https://yobeigyeotsifsvxlpwz.supabase.co/functions/v1/appstore-notifications`.
- **Xcode**: Signing & Capabilities: HealthKit, Sign in with Apple (the entitlements file already lists them). Raise or lower `IPHONEOS_DEPLOYMENT_TARGET` (26.5) to match the devices you test on.
- **Backups**: Supabase daily backups are on for paid plans; Point-in-Time Recovery is an add-on. Check Project Settings > Database.

## Integrations

| integration | API | scopes / permissions | review | limits |
| --- | --- | --- | --- | --- |
| Apple Health | HealthKit (on device) | read: workouts, active energy, body mass, body fat, resting HR, HRV, glucose, SpO2, respiratory rate, VO2 max, sleep; write: 15 dietary types | App Review checks the usage strings and that health data isn't used for ads | none |
| Open Food Facts | public REST, no key | none | none; ODbL attribution in About | product lookups fine; search is rate-limited (only on explicit tap) |
| USDA FDC | bulk CSV download | none | none; public domain | none |
| Claude API | Messages API | API key | none | your org's rate limits; per-user daily quotas above |
| App Store | StoreKit 2 + App Store Server API | In-App Purchase key | subscription review with the first build | none relevant |

## Security checklist

- [x] secrets only in env vars (`supabase/functions/.env`, gitignored); the app ships only the anon key, which RLS is built around
- [x] input validated on the server: every function bounds its strings, checks storage paths belong to the caller, rejects non-public URLs (and re-checks after redirects), caps page and photo size
- [x] authorisation on every read and write: RLS on all 25 tables, Gold checks in RLS/RPCs/functions; tested with a second user in schema-check
- [x] rate limits: Supabase Auth's built-in limits on sign up / sign in / email; daily per-user quotas on AI functions. ponytail: the quota check is read-then-write, so two simultaneous calls can both pass at the limit
- [x] webhooks verified: App Store notifications are re-fetched from Apple before anything is written; event ids deduped
- [x] uploads: private buckets, 5 MB and image-type limits, per-user folders, meal photos deleted after analysis
- [x] no user data in logs: functions log error messages only, never bodies
- [ ] dependencies audited: `deno check` resolves under Deno's 24-hour minimum-dependency-age policy; run `npm audit` in `replica/schema-check` before release
- [ ] privacy policy lists every processor: Supabase (database, auth, storage), Anthropic (photo/voice/recipe/coach requests), Apple (payments, Health stays on device), Open Food Facts (barcode lookups). Written in replica-launch; `AppLinks.privacy` is a placeholder until then

## Not done here

- Email templates: Supabase's default confirm / reset emails; customise the copy in Auth > Email Templates once SMTP is set.
- Background jobs: none needed (repeats materialise on read, fast reminders are local notifications, renewals arrive by webhook).
- `Info.plist` is gitignored (it holds the Supabase keys), so the `mince://` URL scheme added there won't reach other clones of the repo; move the keys to `Secrets.xcconfig` if you want Info.plist tracked.
