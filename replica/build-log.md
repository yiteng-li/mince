# Build log: mince

Checks used throughout: `xcodebuild` (0 errors, 0 warnings in app sources), `replica/logic-check/run.sh` (domain logic),
`replica/schema-check` (`npm test`, schema + RLS + RPCs in PGlite), simulator screenshots in demo mode (`-demo`, see `mince/Utilities/Demo.swift`).
Screens are verified against fixture data; the live Supabase path compiles but has not run end to end (no backend applied yet).

| ID | date | status | missing / notes | harder than expected |
| --- | --- | --- | --- | --- |
| shell | 2026-11-05 | done | 5 tabs, + menu (nav bar), sheet router `LogSheet`, deep links `mince://` | moving + off a floating button: it covered row values |
| S01/S02 | 2026-11-05 | done | email + password, Apple, reset | Apple needs the Supabase provider configured |
| S03 | 2026-11-05 | done | 5 steps, guardrail, writes first weight biometric | |
| S04 | 2026-11-05 | done | ring, macros, streak, water, fast, scores, weight trend, pinned charts, coach | |
| S05 | 2026-11-05 | done | groups, subtotals (Gold), energy summary, nutrient tables, swipe/undo, multi-select, copy/paste, copy yesterday, move group, repeat, complete | |
| S06 | 2026-11-05 | done | order/visibility from profiles.plus_menu | |
| S07/S08 | 2026-11-05 | done | search (FTS + trigram), recents, filters, meals, branded via Open Food Facts, serving picker, time (Gold) | |
| S09 | 2026-11-05 | done | camera + manual code, OFF lookup, unknown -> custom food | |
| S10/S11 | 2026-11-05 | partial | review UI done; Edge Functions in backend step | |
| S12-S16 | 2026-11-05 | done | quick add, exercise (MET), biometrics (pair/scale/duration), note, water | |
| S17 | 2026-11-05 | done | timer, history edit, schedules + local notifications | |
| S18-S21 | 2026-11-05 | done | custom foods (per-serving entry -> per 100 g), recipes (cooked weight, servings), meals, share (Gold) | serving ids must survive edits or past entries lose their serving name |
| S22 | 2026-11-05 | partial | UI + unmatched-line fixing; Edge Function in backend step | |
| S23-S26 | 2026-11-05 | done | ranges (7d Basic), energy chart, averages, scores, suggestions, custom + biometric charts, nutrient sources, Oracle | |
| S27/S28 | 2026-11-05 | done | BMR formulas, activity, goal, macro modes, presets, overrides, Macro Scheduler | |
| S29 | 2026-11-05 | done | rule editor + list; materialised on day open | |
| S30 | 2026-11-05 | done | private bucket, signed URLs | |
| S31 | 2026-11-05 | done | HealthKit import (workouts, active energy, weight, vitals, sleep) + nutrition export | needs HealthKit capability on a signed device build |
| S32 | 2026-11-05 | done | settings, groups, + menu, data, about | |
| S33 | 2026-11-05 | partial | StoreKit 2 + `Products.storekit` for local testing; server verification in backend step | |
| S34 | 2026-11-05 | done | PDF (ImageRenderer), daily totals CSV, full diary CSV | |
| S35 | 2026-11-05 | partial | dashboard card; Edge Function in backend step | |
| S36 | 2026-11-05 | partial | Siri / Shortcuts intent done; widgets and Watch need new Xcode targets | |

Bugs caught by the checks: daily totals double-counted energy (SQL), 63.5 kg showed as "9 st 14 lb" (rounding), saving a food would have
nulled serving_id on past entries, `Day` used UTC so late-evening logs landed on tomorrow (the starter code had this bug).
