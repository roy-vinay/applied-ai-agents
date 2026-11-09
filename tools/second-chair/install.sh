#!/bin/bash
# Installs or updates Second Chair in /Applications. Run it again any time to get the newest version:
#   curl -fsSL https://raw.githubusercontent.com/roy-vinay/applied-ai-agents/main/tools/second-chair/install.sh | bash
set -euo pipefail

URL="https://github.com/roy-vinay/applied-ai-agents/releases/download/second-chair-latest/SecondChair-macOS.zip"
DEST="/Applications/Second Chair.app"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

[ "$(uname)" = "Darwin" ] || { echo "Second Chair is a Mac app."; exit 1; }
[ "$(uname -m)" = "arm64" ] || { echo "Second Chair needs an Apple silicon Mac."; exit 1; }
MAJOR="$(sw_vers -productVersion | cut -d. -f1)"
[ "$MAJOR" -ge 26 ] || { echo "Second Chair needs macOS 26 or later (this Mac has $(sw_vers -productVersion))."; exit 1; }

echo "Downloading the latest Second Chair..."
curl -fL --progress-bar "$URL" -o "$TMP/SecondChair-macOS.zip"
ditto -x -k "$TMP/SecondChair-macOS.zip" "$TMP"

# Quit the running copy so it can be replaced. Your folders, index and settings are kept.
osascript -e 'quit app "Second Chair"' >/dev/null 2>&1 || true
sleep 1
pkill -x SecondChair >/dev/null 2>&1 || true

UPDATING=0
[ -d "$DEST" ] && UPDATING=1
rm -rf "$DEST"
mv "$TMP/Second Chair.app" "$DEST"
if [ "$UPDATING" = 1 ]; then
  # Not signed with a fixed identity yet, so macOS treats each update as a new app. Reset permissions
  # so macOS asks again cleanly instead of silently ignoring the old grants.
  for service in ScreenCapture Microphone SpeechRecognition; do
    tccutil reset "$service" io.github.roy-vinay.secondchair >/dev/null 2>&1 || true
  done
  echo "Permissions were reset for the new version; Second Chair will ask again when it needs them."
fi
xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true
open "$DEST"

VERSION="$(defaults read "$DEST/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo "")"
echo "Second Chair $VERSION is installed. Look for the chair icon in the menu bar."
