# Test plan: mince

Automated: `minceUITests` (XCUITest, demo mode, 16 cases), `replica/logic-check/run.sh` (domain logic), `replica/schema-check` (`npm test`: schema, RLS, RPCs),
`deno check` on Edge Functions. Run the UI suite with:

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
| F04-H1 | photo | Gold: photo -> items -> log | M (needs ANTHROPIC_API_KEY) | - |
| F05-H1 | voice / Siri | text -> items -> log | M | - |
| F06-H1 | review day | groups, entries, energy summary, nutrient tables | A | pass |
| F06-H2 | review day | tap nutrient -> sources from today's foods | A | pass |
| F06-E1 | review day | previous-day navigation | A | pass |
| F06-E2 | review day | totals: food + quick add summed once per nutrient | S | pass |
| F07-H1 | recipe | ingredients -> recompute per 100 g | S | pass |
| F07-E1 | recipe/food | editing a food keeps past entries' serving names | code review (serving ids preserved) | - |
| F08-H1 | import recipe | URL with JSON-LD -> matched ingredients | M | - |
| F08-N1 | import recipe | private / IP-literal URLs rejected | code review (`safeURL`) | - |
| F09-H1 | quick add | label + kcal -> row in diary | A | pass |
| F09-H2 | exercise | MET estimate shown, row added with activity name | A | pass |
| F10-H1 | fasting | open fast shows timer and schedule | A | pass |
| F10-E1 | fasting | can't open two fasts at once | S | pass |
| F11-N1 | trends | Basic: longer range opens paywall (client) | A | pass |
| F11-N2 | trends | Basic: server refuses ranges > 7 days | S | pass |
| F12-N1 | Gold | Basic: Photo opens paywall | A | pass |
| F12-H1 | Gold | Gold: Photo log opens | A | pass |
| F12-H2 | Gold | purchase with StoreKit test config, server records it | M (Xcode run + ALLOW_XCODE_STOREKIT) | - |
| F13-E1 | targets | macro % must total 100 | A | pass |
| F13-H1 | targets | Mifflin / Katch / keto / Macro Scheduler templates | L | pass |
| F14-H1 | repeat items | materialised once; deleted day stays deleted | S | pass |
| F15-H1 | Apple Health | import is idempotent (unique external id) | S (index) + M (device) | - |
| F16-H1 | data | bulk delete range, delete account | M | - |
| A11Y-1 | all | Diary: element descriptions + hit regions audit | A | pass |
| A11Y-2 | all | Diary at accessibility XXXL text: nothing truncated | screenshot | pass |
| A11Y-3 | all | colour contrast of every token pair, light and dark | `contrast.py` | pass (0 AA failures) |
