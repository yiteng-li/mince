# Test plan: mince

Automated:
- `replica/check-all.sh` runs everything that doesn't need a simulator:
  - `logic-check`: targets, units, scores, days
  - `schema-check`: schema, RLS (second user), RPCs, mince+ gates
  - `contract-check`: the app's real Swift models encode every payload it writes (18 tables); Postgres stores them under RLS;
    every read shape the app requests (28: embeds and RPCs) decodes back into the models with the SDK's coder settings
  - Edge Functions: `deno check` plus 42 end-to-end tests of the real handlers with the network stubbed (Supabase, Claude, App Store, recipe sites)
- `minceUITests`: 38 XCUITest flows in demo mode (reads and writes kept in memory). Run with:

```bash
xcodebuild build-for-testing -project mince.xcodeproj -scheme mince -destination 'generic/platform=iOS Simulator'
xcodebuild test-without-building -xctestrun <DerivedData>/Build/Products/*.xctestrun -destination 'id=<simulator>'
```
(The project targets iOS 26.5; on an older simulator runtime add `IPHONEOS_DEPLOYMENT_TARGET=<runtime>` to the first command.)

Legend: **A** automated and passing, **S** schema-check, **L** logic-check, **M** manual (needs the live backend, a device or a store account), **-** not run.

| case | flow | what | how | result |
| --- | --- | --- | --- | --- |
| F01-H1 | sign up | email sign up, confirm, land in onboarding | M | - (needs hosted Supabase) |
| F01-H2 | sign up | Sign in with Apple | M | - |
| F01-N1 | sign up | invalid email rejected before any request | A | pass |
| F01-N2 | sign up | password under 8 characters rejected | M (same code path as N1) | - |
| F01-E1 | onboarding | can't continue without weight | A | pass |
| F01-E2 | onboarding | guardrail warns on > 1% body weight per week | L | pass |
| F02-H1 | log food | search, pick, log; entry appears in the diary | A | pass |
| F02-E1 | log food | amount 0 can't be logged, message shown | A | pass |
| F02-E2 | log food | delete then Undo restores the entry | A | pass |
| F02-E3 | log food | logging at 23:30 lands on today, not tomorrow (local day) | L (Day uses local calendar) | pass |
| F02-E4 | log food | second user can't see or reference my foods/entries | S | pass |
| F03-H1 | barcode | known code found in database, then Open Food Facts | M (camera) | - |
| F03-N1 | barcode | unknown code goes to the custom food editor | M | - |
| F04-H1 | photo | mince+: photo -> items -> log | M (needs ANTHROPIC_API_KEY) | - |
| F05-H1 | voice / Siri | text -> items -> log | M | - |
| F06-H1 | review day | groups, entries, energy summary, nutrient tables | A | pass |
| F06-H2 | review day | tap nutrient -> sources from today's foods | A | pass |
| F06-E1 | review day | previous-day navigation | A | pass |
| F06-E2 | review day | totals: food + quick add summed once per nutrient | S | pass |
| F07-H1 | recipe | ingredients -> recompute per 100 g | S | pass |
| F07-E1 | recipe/food | editing a food keeps past entries' serving names | code review (serving ids preserved) | - |
| F08-H1 | import recipe | URL with JSON-LD -> matched ingredients | M | - |
| F07-H2 | foods | create a custom food; Save needs name and energy | A | pass |
| F07-H3 | foods | create a meal from searched foods | A | pass |
| F07-H4 | foods | create a recipe; per-serving energy = total / servings | A | pass |
| F07-H5 | foods | delete (archive) a custom food | A | pass |
| F07-H6 | share | shared-food RPC decodes; import gets fresh serving ids | contract-check + code | pass |
| F08-N2 | import recipe | private / IP-literal URLs rejected, also after redirects | function tests | pass |
| F08-H2 | import recipe | JSON-LD (incl. @graph, HowToSection) parsed; page prose not sent; unmatched lines kept | function tests | pass |
| F04-H2 | photo | mince+ + quota enforced; image sent; items and extras matched; photo deleted even on failure | function tests | pass |
| F05-H2 | voice | refusal 422, truncated 422, malformed 502; grams clamped; text capped | function tests | pass |
| F12-H3 | purchase | Apple re-fetch, someone else's purchase 403, expired/refunded no mince+, sandbox fallback, Xcode only with dev flag, token signature | function tests | pass |
| F12-H4 | renewals | dedupe, grace period, owner fallback, retry after Apple outage | function tests | pass |
| F16-H2 | delete account | storage emptied, then auth user deleted with the service key | function tests | pass |
| F02-H5 | diary | edit an entry's amount | A | pass |
| F02-H6 | diary | copy an entry, paste on another day | A | pass |
| F02-H7 | diary | multi-select delete, Undo restores | A | pass |
| F02-H8 | diary | add a diary group; it appears in the diary | A | pass |
| F06-H3 | diary | mark day complete | A | pass |
| F09-H3 | water / note / weight | each adds to the diary; water shows in mL | A | pass |
| F10-H2 | fasting | end and start a fast | A | pass |
| F11-H2 | trends (mince+) | 30-day range; create a custom chart | A | pass |
| F13-H2 | targets | Macro Scheduler template; nutrient override shown as custom | A | pass |
| F14-H2 | repeat items | repeat from the diary, listed in Repeat items | A | pass |
| F16-H3 | data | bulk delete clears the diary | A | pass |
| SMOKE | all | every tab and every More screen opens without an error | A | pass |
| F08-N1 | import recipe | private / IP-literal URLs rejected | code review (`safeURL`) | - |
| F09-H1 | quick add | label + kcal -> row in diary | A | pass |
| F09-H2 | exercise | MET estimate shown, row added with activity name | A | pass |
| F10-H1 | fasting | open fast shows timer and schedule | A | pass |
| F10-E1 | fasting | can't open two fasts at once | S | pass |
| F11-N1 | trends | Basic: longer range opens paywall (client) | A | pass |
| F11-N2 | trends | Basic: server refuses ranges > 7 days | S | pass |
| F12-N1 | mince+ | Basic: Photo opens paywall | A | pass |
| F12-H1 | mince+ | mince+: Photo log opens | A | pass |
| F12-H2 | mince+ | purchase with StoreKit test config, server records it | M (Xcode run + ALLOW_XCODE_STOREKIT) | - |
| F13-E1 | targets | macro % must total 100 | A | pass |
| F13-H1 | targets | Mifflin / Katch / keto / Macro Scheduler templates | L | pass |
| F14-H1 | repeat items | materialised once; deleted day stays deleted | S | pass |
| F15-H1 | Apple Health | import is idempotent (unique external id) | S (index) + M (device) | - |
| F16-H1 | data | bulk delete range, delete account | M | - |
| A11Y-1 | all | Diary: element descriptions + hit regions audit | A | pass |
| A11Y-2 | all | Diary at accessibility XXXL text: nothing truncated | screenshot | pass |
| A11Y-3 | all | colour contrast of every token pair, light and dark | `contrast.py` | pass (0 AA failures) |
