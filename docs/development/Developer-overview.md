# KettleStitch developer overview

Updated 2026-10-11 for version 0.4.4. This describes the implementation as it stands, for whoever picks the code up next. Read the source before changing it; the validation logs under `docs/validation/` describe earlier states and older shortcuts.

Related notes: [Architecture](Architecture.md), [Building and releasing](Building.md), [How detection works](Detection.md).

## Name

The app was PageCrop, then ScanSeamstress, then KettleStitch, all renamed on 2026-10-10. `LegacyNames` and `ImportPolicy.projectExtensions` hold the only remaining references to the earlier names, for opening `.pagecrop` and `.scanseamstress` projects and carrying over old sessions, preferences and the keychain item. The library and diagnostic targets keep the names `CropCore` and `CropCheck`, and the second-opinion code keeps `ClaudeReview` and `sendToClaude` from when Claude was the only provider.

## Purpose and what the user values

A native macOS cropper for books of several hundred photographed pages. In order:

1. Fast, reliable detection of the whole page or spread, with quick manual correction.
2. An optional split line dividing a spread into two pages at export, which follows the user's corrections from page to page.
3. Keyboard access to everything, alongside the mouse. Single keys must never intercept typing in a text field.
4. Privacy: nothing leaves the Mac except the optional second opinion; exports carry no metadata; no personal detail in anything published.

The user steers by small, frequent interaction changes. Follow the newest request rather than redesigning, and update the in-app help, the README and the manual whenever a control changes.

**Not implemented:** page dewarping, edge repair, automatic picture detection, page groups, JBIG2/CCITT compression, editing of recognised text, RAW and PDF import, notarization.

## Workspace

- Built app: `dist/KettleStitch.app`. Release disk images: `dist/KettleStitch-<version>-*.dmg`.
- `examples/` holds the user's own edited project and is **not in the repository** (ignored, and removed from history on 2026-10-11). Never regenerate or overwrite it.
- `sample-images/1940.3/` holds 23 sample photographs, also ignored. Build test fixtures only from photographs that exist.
- `.qa/` is for disposable evaluations and test-project copies, ignored.
- The repository is public. Commits use a GitHub no-reply address; do not commit a personal email address, a home-folder path or an API key.
- The version (0.4.4, build 7) is set by hand in `scripts/build-app.sh` and changed only when the user asks.

## Source map

| File | Responsibility |
|---|---|
| `Sources/CropCore/Model.swift` | Point, Quad, Candidate, Adjustments, Page, Project; geometry transforms; validation; atomic JSON saves |
| `Sources/CropCore/Imaging.swift` | EXIF-aware loading, perspective correction, rotation, deskew, exposure/tone/sharpness, cleanup, smudges, one-bit packing |
| `Sources/CropCore/Split.swift` | PageSplit, homography between crop and output, split geometry, the fold detector and its guide rules |
| `Sources/CropCore/Features.swift` | Skew detection, despeckle, picture zones, smudge strokes, deviation scoring |
| `Sources/CropCore/Detector.swift` | Vision passes, proposal generation and refinement, ranking, deduplication |
| `Sources/CropCore/BackgroundBoundary.swift`, `BackgroundMaterial.swift` | The two background estimates |
| `Sources/CropCore/ProposalPolicy.swift` | Hard limits on automatic proposals; the unequal-perspective penalty |
| `Sources/CropCore/Exporter.swift` | ExportOptions, per-page rendering, preview, encoding, Vision text recognition, `PDFWriter`, `PDFInfo.strip` |
| `Sources/CropCore/Output.swift` | Output pixel size and PDF page layout from PageFormat |
| `Sources/CropCore/ClaudeReview.swift` | The second opinion's prompt, reply schema and parsing, overlay drawing, usage log, and `run`, the one network call |
| `Sources/CropCore/ReviewProviders.swift` | Providers, offered models and list prices, the request for each API, reading each reply, the no-redirect session |
| `Sources/CropCore/Commands.swift` | Menu enabling and titles (`MenuPolicy`), shortcut reference data, shared progress tracker |
| `Sources/CropCore/Launch.swift` | What opens at launch, untitled names, auto-save rule, sorting dropped files, relinking moved photographs, legacy names |
| `Sources/KettleStitch/main.swift` | AppDelegate: state, project lifecycle, queues, every action, single-key routing, undo |
| `Sources/KettleStitch/Interface.swift` | Window, split view, sidebar cell and its two layouts, `ThumbnailPolicy`, status bar, toolbar |
| `Sources/KettleStitch/Inspector.swift` | Inspector sections, fold buttons, smudge icons, shortcut list |
| `Sources/KettleStitch/Menus.swift` | Menu bar, state for `MenuPolicy`, Open Recent, shortcut and usage-log windows |
| `Sources/KettleStitch/ExportSheet.swift` | Export window |
| `Sources/KettleStitch/Settings.swift` | `Keychain`, `ReviewChoice`, Settings window |
| `Sources/KettleStitch/Canvas.swift` | Drawing, crop and split overlays, magnifier, mouse editing, zoom, smudge painting |
| `Sources/KettleStitch/Smoke.swift` | UI smoke test, import smoke, paging benchmark, thumbnail test |
| `Sources/CropCheck/` | Diagnostic command-line tool |
| `Tests/CropCoreTests/` | 118 unit tests; file names are looser than their contents |

