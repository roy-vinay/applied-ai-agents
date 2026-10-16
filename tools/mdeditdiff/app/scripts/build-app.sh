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
# App icon: white by day (Icon/AppIcon.svg), graphite black at night (Icon/AppIcon-Dark.svg).
# The light icon is the classic .icns, in every size macOS asks for.
ICONSET="build/AppIcon.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
  sips -z $size $size Icon/AppIcon-1024.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  sips -z $((size * 2)) $((size * 2)) Icon/AppIcon-1024.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

# The app switches its Dock icon to match Light or Dark mode while it runs (see AppDelegate).
mkdir -p "$APP/Contents/Resources/Icons"
cp Icon/AppIcon-1024.png "$APP/Contents/Resources/Icons/AppIcon-Light.png"
cp Icon/AppIcon-Dark-1024.png "$APP/Contents/Resources/Icons/AppIcon-Dark.png"

# Where the system supports it, an asset catalog gives Finder and the Dock a dark variant even when
# the app isn't running. This is best effort: if actool can't build it, the light icon is used.
XCASSETS="build/Assets.xcassets"
SET="$XCASSETS/AppIcon.appiconset"
mkdir -p "$SET"
echo '{"info":{"version":1,"author":"xcode"}}' > "$XCASSETS/Contents.json"
python3 - "$SET" <<'PY'
import json, subprocess, sys
out = sys.argv[1]
images = []
for size in (16, 32, 128, 256, 512):
    for scale in (1, 2):
        px = size * scale
        for variant, src in (("light", "Icon/AppIcon-1024.png"), ("dark", "Icon/AppIcon-Dark-1024.png")):
            name = f"{variant}-{size}@{scale}x.png"
            subprocess.run(["sips", "-z", str(px), str(px), src, "--out", f"{out}/{name}"], check=True, capture_output=True)
            entry = {"idiom": "mac", "size": f"{size}x{size}", "scale": f"{scale}x", "filename": name}
            if variant == "dark":
                entry["appearances"] = [{"appearance": "luminosity", "value": "dark"}]
            images.append(entry)
json.dump({"images": images, "info": {"version": 1, "author": "xcode"}}, open(f"{out}/Contents.json", "w"), indent=1)
PY
if xcrun actool "$XCASSETS" --compile "$APP/Contents/Resources" --platform macosx \
     --minimum-deployment-target 14.0 --app-icon AppIcon \
     --output-partial-info-plist build/assets-info.plist >build/actool.log 2>&1; then
  /usr/libexec/PlistBuddy -c "Add :CFBundleIconName string AppIcon" "$APP/Contents/Info.plist" 2>/dev/null || true
  echo "Asset catalog with dark icon compiled."
  [ -n "${GITHUB_ACTIONS:-}" ] && echo "::notice title=App icon::Asset catalog with light and dark icons compiled ($(ls "$APP/Contents/Resources" | tr '\n' ' '))"
else
  echo "warning: actool could not build the asset catalog; using the light icon only."
  cat build/actool.log
  [ -n "${GITHUB_ACTIONS:-}" ] && echo "::warning title=App icon::actool failed: $(tail -3 build/actool.log | tr '\n' ' ')"
fi
plutil -lint "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
codesign --verify --verbose "$APP"
lipo -info "$APP/Contents/MacOS/MDEditDiff"

(cd build && ditto -c -k --keepParent mdEditDiff.app mdEditDiff-macOS.zip)
[ -n "${GITHUB_ACTIONS:-}" ] && [ -s build/actool.log ] && echo "::notice title=actool output::$(head -c 1500 build/actool.log | tr '\n' ' ')"
echo "Built $(pwd)/build/mdEditDiff.app and build/mdEditDiff-macOS.zip"
