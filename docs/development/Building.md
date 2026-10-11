# Building and releasing

KettleStitch is a Swift package with no external dependencies. It needs a macOS Swift toolchain (built here with Xcode 16.4 / Swift 6.1.2); the deployment target is macOS 13.

## Build the app

```sh
./scripts/build-app.sh          # dist/KettleStitch.app, for this Mac's architecture
swift test --disable-sandbox    # the unit tests
```

`scripts/build-app.sh`, in order:

1. Runs `swift build --disable-sandbox -c release`, with the Clang and SwiftPM module caches under `$TMPDIR`.
2. Creates the bundle folders and copies the executable in under a temporary name, then renames it into place.
3. Makes `AppIcon.icns` from `Resources/AppIcon.png`.
4. Writes `Contents/Info.plist`. The version (`CFBundleShortVersionString`) and build number (`CFBundleVersion`) are set by hand in the script.
5. Ad-hoc signs the bundle with `codesign --force --sign -`.

Rebuilding while the app is open is safe for the files, but the running copy can no longer read its keychain items until it is reopened: macOS ties that access to the program file, which has just been replaced. The app detects this and says so. Each build also has a new ad-hoc signature, so macOS may ask once for permission to read a saved API key.

Tests that use Vision or Core Image need access to the macOS graphics services; a restrictive command sandbox can stop those working even though the app runs normally.

## Release

```sh
./scripts/build-dmg.sh
```

This builds twice, with `RELEASE=universal` and `RELEASE=silicon`, and writes `dist/KettleStitch-<version>-universal.dmg` and `dist/KettleStitch-<version>-apple-silicon.dmg`, each holding the app and a shortcut to Applications. Release builds are stripped of debugging records, which would otherwise name the folders they were built in. The disk images are attached to a GitHub release, not committed.

The app is not notarized, so Gatekeeper blocks the first launch of a downloaded copy; the README tells users how to allow it.

## Test modes

Setting `KETTLESTITCH_TEST_DIR` to a folder puts the app in test mode: it uses that folder instead of Application Support, opens `Recovery.kettlestitch` from it if present, stays out of Open Recent, never asks questions, and leaves the keychain alone unless `KETTLESTITCH_TEST_KEYCHAIN` is also set.

| Run | What it does |
| --- | --- |
| `KettleStitch --smoke` | Drives the real window with synthetic keys and clicks, checks the results, writes screenshots to the test folder, and quits. Needs a project of at least two readable photographs. |
| `KETTLESTITCH_SMOKE_FOLDER=… KETTLESTITCH_SMOKE_PROJECT=… KettleStitch` | Starts empty, imports the folder as a drop would, then opens the project. |
| `KettleStitch --bench` | Times stepping through a long project near its start, middle and end. Needs more than 30 pages. |
| `KettleStitch --bench --thumbs` | Exercises the sidebar pictures: removing pages, black-and-white preview, a lost picture, a stuck request, a missing file. Add `--early` to start while pictures are still loading. |
| `KettleStitch --bench --large-sidebar` | Writes a screenshot of the large sidebar layout. |
| `KETTLESTITCH_REPORT=file KettleStitch` | Writes the page count and window title after launch and quits. |

Always run these against a copy of a project, never a real one: they edit it.

## The command-line checker

`CropCheck` is built alongside the app.

```sh
.build/release/CropCheck --benchmark 300
.build/release/CropCheck --collection /path/to/photos /path/to/diagnostics 300
.build/release/CropCheck --split project.kettlestitch /path/to/folder 12
.build/release/CropCheck --deskew project.kettlestitch /path/to/folder 12
.build/release/CropCheck --claude-files project.kettlestitch 5 /path/to/folder
```

- `--collection` detects a crop for each photograph and writes a project and contact sheets showing the whole photograph with the proposed boundary. A proposal is not a verified crop.
- `--split` proposes a split for a project's first pages without changing the project, prints each position and writes small copies of the two halves.
- `--deskew` prints the measured tilt of each page, or "unclear", and writes small deskewed copies.
- `--claude-files` writes what a second opinion would upload for one page (the two images, the prompt and the reply schema) without contacting anyone.

## Collecting detector mistakes

Holding Option while opening the Tools menu shows **Save Bad Crop/Split Example** (⌥⌘B at any time). It writes the photograph, `example.json` (the page's crop, split and proposals, and the page before it, with file names only) and `overlay.jpg` into a new folder under `Bad Examples` in the support folder.
