#!/bin/sh
# Builds a release nodch.app into build/ (gitignored), ad-hoc signed. No Xcode needed.
# With NODCH_SIGN_IDENTITY set (a "Developer ID Application: ..." name), it signs with that identity, the hardened
# runtime and app/Resources/Nodch.entitlements instead. scripts/release.sh does that and notarizes.
#
#   scripts/bundle.sh                              build build/Nodch.app
#   build/Nodch.app/Contents/MacOS/Nodch --demo    try it without Nod
#   open build/Nodch.app                           run it
#
# The bundle carries app/Resources/Info.plist: bundle id dev.nodch.Nodch, no Dock icon (LSUIElement) and the
# microphone and speech recognition usage descriptions macOS shows before the quick prompt first listens.
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
app="$root/build/Nodch.app"

case "${1:-}" in
    -h|--help) sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
esac

swift build --package-path "$root/app" -c release --product Nodch
binary="$(swift build --package-path "$root/app" -c release --show-bin-path)/Nodch"

rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp "$binary" "$app/Contents/MacOS/Nodch"
cp "$root/app/Resources/Info.plist" "$app/Contents/Info.plist"
printf 'APPL????' > "$app/Contents/PkgInfo"

plutil -lint "$app/Contents/Info.plist"
if [ -n "${NODCH_SIGN_IDENTITY:-}" ]; then
    codesign --force --sign "$NODCH_SIGN_IDENTITY" --identifier dev.nodch.Nodch \
        --options runtime --timestamp --entitlements "$root/app/Resources/Nodch.entitlements" "$app"
else
    codesign --force --sign - --identifier dev.nodch.Nodch "$app"
fi
codesign --verify --deep --strict --verbose=2 "$app"

echo "Built $app"
echo "Usage: open \"$app\"  (or run \"$app/Contents/MacOS/Nodch\" --demo)"
