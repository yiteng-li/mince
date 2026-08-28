# mince — Calorie Tracking App: Kickoff Prompt for Claude Code

I'm building **mince**, a calorie and macro/micronutrient tracking app for iOS, as a personal project to improve my Swift/SwiftUI and app development skills. This is explicitly a *learning project* — I want to write most of the actual feature logic myself. Your job right now is to set up the project **infrastructure and scaffolding** for the first feature only (the core calorie tracker), not to build the whole app.

## Tech stack
- **Client**: Native iOS, Swift + SwiftUI (SwiftUI App lifecycle, iOS 17+ target), MVVM architecture
- **Backend**: Supabase (Postgres, Auth, Storage). Use the official `supabase-swift` SDK via Swift Package Manager.
- **Package management**: Swift Package Manager only, no CocoaPods.

## Current scope — basic calorie tracker ONLY
Build infrastructure for:
1. Auth (sign up / log in / log out via Supabase Auth, email+password to start)
2. A daily diary: log meals/food entries, see running totals for calories + macros (protein/carb/fat) + a few key micronutrients
3. A food database: search/select existing foods, ability to add a custom food with full nutrition facts (modeled after Cronometer's data model — calories, macros, and a reasonable set of micronutrients per 100g/serving)
4. Basic user profile: age, sex, height, weight, activity level → maintenance/cut/bulk calorie targets (Mifflin-St Jeor or similar)

Explicitly **out of scope for now** (future features — just leave clean extension points, don't build):
- QR/barcode scanner (note where it would hook in, e.g. a `BarcodeScannerService` protocol stub)
- AI photo-based calorie estimation (note where it would hook in, e.g. a `FoodPhotoEstimationService` protocol stub with a fake/mock implementation for now)
- Community/social connection to a separate app

## What I want you to actually produce
1. **Xcode project scaffold** with a clean folder structure: `Models/`, `Views/`, `ViewModels/`, `Services/` (networking + Supabase clients), `Utilities/`, `Resources/`.
2. **Supabase schema** as SQL migration files (not applied — just give me the `.sql` I can run in the Supabase SQL editor or via CLI) for: `profiles`, `foods`, `diary_entries` (or `meal_entries`), `weight_logs`. Think through the nutrient columns you'd need to mirror Cronometer-style tracking (macros + key vitamins/minerals) and use sensible types/units.
3. **Supabase client setup**: a `SupabaseService` singleton or environment-injected client, with config read from a gitignored `Secrets.xcconfig` or `.env`-style file (give me a `.gitignore` and a `Secrets.xcconfig.example` template — don't put real keys anywhere).
4. **Auth flow scaffold**: SignUp/LogIn SwiftUI views wired to Supabase Auth, plus an `AuthViewModel` and a root view that switches between authed/unauthed state. Keep the actual validation/error-handling logic light — I want to fill some of that in myself.
5. **Core navigation shell**: a `TabView` with Diary, Add Food, Progress, Settings tabs (stub views are fine for tabs other than Diary).
6. **Data models**: Swift structs for `Food`, `DiaryEntry`, `UserProfile`, `MacroTotals` etc. matching the Supabase schema, `Codable` for Supabase's PostgREST responses.
7. A **README** explaining the architecture decisions, how to set up Supabase locally (env vars, running the SQL), and how to run the app.

## How I want you to work
- Scaffold and wire things up (project structure, models, networking plumbing, navigation) — this is the boring infrastructure I don't need to hand-write.
- For the actual feature logic (e.g., the calorie/macro calculation math, the diary view's UI layout, the "add food" search/filter behavior), stub the functions with clear `// TODO:` comments and a one-line description of what should happen, rather than fully implementing them. I want to write that part.
- Explain your architectural choices briefly as you go (e.g. why MVVM, why this table shape) so I actually learn from the setup, not just copy it.
- Ask me before adding any third-party dependency beyond `supabase-swift`.

## First milestone I'm aiming for
Being able to sign up, log in, see an empty diary for today, manually add a food with calories/macros, and see the daily total update. Get me to a scaffolded starting line for that, then stop and hand it back to me.
