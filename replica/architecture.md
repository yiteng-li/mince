# Architecture: mince (a rebuild of Cronometer's Basic + Gold features)

Reads: `recon.md`, `features.csv`. Schema: `schema.sql` (verified by `schema-check/`, run `npm i && npm test` there).

## Stack

| layer | choice | why |
| --- | --- | --- |
| client | SwiftUI, iOS 17+, MVVM (existing) | already built and the point of the project; Swift Charts, HealthKit, StoreKit 2, Speech, App Intents, WidgetKit are all native |
| database | Supabase Postgres (existing) | one database, RLS already the access model, RPCs for aggregation |
| auth | Supabase Auth: email + password, Sign in with Apple | already wired; Apple sign-in is native and expected on iOS |
| server code | Supabase Edge Functions (Deno/TS) | only where a secret or the service role is needed: AI calls, App Store verification, account deletion |
| AI | Claude API (vision + text) from Edge Functions | photo log, voice parse, recipe-import ingredient parsing, coach; model choice made in replica-backend |
| payments | StoreKit 2 + App Store Server API / Server Notifications V2 | App Store rules require IAP for a digital subscription; Stripe is not allowed here |
| email | Supabase Auth mail, custom SMTP via Resend before launch | only auth mail exists; Supabase's built-in sender is rate-limited |
| files | Supabase Storage, private buckets `snapshots`, `meal-photos` | progress photos and photos sent to photo log |
| jobs | none server-side | repeats materialise on read (`materialize_repeats`), fast reminders are local notifications, renewals arrive by webhook |
| food data | USDA FoodData Central (public domain) seed + Open Food Facts lookup (existing) | Cronometer's NCCDB/lab data is licensed |
| hosting | Supabase (managed) + App Store | nothing else to run |

## Schema

Tables: **25**. Access rules: **Postgres RLS on every table**; Gold-only writes check `public.is_gold()`; service-role-only writes for `subscriptions`, `app_store_events`, `ai_usage`.

Key decisions (each changes the current 0001-0005 schema):

- **Nutrients: catalogue table + `foods.nutrients jsonb` (per 100 g)**, replacing 28 flat columns. Cronometer tracks 84-95 nutrients and every one needs a target row anyway; jsonb keeps "one food = one row" and decodes straight to `[String: Double]` in Swift.
- **One `diary_entries` table for food, quick-add, exercise, biometric and note rows**, discriminated by `kind` with a per-kind check constraint. A day is one query; copy/paste, multi-select, groups and timestamps work for every kind. `weight_logs` folds in as the `weight` biometric.
- **Diary groups are rows** (`diary_groups`, 4 created per user), replacing the fixed `meal_type` check. Renamable, reorderable.
- **Amounts stored as grams** (`amount_g`) plus `serving_id`/`serving_qty` to redisplay what the user picked. `food_servings` holds "1 cup = 240 g".
- **Custom foods are private** (`user_id` set, `on delete cascade`). The current `created_by ... on delete set null` would turn a deleted user's foods into public foods. Shared database foods are `user_id is null` and written only by the seed script. Sharing (Gold) is a token plus copy-on-import.
- **Foods are soft-deleted** (`archived_at`) because diary rows reference them (`on delete restrict`).
- **Recipes are foods** (`kind = 'recipe'`) with `recipe_ingredients`; their nutrients are cached by `recompute_recipe()` on save, so search, totals and Oracle treat them like any food. **Meals** (`meals` + `meal_items`) always explode into separate entries when logged.
- **Profile holds targets and prefs** (1:1, one fetch). Current weight is the latest `weight` biometric, not a profile column. `goal` (cut/maintain/bulk) becomes `goal_kg_per_week`.
- **Micronutrient targets** = DRI defaults (`nutrient_dri`, by sex + age band) overridden by `nutrient_targets`.
- **Gold data stays readable after a lapse**: Gold tables allow select/delete for the owner always, insert/update only while Gold.
- **Composite FKs** `(group_id, user_id) -> diary_groups(id, user_id)` make it impossible to file an entry under someone else's group, without a policy.

Hard constraints the recon found, enforced in the database:

| rule | how |
| --- | --- |
| one open fast per user | partial unique index `fasts (user_id) where ended_at is null` |
| repeat item deleted for one day stays deleted | `repeat_runs (rule_id, day)` primary key |
| Health import is not double-imported | unique `(user_id, source, external_id)` |
| macro % sums to 100 | check on `profiles` |
| max 8 nutrition scores | `cardinality(selected_scores) <= 8` |
| one default serving per food | partial unique index |
| Basic reports limited to 7 days | `nutrient_totals` / `nutrient_sources` raise `gold_required` |
| timestamps are Gold | RLS on `diary_entries.logged_at` (Health imports exempt) |

