# build-app.sh

`scripts/build-app.sh` builds KettleStitch in release mode and assembles `dist/KettleStitch.app`.

```sh
./scripts/build-app.sh
```

What it does, in order:

1. Runs `swift build --disable-sandbox -c release`, with the Clang and SwiftPM module caches under `$TMPDIR`.
2. Creates the bundle folders and copies the `KettleStitch` executable in under a temporary name, then renames it into place. A copy of KettleStitch that is already running keeps its own file, so the script is safe to run while the app is open; quit and reopen the app to use the new build.
3. Writes `Contents/Info.plist`. The version (`CFBundleShortVersionString`) and build number (`CFBundleVersion`) are set by hand in the script.
4. Ad-hoc signs the bundle with `codesign --force --sign -`.

Notes:

- The build is for the Mac's own architecture only (arm64 on Apple Silicon) and is not notarized. Another Mac may need Privacy & Security ▸ Open Anyway on first launch.
- Each build has a new ad-hoc signature, so macOS may ask again for permission to read the Anthropic API key saved in the keychain.
- The script takes no options. It runs quickly and keeps no log.
- Run the tests separately with `swift test --disable-sandbox`.
