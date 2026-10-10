# PageCrop developer handoff

Updated 2026-10-10 after version 0.2.0: Mac-style window and menus, image adjustments, page format, PDF/image export and Send to Claude. This document describes the current implementation, not a proposed redesign. Read the actual source before modifying it; older docs and validation logs may describe superseded shortcuts.

## Purpose and user priorities

Native macOS cropper for collections of roughly 300 book photographs. The first priority is fast, reliable whole-book/spread boundary detection with quick manual correction. The crop is always the whole spread; since 2026-10-10 the user also wants an optional, adjustable split line that divides a spread into two pages at export. The user values keyboard access to everything, alongside mouse controls. Single-key commands must not intercept typing in text fields.

The original request includes eventually adding further imaging capabilities: brightness/contrast, colour/greyscale/B&W, resolution choices, perspective correction, rotation, zoom, reliable autosave, customizable PDFs, and curvature compensation. Research and the user's notes are in a local, untracked notes file under `docs/`. Implemented from that set: cleanup modes, brightness/contrast, physical page size and DPI, PDF and image export, searchable text, both rotation directions. **Not implemented**: edge repair, page dewarping, page groups, JBIG2/CCITT compression, region editing.

## Workspace and important data

- Repository/workspace: `~/shell/projects/cropper`.
- Built app: `dist/PageCrop.app`; executable: `dist/PageCrop.app/Contents/MacOS/PageCrop`.
- **User's live edited project:** `examples/1940.3-review/1940.3.pagecrop`. Never regenerate or replace it with benchmark output. It contains actual manual edits and review decisions.
- Workspace photographs: `sample-images/1940.3/`. On 2026-10-10 the user deleted most of them to save space; 23 remain. The live project still lists 148 pages, so 125 of them show "Could not load this photograph". Build test fixtures only from pages whose photograph exists.
- `.qa/` holds disposable evaluations, test-project copies, screenshots, logs, and backups. `examples/1940.3-review/contact-*.jpg` shows old initial proposals, not current detector output.
- `.gitignore` excludes `.build/`, `dist/`, `.qa/`, `sample-images/`, `.DS_Store`, and the local research notes in `docs/`.

## Build, runtime and distribution

Swift Package Manager, tools version 5.9, macOS deployment target 13. No external package dependencies. Uses AppKit, Vision, CoreImage, ImageIO, CoreGraphics and CoreText. Built on Apple Silicon using Xcode 16.4 / Swift 6.1.2; current executable is **arm64 only**. macOS 13 is the declared minimum, not a tested OS matrix.

```sh
cd ~/shell/projects/cropper
./scripts/build-app.sh
swift test --disable-sandbox
open -n "$PWD/dist/PageCrop.app"
```

The build script sets module cache locations under TMPDIR, makes a release build, writes the app bundle and ad-hoc signs it. Bundle identifier is `local.pagecrop.app`. Version is 0.3.0/build 4, set by hand in the build script, which also declares the document types (project files, images, folders) that let files be dropped on the app's icon. The script replaces the executable by rename, so it can run while the app is open. Licensed GPL-3.0-or-later (`LICENSE`), matching ScanTailor. This is not Developer ID signed or notarized. Another Apple Silicon Mac can run the bundle without Xcode; first launch may require macOS Privacy & Security → Open Anyway. Intel needs a separate or universal build.

Under the agent's restricted execution environment, Vision/CoreImage tests can need an approved unrestricted tool execution because CVPixelBuffer/graphics access fails in the restricted sandbox. `--disable-sandbox` concerns SwiftPM, not that outer restriction. Test files already live in the writable workspace; do not ask for Desktop access repeatedly.

Before restarting the user's app, quit normally so it saves:

```sh
osascript -e 'if application id "local.pagecrop.app" is running then tell application id "local.pagecrop.app" to quit'
open -n ~/shell/projects/cropper/dist/PageCrop.app
```

Do not kill the app or run smoke tests against its live project. Avoid multiple normal instances writing the same project.

## Source map

