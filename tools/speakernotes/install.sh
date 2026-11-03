#!/bin/bash
# Installs or updates SpeakerNotes in /Applications. Run it again any time to get the newest version:
#   curl -fsSL https://raw.githubusercontent.com/roy-vinay/applied-ai-agents/main/tools/speakernotes/install.sh | bash
set -euo pipefail

URL="https://github.com/roy-vinay/applied-ai-agents/releases/download/speakernotes-latest/SpeakerNotes-macOS.zip"
DEST="/Applications/SpeakerNotes.app"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

[ "$(uname)" = "Darwin" ] || { echo "SpeakerNotes is a Mac app."; exit 1; }

echo "Downloading the latest SpeakerNotes..."
curl -fL --progress-bar "$URL" -o "$TMP/SpeakerNotes-macOS.zip"
ditto -x -k "$TMP/SpeakerNotes-macOS.zip" "$TMP"

# Quit the running copy so it can be replaced. Your notes and settings are kept.
osascript -e 'quit app "SpeakerNotes"' >/dev/null 2>&1 || true
sleep 1
pkill -x SpeakerNotes >/dev/null 2>&1 || true

UPDATING=0
[ -d "$DEST" ] && UPDATING=1
rm -rf "$DEST"
mv "$TMP/SpeakerNotes.app" "$DEST"
if [ "$UPDATING" = 1 ]; then
  # The app isn't signed with a fixed identity yet, so macOS treats each update as a new app and quietly
  # stops honoring permissions given to the old one. Clear them so macOS asks again when they're needed.
  for service in Accessibility ScreenCapture AppleEvents; do
    tccutil reset "$service" io.github.roy-vinay.speakernotes >/dev/null 2>&1 || true
  done
  echo "Permissions were reset for the new version; SpeakerNotes will ask again when it needs them."
fi
xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true
open "$DEST"

VERSION="$(defaults read "$DEST/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo "")"
echo "SpeakerNotes $VERSION is installed. Look for its icon in the menu bar."