## API

Most reads/writes go straight to PostgREST through `supabase-swift` with RLS doing authorisation. RPCs exist where SQL beats N round trips; Edge Functions exist only where a secret is needed. Auth = signed-in user JWT unless noted.

| method path | does | who | input | output | flow |
| --- | --- | --- | --- | --- | --- |
| auth `signUp` / `signInWithPassword` / `signInWithIdToken(apple)` | create / open session; trigger makes profile + 4 groups | anyone | email+pw or Apple token | session | F01 |
| auth `resetPasswordForEmail` | reset mail | anyone | email | — | F01 |
| PATCH `/profiles?id=eq.me` | wizard answers, targets, prefs | owner | profile fields | profile | F01, F13 |
| GET `/nutrients`, `/nutrient_dri` | catalogue + defaults (cache on device) | user | — | rows | F06 |
| GET/PUT/DELETE `/nutrient_targets` | custom min/max | owner | key, min, max | rows | F13 |
| GET `/diary_entries?day=eq.D&select=*,food:foods(id,name,nutrients),serving:food_servings(name)` | a day | owner | day | entries | F02, F06 |
| POST `/rpc/materialize_repeats` | add today's repeat items (call before the day fetch) | owner (no-op unless Gold) | day | count | F14 |
| POST `/rpc/nutrient_totals` | per-day per-nutrient sums | owner; >7 days Gold | from, to | rows | F06, F11 |
| POST/PATCH/DELETE `/diary_entries` | log, edit, move group, copy (insert copies), multi-delete (`id=in.(...)`), bulk delete (`day=gte..lte`) | owner | entry | entry | F02-F05, F09, F16 |
| GET/POST/PATCH/DELETE `/diary_groups` | rename / reorder groups | owner | name, position | rows | F02 |
| PUT `/days` | mark day complete | owner | day, completed | row | F06 |
| POST `/rpc/search_foods` | food search | user | q, lim, off | foods | F02 |
| POST `/rpc/recent_foods` | recents | owner | lim | foods | F02 |
| GET `/foods?barcode=eq.X` then OFF lookup (existing service), insert as own food | barcode | user | code | food | F03 |
| POST/PATCH `/foods`, `/food_servings` | custom food | owner | label | food | F03, F07 |
| PATCH `/foods?id=eq.X` `{archived_at}` | delete custom food | owner | id | — | F07 |
| POST `/foods` (kind recipe), `/recipe_ingredients`, then `/rpc/recompute_recipe` | recipe | owner | recipe + ingredients | recipe | F07 |
| POST `/meals`, `/meal_items` | meal | owner | items | meal | F07 |
| GET `/exercises?name=ilike.*q*` | exercise search | user | q | rows | F09 |
| GET `/biometric_types` · POST (custom, Gold) | metric list / custom metric | user / Gold | name, unit | rows | F09 |
| GET `/diary_entries?kind=eq.biometric&biometric_type_id=eq.T&day=gte.A` | weight / biometric chart | owner | type, range | rows | F11 |
| POST `/rpc/nutrient_sources` | top contributing foods in my diary | owner; >7 days Gold | from, to, key | rows | F06, F11 |
| POST `/rpc/oracle` | top foods for a nutrient | Gold | key, per | foods | F06 |
| CRUD `/macro_templates`, `/macro_schedule` | Macro Scheduler | Gold write | template, weekday | rows | F13 |
| CRUD `/repeat_rules` | Repeat Items | Gold write | food/meal, weekdays | rule | F14 |
| CRUD `/fasts`, `/fast_schedules` | fasting timer | Gold write | start/end | rows | F10 |
| CRUD `/custom_charts` | custom charts | Gold write | series, range | rows | F11 |
| PATCH `/foods` `{share_token}` · POST `/rpc/get_shared_food` | share / open a shared food | Gold / any user with token | token | food + servings | F07 |
| Storage `snapshots/<uid>/…` + CRUD `/snapshots` | progress photos | owner | image | row | F09 |
| POST `fn/verify-purchase` | verify a StoreKit 2 signed transaction, upsert `subscriptions` | user | JWS transaction | entitlement | F12 |
| POST `fn/appstore-notifications` | renewals, expiry, refund, revoke | Apple (JWS-verified) | signedPayload | 200 | F12 |
| POST `fn/photo-log` | image -> items with grams, matched to foods | Gold, quota | storage path | items[] | F04 |
| POST `fn/voice-parse` | transcript -> items with grams | Gold, quota | text | items[] | F05 |
| POST `fn/recipe-import` | URL or pasted text -> ingredient lines -> matched foods | Gold, quota | url or text | draft recipe | F08 |
| POST `fn/coach` | short guidance from the user's own 7-30 day aggregates | Gold, quota | range | text | F13 (Crono Coach) |
| POST `fn/delete-account` | `auth.admin.deleteUser` (cascades everything) + storage cleanup | owner | — | 204 | F16 |
| client only | PDF report (`ImageRenderer`), CSV export, HealthKit read/write, local fast notifications, widgets, Siri App Intents | — | — | — | F15, F16 |

