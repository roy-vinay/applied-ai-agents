#!/bin/bash
# Screenshots of the card with sample stories (run on a Mac after build-app.sh; CI does this).
set -euo pipefail
cd "$(dirname "$0")/.."
APP="$PWD/build/Tech60.app"
OUT="$PWD/docs/img"
mkdir -p "$OUT"
shoot() { # name, extra app arguments...
  local name="$1"; shift
  local find=""
  if [[ " $* " == *" --ticker "* || " $* " == *" --dot "* ]]; then find="--floating"; fi
  # --allow-capture: Tech60 normally hides its windows from screen capture.
  "$APP/Contents/MacOS/Tech60" --demo --allow-capture "$@" &
  local pid=$!
  sleep 7
  local id
  id="$(swift scripts/window_id.swift Tech60 $find)"
  screencapture -x -o -l "$id" "$OUT/$name.png"
  kill "$pid" || true
  sleep 2
  echo "Saved $OUT/$name.png"
}
shoot card-light -Appearance light
shoot card-dark -Appearance dark
shoot card-story -Appearance light --open
shoot card-brief -Appearance light --brief
shoot ticker-light -Appearance light --ticker
shoot ticker-dark -Appearance dark --ticker
shoot dot-dark -Appearance dark --dot
