#!/bin/sh
# App <-> database contract: Swift encodes real payloads, Postgres (PGlite) stores them under RLS and returns
# every read shape, Swift decodes them. Needs Xcode command line tools and Node (npm i once).
set -e
cd "$(dirname "$0")"
OUT="${TMPDIR:-/tmp}/mince-contract"
mkdir -p "$OUT"
M=../../mince/Models; U=../../mince/Utilities
xcrun swiftc -o "$OUT/harness" main.swift $M/Day.swift $M/Nutrition.swift $M/Profile.swift $M/Food.swift $M/Diary.swift $M/Gold.swift
"$OUT/harness" encode > "$OUT/payloads.json"
node check.mjs "$OUT/payloads.json" "$OUT/rows.json"
"$OUT/harness" decode "$OUT/rows.json"
