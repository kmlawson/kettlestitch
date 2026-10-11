#!/bin/zsh
# Builds the app for release and packs it into a disk image to hand out: dist/KettleStitch-<version>.dmg,
# holding the app and a shortcut to the Applications folder to drag it onto.
set -euo pipefail
cd "${0:A:h}/.."
RELEASE=1 ./scripts/build-app.sh
APP="$PWD/dist/KettleStitch.app"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")
STAGE="${TMPDIR:-/tmp}/kettlestitch-dmg"
rm -rf "$STAGE"; mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/KettleStitch.app"
ln -s /Applications "$STAGE/Applications"
DMG="$PWD/dist/KettleStitch-$VERSION.dmg"
rm -f "$DMG"
hdiutil create -volname "KettleStitch $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"
echo "Built $DMG"
