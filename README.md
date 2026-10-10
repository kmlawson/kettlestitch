# KettleStitch

A native macOS cropper for large collections of photographed book pages and spreads. It detects the outer boundary of each page or spread, lets you correct it quickly, and exports perspective-corrected pages as a PDF or images, with optional page splitting, deskew, cleanup and searchable text. Editing is non-destructive and the original photographs are never changed.

The app was called PageCrop until version 0.3, and briefly ScanSeamstress. Projects saved as `.pagecrop` or `.scanseamstress` still open; new projects are saved as `.kettlestitch`. On first launch, sessions, preferences and the API key saved under an earlier name are carried over.

## Start

Open `dist/KettleStitch.app`. It opens empty: nothing is reopened on its own. Give it something to work on in any of these ways:

- drop photographs, a folder of photographs or a `.kettlestitch` project onto the app's icon;
- drop them anywhere on the app's window;
- choose **File ▸ Import Photographs…** (**I**) or **File ▸ Open Project…** (**O**);
- double-click a `.kettlestitch` project, or pick one from **File ▸ Open Recent**.

Photographs are added to the project that is open, skipping any already in it; a project file replaces it. Subfolders are not followed. Crops are proposed for the new photographs as they arrive; **B** detects any that are still pending. Inspect each crop, adjust the four corners, and press **Return** to mark it reviewed and move on. Press **P** to see the perspective-corrected, adjusted result; preview stays on as you move between photographs, and the sidebar pictures show the corrected pages while it is on. **E** opens the export sheet.

A project file is written when you save it: **S** or File ▸ Save (⌘S) updates the current file, and **Shift-S** saves it under a new name. With "Save changes automatically every 5 minutes" on in Settings (the default), a project file with unsaved changes is also written every five minutes. A dot in the window's close button marks unsaved changes, and quitting, closing or opening another project saves them if automatic saving is on and otherwise asks before discarding them. Exports carry no metadata from the photographs (no location, camera or owner), and an exported PDF has no producer, creator or dates. Until you name a project with **G** (new project at a chosen path) or **S**, every completed edit is kept in `~/Library/Application Support/KettleStitch/` as `Untitled <date and time>.kettlestitch`, a new file for each session, and it appears under Open Recent. A session nothing was added to leaves no file. Source photographs are referenced by absolute path and never modified. If some cannot be found when a project is opened, KettleStitch looks in the project file's own folder and then asks for the folder they are in now; they are matched by file name, and choosing a folder above several moved folders works too. **File ▸ Locate Missing Photographs…** asks again later. Save a named project for each book.

Every command is in the menus with a Command-key shortcut, and the common ones are in the toolbar. The sidebar lists the photographs; the inspector on the right holds the cropping, image-adjustment and page-format controls. Either side can be hidden from the View menu. The **Page** menu covers moving between photographs, selection, flags, rotation and the page list; the **Crop** menu covers detection, proposals, the page split and Send to Claude. **Help ▸ KettleStitch Keyboard Shortcuts** (or **?**) opens the full key reference. Menu commands that edit a page are unavailable while you type in a field or while a sheet or the Settings window is in front. Drag a corner independently, or drag anywhere on a green edge to move both its endpoints together; drag elsewhere to pan. Option-drag moves the whole crop. The corner magnifier appears during mouse adjustment and disappears on mouse release. Keyboard-selected corners keep it visible for nudging. Crossed or collapsed crops are rejected.

## Keyboard reference

Escape releases either a corner or an edge.

Single-key commands are suspended in text-entry fields and file dialogs.

