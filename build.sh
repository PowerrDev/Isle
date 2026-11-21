#!/bin/zsh
#
#  build.sh
#  Isle
#
#  Fast local build for development: native architecture, ad-hoc signature.
#  For a distributable, notarized build use release.sh instead.
#

set -euo pipefail
cd "${0:A:h}"

swift build -c release

APP=build/Isle.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp .build/release/Isle "$APP/Contents/MacOS/Isle"
strip -x "$APP/Contents/MacOS/Isle"
cp Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

codesign --force --sign - --entitlements Isle.entitlements --options runtime "$APP"

echo "Built $APP  →  open $APP"
