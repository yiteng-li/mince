# Recon map: Cronometer (iOS)

Scope: the whole consumer app, Basic + Gold tiers, rebuilt as the existing `mince` SwiftUI + Supabase app. Excludes Cronometer Pro/Enterprise (professional client management).
For: the owner's own learning project (mince), possibly shipped to the App Store later.
Date: 2026-11-05

## Sources

| # | source | URL | notes |
| --- | --- | --- | --- |
| 1 | Gold page (pricing + full Gold list) | https://cronometer.com/gold/ | 19 Gold features, $10.99/mo or $59.99/yr; Basic vs Gold table |
| 2 | Free version page | https://cronometer.com/features/free-nutrition-tracking-app.html | Basic limits: 7-day insights, 2 basic charts |
| 3 | Track food | https://cronometer.com/features/track-food.html | 4 logging methods, water, copy/paste, multi-select |
| 4 | Exercise & biometrics | https://cronometer.com/features/track-exercises-and-biometrics.html | weight, stool (Bristol), measurements, mood, labs, sleep |
| 5 | Custom diet tracking | https://cronometer.com/features/custom-diet-tracking.html | keto/vegan/etc presets, Macro Scheduler, fasting |
| 6 | Meals & recipes | https://cronometer.com/features/custom-meals-and-recipes.html | meals vs recipes, importer, photo-to-recipe |
| 7 | Reports & charts | https://cronometer.com/features/reports-and-charts.html | nutrition report, charts, custom charts |
| 8 | Integrations | https://cronometer.com/features/sync-devices.html | Apple Health two-way; Fitbit/Garmin/Oura/WHOOP/Dexcom import |
| 9 | Changelog 2021-2026 | https://cronometer.com/blog/cronometer-updates-whats-new-improved | Diary Groups, timestamps, undo, bulk delete, widgets, streaks, snapshots, water, CGM |
| 10 | App Store listing | https://apps.apple.com/us/app/cronometer-calorie-counter/id1145935738 | 4.8 / 100K ratings, IAP prices, Siri + Watch logging |
| 11 | Help center | https://cronometer.zendesk.com/hc/en-us | 403 to automated fetch; read manually if needed |
| 12 | User's own account | — | not used yet; would confirm states marked "guess" below |

## Core loop

Log what you ate (search / barcode / photo / voice) into today's diary and see calories, macros and ~84-95 micronutrients against personal targets.

## Screens

Mobile nav (medium confidence, from changelog + listing): tab bar **Dashboard · Diary · Trends/Discover · Foods · More**, plus a centre **+** menu (customisable).

