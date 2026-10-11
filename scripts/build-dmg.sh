#!/bin/zsh
# Builds the app for release and packs it into disk images to hand out, each holding the app and a shortcut to the
# Applications folder to drag it onto: dist/KettleStitch-<version>-universal.dmg for any Mac, and the smaller
# dist/KettleStitch-<version>-apple-silicon.dmg.
set -euo pipefail
cd "${0:A:h}/.."
APP="$PWD/dist/KettleStitch.app"
for kind in universal silicon; do
  RELEASE=$kind ./scripts/build-app.sh
  VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")
  STAGE="${TMPDIR:-/tmp}/kettlestitch-dmg"
  rm -rf "$STAGE"; mkdir -p "$STAGE"
  cp -R "$APP" "$STAGE/KettleStitch.app"
  ln -s /Applications "$STAGE/Applications"
  DMG="$PWD/dist/KettleStitch-$VERSION-${kind/silicon/apple-silicon}.dmg"
  rm -f "$DMG"
  hdiutil create -volname "KettleStitch $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
  rm -rf "$STAGE"
  echo "Built $DMG ($(lipo -archs "$APP/Contents/MacOS/KettleStitch"))"
done