| File | Responsibility |
|---|---|
| `Sources/CropCore/Model.swift` | Codable Point/Quad/Candidate/Page/Project, geometry transforms, validation, atomic JSON saves |
| `Sources/CropCore/Imaging.swift` | Upright EXIF-aware ImageIO loads, pixel-size metadata, CoreImage perspective correction, rotation, cleanup/brightness/contrast, one-bit packing |
| `Sources/CropCore/Split.swift` | PageSplit, homography between crop and output, split geometry (line, halves), fold detector |
| `Sources/CropCore/Commands.swift` | Menu enabling/titles (`MenuPolicy`), shortcut reference data, context-click selection, shared progress tracker |
| `Sources/CropCore/Features.swift` | Skew detection, despeckle, picture zones, deviation scoring |
| `Sources/CropCore/Launch.swift` | What opens at launch, untitled session names, sorting dropped files into photographs or a project |
| `Sources/CropCore/Output.swift` | Output pixel-size estimate and PDF page layout/DPI from PageFormat |
| `Sources/CropCore/Exporter.swift` | ExportOptions, per-page rendering, image encoding, Vision text recognition, streaming PDFWriter |
| `Sources/CropCore/ClaudeReview.swift` | Review prompt, reply schema and parsing, overlay drawing, `claude -p` process handling |
| `Sources/CropCore/Detector.swift` | Vision passes, proposal generation/refinement, ranking and deduplication; private grayscale edge sampler |
| `Sources/CropCore/BackgroundBoundary.swift` | Corner-colour clusters, foreground rays, robust line fits and intersections |
| `Sources/CropCore/BackgroundMaterial.swift` | Per-photo colour/texture matching and border-connected background mask |
| `Sources/CropCore/ProposalPolicy.swift` | Hard automatic-candidate constraints and soft unequal-perspective penalty |
| `Sources/PageCrop/main.swift` | AppDelegate: state, project lifecycle, queues, actions, single-key routing, undo/redo |
| `Sources/PageCrop/Interface.swift` | Window, split view, sidebar cell, status bar, toolbar |
| `Sources/PageCrop/Inspector.swift` | Inspector controls |
| `Sources/PageCrop/Menus.swift` | Menu bar, state gathering for `MenuPolicy`, Open Recent, shortcuts window |
| `Sources/PageCrop/ExportSheet.swift` | Export options sheet |
| `Sources/PageCrop/Settings.swift` | Settings window and keychain storage of the API key |
| `Sources/PageCrop/Smoke.swift` | Native UI smoke test |
| `Sources/PageCrop/Canvas.swift` | Drawing, crop overlay, magnifier, mouse editing, pan/zoom, keyboard selection state |
| `Sources/CropCheck/main.swift` | Diagnostic CLI: single-image candidate JSON, fixtures, synthetic benchmark, `--claude-files` |
| `Sources/CropCheck/CollectionCheck.swift` | Collection evaluation, contact sheets, diagnostic project and timing output |
| `Tests/CropCoreTests/GeometryTests.swift` | Geometry, detector and policy test classes, despite the narrow filename |
| `Tests/CropCoreTests/SplitTests.swift` | Proposal ordering, Claude-proposal merging, split geometry, fold detection, split export |
| `Tests/CropCoreTests/CommandTests.swift` | Menu rules and shortcut reference |
| `Tests/CropCoreTests/ReviewFixTests.swift` | Regression tests for the 2026-10-10 code review: Claude proposal persistence, verdict recording, structural undo, launch environment, progress, export limits |
| `Tests/CropCoreTests/FeatureTests.swift` | Skew detection, deskewed and split preview, despeckle, picture zones, deviations, their commands |
| `Tests/CropCoreTests/LaunchTests.swift` | Launch and import rules |
| `Tests/CropCoreTests/OutputTests.swift` | Settings decoding, layout, cleanup, export, searchable PDF and Claude reply parsing |

## Data and geometry invariants

Coordinates are normalized 0...1 against the **upright EXIF-oriented original**, with top-left origin. Quad storage is always clockwise: **TL, TR, BR, BL**. This deliberately differs from keyboard numbering 1,2,3,4 = TL,TR,BL,BR. Edge storage is top,right,bottom,left; keyboard edge numbering 5,6,7,8 = top,left,right,bottom. Do not reorder stored geometry to match shortcuts.

