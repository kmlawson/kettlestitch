# How detection works, and its limits

## Crop proposals

The pipeline combines Apple Vision document segmentation, rectangle detection on the original and an enhanced copy, and two independent estimates of the background. It scores coverage of the photograph, support along the edges and plausible geometry, then offers several alternatives, the highest-scoring first and the rest from largest to smallest. Detection runs at a maximum of 1600 pixels on the longest side.

- **Hard limits** (`ProposalPolicy`): a proposal must cover at least 65% of the photograph; its corner angles must be 70–110°; opposite sides may differ in length by at most 40% and diverge by at most 20°. Geometry is checked with the photograph's true aspect ratio. The limits are applied after refinement and again when a project is reopened; manual and reviewed crops, and a reviewer's proposal, are kept regardless.
- **Background estimate**: fits robust lines to the transitions between the page and the dominant colour in the photograph's corners. It helps with dark illustrations that mislead the document detector.
- **Material estimate**: learns the colour and texture of the corner patches of each photograph and counts only matching regions connected to the border. It adds its own proposals and penalises background inside a candidate. It does not recognise particular surfaces or need fingers in the picture; fingers carry no penalty.
- **Spread prior**: ranking penalises unequal lean of the left and right sides, measured against the spread's own horizontal. Three degrees is tolerated; more lowers the score progressively. It is a soft preference, not a rule.

No score is a calibrated probability, and every automatic crop stays unreviewed until the user accepts it. Running detection on an edited page refreshes its proposals without replacing its crop. Stop cancels queued work; a Vision request already running may finish, and its result is discarded. A revision number on each page keeps a stale detection from overwriting a newer edit.

## Page split

See `SplitDetector` in `Sources/CropCore/Split.swift`. The corrected crop is reduced to 640 pixels wide and sampled along rows from 2% to 98% of its height.

1. **Guide.** If an earlier page with the same rotation has a split, that is the guide. When the user has placed or accepted it, or is working one page at a time, it is *trusted*: the proposal is the guide, moved only onto a line within about 1.2% of the width, and a darker line farther off is ignored.
2. **Gutter band.** Otherwise the columns free of print are found (a column counts as printed when more than 4% of rows change tone sharply there). Thin lines running through blank paper, such as rules, frame borders and the fold's shadow, do not divide a band. The band nearest the expected position is taken, and only its middle 60% is searched.
3. **Lines and steps.** A candidate is a near-vertical dark line, or a step in tone of the same sign all the way down. Both must hold over twenty stretches of the height: the two weakest stretches decide, so a line that stops short counts for little.
4. **Fallbacks.** With nothing to see in a roomy band, its centre; with no usable band, the earlier weighted search; failing that, the guide or the centre of the crop.

Up to three alternatives come with each proposal, for the user to step through.

Two cues follow ScanTailor's page-split stage: the fold line and the whitespace cut.

## Deskew, speck removal, unusual pages

- `SkewDetector` tries angles between −8° and 8° and keeps the one at which rows of print, or columns for vertical text, give the sharpest profile. Print is whatever is clearly darker than the paper around it. Tilts under 0.15° are not applied.
- `Despeckle` removes connected specks below a size that depends on the level and the page's resolution, keeping small marks beside print.
- `Deviation` scores each page's crop size, shape, taper and skew against the project's own median and spread; 3.5 or more marks a page unusual.

## Foundations

- Swift and AppKit; ImageIO for decoding, Vision for detection and text recognition, Core Image for perspective correction and cleanup. No external packages.
- EXIF orientation is normalised on load. Crop coordinates are fractions of the upright photograph, in the order top-left, top-right, bottom-right, bottom-left.
- Projects are versioned JSON written atomically.
- Detection, export, review and split proposals each handle one photograph at a time and share one progress bar. Full-size originals are decoded only for export; the canvas shows at most 3200 pixels on the longest side, and the next photograph is decoded ahead.
- Undo covers crops, review state, rotation, flags, image settings, page format, splits, smudges, page order and removal, within the running session. A slider drag is one step.
- The only network use is the optional second opinion; see `ReviewProviders.swift` and the README's section on API keys.

## Not done

Edge repair, correction of page curvature, automatic picture detection, uniform margins, page groups, JBIG2 or CCITT compression, editing of recognised text, RAW and PDF import, detection of changed source files, portable project packages and persistent undo.
