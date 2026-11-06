# Bugs: mince

Found while building and testing. All fixed.

### BUG-001: Diary date arrows fire every button in the row
- Severity: S2 · Flow F06-E1 · Screen S05 · Device: iPhone 17 Pro sim, iOS 26.0
Steps: 1. Open Diary. 2. Tap the left chevron.
Expected: yesterday. Actual: stays on today (prev, calendar and next all fire inside a List row); chevron hit area 8×14 pt.
Evidence: testF06_E1_previousDayNavigation, accessibility audit "Hit area is too small".
Status: fixed (borderless buttons, 44 pt targets in `DateNavigator`).

### BUG-002: Number fields put the cursor before the existing value
- Severity: S3 · Flow F02-E1 · Screen S08
Steps: 1. Open a food. 2. Tap Amount ("1"). 3. Type 0.
Expected: 0. Actual: "01" (right-aligned field, cursor at start).
Evidence: testF02_E1_zeroAmountCannotBeLogged debug output `amount value: 01`.
Status: fixed (`NumberField` selects its text on focus).

### BUG-003: "How burned adds up" tap target 16 pt tall
- Severity: S3 · Screen S04/S05 · Evidence: accessibility audit. Status: fixed (custom 44 pt toggle).

### BUG-004: Energy card unreadable at large text sizes
- Severity: S3 · Screen S04/S05 · Steps: Settings > Accessibility > Larger Text, max. Actual: "Eat-en", "1,3 / 52 kcal", "kcal left" outside the ring.
Evidence: replica/clone-screens (XXXL screenshot before/after). Status: fixed (stacks when it doesn't fit; ring text capped).

### BUG-005: Nutrient bar names/values truncate at large text sizes
- Severity: S4 · Status: fixed (`ViewThatFits`, wrapping text).

### BUG-006: Daily totals counted energy twice when a day had quick adds
- Severity: S2 · Flow F06-E2 · Found by schema-check. Status: fixed (single aggregation in `nutrient_totals`).

### BUG-007: 63.5 kg displayed as "9 st 14 lb"
- Severity: S4 · Found by logic-check. Status: fixed (round before splitting stones).

### BUG-008: Editing a food would have cleared serving names on past entries
- Severity: S2 (data) · Found in review before release. Status: fixed (servings upserted by id, not deleted and re-created).

### BUG-009: Late-evening logs saved to tomorrow (starter code)
- Severity: S2 · Found in review: the starter `DiaryService` formatted days in UTC. Status: fixed (`Day` uses the device time zone).

### BUG-010: Opening a saved recipe would fail on the live backend
- Severity: S2 · Flow F07 · Found reading the select shapes for the contract check.
`recipe_ingredients` has two foreign keys to `foods`, so PostgREST rejects `food:foods(...)` as ambiguous.
Status: fixed (`food:foods!food_id(...)`).

### BUG-011: Opening a shared-food link always failed to decode
- Severity: S2 · Flow F07 (share) · Evidence: contract-check `rpc_get_shared_food -> keyNotFound food_id`.
Status: fixed (the RPC keeps `food_id` on servings).

### BUG-012: Importing a shared food tried to overwrite the sharer's servings
- Severity: S2 · The copy kept the original serving ids, so saving upserted rows owned by someone else (RLS blocks it, so the import failed).
Status: fixed (fresh serving ids on import).

### BUG-013: Select mode in the diary deleted nothing
- Severity: S2 · Flow F02 (multi-select) · Evidence: testF02_H4_multiSelectDelete, screenshot after tapping Delete showed the More tab.
Two causes: the row's tap handler swallowed selection taps, and the Copy/Delete bar sat under the tab bar, so Delete switched tabs.
Status: fixed (taps toggle selection; tab bar hidden while selecting). Undo restores every deleted row.

### BUG-014: Tapping the middle of a food row did nothing
- Severity: S3 · Foods list, ingredient picker, suggestions · Evidence: testF07_H2_createMeal.
Status: fixed (`contentShape` on `FoodResultRow`).

### BUG-015: Number fields had no name for VoiceOver
- Severity: S3 · All forms read fields as "0". Status: fixed (each field is labelled with its title).

### BUG-016: Water logs showed as "0 kcal · P 0g · C 0g · F 0g" rows
- Severity: S3 · Screen S05. Status: fixed (they read "Water · 500 mL").

### BUG-017: Edited entries briefly lost their serving name
- Severity: S4 · Until the next reload the row showed grams only. Status: fixed.

## To check (not reproduced)

- Live backend paths (auth, Edge Functions, purchases, HealthKit on device) haven't run end to end; first run after `supabase db reset --linked` may surface PostgREST shape mismatches.
- The accessibility audit's Dynamic Type check reports texts inside `ViewThatFits` branches that aren't displayed; screenshots at XXXL show no truncation.
- `Products.storekit` scheme path (`../../Products.storekit`) is unverified until you run from Xcode.