| ID | screen | route / how to reach | purpose | key components | states seen |
| --- | --- | --- | --- | --- | --- |
| S01 | Welcome / sign up | first launch | create account | email+password, Apple sign-in, demo account | empty, error |
| S02 | Log in / reset password | S01 | auth | form, forgot-password link | error, loading |
| S03 | Onboarding: profile + target wizard | after sign-up | sex, DOB, height, weight, activity, weight goal + rate, diet preset | stepper wizard, pickers, guardrail warnings | validation error |
| S04 | Dashboard | tab 1 | today at a glance | energy ring, macro bars, streak, water widget, fasting card, pinned charts, nutrition scores, Crono Coach tip | empty day, filled |
| S05 | Diary (day) | tab 2 | log + review a day | date nav/calendar, diary groups (Breakfast/Lunch/Dinner/Snacks, renamable), entries (food/exercise/biometric/note), Energy Summary, Nutrient Targets tables, Mark Day Complete | empty, filled, past day, future day, loading |
| S06 | Plus menu | centre + | entry point to every log type | customisable action grid: food, barcode, photo, voice, exercise, biometric, note, water, fast, quick-add | — |
| S07 | Add food: search | S06 | find a food | search field, filters (all/common/branded/custom/meals/recipes), sort, recent/frequent, multi-select | empty query, no results, loading |
| S08 | Food detail / serving picker | tap a result | choose amount + group + time | serving unit picker, quantity, nutrition label preview, group picker, timestamp (Gold) | — |
| S09 | Barcode scanner | S06 | scan UPC | camera view, manual code entry, not-found → create food | permission denied, not found |
| S10 | Photo log (Gold) | S06 | AI identify foods from a photo | camera, detected items list w/ servings, ingredient suggestions (oil/butter), save-as-recipe | analysing, low confidence, error |
| S11 | Voice log (Gold) | S06 / Siri | speak a meal | mic button, transcript, parsed items list, confirm | permission denied, no match |
| S12 | Quick add | S06 | log raw kcal/macros without a food | kcal, P/C/F fields | — |
| S13 | Exercise log | S06 | log a workout | exercise search, duration, kcal override | imported vs manual |
| S14 | Biometric log | S06 | log weight/measurements/labs/mood/stool/sleep | metric picker by category, value + unit, custom metric (Gold) | — |
| S15 | Note | S06 | free-text day note | text editor | — |
| S16 | Water | S06 / diary widget | log water | +cup buttons, total vs target | — |
| S17 | Fasting timer (Gold) | S06 / S04 | start/stop/schedule fasts | timer ring, presets (16:8 etc.), recurring schedule, history | active, scheduled, none |
| S18 | Foods hub | tab 4 | manage custom foods, meals, recipes | segmented list, search, create buttons | empty |
| S19 | Custom food editor | S18 / S09 not-found | enter a nutrition label | name, brand, barcode, serving sizes (incl. volumetric), all nutrients | validation |
| S20 | Recipe editor | S18 | build a recipe | ingredients list, servings / final weight, advanced serving sizes, nutrition summary, share (Gold) | — |
| S21 | Meal editor | S18 / save group as meal | bundle foods | item list, explode-on-log option | — |
| S22 | Recipe importer (Gold) | S18 | URL or pasted text → recipe | URL field, paste area, parsed ingredient matches, fix-ups | parsing, unmatched lines |
| S23 | Trends / Reports | tab 3 | nutrition over a range | date range (7d Basic, any Gold), averages vs targets, top food sources per nutrient, highlighted nutrients | range-locked (Basic) |
| S24 | Charts | S23 | plot metrics over time | weight chart, energy chart (Basic); Custom Charts any nutrient/biometric, dual axis, pin to dashboard (Gold) | locked |
| S25 | Nutrition Scores (Gold) | S04 / S23 | composite scores (keto, plant-based, women's/men's health, calcium absorption, etc.) | score cards, per-nutrient breakdown, up to 8 selected | — |
| S26 | Oracle / Food Suggestions (Gold) | S05 nutrient row / S23 | best foods for a nutrient / remaining targets | nutrient picker, ranked food list | — |
| S27 | Targets settings | More | energy + macro + micro targets | BMR method, activity, weight goal, macro mode (ratio %, grams, keto), per-nutrient min/max, diet presets | — |
| S28 | Macro Scheduler (Gold) | S27 | per-weekday macro templates | template list, weekday assignment | — |
| S29 | Repeat items (Gold) | entry context menu | schedule a food/meal to auto-appear | daily / weekly / specific days | — |
| S30 | Progress photos (Snapshots) | More / S14 | dated body photos | grid, compare | empty |
| S31 | Integrations | More | connect Apple Health etc. | provider list, toggles per data type | connected, error |
| S32 | More / Settings | tab 5 | account, units, diary groups, display, data | sections, search | — |
| S33 | Subscription / paywall | any Gold lock | upgrade | plan cards (monthly/annual), restore purchases | purchasing, active, expired |
| S34 | Print / export report (Gold) | S23 | PDF report, CSV export | range picker, share sheet | generating |
| S35 | Crono Coach (Gold) | S04 | AI guidance from user data | chat/tip cards | — |
| S36 | Widgets + Watch + Siri | system | glanceable totals, streak, quick log | WidgetKit, App Intents | — |

## Flows

