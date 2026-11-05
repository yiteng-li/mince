# Components: mince

Tokens: `tokens.json` (light), `tokens.dark.json` (dark), mirrored in `mince/Utilities/Theme.swift`.
Primitives: `mince/Views/DesignSystem/` (`Primitives.swift`, `DesignSystemView.swift` with `#Preview`).
Icons: SF Symbols only (platform icons, not Cronometer's). Font: system SF via Dynamic Type text styles.
No web stack, so no tokens.css / Tailwind: SwiftUI reads `Theme` directly. Screens never use raw hex or raw point sizes.

Shared rules
- Every tap target >= 44 pt. Every number uses `.monospacedDigit()`.
- Colour is never the only signal: over/under states also change the icon or label.
- Respect Dynamic Type up to accessibility sizes (rows wrap, never truncate a number), Reduce Motion (no ring animation), dark mode.
- Gold-locked controls stay visible with a `GoldBadge` and open the paywall (S33); they are never hidden.

```
PrimaryButton / SecondaryButton / DestructiveButton
  variants  primary (accent fill), secondary (surface + border), destructive (danger text), gold (gold fill, on-gold text)
  sizes     regular 50pt tall full-width; compact 36pt
  states    default, pressed (opacity .8), disabled (opacity .4, not tappable), loading (spinner replaces icon, label kept for VoiceOver)
  tokens    radius md, type heading, space 16 horizontal
  a11y      real Button, .accessibilityLabel = title, loading adds "loading" hint
  used on   S01-S03, S08, S10-S14, S17, S19-S22, S33

DateNavigator
  parts     chevron back, date title (Today / Yesterday / "Wed 5 Nov"), chevron forward, calendar sheet on title tap
  states    today, past, future (forward allowed: Cronometer lets you pre-log), day completed (checkmark.seal on title)
  tokens    type heading, text; chevrons accent
  a11y      chevrons labelled "Previous day" / "Next day"; swipe left/right on the diary also pages days
  used on   S05, S23

DiaryGroupSection
  parts     header (group name, optional subtotal kcal [Gold], add button), rows, empty prompt "Add food"
  states    empty, filled, collapsed
  tokens    header type label/text-muted, surface card, radius lg
  a11y      header is .isHeader; add button "Add to <group>"
  used on   S05

DiaryEntryRow
  kinds     food (name, amount + unit, kcal), quick_add, exercise (minutes, -kcal in success), biometric (value + unit), note (2-line text), water
  states    default, selected (multi-select checkmark), timestamped (time caption, Gold), repeated (arrow.triangle.2.circlepath glyph)
  gestures  swipe trailing delete -> toast with Undo; swipe leading copy; long-press context menu (edit, copy, move group, repeat [Gold], delete)
  tokens    type body + footnote/text-muted, row-min-height 44
  a11y      combined element: "Almonds, 50 grams, 290 calories"; actions exposed as accessibilityActions
  used on   S05

EnergyRing
  parts     ring (consumed / target), centre remaining kcal, caption consumed / burned
  states    under, at target (+-5%), over (ring turns warning, label "over by N")
  tokens    energy on track, ring-size 160, ring-line 14, type metric
  a11y      single element: "1,240 of 2,100 calories eaten, 860 remaining"
  used on   S04, S05

EnergySummary
  parts     consumed; burned = BMR + baseline activity + exercise + TEF; remaining; tap to expand breakdown
  tokens    surface card, type body/footnote
  used on   S05

MacroBar / NutrientBar
  parts     label, amount / target + unit, % bar, optional min-max band
  states    no target (bar hidden, amount only), below min (track only + text-muted %), in range (colour fill), over max (warning fill + exclamationmark.triangle)
  tokens    protein / carbs / fat / accent fill on track, bar-height 8, radius pill
  a11y      "Protein, 82 of 120 grams, 68 percent"
  used on   S04, S05, S23

NutrientTargetTable
  parts     category header (General, Carbohydrates, Lipids, Protein, Vitamins, Minerals, Other), NutrientBar rows; tap row -> nutrient sources + Oracle [Gold]
  states    loading (redacted placeholder rows), filled
  used on   S05, S23

SearchField + FilterChips
  parts     .searchable field, chips: All, Foods, My foods, Recipes, Meals; sort menu
  states    empty (shows Recent), typing (debounced 250 ms), results, no results ("Create custom food" button), error (retry)
  a11y      chips are toggle buttons with selected trait
  used on   S07, S18, S26

ServingPicker
  parts     quantity field (decimal keypad), unit menu from food_servings (+ g, oz), live nutrition preview, group picker, time picker [Gold]
  states    invalid quantity (danger caption, add disabled)
  used on   S08, S20, S21

NutritionLabel
  variants  compact (kcal + P/C/F), full (all nutrients, grouped like NutrientTargetTable)
  used on   S08, S19, S20

FormField
  parts     label, input, unit suffix, helper / error caption
  states    default, focused (accent border), error (danger border + caption), disabled
  tokens    border-input, radius md
  used on   S01-S03, S12-S14, S19, S27

Chart
  variants  line (weight, biometrics), bar (energy per day), dual-axis (custom charts, Gold)
  states    empty ("Log a few days to see a trend"), data, range-locked (blurred + GoldBadge beyond 7 days)
  tokens    Swift Charts, series colours from macro/energy roles
  a11y      .accessibilityChartDescriptor with summary
  used on   S04, S24

TimerRing (fasting)
  states    idle (Start fast), active (elapsed / target, End fast), complete (success), scheduled (next start time)
  used on   S17, S04

GoldBadge + PaywallSheet
  badge     "Gold" capsule, gold fill, on-gold text, lock.fill glyph
  sheet     plan cards (monthly / annual, annual marked best value), restore purchases, terms + privacy links, close
  states    loading products, purchasing, success, failed, pending (Ask to Buy)
  used on   every Gold entry point, S33

Toast
  parts     message + optional Undo, auto-dismiss 4 s, swipe to dismiss
  a11y      posted as an accessibility announcement
  used on   S05, S18

PlusMenu
  parts     grid of actions (Food, Barcode, Photo [Gold], Voice [Gold], Quick add, Exercise, Biometric, Water, Note, Fast [Gold])
  states    default, edit mode (reorder / hide, saved to profiles.plus_menu)
  used on   S06

EmptyState
  parts     SF Symbol, one-line title, one-line hint, optional action
  used on   every list
```
