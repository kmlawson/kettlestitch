# PageCrop validation

Validated on 10 October 2026 on this Apple Silicon Mac running macOS 26.6.2, built with Xcode 16.4 and Swift 6.1.2.

## Automated checks

Four XCTest tests pass: invalid and crossed quadrilaterals are rejected; a 300-page project round-trips through the atomic save format; perspective correction and quarter-turn rotation produce the expected dimensions; and a generated dark diagonal illustration does not replace the surrounding spread boundary.

An AppKit smoke run opened a 300-entry project referencing the supplied HEIC files, loaded a preview, changed a corner, undid and redid the change, accepted the crop, navigated, and exported an original-resolution corrected JPEG. The export was 5381 by 4005 pixels. No assertion or export error occurred. The app's view was rendered and visually inspected for layout and image alignment. Peak memory footprint for this short UI plus full-resolution export run was 473,760,800 bytes, approximately 474 MB. This is not a prolonged interactive soak test or a measurement of frame latency. See [UI smoke log](ui-real-smoke.txt).

## Real photographs

The supplied `~/Desktop/1940.3` folder contains 148 HEIC files. A sampled original is 5712 by 4284 pixels. The stress run cycles through those files until 300 decode-and-detect passes have completed. It also generates contact sheets for the 148 distinct file paths and a project containing each once. It does not claim 300 different photographs or include full-resolution export of all 300 in that detection timing.

The final run completed 300 decode-and-detect passes in 31.88 seconds, with a median of 0.102 seconds and a 95th percentile of 0.133 seconds per pass. No processing errors occurred. Peak memory footprint was 147,210,984 bytes, approximately 147 MB. These measurements include contact-sheet generation for the distinct sources. Full measurements are recorded in [the real-image benchmark log](benchmark-real.txt). Proposal count measures whether an algorithm returned corners, not whether those corners are correct. The results are useful as starting crops; none has been marked reviewed automatically.

The collection exposed failures that the initial synthetic benchmark missed. Apple Vision sometimes selected a diagonal through a photograph, a printed panel, or only one page. Independent background-color boundary estimates, broader-coverage ranking and shape penalties improved those cases. Several background estimates are tried because one corner sample can contain paper, shadow or a hand.

A wider local edge search was evaluated and rejected because it sometimes moved a boundary inward onto printed borders. The delivered build retains the smaller local search and favors a conservative whole-spread proposal. Intermediate experiment logs remain in this folder for traceability; `benchmark-real.txt` is the delivered build's run.

## What still needs correction

The cover and spine photographs are poor fits for the whole-spread preference. The first photograph shows a thin book spine, and the last includes another object beside the cover. Some proposals retain too much background, page-stack shadow or fingers. Hands, inserted sheets and curved corners can also distort a fitted side. Even an apparently good proposal may trim a narrow paper margin or require a corner adjustment.

Inspect all proposals at useful zoom before accepting them. The thumbnail contact sheets are a coarse diagnostic, not pixel-level ground truth. No measured acceptance rate, formal comparison against other software, or general-purpose accuracy percentage is claimed. Tuning on this collection is not a held-out evaluation; additional books and backgrounds are needed to assess generalization.

## Deliverables

- `dist/PageCrop.app`: native local build, ad-hoc signed.
- `examples/1940.3-review/1940.3.pagecrop`: 148 original paths and editable proposals, all unreviewed.
- `examples/1940.3-review/contact-01.jpg` through `contact-10.jpg`: complete source photographs with crop overlays.
- `README.md`: workflow, full shortcut table, build instructions and current limitations.

Originals were read only. All generated project, diagnostic and export files are in the cropper workspace. Source images were not copied into the project or uploaded to a service.

## Update 0 1 1

Added hard limits to every automatic proposal: at least 65 percent image coverage, 70 to 110 degree corner angles, opposite-edge length ratio at most 1.4, and opposite-edge divergence at most 20 degrees. Angles use actual image aspect ratio. Saved projects have their proposal lists filtered on opening. Unreviewed rejected automatic selections are replaced with an admissible proposal or full-image fallback; manual and reviewed crops remain unchanged.

All eight automated tests pass, including the threshold boundary, the reported diagonal and half-page examples, preservation of manual crops, and synchronized movement of an edge's endpoints. A separate 300-entry UI check passed mouse edge dragging, magnifier dismissal on mouse release, keyboard edge movement, undo/redo, review, and export. Reprocessing the 148 supplied HEICs completed without errors in 18.60 seconds. This rerun checks the new proposal limits, not a ground-truth accuracy score.

Keyboard edge selection uses 5 top, 6 right, 7 bottom, and 8 left. WASD or Option plus arrow keys moves the selected edge, with Shift for larger steps. Escape releases selection.


## Background material and selection controls — 10 October update

Added per-photo corner-patch RGB and local texture matching, restricted to image-border-connected material. A textured-material proposal joins existing detectors and contained background lowers candidate ranking. Learning requires repeated textured samples in at least two corners; the first experiment incorrectly learned pale page margins, so flat patches are excluded. Fingers carry no penalty and are not semantically recognized; their visible edges can supply normal boundary evidence. Ground-truth accuracy is not established. Covers/spines smaller than the 65% rule remain difficult.

Ten core tests pass, including background containment versus isolated similar-coloured printed content. Final 148-photo evaluation: 18.91 seconds, median 0.118 seconds, p95 0.173 seconds, zero processing failures. Contact sheets in `.qa/material-final` were spot-checked, including the pale-margin regression. This is processing coverage, not an accuracy score. Existing manual edits and cached candidates are not overwritten; D reruns the current photo.

Selection controls now use plain arrow keys, Shift for larger movements, Escape to restore navigation. Edge selection: 5 top, 6 left, 7 right, 8 bottom. WASD selection interception removed; S and D retain their ordinary commands.

## Uneven perspective ranking

Added a rotation-invariant soft penalty for unequal outer-edge lean, prompted by IMG_6802.HEIC. Eleven tests pass, including the reported quadrilateral, a balanced trapezoid, and camera rotation. All 148 photos process without errors in 18.83 seconds. Six top proposals changed. The reported diagonal-right-edge proposal is no longer first; the replacement still includes some extra background and needs review. Existing saved crops are preserved; D generates newly ranked proposals.
