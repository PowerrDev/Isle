#!/bin/zsh
#
#  release.sh
#  Isle
#
#  Produces a signed, notarized, stapled, universal (Apple silicon + Intel)
#  disk image ready to share with anyone.
#
#  One-time setup
#    1. Join the Apple Developer Program and create a "Developer ID Application"
#       certificate (Xcode ▸ Settings ▸ Accounts ▸ Manage Certificates ▸ +).
#    2. Store notarization credentials in the keychain:
#         xcrun notarytool store-credentials isle-notary \
#             --apple-id <your Apple ID> --team-id <TEAMID> --password <app-specific password>
#
#  Usage
#    DEVELOPER_ID="Developer ID Application: Your Name (TEAMID)" ./release.sh
#
#  Optional environment
#    NOTARY_PROFILE   Keychain profile name (default: isle-notary)
#    SKIP_NOTARIZE=1  Sign and package only, for a quick local check
#

set -euo pipefail
cd "${0:A:h}"

: "${DEVELOPER_ID:?Set DEVELOPER_ID to your \"Developer ID Application: …\" identity}"
NOTARY_PROFILE="${NOTARY_PROFILE:-isle-notary}"

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Info.plist)
BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" Info.plist)
OUT=build/release
APP="$OUT/Isle.app"
DMG="$OUT/Isle-$VERSION.dmg"

step() { print -P "\n%B==> $1%b" }

# MARK: - Build

step "Building universal binary ($VERSION, build $BUILD)"
swift build -c release --arch arm64 --arch x86_64
BINARY=.build/apple/Products/Release/Isle
lipo -info "$BINARY"

# MARK: - Bundle

step "Assembling Isle.app"
rm -rf "$OUT"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY" "$APP/Contents/MacOS/Isle"
strip -x "$APP/Contents/MacOS/Isle"
cp Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# MARK: - Sign

step "Signing with hardened runtime"
codesign --force --timestamp --options runtime \
         --entitlements Isle.entitlements \
         --sign "$DEVELOPER_ID" "$APP"
codesign --verify --strict --verbose=2 "$APP"

# MARK: - Package

step "Creating disk image"
STAGING="$OUT/dmg"
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "Isle" -srcfolder "$STAGING" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null
rm -rf "$STAGING"
codesign --force --timestamp --sign "$DEVELOPER_ID" "$DMG"

# MARK: - Notarize

if [[ "${SKIP_NOTARIZE:-0}" == 1 ]]; then
    step "Skipping notarization"
else
    step "Notarizing (this usually takes a few minutes)"
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait

    step "Stapling tickets"
    xcrun stapler staple "$DMG"

    step "Verifying with Gatekeeper"
    spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
fi

step "Done → $DMG"
