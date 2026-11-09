#!/bin/bash
# Builds Second Chair.app for Apple silicon (the only supported Macs) and a zip for download.
# Ad-hoc signed, not notarized; see the README for how to open it the first time.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --arch arm64 --product SecondChair
BIN="$(swift build -c release --arch arm64 --show-bin-path)"

APP="build/Second Chair.app"
rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/SecondChair" "$APP/Contents/MacOS/SecondChair"
cp Info.plist "$APP/Contents/Info.plist"

ICONSET="build/AppIcon.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
  sips -z $size $size Icon/AppIcon-1024.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  sips -z $((size * 2)) $((size * 2)) Icon/AppIcon-1024.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

plutil -lint "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
codesign --verify --verbose "$APP"
lipo -info "$APP/Contents/MacOS/SecondChair"

(cd build && ditto -c -k --keepParent "Second Chair.app" SecondChair-macOS.zip)
echo "Built $(pwd)/$APP and build/SecondChair-macOS.zip"
