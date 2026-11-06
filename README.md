# mince

A calorie, macro and micronutrient tracker for iOS: a rebuild of Cronometer's Basic and Gold features.
SwiftUI client, Supabase backend (Postgres + Auth + Storage + Edge Functions), StoreKit 2 subscriptions, Claude for photo/voice/recipe parsing.

Planning and status live in `replica/`: `recon.md` (screens, flows), `architecture.md` (stack, schema, API), `features.csv`
(what's built), `backend.md` (deploy steps, security checklist), `test-plan.md`, `bugs.md`, `build-log.md`.
[CONCEPTS.md](CONCEPTS.md) and SPECIFICATION.md describe the earlier starter version.

## Layout

```
mince/
  MinceApp.swift        entry point, injects AppModel
  Models/               Codable types matching the schema (Day, Food, DiaryEntry, Profile, mince+ types)
  Utilities/            Theme (design tokens), Targets (BMR, macros, DRI), Units, NutritionScores, Demo fixtures, Siri intent
  ViewModels/AppModel   session, profile, catalogues, mince+ status, selected day, sheet router
  Services/             one struct per area; Supabase, Open Food Facts, HealthKit, StoreKit, speech, Edge Functions
  Views/                Dashboard, Diary, Log (food, barcode, photo, voice, quick entries), Foods, Trends, Fasting, More, Paywall
supabase/
  migrations/           schema + RLS + RPCs, storage buckets, reference data (nutrients, DRIs, exercises, biometrics)
  functions/            photo-log, voice-parse, recipe-import, coach, verify-purchase, appstore-notifications, delete-account
  seed/usda_import.py   builds the shared food database from USDA FoodData Central downloads
Products.storekit       local StoreKit test products (mince+ monthly / annual)
minceUITests/           end-to-end tests in demo mode
```

## Run

1. Supabase: follow "Deploy" in `replica/backend.md` (reset the linked project, apply migrations, import USDA foods, set secrets, deploy functions).
2. `mince/Info.plist` holds `SUPABASE_URL` and `SUPABASE_ANON_KEY` (gitignored).
3. Open `mince.xcodeproj`, add HealthKit and Sign in with Apple under Signing & Capabilities, run.

No backend handy? Run a Debug build with launch argument `-demo` (add `-plus` for mince+ features) to use fixture data.

## Checks

```bash
replica/logic-check/run.sh                     # targets, units, scores, days
(cd replica/schema-check && npm i && npm test) # schema, RLS, RPCs in an in-memory Postgres
deno check supabase/functions/*/index.ts       # Edge Functions
# UI tests: see replica/test-plan.md
```
