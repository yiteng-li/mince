#!/bin/sh
# Every check that doesn't need a simulator. Needs Xcode command line tools, Node and Deno.
#   replica/check-all.sh
set -e
cd "$(dirname "$0")/.."
echo "== domain logic";        replica/logic-check/run.sh
echo "== schema, RLS, RPCs";   (cd replica/schema-check && npm i --silent && npm test --silent | grep -E "ALL OK|Error")
echo "== app <-> database";    (cd replica/contract-check && npm i --silent && sh run.sh | tail -2)
echo "== edge functions";      (cd supabase/functions && deno check */index.ts && deno test --allow-env --allow-read=. tests/)
echo "== all checks passed"