| Action | Shortcut |
|---|---|
| New / import / open / save / save as | G / I / O / S / Shift-S |
| Detect current / detect pending | D / B |
| Stop background detection and export | Escape, when no corner is selected |
| Previous / next | Left / Right |
| First / last | Home / End |
| Move ten photographs | Page Up / Page Down |
| Accept crop and next | Return |
| Next unreviewed | N |
| Cycle alternative proposals | [ / ] |
| Select top-left / top-right / bottom-left / bottom-right | 1 / 2 / 3 / 4 |
| Select top / left / right / bottom edge | 5 / 6 / 7 / 8 |
| Move selected corner or edge | Arrow keys |
| Larger corner movement | Add Shift |
| Release corner or edge and restore arrow navigation | Escape |
| Expand left / bottom / top / right edge | H / J / K / L |
| Contract left / bottom / top / right edge | Shift + H / J / K / L |
| Shrink / expand whole crop | ; / ' |
| Corrected preview | P |
| Rotate output clockwise / counterclockwise | R / Shift + R |
| Add or remove a flag | M |
| Send to Claude | A |
| Propose page split / remove it | T / Shift + T (also V / Shift + V; ⌘T / ⇧⌘T) |
| Move split left / right | , / . |
| Larger split movement | Add Shift |
| Deskew / remove deskew | Q / Shift + Q (⌘K / ⇧⌘K) |
| Turn the page by 0.1° | Option + , / Option + . |
| Draw a picture zone / remove the zones | W / Shift + W |
| Next unusual page | U |
| Zoom in / out / fit | + / − / F or 0 |
| Copy previous photograph's crop | C |
| Reset to whole image | X |
| Undo / redo | Z / Y; Command-Z / Command-Y also available |
| Export | E |
| Shortcut reference | ? |

Nudges use preview-pixel increments. The current preview is capped at 3200 pixels along its longest side. Rotation applies to the corrected output; the source-corner editor retains its canonical source orientation.

## Selecting several pages

Shift-click or Command-click in the sidebar, or choose **Page ▸ Select All Pages**, to select several photographs. The one on screen stays on screen. Flags, image adjustments, page format, Paste Settings, Remove from Project, the export sheet's **Selected Pages** choice and Send to Claude then apply to the whole selection. Cropping always applies to the photograph on screen only.

Right-clicking a row in the sidebar acts on that row, or on the whole selection if the row is part of it.

**Page ▸ Reverse Pages Order** and **Remove from Project** change the project only; photographs on disk are never touched. Both can be undone, as can an import, and undoing them keeps any detection, review or editing done to the pages since. They are unavailable while detection, an export or a Claude review is running.

## Splitting facing pages

Many photographs show two facing pages. **V** (or **Page ▸ Propose Page Split**, Command-T, or **Split** in the inspector) looks for the fold inside the crop and draws a pink line there, distinct from the green crop. With several pages selected it proposes a split on each.

- Drag the line to move it; drag the square at either end to tilt it.
- **,** and **.** move it left and right by 0.2% of the spread; with Shift, 1%. Option-Command-Left and -Right do the same from the menu.
- **Shift-V** (or **Remove Page Split**) removes it, and the photograph exports as one page again.
- The line is stored as a position across the crop, so it follows the crop when you adjust the corners. Neither page can be thinner than 3% of the spread.
- Pages with a split read "split" in the sidebar, and the corrected preview shows the line.

On export, a page whose split is still in place becomes two pages: two PDF pages, or two image files ending `-1` and `-2`. Each half is perspective-corrected separately, so a tilted fold gives two straight pages, and each keeps the spread's resolution. **Split Pages** in the export sheet chooses *Left Page First*, *Right Page First* (for books read right to left) or *Ignore Splits*.

The split is measured across the rotated output. Turning the output a half turn mirrors it; a quarter turn drops it and looks for the fold again.

When an earlier page already has a split, the proposal goes by the nearest one: the fold is expected at the same fraction across the crop, whatever the crop's size, the line nearest that position that looks like a fold is taken, even if another is darker, and that position is used when no fold stands out. A fold runs the whole way across the page: a dark line that stops short of the top or bottom, such as the border of a printed frame, is not taken for one. When the page has a split, **Send to Claude** also shows Claude the line and asks whether it is on the fold; a corrected line is applied directly (Undo puts it back), while a crop fix still waits as a proposal. Proposing splits on several selected pages works down the list, each page going by the one before. The proposal follows the two cues ScanTailor's page-split stage uses, rewritten for this app rather than copied: a near-vertical dark line or shadow in the middle of the spread, and a column free of print between two bodies of content. A dark line with print right beside it is taken for a rule or a stroke of text rather than the fold. When neither cue stands out, the line goes at the centre and the status bar says so. Every proposal needs a visual check; on the sample collection most land on the fold and a few are off by a strip of the neighbouring page.

## Deskew

**T** (or **Crop ▸ Deskew**, Command-K, or **Auto** in the inspector) measures the tilt of the lines of text in the corrected page and turns the page level. With several pages selected it measures each. A split spread gets one angle per page.