`Quad.valid` requires finite in-image coordinates, positive area, clockwise convexity and no degeneracy. `scaled(by:)` scales about the corner centroid and limits expansion uniformly at image boundaries. `movingEdge` moves two endpoints together, clamping the shared delta. `translated(by:)` moves all four together and clamps the common delta. `movingCornerPreservingAngles` intersects translated supporting lines with the unchanged opposite edges; it fixes the opposite corner, adjusts both neighbours, and preserves all side directions. Invalid angle-locked moves are ignored rather than distorting the shape.

`Page` stores UUID, absolute source path, quad, candidate list, status, reviewed flag, output rotation, revision and optional image aspect ratio, plus optional `adjustments` (with optional `despeckle`), `format`, `flagged`, `reviewNote`, `split`, `deskew` (one angle per output part, left page first) and `pictureZones` (rectangles in output fractions). A split's `top` and `bottom` are fractions across the corrected, rotated output, so it follows the crop; `SplitGeometry` converts to and from photograph coordinates. New fields must stay optional so earlier version 1 projects decode; the JSON schema remains version 1. `Project.read` validates geometry, obtains missing aspect metadata, and filters cached invalid automatic proposals. It may replace an invalid unreviewed automatic crop, but preserves manual and reviewed crops. Saving uses atomic Data.write.

Project files reference photographs by **absolute path**, without embedding them or providing relocation UI. Moving work to another Mac currently needs path rewriting in the JSON. Back up and close the project before external edits. Portable projects are a known missing feature.

## UI, persistence and concurrency

