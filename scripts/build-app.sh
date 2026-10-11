#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
export CLANG_MODULE_CACHE_PATH="${TMPDIR:-/tmp}/kettlestitch-clang"
export SWIFTPM_MODULECACHE_OVERRIDE="${TMPDIR:-/tmp}/kettlestitch-swift"
# RELEASE makes a build that is given to others, without the debugging records that name the folders it was built
# in: RELEASE=universal for Apple Silicon and Intel alike, RELEASE=silicon for Apple Silicon alone.
case "${RELEASE:-}" in
  universal) swift build --disable-sandbox -c release --arch arm64 --arch x86_64; BUILT=.build/apple/Products/Release/KettleStitch ;;
  silicon)   swift build --disable-sandbox -c release --arch arm64; BUILT=.build/arm64-apple-macosx/release/KettleStitch ;;
  "")        swift build --disable-sandbox -c release; BUILT=.build/release/KettleStitch ;;
  *)         echo "RELEASE must be universal or silicon"; exit 2 ;;
esac
APP="$PWD/dist/KettleStitch.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
# Rename into place: a running copy keeps its old file instead of having it overwritten.
cp "$BUILT" "$APP/Contents/MacOS/KettleStitch.new"
if [[ -n "${RELEASE:-}" ]]; then strip -S "$APP/Contents/MacOS/KettleStitch.new"; fi
mv -f "$APP/Contents/MacOS/KettleStitch.new" "$APP/Contents/MacOS/KettleStitch"
# The icon in every size macOS asks for, made from the one 1024-pixel picture.
ICONSET="${TMPDIR:-/tmp}/kettlestitch-icon/AppIcon.iconset"
rm -rf "$ICONSET"; mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
  sips -z $size $size Resources/AppIcon.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  sips -z $((size*2)) $((size*2)) Resources/AppIcon.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>KettleStitch</string>
<key>CFBundleIdentifier</key><string>local.kettlestitch.app</string>
<key>CFBundleName</key><string>KettleStitch</string>
<key>CFBundleDisplayName</key><string>KettleStitch</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.4.6</string>
<key>CFBundleVersion</key><string>8</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>CFBundleDocumentTypes</key><array>
<dict><key>CFBundleTypeName</key><string>KettleStitch Project</string><key>CFBundleTypeRole</key><string>Editor</string><key>LSHandlerRank</key><string>Owner</string><key>LSItemContentTypes</key><array><string>local.kettlestitch.project</string></array></dict>
<dict><key>CFBundleTypeName</key><string>Photograph</string><key>CFBundleTypeRole</key><string>Viewer</string><key>LSHandlerRank</key><string>Alternate</string><key>LSItemContentTypes</key><array><string>public.image</string></array></dict>
<dict><key>CFBundleTypeName</key><string>Folder of Photographs</string><key>CFBundleTypeRole</key><string>Viewer</string><key>LSHandlerRank</key><string>None</string><key>LSItemContentTypes</key><array><string>public.folder</string></array></dict>
</array>
<key>UTExportedTypeDeclarations</key><array>
<dict><key>UTTypeIdentifier</key><string>local.kettlestitch.project</string><key>UTTypeDescription</key><string>KettleStitch Project</string><key>UTTypeConformsTo</key><array><string>public.json</string></array><key>UTTypeTagSpecification</key><dict><key>public.filename-extension</key><array><string>kettlestitch</string><string>scanseamstress</string><string>pagecrop</string></array></dict></dict>
</array>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
echo "Built $APP"
