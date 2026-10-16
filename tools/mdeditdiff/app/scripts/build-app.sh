#!/bin/bash
# Builds mdEditDiff.app (Apple silicon and Intel) and a zip for download.
# The app is ad-hoc signed, not notarized; see the README for how to open it.
set -euo pipefail
cd "$(dirname "$0")/.."

ARCHS=(--arch arm64 --arch x86_64)
swift build -c release "${ARCHS[@]}" --product MDEditDiff
BIN="$(swift build -c release "${ARCHS[@]}" --show-bin-path)"

APP=build/mdEditDiff.app
rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/MDEditDiff" "$APP/Contents/MacOS/MDEditDiff"
cp -R Sources/MDEditDiffApp/Resources/Preview "$APP/Contents/Resources/Preview"
cp Info.plist "$APP/Contents/Info.plist"
# App icon: every size macOS asks for, from the 1024px master (Icon/AppIcon.svg is the source).
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
lipo -info "$APP/Contents/MacOS/MDEditDiff"

(cd build && ditto -c -k --keepParent mdEditDiff.app mdEditDiff-macOS.zip)
echo "Built $(pwd)/build/mdEditDiff.app and build/mdEditDiff-macOS.zip"
