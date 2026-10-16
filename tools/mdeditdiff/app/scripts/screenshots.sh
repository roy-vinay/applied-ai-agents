#!/bin/bash
# Takes the README screenshots of the built app (run on a Mac after build-app.sh; CI does this).
set -euo pipefail
cd "$(dirname "$0")/.."
APP="$PWD/build/mdEditDiff.app"
OUT="$PWD/../docs/img"
mkdir -p "$OUT"
WORK="$(mktemp -d)"
cp ../demo/plan.md "$WORK/plan.md"

shoot() { # name, extra app arguments...
  local name="$1"; shift
  open -n -a "$APP" "$WORK/plan.md" --args "$@"
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
