#!/usr/bin/env bash
# Regenerate the cockpit's data files FROM the engine, so the "single source of
# truth" claim is a build step, not a promise. Run from the repo root:
#   scripts/regen-cockpit-data.sh
# CI runs this and `git diff --exit-code`s the result, so committed data can
# never drift from what the engine actually decides.
set -euo pipefail

here="$(cd "$(dirname "$0")/.." && pwd)"
data="$here/cockpit/src/data"
dataset="$data/dataset.json"

bin="$(cd "$here/engine" && cabal list-bin plm-access)"

# The dataset is the single input; every derived file comes from the engine.
"$bin" decisions < "$dataset" > "$data/decisions.json"
"$bin" eval      < "$dataset" > "$data/eval.json"
"$bin" diff      < "$dataset" > "$data/diff.json"

echo "regenerated: decisions.json, eval.json, diff.json (from dataset.json)"
