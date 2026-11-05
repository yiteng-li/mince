# Bugs: mince

Found while building and testing. All fixed in the working tree (nothing is committed yet).

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

## To check (not reproduced)

- Live backend paths (auth, Edge Functions, purchases, HealthKit on device) haven't run end to end; first run after `supabase db reset --linked` may surface PostgREST shape mismatches.
- The accessibility audit's Dynamic Type check reports texts inside `ViewThatFits` branches that aren't displayed; screenshots at XXXL show no truncation.
- `Products.storekit` scheme path (`../../Products.storekit`) is unverified until you run from Xcode.
