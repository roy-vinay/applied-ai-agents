#!/bin/bash
# Builds Tech60.app (Apple silicon and Intel) and a zip for download. Ad-hoc signed, not notarized.
set -euo pipefail
cd "$(dirname "$0")/.."
ARCHS=(--arch arm64 --arch x86_64)
swift build -c release "${ARCHS[@]}" --product Tech60
BIN="$(swift build -c release "${ARCHS[@]}" --show-bin-path)"
APP=build/Tech60.app
rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/Tech60" "$APP/Contents/MacOS/Tech60"
cp Info.plist "$APP/Contents/Info.plist"
# App icon, drawn by code so it stays in the repo as source.
swift scripts/make_icon.swift build/AppIcon.iconset docs/img/app-icon.png
iconutil -c icns build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
codesign --force --deep --sign - "$APP"
(cd build && ditto -c -k --keepParent Tech60.app Tech60-macOS.zip)
echo "Built $PWD/build/Tech60.app and build/Tech60-macOS.zip"
