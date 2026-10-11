# KettleStitch manual

How each part of the app works. For installation and the complete list of shortcuts, see the [README](../README.md).

Keys are written as they are typed: **t** on its own, **Shift T** with Shift held.

## Contents

- [Getting started](#getting-started)
- [The window](#the-window)
- [Cropping](#cropping)
- [Working on several pages at once](#working-on-several-pages-at-once)
- [Splitting facing pages](#splitting-facing-pages)
- [Deskew](#deskew)
- [Image settings](#image-settings)
- [Picture zones](#picture-zones)
- [Smudging and cloning](#smudging-and-cloning)
- [Page format](#page-format)
- [Preview](#preview)
- [Finding unusual pages](#finding-unusual-pages)
- [Export](#export)
- [A second opinion from Claude, OpenAI or Gemini](#a-second-opinion-from-claude-openai-or-gemini)
- [Projects and where things are kept](#projects-and-where-things-are-kept)
- [Troubleshooting](#troubleshooting)
- [What it cannot do](#what-it-cannot-do)

## Getting started

KettleStitch opens empty; it does not reopen your last project on its own. Give it something to work on in any of these ways:

- drop photographs, a folder of photographs or a `.kettlestitch` project onto the window or the app's icon;
- choose **File ▸ Import Photographs…** (**i**) or **File ▸ Open Project…** (**o**);
- double-click a `.kettlestitch` project, or pick one from **File ▸ Open Recent**.

Photographs are added to the project that is open, skipping any already in it; a project file replaces it. Subfolders of a dropped folder are not followed. Supported photographs are JPEG, PNG, HEIC/HEIF, TIFF and BMP. A long import shows a notice over the canvas until the pages appear.

As soon as photographs arrive, a crop is proposed for each. A typical pass through a book is then:

1. Step through with **→**. Fix a crop by dragging its corners or edges, or with the keys under [Cropping](#cropping).
2. For a two-page spread, press **t** to split it.
3. Press **p** to see the corrected result.
4. Press **Return** to accept the page and move on.
5. Press **e** to export.

Your photographs are never changed. Everything you do is recorded in the project.

## The window

- **Sidebar** (left): the photographs in order. A toolbar button beside the sidebar's own, or **View ▸ Large Sidebar Pictures** (⌃⌘L), switches between compact rows (a small picture beside the name and status) and large pictures with only the number, name and file type beneath. A warning triangle in place of a picture means the photograph is missing or cannot be read.
- **Canvas** (centre): the photograph with its crop in green and, if there is one, the split in pink. A mouse wheel zooms about the pointer; a trackpad scrolls with two fingers and zooms by pinching. **f** or **0** fits the photograph; **=** and **-** zoom.
- **Inspector** (right): sections for the **Cropping Frame**, **Image Settings** and **Page Format**, which fold away under their headings, and a short list of the most used keys.
- **Status bar** (bottom): what just happened, and progress for work under way, with a button to stop it. **Esc** also stops it.

Every command is in the menus. A command with a key of its own shows just that key there; only the standard file and edit commands use ⌘. Single keys are off while you type in a field. **/** opens the full shortcut reference.

## Cropping

Each photograph gets several proposed crops, best first. **[** and **]** step through them, as does the **Proposal** menu in the inspector.

To adjust a crop:

- Drag a corner, or drag a green edge to move both its ends. **Shift-drag** a corner keeps the crop's angles. **Option-drag** moves the whole crop. Dragging elsewhere moves the picture.
- **1 2 3 4** select a corner and **5 6 7 8** an edge; the arrow keys then nudge it (with Shift, farther). **Esc** releases it and gives the arrow keys back to moving between photographs.
- **h j k l** push the left, bottom, top and right side outward; with **Shift** they pull it in; with **Option** they move the whole crop.
- **;** and **'** shrink and expand the whole crop. A side that reaches the edge of the photograph stops there while the others keep growing.
- **c** copies the previous photograph's crop. **Shift →** goes to the next photograph and takes the current crop along.
- **x** sets the crop to the whole photograph. **d** detects again.

**Return** marks the page reviewed and moves on; **n** jumps to the next unreviewed page. **m** flags a page to come back to. **r** and **Shift R** turn the page a quarter turn, or every selected page. **Edit ▸ Copy Rotation** and **Paste Rotation** (⌥⌘C, ⌥⌘V) carry one page's rotation to others; rotation is kept apart from the image settings and page format, so Copy Settings and Apply Settings to All Pages leave it alone. The photograph is shown turned the same way, so you adjust the crop the way round it will come out; the corner keys, **h j k l** and the arrow keys all go by what you see. Stepping past the first or last page flashes a red frame instead of moving.

Things to know about the proposals:

- A proposal must cover at least 65% of the photograph and be roughly rectangular; anything else is discarded. If nothing qualifies, the crop is the whole photograph and the status says to crop by hand.
- Detection is a heuristic. Cluttered backgrounds, tight framing, strong shadows, fingers and bent pages can all need correcting, so look at every page.
- Detecting again on a page you have already edited refreshes its list of proposals without replacing your crop.
- **b** detects every page still pending; **d** does the same when several pages are selected.

## Working on several pages at once

Shift-click or ⌘-click in the sidebar, or choose **Page ▸ Select All Pages** (⇧⌘A). The photograph on screen stays on screen. Image settings, page format, flags, rotation, splits, deskew, smudge removal, Remove from Project, the export window's Selected Pages choice and the second opinion then apply to the whole selection. Cropping always applies to the photograph on screen only.

Right-clicking a row acts on that row, or on the whole selection if the row is part of it.

To reorder pages, drag them up or down in the sidebar; several selected pages move together. **Page ▸ Move Up** (⌥⌘↑) and **Move Down** (⌥⌘↓) do the same from the keyboard. The order is saved with the project and is the order of the exported pages.

**Page ▸ Reverse Pages Order** and **Remove from Project** (⌘⌫) change the project only; the photographs on disk are untouched. All of these can be undone, as can an import.

## Splitting facing pages

**t** looks for the fold between two facing pages and draws a pink line there. On export, the page becomes two.

- **t again** steps through up to three other candidates and back to the first, as long as you have not moved the line yourself.
- Drag the line to move it; drag the square at either end to tilt it.
- **y** and **u** move it left and right by 0.2% of the spread; with **Shift**, by 1%.
- **Shift T** removes it.
- **Option t** proposes a split on every page that has none, working down the book. It never runs unasked, and leaves pages that already have a split alone.

How the proposal is made:

- Working through a book page by page, each proposal starts from the split on the page before, as you left it. It goes at the same place across the new crop, whatever the crop's size, and moves only slightly, onto a fold visible within about a hundredth of the width.
- Without a page to go by, the fold is looked for in the band of blank paper between the two pages' print. Borders of printed frames and other lines at the edges of that band are ignored, and a faint change in the paper's tone counts as a fold as well as a dark line.
- A fold runs the whole height of the page; a line that stops short is not taken for one.
- When several pages are done at once, a previous split is trusted this way only if you placed it by hand or accepted the page; otherwise it is a hint.

Check each one. The line is stored as a position across the crop, so it follows the crop when you adjust the corners. Turning the output a half turn mirrors the split; a quarter turn looks for the fold again.

Each half is perspective-corrected separately, so a tilted fold still gives two straight pages. **Split Pages** in the export window chooses which half comes first (right first for books read right to left) or exports spreads whole.

## Deskew

**q** measures the tilt of the lines of text and turns the page level. A split spread gets one angle for each page.

- **Option ,** and **Option .** turn the page by 0.1°, up to 15° either way. **Shift Q** removes the deskew.
- **Split a spread before deskewing it.** The two pages of an open book rarely tilt the same way, and one angle for the whole spread suits neither. Once the page is split, each half is measured and turned on its own, and a **Deskew Of** row appears in the inspector: *Both*, *Left* or *Right* chooses which page Auto, the 0.1° turns and Reset act on. **Option /** steps through the three.
- The angle shows under the file name in the inspector.
- A tilt under 0.15° is within the measurement's error and is not applied. A page needs at least five lines of text to be measured.
- A page with little text, such as an advertisement, can give a false reading, so check the preview.

The crop already squares the page to the paper's edges, so most pages need nothing.

## Image settings

These apply to the exported page, not to the photograph as shown for cropping, so changing one turns the [preview](#preview) on.

- **Mode**, four buttons: *None* leaves the photograph as it is. *Black & White* evens out the lighting, whitens the paper and reduces the page to pure black and white. *Grayscale* evens the lighting and whitens the paper, keeping gray tones. *Color* does the same while keeping colour.
- **Despeckle** (Off, 1, 2, 3) removes specks from Black & White pages; 1 takes only the smallest. Small marks beside print, such as dots and accents, are kept.
- **Exposure** lightens or darkens the photograph as a longer or shorter exposure would, up to two stops either way.
- **Brightness** and **Contrast** shift and stretch the tones. In Black & White, brightness moves the cut-off between black and white.
- **Sharpness** strengthens edges.

Exposure, Brightness and Contrast are neutral in the middle and show a value from −100 to +100; Sharpness runs from 0 to 100. The arrow beside the heading resets everything.

To reuse settings:

- **v** copies the previous page's image settings to this page.
- **Edit ▸ Copy Settings** and **Paste Settings** (⇧⌘C, ⇧⌘V) carry image settings and page format between pages.
- **Apply Settings to All Pages**, under the Page Format section, copies them to the whole project. Crops and splits are never copied.
- **Presets** keep a set of image settings under a name. Set a page up the way you like, then choose **Save These Settings as a Preset…** from the **Preset** menu at the top of the section (or **Edit ▸ Image Settings Preset**) and name it, for example "Text pages" or "Colour plates". Choosing the preset later gives its mode, exposure, brightness, contrast, sharpness and despeckle to every selected page in one step that ⌘Z undoes. Tick the box when saving to keep the page format in the preset too. Presets are kept on this Mac for all projects; deleting one does not change pages it was applied to.

The cleanup modes estimate the paper's tone from the brightest part of each neighbourhood, so large dark pictures lighten around their edges. Use *None*, or a [picture zone](#picture-zones), where that matters.

## Picture zones

On a Black & White page, photographs and drawings turn into harsh black shapes. **w** lets you drag a rectangle over a picture; inside it the page keeps its gray tones while the rest stays black and white.

- One drag draws one zone. **Esc** cancels. Right-click a zone to remove it; **Shift W** removes all of them from the selected pages.
- Zones are drawn in blue and follow the crop and the split.
- They have no effect in the other modes.
- **Picture Zones** in Settings chooses how a zone is kept: *Grayscale* (the default) keeps its gray tones and *Color* its colours, both with the page's exposure, brightness and contrast; *None* leaves it exactly as photographed. A zone is never whitened like the paper around it, which would wash a picture out.

## Smudging and cloning

The smudge brush blurs print that should not be readable in the output.

- Click the hand button in the inspector's Smudge row, or press **Shift B**. The **Brush** (width), **Strength** and **Grain** sliders appear while the brush is in use.
- Drag over the text. Each drag is one stroke, and ⌘Z undoes the last.
- **Grain** sets how much gray speckle is laid over the blur. A smooth blur stands out against the texture of the paper around it; grain makes the patch less conspicuous. Set it to 0 for none.
- **Esc** puts the brush down. The crossed-out hand button, or **Option Shift B**, removes the smudges from the selected pages.

The **clone brush** paints a copy of one part of the page over another, for covering a mark with clean paper.

- Click the button in the Clone row, or press **Shift C**. Only the Brush width applies to it.
- **Option-click** the place to copy from. A ring marks it.
- Drag where the copy should go. The copy keeps the same distance and direction from the source for every stroke, so you can build up an area in several strokes; Option-click again to copy from somewhere else.
- **Esc** puts the brush down. The crossed-out button, or **Option Shift C**, removes everything cloned on the selected pages.

Smudges and cloned areas lie on the photograph, so they stay on the same text when the crop or split changes, and they appear in the preview and in every export. It is a blur, not a black box: at low strength large print may still be guessable, so use a high strength for anything that must not be read. A page sent for a [second opinion](#a-second-opinion-from-claude-openai-or-gemini) is sent without its smudges.

## Page format

**Page Format** sets the physical size of the exported page. Enter a width or a height in centimetres and the other follows the crop's proportions; the line beneath shows the resulting resolution. A page with no size entered counts as 300 DPI.

**Presets** centres the page on a standard sheet (A3, A4, A5, B5, US Letter, US Legal) in exported PDFs, turning the sheet to suit the page.

## Preview

**p** shows the page as it will be exported: cropped, straightened, split and with its image settings. It stays on as you move between pages, and while it is on the sidebar shows the corrected pages too. A split spread is shown as its two pages with a black band between them.

Selecting a corner or edge, picking up the smudge brush or drawing a picture zone turns the preview off, since those work on the photograph.

## Finding unusual pages

**View ▸ Show Deviations** (⌘J) lists every page with how far its crop is from what is usual in the project, in four measures: **Size**, **Shape**, **Taper** (how unequal opposite sides are) and **Skew** (the deskew angle). Click a column heading to sort by it; click a row to go to that page.

A page that stands well apart is marked ⚠︎ with the reason in the sidebar, and **.** goes to the next one. The scale is the project's own, so one mis-detected crop among hundreds of similar spreads stands out; covers and fold-outs will be marked too. A project of fewer than five pages marks nothing.

## Export

**e** opens the export window.

- **Include**: all pages, or only the selection. Pages you have not reviewed are included.
- **Format**: one PDF; one **PDF with Apple Vision OCR**, which adds an invisible layer of recognised text so the PDF can be searched and copied from; or a folder of JPEG, PNG or TIFF files.
- **Text Language**, for the OCR format: automatic unless you choose one.
- **Split Pages**: left half first, right half first, or ignore splits.
- **JPEG Quality**: for JPEG files and for colour and grayscale pages inside a PDF. Black & White pages are stored as compact one-bit images.
- **Maximum DPI**: reduces pages above the limit, for a smaller file. Pages are never enlarged.

The choices are remembered. The progress in the status bar counts output pages, so a split spread counts as two, and it stays until the file is complete. A PDF is written to a temporary file and moved into place only when finished, so stopping leaves no partial PDF. Image files go into a new dated folder and are named after the originals.

Text recognition runs on your Mac. It adds a second or more per page and is less reliable for vertical text; the recognised text cannot be edited.

Exports carry nothing from the photographs' metadata (no location, camera or owner), and a PDF has no producer, creator or dates.

## A second opinion from Claude, OpenAI or Gemini

Optionally, a model can check a page's crop and split. This is the only feature that uses the network, and it needs your own API key.

Set it up once in **KettleStitch ▸ Settings…**: choose a provider, paste a key for it and choose a model.

| Provider | Models, cheapest first |
| --- | --- |
| Claude (Anthropic) | Haiku 5.5, Sonnet 5.5, Opus 5.5 |
| OpenAI | GPT-6 Luna, GPT-6.1 Sol, GPT-6 Astra |
| Gemini (Google) | Gemini 3.5 Flash-Lite, Gemini 3.8 Flash, Gemini 3.1 Pro (preview) |

Then **a**, or the toolbar's Second Opinion button, sends the page on screen, or each selected page in turn. The menu command names the provider you chose.

- **What is sent:** two reduced copies of the page (longest side 1568 pixels), one plain and one with the crop and split drawn on it, plus the crop's coordinates. Nothing else, and only to that provider. See [API keys and security](../README.md#api-keys-and-security) in the README.
- **While you wait:** the status bar names the model and page and counts the seconds; the page dims under a spinner in the sidebar. **Esc** stops.
- **The answer:** if the model moves a corner, its crop is selected at once and added to the proposals under the provider's name. A corrected split line is applied the same way. ⌘Z puts either back. Its comment, of a few words, appears under the file name.
- **If you edited the crop while waiting,** the answer is discarded.
- **Cost:** the status bar shows the tokens used and, where the price is known, an estimate of the cost. **Tools ▸ Second Opinion Usage Log…** lists every request.
- **Failures:** a busy service is retried up to three times. A rejected key, or a model declining a page, is reported once and stops a batch.

A model's corners are estimates; treat them like any other proposal.

## Projects and where things are kept

- **A project** is a small `.kettlestitch` file holding the list of photographs and what to do with each. It stores each photograph's full location, not the photograph.
- **Saving:** **s** (⌘S) saves the project file; **Shift S** saves under a new name; **g** starts a new project at a place you choose. A dot in the window's close button marks unsaved changes.
- **Auto-save:** with "Save changes automatically every 5 minutes" on in Settings (the default), a project file is saved every five minutes, and when you quit, close or open another project. With it off, you are asked.
- **Quitting with work never saved to a file:** you are asked whether to save it, and where. If you choose not to, it is not lost: see the next point.
- **Untitled work** is kept as you go in `~/Library/Application Support/KettleStitch/`, as `Untitled <date and time>.kettlestitch`, and appears under Open Recent.
- **After a crash:** unsaved changes to a project file are also kept aside, a couple of seconds after you stop editing. If KettleStitch closes without saving them, the **Recovery** window opens the next time and lists them. Opening a copy shows the project with those changes still unsaved; the project file changes only when you save. **File ▸ Recovery…** shows the same list at any time, with untitled work too, and is where to delete copies you no longer want. Nothing is deleted on its own.
- **Moved photographs:** if a project cannot find its photographs, it looks in its own folder and then asks where they are now. They are matched by file name, and you can choose a folder above several moved folders. **File ▸ Locate Missing Photographs…** asks again later.
- **API keys** are in your login keychain, one for each provider.
- **The usage log** for second opinions is `claude-usage.json` in the same Application Support folder.
- Projects from the app's earlier names, `.pagecrop` and `.scanseamstress`, still open.

## Troubleshooting

**macOS will not open the app.** It is not notarized. Try to open it once, then use System Settings ▸ Privacy & Security ▸ Open Anyway. The README's install section has the steps.

**A sidebar row shows a warning triangle.** The photograph is missing or cannot be read. Use File ▸ Locate Missing Photographs… if it was moved.

**"KettleStitch was updated while it was running…"** in Settings or when sending a page. macOS will not let a copy of the app that was replaced on disk read the keychain. Quit and reopen; your key is still saved.

**macOS asks for permission to use a key.** This can happen once after installing a new version. Choose Always Allow.

**A split lands on a printed border or the wrong line.** Press **t** again for another candidate, or drag the line. Once one page is right, the following pages start from it.

**A Black & White page loses a picture.** Draw a [picture zone](#picture-zones) over it.

**Moving between pages feels slow.** Detection of a newly imported book runs in the background for a while and competes for the processor; **Esc** stops it, and **b** resumes it for the pages still pending.

**Is there a newer version?** Choose **KettleStitch ▸ Check for Updates…**. It asks GitHub for the latest release and offers to open the download page. Nothing is checked unless you ask. To be told at launch instead, turn on **Check for updates on startup** in Settings: a newer version is then mentioned in the status bar at the bottom of the window.

## What it cannot do

- Flatten curved pages. Perspective correction straightens a flat page seen at an angle, not the bend near a spine.
- Import PDFs or RAW files. A multi-page TIFF contributes its first image only.
- Find pictures on a page by itself; picture zones are drawn by hand.
- Edit recognised text, or correct it.
- Keep undo history after you quit.
- Notice that a photograph has been changed on disk.

## For developers

Notes on the code, building and the measurements behind the detectors are in [`development/`](development/) and [`validation/`](validation/).