Webhooks in: App Store Server Notifications V2 -> `appstore-notifications`. Webhooks out: none.
Jobs: none. (Optional later: a nightly `expire_stale_subscriptions` pg_cron if notifications are missed; `is_gold()` already checks `expires_at`.)

Route count: 37 rows above (30 PostgREST/RPC/storage, 7 Edge Functions).

## The parts that bite

- **Time zones / DST:** `day` is the device's local date, chosen by the client, never derived from `now()` on the server. Instants (`logged_at`, fasts) are `timestamptz`. A fast belongs to the day it started. Changing time zone mid-trip doesn't move past days.
- **Idempotency:** App Store notifications deduped on `notificationUUID` (`app_store_events`); `subscriptions` keyed by `original_transaction_id` so verify-purchase + webhook can both upsert. Health imports keyed by sample UUID. Repeats keyed by `(rule, day)`.
- **Races:** two devices materialising repeats -> `repeat_runs` PK makes the second a no-op. Starting a fast twice -> partial unique index.
- **Entitlement trust:** client-side Gold checks are UI only. The server checks `is_gold()` in RLS, RPCs and every Edge Function. Set `appAccountToken = user id` on purchase so transactions map to users.
- **Double-counted energy:** with Health active energy on, replace the activity multiplier instead of adding to it (`use_health_active_energy`); skip Health workouts that duplicate manual ones.
- **Rate limits / cost:** AI functions check `ai_usage` (e.g. 30 photos/day) before calling the model; images resized on device (<1 MB) before upload.
- **File sizes:** buckets capped at 5 MB, image MIME types only.
- **Search quality:** USDA names are verbose ("Nuts, almonds"). Rank own foods and recents first; trigram for typos; consider a `common_name` column if results feel bad.
- **Recipe importer:** many sites block bots; parse schema.org `Recipe` JSON-LD first, fall back to pasted text. Only fetch the URL the user gave.
- **Offline:** not supported (Cronometer is online-first too). Show a clear error, never drop a write silently.
- **GDPR / App Store deletion:** `delete-account` removes the auth user; every user table cascades; storage folder deleted in the same function.
- **Data licensing:** OFF is ODbL (attribution in About). USDA is public domain. Nutrition score formulas are our own.

## Migration path (from 0001-0005)

`0006` onwards, written by replica-backend: create new tables; add `foods.nutrients` and backfill from the flat columns, then drop them; rename `created_by -> user_id` (cascade); create `diary_groups` for existing users and map `meal_type`; move `quantity_g -> amount_g`, `logged_on -> day`; copy `weight_logs` into `diary_entries` as weight biometrics, then drop it; `profiles.weight_kg` -> weight biometric, `goal` -> `goal_kg_per_week`. If the hosted project has no real data, reset it and apply `schema.sql` as one migration instead.

## Build order

1. **Vertical slice** — sign up, set a minimal profile, search a seeded food, log it to a group, see energy + macros + micros vs DRI targets.
   Screens S01, S02, S05, S07, S08. Tables profiles, nutrients, nutrient_dri, foods, food_servings, diary_groups, diary_entries. Routes auth, search_foods, diary_entries CRUD, nutrient_totals. Plus the USDA seed script (Foundation + SR Legacy, ~8k foods).
2. **Must-haves (Basic)** — onboarding wizard + energy/macro targets (S03, S27); custom foods, recipes, meals (S18-S21); barcode (S09); quick add (S12); exercise (S13) + weight (S14); edit/undo; weight + energy charts and 7-day report (S23, S24); units; delete account.
3. **Gold infrastructure** — subscriptions, verify-purchase, appstore-notifications, paywall (S33), `is_gold()` gating. Then Gold musts: unlimited ranges, timestamps, Repeat Items (S29), Macro Scheduler (S28), Fasting Timer (S17), Recipe Importer (S22), Photo Log (S10).
4. **Should-haves** — Sign in with Apple, voice log + Siri (S11), Apple Health (S31), nutrient sources, Oracle + Food Suggestions (S26), Nutrition Scores (S25), Custom Charts, custom biometrics, PDF/CSV (S34), water (S16), notes (S15), streaks, copy/paste, multi-select, diet presets.
5. **Could-haves** — snapshots (S30), sharing, coach (S35), widgets + Watch (S36), plus-menu customisation, group subtotals, CGM charts, localisation.
6. **Fixes from replica-entrepreneur** once it runs.