## Data and geometry invariants

Coordinates are fractions of the **upright, EXIF-oriented photograph**, origin top-left. A Quad is stored clockwise: **TL, TR, BR, BL**. This deliberately differs from the corner keys 1 2 3 4 = TL, TR, BL, BR and edge keys 5 6 7 8 = top, left, right, bottom. Do not reorder stored geometry to match shortcuts.

`Quad.valid` requires finite in-image coordinates, positive area, clockwise convexity and no degeneracy. `scaled(by:)` scales about the centroid and clamps each coordinate, so a side at the boundary stops while the others grow. `movingEdge` and `translated` clamp a shared delta. `movingCornerPreservingAngles` keeps every side's direction and ignores a move that would leave the image.

`Page` stores a UUID, the photograph's absolute path, quad, candidates, status, reviewed flag, rotation, revision and aspect ratio, plus optional `adjustments` (cleanup mode, brightness, contrast, and optional despeckle, sharpness, exposure), `format`, `flagged`, `split`, `splitByHand`, `deskew`, `pictureZones`, `smudges` and `reviewNote`.

- **New fields must be optional**, so earlier version 1 projects still decode. The schema stays version 1.
- A split's `top` and `bottom` are fractions across the corrected, rotated output, so it follows the crop. `SplitGeometry` converts to and from photograph coordinates.
- Smudges are in photograph coordinates, so they stay on the same print when the crop changes.
- `Project.read` validates geometry and filters cached automatic proposals that break the limits; it never replaces a manual or reviewed crop.

## How the app holds together

**State and undo.** AppDelegate owns the project on the main thread. `edit` snapshots the affected pages for undo, bumps `revision` for geometry changes, calls `save()` and refreshes views. Undo entries are page snapshots or a page-list snapshot (import, reorder, removal); restoring a list keeps each page's current data. Settings apply to `targetIndexes`: the sidebar selection when it includes the photograph on screen. `reloadPages()` must wrap every full table reload, because NSTableView resets its selection.

**Saving.** `save()` records a change. An untitled session is written to Application Support, coalesced to once a second (`writeUntitled`). A named project is only marked `unsaved` and written by File ▸ Save, the five-minute auto-save timer, or `confirmUnsaved()`, which guards quit, close, New and Open and saves silently when auto-save is on or in test mode.

**Loading and display.** Files arrive through `receive(_:)`, which lists folders and reads sizes off the main thread behind a notice. The canvas shows at most 3200 pixels; `readAhead` decodes the next photograph in the direction of travel and keeps the current one and its two neighbours. `loadCurrent` leaves the placeholder empty during a page change; the "drop photographs here" text is only for an empty project.

**Queues.** Separate queues handle display, sidebar pictures (three at a time), detection, splits, export and review. A display token discards stale images; `generation` and page revisions keep a stale detection from overwriting an edit. Split operations read their guide on the main thread when their turn comes, so do not wait on the split queue from the main thread.

**Sidebar pictures.** Held in plain dictionaries, not an `NSCache`. `checkThumbnails()` runs every two seconds and reloads a visible row left blank with nothing under way. A preview picture is rendered from a 640-pixel copy and reduced, because cleanup run on the 120-pixel picture wipes text to white. `ThumbnailPolicy` has the sizes for both sidebar layouts.