```
F01 Sign up and get targets
    S01 -> S03 (wizard) -> S04
    happy path clicks: ~8
    edge: email taken, unconfirmed email, unsafe weight-loss rate (guardrail), skip wizard

F02 Log a food by search (core loop)
    S05 -> S06 -> S07 -> S08 -> S05 (totals + targets update)
    happy path clicks: 4 (+, food, tap result, add)
    edge: no results, food in different unit (cups vs g), log to past date, wrong group

F03 Log by barcode
    S06 -> S09 -> S08 -> S05 ; not found -> S19 -> S08
    happy path clicks: 3
    edge: camera denied, unknown UPC, OFF data missing nutrients

F04 Log by photo (Gold)
    S06 -> S10 (capture -> review items -> adjust) -> S05 ; optional save as recipe
    happy path clicks: 4
    edge: non-food photo, hidden oil/butter, low-confidence item

F05 Log by voice / Siri (Gold)
    S06 -> S11 -> confirm -> S05
    edge: ambiguous quantity, no match

F06 Review the day
    S05 Energy Summary + Nutrient Targets -> tap nutrient -> S26 suggestions (Gold)
    edge: no targets set, over max (e.g. sodium upper limit)

F07 Create recipe / meal
    S18 -> S20 (add ingredients via S07) -> save -> log via S07
    edge: recipe weight after cooking, volumetric serving, explode on log

F08 Import recipe (Gold)
    S18 -> S22 (URL) -> review matches -> S20 -> save
    edge: site blocks fetch, unmatched ingredient lines

F09 Log exercise, biometric, water, note
    S06 -> S13 | S14 | S16 | S15 -> S05
    edge: duplicate imported workout, unit conversion (lb/kg, stones)

F10 Fasting (Gold)
    S04/S06 -> S17 start -> end -> history on S05
    edge: fast spans midnight / DST, recurring schedule

F11 Trends and charts
    S23 range -> S24 chart; Basic limited to 7 days -> S33 paywall
    edge: range with gaps, mixed units

F12 Upgrade to Gold
    any lock -> S33 -> StoreKit purchase -> unlocked
    edge: restore on new device, expiry, refund, family sharing

F13 Change targets / macro schedule
    S32 -> S27 -> S28 (Gold)
    edge: macro % not summing to 100, keto mode net carbs

F14 Repeat items (Gold)
    S05 entry -> S29 -> appears on future days
    edge: edited after repeat set, deleted on one day only

F15 Connect Apple Health
    S31 -> HealthKit permission -> import workouts/weight/sleep; export nutrition
    edge: permission partially denied, double-counted energy

F16 Export / print / delete data
    S34 PDF/CSV ; S32 bulk delete date range ; delete account
```

## Components

| component | variants | states | used on |
| --- | --- | --- | --- |
| Primary button | primary, secondary, destructive, Gold-locked | default, pressed, disabled, loading | all |
| Date navigator | day pager + calendar sheet | today, past, completed-day mark | S05, S23 |
| Diary group section | food group, exercise, biometrics, notes | collapsed, expanded, subtotal | S05 |
| Diary entry row | food, exercise, biometric, note, water, fast | swipe delete/copy, multi-select, timestamp | S05 |
| Energy ring / summary | consumed vs burned vs remaining; BMR, activity, exercise, TEF breakdown | under, over | S04, S05 |
| Macro bars | P/C/F (+ net carbs) | under, in range, over | S04, S05 |
| Nutrient target row | category tables (General, Carbs, Lipids, Protein, Vitamins, Minerals) | % bar, below min, over max, no target | S05, S23 |
| Search field + filter chips | — | empty, typing, results, no results | S07, S18, S26 |
| Serving picker | unit wheel + quantity | — | S08, S20 |
| Nutrition label | full / compact | — | S08, S19 |
| Paywall lock badge | inline badge, full sheet | locked, trial | Gold features |
| Chart | line, bar, dual-axis | empty, data, locked range | S04, S24 |
| Timer ring | fasting | idle, active, done | S17, S04 |
| Toast + undo | — | shown, dismissed | S05 delete |
| Plus menu grid | — | edit mode | S06 |

## Inferred data model

