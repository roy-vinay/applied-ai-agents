#!/bin/bash
# Takes screenshots of the built app (run on a Mac after build-app.sh; CI does this), and checks that
# the notes window stays out of a full-screen capture when "Hide from Screen Share" is on.
set -euo pipefail
cd "$(dirname "$0")/.."
APP="$PWD/build/SpeakerNotes.app"
OUT="$PWD/docs/img"
NOTES="$PWD/examples/sample-talk.md"
DOMAIN=io.github.roy-vinay.speakernotes
mkdir -p "$OUT"
rm -f "$OUT"/app-*.png "$OUT"/capture-*.png

# Emphasis the screenshots show: what an instruction like "highlight the parts of an agent" produces.
RULES='[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","label":"Highlight the parts of an agent","phrases":["Planner","Tool Router","Memory"],"style":"highlight"},{"id":"7A1B2C3D-8B86-D011-B42D-00C04FC964FF","label":"perceive, plan, act, reflect","phrases":["perceive","plan","act","reflect"],"style":"color"}]'

# Put a sample slide on the desktop, so captures show what an audience would see behind the notes.
SLIDE="$PWD/examples/sample-slide.png"
osascript -e "tell application \"System Events\" to tell every desktop to set picture to \"$SLIDE\"" >/dev/null 2>&1 \
  || echo "Couldn't set the desktop picture; captures will show the plain desktop."
sleep 2

launch() { # extra app arguments...
  defaults delete "$DOMAIN" >/dev/null 2>&1 || true
  defaults write "$DOMAIN" "emphasis:$NOTES" -data "$(printf '%s' "$RULES" | xxd -p | tr -d '\n')"
  open -n -a "$APP" --args -hiddenFromShare NO "$@"
  sleep 6
}
quit() { pkill -x SpeakerNotes || true; sleep 2; }

window() { # name: just the notes window
  local id
  id="$(swift scripts/window_id.swift SpeakerNotes)"
  screencapture -x -o -l "$id" "$OUT/$1.png"
  echo "Saved $OUT/$1.png"
}

region() { # name [padding]: the notes window plus what's around it (popovers, the desktop)
  local pad="${2:-36}" b x y w h
  b="${BOUNDS:-$(swift scripts/window_id.swift SpeakerNotes --bounds)}"
  IFS=, read -r x y w h <<< "$b"
  screencapture -x -R "$((x - pad)),$((y - pad)),$((w + 2 * pad)),$((h + 2 * pad))" "$OUT/$1.png"
  echo "Saved $OUT/$1.png ($b)"
}

launch -filePath "$NOTES" -slideIndex 1
window app-present
quit

launch -filePath "" -notes ""
window app-empty
quit

launch -filePath "$NOTES" -slideIndex 1 -startEditing YES
window app-edit
quit

# Scroll as I speak, with a transcript played as if spoken (with a few recognition-style mistakes).
launch -filePath "$NOTES" -slideIndex 1 -simulateSpeech "every agent repeats for steps perceive plan act and reflect the planner breaks the goal into small steps the tool router picks the right tool for each step the memory keeps what worked"
sleep 7
window app-voice
quit

# Popovers are their own windows, so capture the area around the notes window.
launch -filePath "$NOTES" -slideIndex 1 -openPopover text
region app-text-settings
quit
launch -filePath "$NOTES" -slideIndex 1 -openPopover emphasis
region app-emphasize
quit

# The real test: the same part of the screen captured with "Hide from Screen Share" off, then on.
launch -filePath "$NOTES" -slideIndex 1
BOUNDS="$(swift scripts/window_id.swift SpeakerNotes --bounds)"
screencapture -x "$OUT/capture-visible.png"
region capture-visible-crop 60
quit
defaults delete "$DOMAIN" >/dev/null 2>&1 || true
open -n -a "$APP" --args -filePath "$NOTES" -slideIndex 1 -hiddenFromShare YES
sleep 6
screencapture -x "$OUT/capture-hidden.png"
region capture-hidden-crop 60
quit
# Frames for the animated demo: three slides, each with the notes on the matching slide, captured as you
# see it (hiding off) and as a full-screen share receives it (hiding on).
mkdir -p "$OUT/demo"
rm -f "$OUT"/demo/*.png
for i in 1 2 3; do
  osascript -e "tell application \"System Events\" to tell every desktop to set picture to \"$PWD/examples/slides/slide-$i.png\"" >/dev/null 2>&1 || true
  sleep 2
  launch -filePath "$NOTES" -slideIndex "$((i - 1))"
  screencapture -x "$OUT/demo/visible-$i.png"
  quit
  defaults delete "$DOMAIN" >/dev/null 2>&1 || true
  defaults write "$DOMAIN" "emphasis:$NOTES" -data "$(printf '%s' "$RULES" | xxd -p | tr -d '\n')"
  open -n -a "$APP" --args -filePath "$NOTES" -slideIndex "$((i - 1))" -hiddenFromShare YES
  sleep 6
  screencapture -x "$OUT/demo/hidden-$i.png"
  quit
done
ls -la "$OUT" "$OUT/demo"
