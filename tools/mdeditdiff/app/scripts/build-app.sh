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
plutil -lint "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
codesign --verify --verbose "$APP"
lipo -info "$APP/Contents/MacOS/MDEditDiff"

(cd build && ditto -c -k --keepParent mdEditDiff.app mdEditDiff-macOS.zip)
echo "Built $(pwd)/build/mdEditDiff.app and build/mdEditDiff-macOS.zip"