**Keys and menus.** Single keys are handled in `handleKey` by a local event monitor, which ignores ⌘ and ⌃ combinations and text editing. Menu items show the same bare keys; `validateMenuItem` turns a bare-key item off while a field is edited or another window is key. Shortcut lists show a letter in lower case unless Shift is held (`ShortcutReference.shown`).

**Splits.** `proposeSplits` passes the previous page's split as a guide, trusted when the user placed or accepted it or is working one page at a time. Each proposal carries alternatives, which `proposeSplit` steps through on repeated **t** while the split is where the proposal put it.

**Second opinion.** `sendToClaude` reads the key for the chosen provider from the keychain and hands it to `ClaudeReview.run`, which sends it in one header over an ephemeral session that refuses redirects. A corrected crop is selected at once and kept as a proposal named after the provider; a corrected split is applied; both are one undo step. **None of the three providers has been exercised against the live service from here**; tests use a scripted `URLProtocol`. The model list in `ReviewModel.all` was checked against each provider's documentation on 2026-10-11 and will go stale.

**Keychain.** One item per provider, service `local.kettlestitch.app.<provider>`. Test mode leaves the keychain alone unless `KETTLESTITCH_TEST_KEYCHAIN` is set. A running copy whose program file has been replaced by a rebuild is refused its keys; `Keychain.replacedSinceLaunch` detects this.

**Export.** Progress counts output pages. A PDF is written to a temporary file, its information dictionary blanked in place (Quartz always writes Producer and dates), then moved into place.

## Interaction contract

The README has the complete shortcut list and is the reference. Points that are easy to break:

- Mouse selection must **never capture the arrow keys**. `CropCanvas.keyboardSelection` is set only by the number keys and cleared by a canvas click, Escape, fit or navigation.
- **c** copies the previous crop every time; **Shift →** steps on and copies. **v** copies the previous page's image settings and turns the preview on.
- **y** and **u** move the split; **.** goes to the next unusual page; **z** undoes and **Shift Z** redoes. Comma is unassigned except with Option, for deskew.
- **t** proposes a split, then cycles candidates. **Option t** proposes on every unsplit page and is never run unasked.
- A mouse wheel zooms about the pointer; a precise-scrolling device (trackpad, Magic Mouse) pans.
- The preview stays on across pages; selecting a corner or edge, the smudge brush and drawing a picture zone turn it off.
- Stepping past either end of the book flashes the canvas and reloads nothing.
- Importing starts detection on the new pages. Nothing else is detected or proposed unasked.

## Verification

**The user asked on 2026-10-10 for red/green test-first work**: write the test, see it fail, then implement. Put decision logic in `CropCore` where it can be tested; the smoke test is a second check.

- `swift test --disable-sandbox`: 118 tests.
- The smoke, benchmark and thumbnail modes are described in [Building and releasing](Building.md). The UI smoke occasionally fails its first menu-state check (`Smoke.swift`, the line after the settings screenshot) when the test window is not frontmost, and passes on rerun; this is a flaw in the test, not yet fixed.
- Under a restricted execution environment, tests that use Vision or Core Image may need an unrestricted run.
- No labelled accuracy measurement exists for crops or splits. The split detector was tuned on synthetic spreads and compared on the 23 sample photographs. **Save Bad Crop/Split Example** (⌥⌘B) is how real failures are collected.

Before restarting the user's app, quit it normally so it saves, and never run a smoke test against a real project:

```sh
osascript -e 'if application id "local.kettlestitch.app" is running then tell application id "local.kettlestitch.app" to quit'
open -n dist/KettleStitch.app
```

## Known weaknesses

- Crop detection: shadows, backing boards and the stack of pages beyond the spread can remain in a crop; small covers conflict with the 65% minimum.
- Split detection on real books is unmeasured; ragged folds with staples or stains read as print rather than as a line.
- AppDelegate is very large; operations and state are not separated.
- The second opinion sends the page without its smudges.
- No notarization, so every downloaded copy meets Gatekeeper.

## Ideas, not authorised work

A labelled regression set for crops and splits; a disk cache for sidebar pictures; portable projects that carry their photographs; a notarized build; splitting AppDelegate.