- **Option-,** and **Option-.** turn the page counterclockwise and clockwise by 0.1°, up to 15°. **Shift-T** removes the deskew.
- The angle is shown under the file name, and the corrected preview shows the result. For a split spread the preview shows the two pages side by side, each with its own angle.
- The page keeps its size; the thin wedges a turn exposes at the edges repeat the edge of the paper.
- A tilt under 0.15° is within the measurement's error and is not applied. Changing the crop, rotation or split while a measurement is running discards it.

The measurement follows ScanTailor's deskew stage in outline: it tries angles between −8° and 8° and keeps the one at which rows, or for vertical text columns, of print give the sharpest profile. Print is taken to be whatever is clearly darker than the paper around it, so uneven lighting and dark pictures do not count. A page needs at least five lines to be measured. The crop already squares the page to the paper's edges, so most pages need nothing: of the first 30 sample pages, 26 measured level, 2 were unclear and 2 were given an angle. The one of those two I looked at, an advertisement with few lines of text, appears to be a false reading, so check the preview after deskewing.

## Picture zones

On a page set to **Black & White**, photographs and drawings turn into harsh black shapes. **W** (or **Crop ▸ Add Picture Zone**, or **Add Zone** in the inspector) lets you drag a rectangle over a picture; inside it the page keeps its gray tones, as a photograph, while the rest stays pure black and white.

- One drag draws one zone. **Escape** cancels. Right-click a zone to remove it; **Shift-W** removes all of them from the selected pages.
- Zones are drawn in blue on the photograph and stored as positions within the crop, so they follow the crop and the split.
- A page with a zone is exported as an 8-bit gray image instead of a one-bit image; a split page without a picture on its side stays one-bit.
- Zones have no effect in the other cleanup modes. They are drawn by hand; pictures are not found automatically.

## Finding unusual pages

**View ▸ Show Deviations** (Command-J) lists every page with how far its crop is from what is usual in the project, in four measures: **Size** (how much of the photograph the crop covers), **Shape** (its proportions), **Taper** (how unequal opposite sides are) and **Skew** (the deskew angle, where one has been set). Click a column heading to sort by that measure, worst first; click **Page** to return to page order. Click a row to go to that page.

A page whose worst measure is 3.5 or more is marked unusual: it shows ⚠︎ and the reason in the sidebar, and **U** (or **Page ▸ Go To ▸ Next Unusual Page**) goes to the next one. The scale is the project's own median and spread, so a mis-detected crop among 300 similar spreads stands out, and a project of fewer than five pages marks nothing. Covers, fold-outs and other legitimately different pages will be marked too.

## Image adjustments and page format

The inspector's **Image Adjustments** apply to the corrected output, not the source view, so changing one switches to the corrected preview.

- **Cleanup** has four modes. *None* leaves the photograph as it is. *Color* evens out lighting and whitens the paper. *Grayscale* does the same and removes colour. *Black & White* then reduces the page to pure black and white.
- **Despeckle** (Off, 1, 2, 3) removes specks from Black & White output: 1 takes only the smallest, 3 larger ones too, scaled to the page's resolution. A small mark beside print, such as a dot or a voicing mark, is kept. It has no effect in the other modes or inside picture zones.
- **Brightness** and **Contrast** apply in every mode; each slider is neutral in the middle and shows its value, from −100 to +100, beside it. **Sharpness** runs from 0 to 100 and strengthens edges. In Black & White, brightness moves the black/white cut-off.
- The arrow beside the heading resets all three.

Cleanup estimates the paper tone from each neighbourhood's brightest area, so large dark illustrations and photographs lighten around their edges. Use *None* for pages where that matters.

**Page Format** sets the physical size of the corrected page. Enter a width or a height in centimetres; the other follows the crop's proportions. The resolution line shows the resulting DPI. A page with no size entered counts as 300 DPI. **Fit into** centres the page on a standard sheet (A3, A4, A5, B5, US Letter, US Legal) in exported PDFs, turning the sheet to match the page.

**Edit ▸ Copy Settings** and **Paste Settings** carry adjustments and page format between pages. **Apply Settings to All Pages** copies them to the whole project.

## Export

**E** or **File ▸ Export…** opens the export sheet.

