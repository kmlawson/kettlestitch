#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
export CLANG_MODULE_CACHE_PATH="${TMPDIR:-/tmp}/pagecrop-clang"
export SWIFTPM_MODULECACHE_OVERRIDE="${TMPDIR:-/tmp}/pagecrop-swift"
swift build --disable-sandbox -c release
APP="$PWD/dist/PageCrop.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
# Rename into place: a running copy keeps its old file instead of having it overwritten.
cp .build/release/PageCrop "$APP/Contents/MacOS/PageCrop.new"
mv -f "$APP/Contents/MacOS/PageCrop.new" "$APP/Contents/MacOS/PageCrop"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>PageCrop</string>
<key>CFBundleIdentifier</key><string>local.pagecrop.app</string>
<key>CFBundleName</key><string>PageCrop</string>
<key>CFBundleDisplayName</key><string>PageCrop</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.3.0</string>
<key>CFBundleVersion</key><string>4</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>CFBundleDocumentTypes</key><array>
<dict><key>CFBundleTypeName</key><string>PageCrop Project</string><key>CFBundleTypeRole</key><string>Editor</string><key>LSHandlerRank</key><string>Owner</string><key>LSItemContentTypes</key><array><string>local.pagecrop.project</string></array></dict>
<dict><key>CFBundleTypeName</key><string>Photograph</string><key>CFBundleTypeRole</key><string>Viewer</string><key>LSHandlerRank</key><string>Alternate</string><key>LSItemContentTypes</key><array><string>public.image</string></array></dict>
<dict><key>CFBundleTypeName</key><string>Folder of Photographs</string><key>CFBundleTypeRole</key><string>Viewer</string><key>LSHandlerRank</key><string>None</string><key>LSItemContentTypes</key><array><string>public.folder</string></array></dict>
</array>
<key>UTExportedTypeDeclarations</key><array>
<dict><key>UTTypeIdentifier</key><string>local.pagecrop.project</string><key>UTTypeDescription</key><string>PageCrop Project</string><key>UTTypeConformsTo</key><array><string>public.json</string></array><key>UTTypeTagSpecification</key><dict><key>public.filename-extension</key><array><string>pagecrop</string></array></dict></dict>
</array>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
echo "Built $APP"
