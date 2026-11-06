#!/bin/sh
# Compiles the pure model/logic files with a self-check and runs it. No simulator needed.
set -e
cd "$(dirname "$0")/../.."
OUT="${TMPDIR:-/tmp}/mince-logic-check"
xcrun swiftc -o "$OUT" replica/logic-check/main.swift \
  mince/Models/Day.swift mince/Models/Nutrition.swift mince/Models/Profile.swift mince/Models/Food.swift \
  mince/Models/PlusFeatures.swift mince/Utilities/Targets.swift mince/Utilities/Units.swift mince/Utilities/NutritionScores.swift
"$OUT"