- **Include**: all pages, or only the sidebar selection. Unreviewed pages are included.
- **Format**: one PDF, or a folder of JPEG, PNG or TIFF files.
- **Type** (PDF): image only, or image plus an invisible searchable text layer recognized on this Mac by Apple Vision. **Text Language** is automatic unless you choose one. Recognition adds a second or more per page, and vertical text is recognized less reliably than horizontal text.
- **Page Cleanup**: override every page's cleanup mode for this export.
- **JPEG Quality**: used for JPEG files and for colour and grayscale pages inside a PDF. Black & White pages are stored as one-bit images in PDF, PNG and TIFF.
- **Maximum DPI**: downsamples pages above the limit. Pages are never enlarged.
- **Protection**: a password required to open the PDF. It is not remembered. It must be at most 32 unaccented letters, digits and common symbols, which is all PDF protection can store here.

The other choices are remembered between exports. A PDF is written to a temporary file and moved into place when complete; stopping an export leaves no partial PDF. Image exports go into a new dated subfolder.

## Send to Claude

**A**, **Page ▸ Send to Claude** (Option-Command-C) or the toolbar button asks Claude to check the crop of the photograph on screen, or of every selected photograph in turn.

Set it up once in **KettleStitch ▸ Settings…**: paste an Anthropic API key and choose **Haiku 5.5** or **Sonnet 5.5**. The key is stored in the login keychain. The feature runs the `claude` command-line tool (Claude Code), which must be installed.

For each page KettleStitch writes two reduced JPEGs (longest side 1568 pixels) to a temporary folder: the photograph, and the photograph with the current crop, corner labels and a coordinate grid drawn on it. It runs `claude -p` in that folder with the key in the environment and the crop coordinates in the prompt, and asks for a verdict, a short comment and four corner coordinates. The temporary files are deleted afterwards.

- While you wait, the status bar names the page Claude is looking at and counts the seconds, with a progress bar beside it. In the sidebar that page dims under a spinner and reads "Waiting for Claude…"; the rest of a batch read "Queued for Claude".
- Claude's comment appears in the inspector under the file name. It is dropped if you then change the crop by hand, and an answer about a crop you edited while Claude was looking is not kept.
- If Claude moved any corner, its version is added to the proposals as **Claude**. Your crop is not changed; choose the proposal from the menu or with **[** and **]** to try it, and undo if you disagree.
- Pages with a Claude proposal show "Claude fix" in the sidebar.
- Escape stops a batch. An error such as a rejected key stops the batch and is shown once.

This is the only feature that uses the network: the reduced photograph and its crop go to Anthropic and are billed to your API key. A model's corner estimates are approximate; treat them like any other proposal. Running detection again keeps Claude's entry; sending the page to Claude again replaces it.

## Detection behavior

Automatic proposals must cover at least **65%** of the source photograph. Their corner angles must be **70–110°**, opposite side lengths may differ by at most **40%**, and opposite sides may diverge by at most **20°**. Geometry is checked in image coordinates with its true aspect ratio. These are hard filters applied after refinement and when reopening old projects; manual and reviewed crops are preserved. If no candidate passes, the full photograph remains available for manual cropping.

The pipeline combines Apple Vision document segmentation, rectangle detection on original and enhanced analysis images, and an independent border-background estimate. It scores whole-image coverage, edge support and plausible geometry, then offers several alternatives. Local supporting-line refinement helps align candidates with visible page boundaries. Detection runs at a maximum of 1600 pixels on the longest side.

The background estimate fits robust lines to foreground transitions relative to the dominant color in the photograph's corners. It helps with dark illustrations that mislead the document detector. It is still a heuristic: cluttered backgrounds, tight framing, strong shadows, fingers, bent pages and unusual photographs can require correction.

Every automatic crop remains unreviewed. No score is presented as a calibrated accuracy percentage. Proposals are listed with the highest-scoring one first and the rest from largest to smallest. Running D on a manually edited or already processed photograph refreshes its proposal list; it does not replace that crop, and it keeps Claude's proposal if there is one. Choose an alternative explicitly with the menu or brackets. B only processes pending photographs, as does D when several photographs are selected. Stop cancels queued jobs; the currently executing Vision request may finish, but its result is discarded.

## Foundations and limits