The app opens empty (`LaunchPolicy`): no project is reopened unless `--project` or `PAGECROP_TEST_DIR` asks for one. Each session autosaves to its own `Untitled <timestamp>.pagecrop` in Application Support, written only once it has pages. Files arrive through one route, `receive(_:)`, from the Import panel, a drop on the window (the delegate is the window's dragging destination) or `application(_:open:)` for the app's icon and double-clicked projects. A second smoke mode checks this: set `PAGECROP_SMOKE_FOLDER` and `PAGECROP_SMOKE_PROJECT` with an empty `PAGECROP_TEST_DIR`. `PAGECROP_REPORT=<file>` in test mode writes the page count after launch and quits, for testing launches through `open`.

AppDelegate owns project state on the main thread. `edit` snapshots the affected Pages for undo, clears redo, increments revision for geometry changes only, saves, and refreshes views. Undo entries are either page snapshots (matched by UUID, one entry per multi-page change) or a page-list snapshot for import, reordering and removal. Restoring a list snapshot takes only membership and order from it (`Project.restoringStructure`); each page keeps its current data. Manual crops go through `Page.setManualCrop`, proposals through `Page.selectProposal`, Claude verdicts through `Page.record`. Settings edits apply to `targetIndexes`: the sidebar selection when it contains the photograph on screen. `reloadPages()` must wrap every full table reload, because NSTableView resets its selection and would otherwise change the current photograph. Autosave also occurs for navigation and detection results, and at normal termination. Unnamed work goes to the session's untitled file in `~/Library/Application Support/PageCrop/`; nothing is reopened at launch. Save failures appear in the title/status.

Separate serial OperationQueues handle display, thumbnails, detection, export and Claude review. Display uses a UUID token to discard stale results; project/generation tokens and page revisions prevent detection overwriting intervening edits. Thumbnail cache is bounded at 24 MiB. Display images are capped at 3200 pixels on the longest side; detection uses 1600. Full originals are decoded sequentially for export, not held for the entire collection.

`loadCurrent` clears the canvas image while loading, but sets its placeholder to an empty string. **Do not show “Open a folder” during page transitions.** That text is only for an empty project. Failed image loads get an explicit failure placeholder. Neighbour prefetching and a continuous old-image transition are not implemented.

Detection action D refreshes candidates. It assigns the top result to the actual crop only when page status is Pending. For already edited/detected pages, select a refreshed candidate with brackets or the popup. B detects only Pending pages, not every unreviewed page.

## Current interaction contract

| Input | Action |
|---|---|
| Left / Right | Previous / next photograph, unless keyboard crop selection is active |
| 1 / 2 / 3 / 4 | Select TL / TR / BL / BR corner **and activate arrow editing** |
| 5 / 6 / 7 / 8 | Select top / left / right / bottom edge **and activate arrow editing** |
| Arrows after 1–8 | Nudge selected corner/edge by one display-image pixel; Shift uses ten |
| Escape | Release selection/arrow editing; otherwise stop background work |
| H / J / K / L | Expand left / bottom / top / right side by 0.5% of image dimension |
| Shift-H/J/K/L | Contract that side by the same amount |
| Option-H/J/K/L | Translate whole crop left / down / up / right by 0.5%; add Shift for 2% |
| `;` / `'` | Shrink / expand whole crop independently of selection or C; expansion is 2% per dimension, shrink is its inverse |
| C | Copy previous photograph's crop, every time; no repeat-to-expand behaviour remains |
| `[` / `]` | Previous / next proposed crop |
| Return / N | Accept and next / next unreviewed |
| Home / End | First / last image |
| Page Up / Page Down | Move ten images |
| P / R / Shift-R | Corrected preview / clockwise / counterclockwise output rotation |
| M / A | Flag / Send to Claude |
| V / Shift-V | Propose page split / remove it |
| T / Shift-T | Deskew / remove deskew; Option-`,` and Option-`.` turn by 0.1° |
| W / Shift-W | Draw a picture zone / remove zones |
| U | Next unusual page |
| `,` / `.` | Move split left / right by 0.2%; Shift 1% |
| + / − / F or 0 | Zoom in / out / fit |
| G / I / O / S | New project / import / open / save as |
| D / B | Detect current / detect Pending |
| X / Z / Y / E / ? | Full-image crop / undo / redo / export sheet / help |

Mouse controls:

- Drag a corner independently. **Shift-drag preserves angles**, moves adjacent corners and fixes the opposite one.
- Drag anywhere on a green edge (10-pixel hit tolerance) to move both endpoints together. Corners have priority within 24 pixels.
- Drag elsewhere to pan. Option-drag translates the crop. Scroll pans and pinch zooms.
- Mouse selection must **never capture arrow keys**. `CropCanvas.keyboardSelection` is distinct from `hasSelection`; it is set only by number-key dispatch, cleared by canvas mouseDown, Escape or fit/navigation. Corner buttons also do not capture arrows.
- The magnifier appears for corner dragging/keyboard selection, disappears on mouseUp, and follows keyboard corner nudging. It normally sits top-right; if that box plus a 24-pixel margin covers the active corner it switches to bottom-left. It retains placement until obstructing again, avoiding oscillation. New corner selection resets its preferred placement.
- Plain HJKL no longer pans, and WASD no longer nudges. S/D retain their regular commands.
- App-level key monitoring ignores Command/Control combinations and text-field/text-view editing. Keep menu editing shortcuts usable. Menu items use Command-key equivalents only; single keys stay in `handleKey`. Inspector text fields hand focus back to the canvas on Return.

## Automatic detector

1. Apple Vision document segmentation.
2. Vision rectangle detection on original and contrast-enhanced grayscale analysis images.
3. Corner-colour background estimates: four ranked clusters, foreground ray crossings, robust supporting-line fits.
4. Material-based background estimate: 400×300 raster, 100×75 patch grid, RGB means and local luminance variation. Learn recurring textured patches from at least two corners, classify matching regions, then flood only from image borders. Isolated similarly coloured print inside a page must not count as tabletop. This is appearance matching, **not semantic cork or finger recognition**.
5. Original and locally refined candidates; grayscale refinement searches ±0.012 normalized displacement. Wider searches previously snapped to printed borders.
6. Hard policy filtering, heuristic ranking, geometric deduplication (mean corner distance <0.012), at most six proposals, returned best first and then largest to smallest (`Candidate.ordered`). A new detection keeps an existing Claude proposal (`Candidate.merging`).

Hard automatic limits: area at least 65% of the photograph; corner angles 70–110°; opposite side-length ratio ≤1.4; opposing edge divergence ≤20°. Evaluate angles/lengths in aspect-correct pixel geometry. Manual edits are not restricted to these automatic thresholds.

Ranking combines coverage, edge support, source confidence/bonus, border proximity, shape plausibility, contained background, and unequal perspective. The latter compares left/right outer-edge lean relative to the spread's own horizontal direction, tolerates 3° imbalance, then applies a capped penalty. It discourages a nearly vertical side paired with a highly slanted side without banning balanced trapezoids or camera rotation. Scores are not calibrated probabilities.

Finger guidance from user: fingers are optional and commonly near lower corners; fingers outside the page are fine, and visible finger/page intersections can be useful corner cues. **There is no finger penalty or dedicated finger detector.** Existing visible-edge evidence may include them. Do not claim semantic hand recognition, and do not shrink away real page content to remove fingers.

Known detection limitations: shadows, backing boards and outer page stacks can remain in crops; pale margins touching corners can contaminate learning (texture threshold >0.025 added after a regression); small covers/spines conflict with the 65% minimum; generic rectangles do not fully model book folds. The uneven-perspective example is IMG_6802.HEIC: its former slanted right-edge proposal was demoted, but the replacement still contains excess background. No labelled accuracy measurement exists.

## Verification and diagnostics

**Red/green TDD is required from 2026-10-10**: write the test first, show it fail, then implement. Put decision logic in `CropCore` so it can be tested; the smoke test is a second check.

Latest core run: **108 tests passed**. The original 13 cover geometry, 300-page JSON roundtrip, perspective/rotation, policy, illustrated-page detection, edge movement, material connectivity, asymmetric perspective, angle-locked corner movement and translation; `OutputTests.swift` adds settings decoding, layout, cleanup, export, searchable PDF and Claude reply parsing. The magnifier-placement change has no dedicated UI test. The smoke test now also covers both rotation directions, flags, multi-page adjustments as one undo step, copy/paste settings, reorder/remove undo, and writes `window.png`, `export-sheet.png`, `settings.png` and a two-page searchable `export-check.pdf`. Send to Claude was checked once by hand through the CLI with the account login; the `--bare` API-key path has not been run.

Latest full detector evaluation: 148 images, zero processing errors, 18.83 s, median 0.122 s, p95 0.155 s (`.qa/perspective-evaluation/`). All yielded proposals; that is **not** 100% accuracy. Earlier 300-operation real-photo benchmark was ~31.88 s and ~147 MiB footprint; later detector additions were not rebenchmarked at 300. Earlier native UI/full-resolution-export smoke peaked near 474 MiB.

```sh
.build/release/CropCheck --collection sample-images/1940.3 .qa/new-evaluation
.build/release/CropCheck --benchmark 300
.build/release/CropCheck sample-images/1940.3/IMG_6802.HEIC
```

Collection evaluation writes a diagnostic `1940.3.pagecrop`, timing results and contact sheets. **Always use a fresh .qa output folder**, never the live project directory. Visually inspect changed top proposals; passing geometry constraints is not proof the page boundary is correct.

Native UI smoke mode lives in AppDelegate, runs synthetic mouse/key events after loading, renders `ui.png`, checks edits/undo/redo/review and exports a full-resolution JPEG. It mutates its test project and terminates itself. Always create a **copy** of a project as `.qa/<test>/Recovery.pagecrop` with selected=0, then run:

```sh
PAGECROP_TEST_DIR="$PWD/.qa/<test>" dist/PageCrop.app/Contents/MacOS/PageCrop --smoke
```

The environment override isolates app support and keeps the test out of Open Recent. The smoke expects at least two valid source images. It restores a captured display image during synchronous navigation checks because asynchronous loading cannot finish inside the same callback. Relevant logs: `.qa/keyboard-only/smoke.txt`, `.qa/side-controls/smoke.txt`, `.qa/material-ui/smoke.txt`. Test mode's assertions are in release too; a failure may exit 133 with little detail, so use a debug build to locate the line.

## Suggested next work and cautions

The user is actively steering small interaction refinements. Follow their newest request rather than rebuilding the UI or changing shortcut conventions unsolicited. Preserve manual edits and original images. Keep main-thread image decoding bounded and benchmark on real local files. Update in-app help and README whenever controls change; historical validation entries can remain historical.

Useful future foundations: portable project paths/relinking, a labelled detector regression set, more explicit operation/state separation from the large AppDelegate, neighbouring preview prefetch, accurate output sizing/PDF/OCR, and a distribution build with versioning and notarization. These are future ideas, not pending authorized work.