```
User/Profile   id, display_name, sex, dob, height_cm, weight_kg, activity_level, unit prefs (metric/imperial/stones), locale, tz
               evidence: S03 wizard, changelog (stones, units) ; confidence: high

TargetSettings user_id, bmr_method, activity_level, weight_goal_kg_per_week, macro_mode (ratio|grams|keto), protein/carb/fat targets, diet_preset
               evidence: S27, changelog "macro % ratios" (Jul 2024), Galveston/keto presets ; confidence: high

NutrientTarget user_id, nutrient_id, min, max, enabled  (defaults from DRI by sex/age)
               evidence: S05 targets tables, "custom macro and micronutrient targets" ; confidence: high

MacroSchedule  user_id, weekday, template (kcal, P, C, F)   [Gold]
               evidence: Gold page ; confidence: high

Nutrient       id, name, unit, category, display order (84-95 rows)
               evidence: "up to 95 nutrients", nutrient tables ; confidence: high (catalog), guess on exact list

Food           id, source (usda|off|custom|recipe), owner_id, name, brand, barcode, nutrients per 100 g, is_public/shared
FoodServing    food_id, name ("1 cup"), grams (or ml), is_default
               evidence: S08 serving picker, volumetric servings (May 2024) ; confidence: high

Recipe         = Food with source=recipe + RecipeIngredient(recipe_id, food_id, serving_id, quantity), servings, final_weight_g
Meal           id, owner_id, name, explode_on_log + MealItem(meal_id, food_id, serving_id, quantity)
               evidence: S20/S21, "explode Custom Meals" (Feb 2024) ; confidence: high (meal vs recipe split medium)

DiaryGroup     user_id, position, name (Breakfast/Lunch/Dinner/Snacks, renamable)
DiaryEntry     id, user_id, day (date), group_id, logged_at (timestamp, Gold), kind (food|exercise|biometric|note|quick_add|water),
               food_id/serving/quantity | exercise fields | biometric fields | note text
               evidence: S05, Diary Groups for all (May 2024), timestamps (Gold) ; confidence: high
DayStatus      user_id, day, completed bool
               evidence: "Mark Day As Complete" ; confidence: high

Exercise       catalog: id, name, MET value ; ExerciseEntry: minutes, kcal, source (manual|healthkit)
               evidence: S13, Pickleball added to database ; confidence: medium (MET-based is a guess)

BiometricType  id, owner_id (null = built-in), name, unit, category   [custom = Gold]
Biometric      user_id, type_id, value, measured_at, source
               evidence: S14, biometric categories (Dec 2021) ; confidence: high

Fast           user_id, started_at, ended_at, target_hours ; FastSchedule recurring   [Gold]
RepeatRule     user_id, source entry (food/meal/recipe + qty + group), cadence (daily|weekly|weekdays[])   [Gold]
Snapshot       user_id, day, photo path
Integration    user_id, provider, status, tokens/last_sync
Subscription   user_id, tier, product_id, expires_at, original_transaction_id
               evidence: Gold page, StoreKit IAP on listing ; confidence: high
ScoreSelection user_id, score_id (up to 8)   [Gold] ; Score formulas: guess
CustomChart    user_id, series[], range, pinned   [Gold]
Share          food/recipe id, share token   [Gold]
```

Relationships: User 1-1 Profile/TargetSettings; User 1-n DiaryEntry, DiaryGroup, Biometric, Fast, RepeatRule, Food(custom), Meal; Food 1-n FoodServing; Recipe n-n Food via RecipeIngredient; Meal n-n Food via MealItem; DiaryEntry n-1 Food.

## Feature matrix

See `features.csv`. Must: 33, should: 23, could: 12, skip: 8.

## Out of scope (cannot or should not be cloned)

- Cronometer's curated food database (NCCDB licensed + their lab-analysed data). Use USDA FoodData Central (public domain) + Open Food Facts (ODbL, already wired via `OpenFoodFactsService`).
- Cronometer's nutrition score formulas, copy, logo, icons and brand. Write our own scores from published sources (e.g. DRI coverage), our own names.
- Partner perks (WHOOP/Oura discounts), Instacart ordering, Refer-a-Friend rewards: partner deals.
- Ads: Basic is ad-supported; mince has no reason to show ads. "Ad-free" is the default.
- Cronometer Pro / Enterprise (client management for dietitians).
- Device integrations that need partner approval (Garmin, WHOOP, Oura, Dexcom, Polar, Withings, Suunto) — could later via their public developer programmes; Apple Health covers most of it on iOS.
- Newsfeed / Discover editorial content.

## Size

Screens 36, flows 16, entities ~22. Hard parts: nutrient catalogue + DRI targets (~90 nutrients, age/sex bands); food database seeding (USDA FDC import + search ranking); photo/voice logging (vision/LLM API); HealthKit two-way sync without double-counting energy; StoreKit 2 subscriptions with server-side entitlement; recipe importer (HTML schema.org/Recipe parsing + ingredient matching). Size: **XL** — rescope into milestones (see architecture build order).