- Swift/AppKit UI, ImageIO decoding, Vision detection and text recognition, Core Image perspective rendering and cleanup; no external package dependencies. Nothing leaves the Mac except through Send to Claude.
- Bounded queues for current preview, thumbnails, detection and export. Thumbnail cache capped at 24 MiB. Detection, export, Claude review and split proposals each process one image at a time and share one progress bar; full originals are decoded only for export.
- EXIF orientation normalized on load. Crop coordinates are normalized against the upright original, ordered top-left, top-right, bottom-right, bottom-left.
- Versioned JSON projects written atomically. Revision checks prevent stale detection from replacing newer edits. Undo/redo covers crop geometry, review state, output rotation, flags, image adjustments, page format, page order and removal within the running session. A slider drag is one undo step.
- Originals are referenced, not copied. Source relinking, file-change detection, portable project packages, and persistent undo history remain future work.
- TIFF import uses the first image. RAW and PDF import are not implemented. Supported photographs: JPEG, PNG, HEIC/HEIF, TIFF and BMP.
- Export includes any unreviewed photographs. New output folders prevent overwriting earlier image exports. Each file is finalized through a temporary path. Export cancellation takes effect between pages.
- Edge repair, nonlinear curvature correction, automatic picture detection, content selection and uniform margins, page groups, JBIG2 or CCITT compression and editing of recognized text remain future work. Perspective correction cannot flatten curved paper.
- This local build is ad-hoc signed for Apple Silicon. It is not a notarized distribution release.

## Build and verify

Requires a macOS Swift toolchain; built here with Xcode 16.4 / Swift 6.1.2. Deployment target is macOS 13; runtime verification was on macOS 26.6.2 only.

```sh
./scripts/build-app.sh
swift test --disable-sandbox
.build/release/CropCheck --benchmark 300
.build/release/CropCheck --collection /path/to/photos /path/to/diagnostics 300
.build/release/CropCheck --claude-files project.kettlestitch 5 /path/to/folder
.build/release/CropCheck --split project.kettlestitch /path/to/folder 12
.build/release/CropCheck --deskew project.kettlestitch /path/to/folder 12
```

`--deskew` prints the measured tilt of each page (or "unclear") and writes small deskewed copies, again without changing the project.

`--split` proposes a split for a project's first pages without changing the project, prints each position and writes small copies of the two halves to inspect.

`--claude-files` writes exactly what Send to Claude would upload for one page (the two images, the prompt and the reply schema) without contacting anyone.

The collection check cycles through the source files if the requested count exceeds their number. It saves a project containing each unique source and contact sheets showing the **complete source photograph plus the proposed boundary**. A generated proposal is not a verified correct crop.

The build script replaces the app's executable by rename, so it is safe to run while KettleStitch is open; quit and reopen the app to get the new build. Each build is ad-hoc signed afresh, so macOS may ask once more for permission to read the saved API key.

Tests requiring Vision/Core Image need access to the macOS graphics services; a restrictive command sandbox can prevent those services from working even though the app works normally.

Performance and evaluation findings: [Validation](docs/Validation.md).

Press **C** to copy the previous photo’s crop. **;** shrinks the current crop and **'** expands it by 2% per dimension, independently of C or selection. H/J/K/L move the left/bottom/top/right side outward by 0.5% of the image dimension; Shift reverses the direction. Expansion stops at the image boundary. All changes support undo. Mouse dragging still pans the image; Option-drag moves the whole crop.

The material detector learns recurring corner-patch colour and local texture from each photo, and only counts matching regions connected to the image border. It adds material-boundary proposals and penalizes background inside candidates. It does not recognize cork semantically or require fingers; visible occlusion edges can contribute to ordinary boundary evidence. Fingers themselves carry no penalty.

Arrow-key crop editing activates only through **1–8**, never through mouse selection or dragging. Clicking the canvas or pressing Escape exits that keyboard editing mode. Left/right then navigate photographs.

Whole-spread ranking also penalizes unequal left/right perspective lean, measured relative to the spread’s own horizontal axis. A 3° imbalance is tolerated; larger differences progressively lower the score. This is a soft prior, not a claim that all legitimate photographs have symmetric perspective.

**Shift-drag a corner** preserves the original directions and angles of all four sides: neighbouring corners adjust along their opposite edges while the opposite corner stays fixed. Ordinary dragging moves one corner independently. Invalid or out-of-image angle-locked positions are ignored.

**Option-H/J/K/L** translates the entire crop left/down/up/right by 0.5% of the image dimension; adding **Shift** uses 2% steps. All corners move together and stop at image boundaries.

The corner magnifier switches between the top-right and bottom-left of the canvas when it would obscure the active corner, retaining its position during movement to avoid flicker.

## License

KettleStitch is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version. This is the same license as ScanTailor. KettleStitch is distributed in the hope that it will be useful, but without any warranty; see [LICENSE](LICENSE) for the full text.
