# PageCrop

A native macOS cropper for large collections of photographed book pages and spreads. Version 0.1 is a working prototype focused on outer-boundary detection, fast correction and safe, non-destructive editing.

## Start

Open `dist/PageCrop.app`. A prepared project for your supplied collection is at `examples/1940.3-review/1940.3.pagecrop`; press **O** to open it. Its 148 proposals are ready for review.

For a new collection, press **G**, then **I** to import photographs or a folder, then **B** to detect all pending pages. Inspect each crop, adjust the four corners, and press **Return** to mark it reviewed and move on. Press **P** to see the perspective-corrected result. **E** exports full-resolution corrected JPEGs into a new subfolder.

**G** starts a new collection at a chosen project path. **S** saves a copy under a chosen name. Every completed edit is autosaved; the app reopens its last saved project. Before choosing a project file, recovery lives in `~/Library/Application Support/PageCrop/Recovery.pagecrop`. Source photographs are referenced by absolute path and never modified. Keep them in place. Save a named project for each book.

All main actions also have buttons. Drag a corner independently, or drag anywhere on a green edge to move both its endpoints together; drag elsewhere to pan. Option-drag moves the whole crop. The corner magnifier appears during mouse adjustment and disappears on mouse release. Keyboard-selected corners keep it visible for nudging. Crossed or collapsed crops are rejected.

## Keyboard reference

Escape releases either a corner or an edge.

Single-key commands are suspended in text-entry fields and file dialogs.

| Action | Shortcut |
|---|---|
| New / import / open / save as | G / I / O / S |
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
| Rotate output clockwise | R |
| Zoom in / out / fit | + / − / F or 0 |
| Copy previous photograph's crop | C |
| Reset to whole image | X |
| Undo / redo | Z / Y; Command-Z / Command-Y also available |
| Export all photographs | E |
| Shortcut reference | ? |

Nudges use preview-pixel increments. The current preview is capped at 3200 pixels along its longest side. Rotation applies to the corrected output; the source-corner editor retains its canonical source orientation.

## Detection behavior

Automatic proposals must cover at least **65%** of the source photograph. Their corner angles must be **70–110°**, opposite side lengths may differ by at most **40%**, and opposite sides may diverge by at most **20°**. Geometry is checked in image coordinates with its true aspect ratio. These are hard filters applied after refinement and when reopening old projects; manual and reviewed crops are preserved. If no candidate passes, the full photograph remains available for manual cropping.

The pipeline combines Apple Vision document segmentation, rectangle detection on original and enhanced analysis images, and an independent border-background estimate. It scores whole-image coverage, edge support and plausible geometry, then offers several alternatives. Local supporting-line refinement helps align candidates with visible page boundaries. Detection runs at a maximum of 1600 pixels on the longest side.

The background estimate fits robust lines to foreground transitions relative to the dominant color in the photograph's corners. It helps with dark illustrations that mislead the document detector. It is still a heuristic: cluttered backgrounds, tight framing, strong shadows, fingers, bent pages and unusual photographs can require correction.

Every automatic crop remains unreviewed. No score is presented as a calibrated accuracy percentage. Running D on a manually edited or already processed photograph refreshes its proposal list; it does not replace that crop. Choose an alternative explicitly with the menu or brackets. B only processes pending photographs. Stop cancels queued jobs; the currently executing Vision request may finish, but its result is discarded.

## Foundations and limits

- Swift/AppKit UI, ImageIO decoding, Vision detection, Core Image perspective rendering; no external dependencies or network processing.
- Bounded queues for current preview, thumbnails, detection and export. Thumbnail cache capped at 24 MiB. Detection and export each process one image at a time; full originals are decoded only for export.
- EXIF orientation normalized on load. Crop coordinates are normalized against the upright original, ordered top-left, top-right, bottom-right, bottom-left.
- Versioned JSON projects written atomically. Revision checks prevent stale detection from replacing newer edits. Undo/redo covers crop geometry, review state and output rotation within the running session.
- Originals are referenced, not copied. Source relinking, file-change detection, portable project packages, and persistent undo history remain future work.
- TIFF import uses the first image. RAW and PDF import are not implemented. Supported photographs: JPEG, PNG, HEIC/HEIF, TIFF and BMP.
- Export is corrected JPEG at quality 0.96, including any unreviewed photographs. New output folders prevent overwriting earlier exports. Each file is finalized through a temporary path. Export cancellation takes effect between images.
- Brightness, contrast, cleanup modes, nonlinear curvature correction, adjustable physical aspect ratio/DPI, PDF generation and OCR remain future work. Perspective correction cannot flatten curved paper.
- This local build is ad-hoc signed for Apple Silicon. It is not a notarized distribution release.

## Build and verify

Requires a macOS Swift toolchain; built here with Xcode 16.4 / Swift 6.1.2. Deployment target is macOS 13; runtime verification was on macOS 26.6.2 only.

```sh
./scripts/build-app.sh
swift test --disable-sandbox
.build/release/CropCheck --benchmark 300
.build/release/CropCheck --collection /path/to/photos /path/to/diagnostics 300
```

The collection check cycles through the source files if the requested count exceeds their number. It saves a project containing each unique source and contact sheets showing the **complete source photograph plus the proposed boundary**. A generated proposal is not a verified correct crop.

Tests requiring Vision/Core Image need access to the macOS graphics services; a restrictive command sandbox can prevent those services from working even though the app works normally.

Performance and evaluation findings: [Validation](docs/Validation.md).

Press **C** to copy the previous photo’s crop. **;** shrinks the current crop and **'** expands it by 2% per dimension, independently of C or selection. H/J/K/L move the left/bottom/top/right side outward by 0.5% of the image dimension; Shift reverses the direction. Expansion stops at the image boundary. All changes support undo. Mouse dragging still pans the image; Option-drag moves the whole crop.

The material detector learns recurring corner-patch colour and local texture from each photo, and only counts matching regions connected to the image border. It adds material-boundary proposals and penalizes background inside candidates. It does not recognize cork semantically or require fingers; visible occlusion edges can contribute to ordinary boundary evidence. Fingers themselves carry no penalty.

Arrow-key crop editing activates only through **1–8**, never through mouse selection or dragging. Clicking the canvas or pressing Escape exits that keyboard editing mode. Left/right then navigate photographs.

Whole-spread ranking also penalizes unequal left/right perspective lean, measured relative to the spread’s own horizontal axis. A 3° imbalance is tolerated; larger differences progressively lower the score. This is a soft prior, not a claim that all legitimate photographs have symmetric perspective.

**Shift-drag a corner** preserves the original directions and angles of all four sides: neighbouring corners adjust along their opposite edges while the opposite corner stays fixed. Ordinary dragging moves one corner independently. Invalid or out-of-image angle-locked positions are ignored.

**Option-H/J/K/L** translates the entire crop left/down/up/right by 0.5% of the image dimension; adding **Shift** uses 2% steps. All corners move together and stop at image boundaries.

The corner magnifier switches between the top-right and bottom-left of the canvas when it would obscure the active corner, retaining its position during movement to avoid flicker.
