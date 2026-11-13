#!/bin/sh
# Builds, signs, notarizes and zips nodch for release. Needs a Developer ID Application identity in the keychain and
# a notarytool keychain profile (xcrun notarytool store-credentials nodch).
#
#   scripts/release.sh                 sign, notarize, staple, write dist/Nodch-<version>.zip
#   scripts/release.sh --no-notarize   stop after signing and zipping
#
# NODCH_SIGN_IDENTITY   signing identity (default: the first "Developer ID Application" in the keychain)
# NODCH_NOTARY_PROFILE  notarytool keychain profile (default: nodch)
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
app="$root/build/Nodch.app"
notarize=1

for arg in "$@"; do
    case "$arg" in
        -h|--help) sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        --no-notarize) notarize=0 ;;
        *) echo "release.sh: unknown option $arg (try -h)" >&2; exit 2 ;;
    esac
done

identity="${NODCH_SIGN_IDENTITY:-}"
if [ -z "$identity" ]; then
    identity=$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application:[^"]*\)".*/\1/p' | head -1)
fi
if [ -z "$identity" ]; then
    echo "release.sh: no Developer ID Application identity in the keychain. Install one or set NODCH_SIGN_IDENTITY." >&2
    exit 1
fi

profile="${NODCH_NOTARY_PROFILE:-nodch}"
if [ "$notarize" = 1 ] && ! xcrun notarytool history --keychain-profile "$profile" >/dev/null 2>&1; then
    echo "release.sh: notarytool keychain profile \"$profile\" not found or not usable." >&2
    echo "Create it with: xcrun notarytool store-credentials $profile (or pass --no-notarize)." >&2
    exit 1
fi

version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$root/app/Resources/Info.plist")
dist="$root/dist"
zip="$dist/Nodch-$version.zip"
mkdir -p "$dist"

NODCH_SIGN_IDENTITY="$identity" "$root/scripts/bundle.sh"

rm -f "$zip"
ditto -c -k --keepParent "$app" "$zip"

if [ "$notarize" = 1 ]; then
    xcrun notarytool submit "$zip" --keychain-profile "$profile" --wait
    xcrun stapler staple "$app"
    rm -f "$zip"
    ditto -c -k --keepParent "$app" "$zip"
fi

echo "Wrote $zip"
shasum -a 256 "$zip"
if [ "$notarize" = 1 ]; then
    spctl -a -vv "$app"
else
    echo "Not notarized (--no-notarize): Gatekeeper will reject this build on other Macs."
fi
