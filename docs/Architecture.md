# KettleStitch architecture

`CropCore` owns normalized geometry, project persistence, EXIF-aware image decoding, boundary proposals and perspective export. `KettleStitch` owns application state, bounded work queues, revision checks, AppKit controls and the custom canvas. `CropCheck` provides reproducible detector evaluation and complete-source contact sheets. Geometry and persistence have XCTest coverage.

The source coordinate system is upright EXIF-normalized image space with a top-left origin. Vision's bottom-left coordinates are converted at the boundary. Core Image coordinates are converted only inside the renderer. The project stores a quadrilateral and a separate output rotation, leaving room for a future distortion recipe.

Document segmentation, two rectangle passes and background fitting generate independent candidates. Candidate ranking favors broad outer coverage and boundary support, and penalizes severely unequal opposite edges or diagonal boundaries. Background fitting uses border-color differences and robust line estimation. Local refinement translates each edge slightly and intersects its neighbors. This is not a learned model and should remain replaceable.

The UI never queues unrestricted image tasks. Detection, display loading, thumbnails and export each have one worker. This permits the editor to load while batch analysis continues, with at most four image workers active. Obsolete display results carry tokens; detection results carry project-generation tokens and per-page revisions. Manual edits invalidate earlier analysis results.

Small project metadata is encoded and atomically replaced on committed changes. Images stay in their original locations. This is a deliberate first-version tradeoff: simple, inspectable project files and no duplicate photo library, but no source relinking or fingerprint validation yet. For portable or multi-window projects, move persistence to a document package and add persistent file access bookmarks and relinking.

Future image operations should become versioned recipe stages: orientation, geometric correction, tonal adjustments, page format, then export. Nonlinear book flattening needs an interior mesh or surface model, not additional arbitrary corner manipulation. PDF export should stream pages instead of retaining an entire decoded PDF document in memory.
