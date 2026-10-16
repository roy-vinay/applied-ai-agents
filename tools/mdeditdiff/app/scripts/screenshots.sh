#!/bin/bash
# Takes the README screenshots of the built app (run on a Mac after build-app.sh; CI does this).
set -euo pipefail
cd "$(dirname "$0")/.."
APP="$PWD/build/mdEditDiff.app"
OUT="$PWD/../docs/img"
mkdir -p "$OUT"
WORK="$(mktemp -d)"
cp ../examples/plan.md "$WORK/plan.md"

shoot() { # name, extra app arguments...
  local name="$1"; shift
  open -n -a "$APP" "${WORK}/plan.md" --args "$@"
  sleep 9
  local id
  id="$(swift scripts/window_id.swift mdEditDiff || swift scripts/window_id.swift MDEditDiff)"
  screencapture -x -o -l "$id" "$OUT/$name.png"
  pkill -x MDEditDiff || true
  sleep 2
  echo "Saved $OUT/$name.png"
}

rm -f "$OUT"/app-*.png
shoot app-read -DefaultMode read
shoot app-split -DefaultMode split
shoot app-edit -DefaultMode edit
shoot app-read-dark -DefaultMode read -Appearance dark

# Changes since you last read: you read the plan, then an agent and someone else change it.
if command -v mdeditdiff >/dev/null; then
  CH="$(mktemp -d)"
  cp ../examples/plan.md "$CH/plan.md"
  mdeditdiff seen "$CH/plan.md" --reader "$(id -un)"
  perl -0pi -e 's/- Should exports include archived rows\?\n//; s/2\. Build the CSV on the server\./2. Build the CSV on the server, streaming rows so large reports never time out./; s/(## Rollout)/Decision: archived rows are excluded.\n\n$1/' "$CH/plan.md"
  mdeditdiff changes "$CH/plan.md" --reader planner --peek >/dev/null
  perl -0pi -e 's/- What is the row limit\?/- What is the row limit? Proposed: 100,000 rows./; s/\| Beta \| 10 customers \|/| Beta | 25 customers |/' "$CH/plan.md"
  mdeditdiff checkpoint "$CH/plan.md" --author planner --note "Proposed a row limit"
  WORK="$CH" shoot app-changes -DefaultMode read
fi
