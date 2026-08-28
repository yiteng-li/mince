# mince

A calorie/macro/micronutrient tracker. iOS + SwiftUI client, Supabase backend.

This repo currently holds **infrastructure only** — auth wiring, data models,
Supabase schema, navigation shell, networking plumbing — for the first
milestone: sign up → log in → see an empty diary → add a food → see totals
update. Feature logic (the calorie math, the diary layout, food search) is
left as `// TODO` stubs on purpose; see "What's stubbed" below.

## Architecture

**MVVM.** Views hold no business logic; `ViewModel`s (`ObservableObject`,
`@Published` state) call `Service`s; `Service`s own all Supabase/PostgREST
calls. This keeps the stub boundary clean — you fill in ViewModel/View logic
without needing to touch networking code.

**Nutrients as plain columns on `foods`, not an EAV table.** The tracked
nutrient set is fixed (macros + ~20 key micros, not Cronometer's full ~80),
so a `food_nutrients` join table would add query complexity with no real
payoff at this scale. See `supabase/migrations/0002_foods.sql`.

**Nutrients stored per-100g.** `foods` holds per-100g/100ml values plus a
`serving_size_g`/`serving_name` convenience default. `diary_entries` stores
`quantity_g` + `food_id` — not a nutrient snapshot — so totals always reflect
a food's current data. Computing those totals (join + scale + sum) is
exactly the logic left as a TODO in `DiaryViewModel`/`MacroTotals`.

**No stored calorie targets.** `profiles` holds raw inputs (age via DOB, sex,
height, weight, activity level, goal). Maintenance/target calories are
derived at read time by `CalorieCalculator` (a TODO) instead of being cached
columns — avoids a stale-target bug the moment someone edits their weight.

**Date columns are `String` (`yyyy-MM-dd`) in Swift**, not `Date`. Supabase's
default JSON decoding is tuned for `timestamptz`, and a plain Postgres `date`
column doesn't round-trip through that cleanly. Parse with a `yyyy-MM-dd`
`DateFormatter` wherever you need an actual `Date`.

## Project layout

```
Sources/mince/
  MinceApp.swift          entry point, injects AuthViewModel
  Models/                 Codable structs matching the Supabase schema
  Views/                  SwiftUI views, grouped by feature
  ViewModels/             ObservableObjects bridging Views ↔ Services
  Services/               Supabase/PostgREST calls, one struct per table (+ 2 protocol stubs)
  Utilities/              CalorieCalculator (TODO math)
supabase/migrations/      SQL to run in the Supabase SQL editor, in order
Secrets.xcconfig.example  copy to Secrets.xcconfig and fill in real values
```

## Xcode project setup (manual — do this once)

This repo has source files but no `.xcodeproj` yet; creating that is a
couple of GUI steps in Xcode:

1. Xcode → File → New → Project → iOS → App. Name it `mince`, interface
   **SwiftUI**, language **Swift**, minimum deployment **iOS 17**. Save it
   at the root of this repo (next to this README).
2. Quit Xcode. Delete the two placeholder files Xcode generated
   (`minceApp.swift`, `ContentView.swift`) — this repo's `Sources/mince/`
   replaces them.
3. Reopen the project, then drag the `Sources/mince` folder's *contents*
   (`MinceApp.swift`, `Models/`, `Views/`, `ViewModels/`, `Services/`,
   `Utilities/`) into the project navigator, into the `mince` group. Choose
   "Copy items if needed" **off** (keep them in place) and "Create groups".
4. File → Add Package Dependencies… → search
   `https://github.com/supabase/supabase-swift` → add the **Supabase**
   product to the `mince` target.

## Supabase setup

1. Create a project at [supabase.com](https://supabase.com).
2. SQL editor → run each file in `supabase/migrations/` **in order**
   (`0001` → `0004`). They create `profiles`, `foods`, `diary_entries`,
   `weight_logs` with row-level security enabled (or use the Supabase CLI:
   `supabase db push` if you've linked the project).
3. Project Settings → API → copy the Project URL and `anon` public key.
4. `cp Secrets.xcconfig.example Secrets.xcconfig`, fill in those two values.
   `Secrets.xcconfig` is gitignored — never commit real keys.
5. In Xcode: Project → Info → Configurations → set both Debug and Release to
   use `Secrets.xcconfig`. Then Target → Info → Custom iOS Target
   Properties → add two rows: `SUPABASE_URL` = `$(SUPABASE_URL)` and
   `SUPABASE_ANON_KEY` = `$(SUPABASE_ANON_KEY)`. `SupabaseService` reads
   those two Info.plist keys at runtime.
6. By default Supabase requires email confirmation for new accounts —
   either confirm via the email Supabase sends, or turn it off under
   Authentication → Providers → Email for faster local testing.

## Running

Build and run the `mince` target on an iOS 17+ simulator or device.

## What's stubbed

Wired for real: models, Supabase client, auth calls, CRUD service calls,
tab navigation, RLS policies, table schema.

Left as `// TODO` for you to write: Mifflin-St Jeor math
(`CalorieCalculator`), diary totals aggregation (`MacroTotals.from`), the
diary screen's actual layout (`DiaryView`), add-food search/filter and the
custom-food form (`AddFoodView`, `FoodService.search`), profile editing UI
(`SettingsView`), and sign-up/login error UX.

Explicitly out of scope, with extension points left in place:
`BarcodeScannerService` (protocol only, nothing implements or calls it) and
`FoodPhotoEstimationService` (protocol + a `MockFoodPhotoEstimationService`
fake, ready to swap for a real implementation later).

One thing to double-check once you can build: `AuthViewModel` calls
`client.auth.signInWithPassword` / `.signUp` / `.authStateChanges` — GoTrue's
auth API has renamed a few methods across supabase-swift versions, and this
couldn't be compiled against the SDK here, so verify those names match what
SPM resolves.
