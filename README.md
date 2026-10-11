# KettleStitch

<p align="center">
  <img src="Resources/AppIcon.png" width="180" alt="KettleStitch icon: the spine of a hand-sewn book, with needle and green thread">
</p>

<p align="center">
  <b>Turn photographs of book pages into clean, cropped, straightened pages.</b><br>
  A native macOS app for working through hundreds of photographed pages and spreads, quickly and from the keyboard.
</p>

KettleStitch is a Claude Code (Opus 5.5) vibe coded application which help you find the edge of each photographed page or two-page spread, lets you correct it in a keystroke or a drag, and exports perspective-corrected pages as a PDF or as images. It can propose a page split for a spread, and offers other ways to clean up the images. Your photographs are never changed: a project is a small file that records what to do with them via a reference to the original files.

It is named after the kettle stitch, a knot that links one sewn section of a book to the next.

## What it does

- **Crop detection.** Each imported photograph gets several proposed crops; pick one with **[** and **]**, adjust its corners and edges, or copy the crop from the page before.
- **Page splitting.** The fold between facing pages is found in the gutter between their print, starting from where you put the split on the previous page. Press **t** again to step through other candidates.
- **Deskew** to level the lines of text, separately for each half of a split spread. Currently does not work very well.
- **Cleanup**: grayscale, black and white with speck removal, exposure, brightness, contrast and sharpness, with picture zones that keep their tones on a black-and-white page.
- **Smudge brush** to blur text that should not be readable in the output.
- **Preview** of exactly what will be exported, kept on as you move from page to page.
- **Export** to PDF or to JPEG, PNG or TIFF. Exports carry no metadata from the photographs (no location, camera or owner), and PDFs carry no producer, creator or dates. OCR via Apple Vision is offered.
- **Review tools**: accept pages as you go, flag ones to return to, and jump to pages whose crop is unlike the rest of the book.
- **A second opinion** (optional): send a page to Claude, OpenAI or Gemini to have its crop and split checked. It is the only feature that uses the network. It talks to the provider directly with your own API key, which is kept in your keychain; nothing else needs to be installed. See [API keys and security](#api-keys-and-security).

The [manual](docs/Manual.md) describes each of these in detail.

## Install

1. Download a disk image from the [Releases page](https://github.com/kmlawson/kettlestitch/releases). Each release offers two:
   - **`KettleStitch-<version>-apple-silicon.dmg`** for Macs with an Apple chip (M1 and later); the smaller download.
   - **`KettleStitch-<version>-universal.dmg`** for any Mac, Intel or Apple Silicon. Choose this one if you are unsure.
2. Open the disk image and drag **KettleStitch** onto the **Applications** folder beside it.
3. Open KettleStitch from Applications, and expect macOS to refuse the first time; see below.

It needs macOS 13 or later. To see which chip your Mac has, choose Apple menu ▸ About This Mac.

> [!WARNING]
> **macOS will block KettleStitch the first time you open it.** The app is not signed with an Apple Developer ID or notarized by Apple, so Gatekeeper reports that it "cannot be opened because Apple cannot check it for malicious software", or that the developer cannot be verified. This is expected for an app distributed this way. To allow it:
>
> 1. Try to open KettleStitch once, and dismiss the warning with **Done** (not *Move to Trash*).
> 2. Open **System Settings ▸ Privacy & Security** and scroll down to the Security section.
> 3. Next to the message that KettleStitch was blocked, click **Open Anyway**, then confirm with your password or Touch ID.
>
> You only need to do this once for each version you install. On macOS 14 and earlier you can instead Control-click the app, choose **Open**, and confirm. From Terminal, `xattr -dr com.apple.quarantine /Applications/KettleStitch.app` has the same effect.
>
> Only do this for a copy you downloaded from this repository's Releases page.

### Build from source

You need Xcode or the Swift toolchain.

```sh
./scripts/build-app.sh          # builds dist/KettleStitch.app for this Mac
open dist/KettleStitch.app
swift test --disable-sandbox    # runs the tests
./scripts/build-dmg.sh          # builds the two release disk images in dist/
```

An app you build yourself is not blocked by Gatekeeper, because it was never downloaded.

## Using it

1. Drop photographs, or a folder of them, onto the window. Crops are proposed straight away.
2. Step through with **→**. Fix a crop by dragging its corners or edges, or with the keys below; **c** copies the crop from the page before.
3. For a two-page spread, press **t** to split it, and drag the line if it is off.
4. Press **p** to see the result, and **Return** to accept the page and move on.
5. Press **e** to export.

Save the project with **s** to return to it later. A project stores each photograph's location; if the photographs are moved, KettleStitch asks where they are now.

## Keyboard shortcuts

Single keys act on the main window and are off while you type in a field. Letters are shown as typed: small on their own, capital only together with Shift. Press **/** or **?** in the app to see this list.

### Project

| Key | Action |
| --- | --- |
| g | New project |
| o | Open project |
| i | Import photographs or a folder |
| s | Save the project |
| Shift S | Save project as |
| e | Export |
| Esc | Stop background work, release a corner or edge, or put down the smudge brush |

### Moving between photographs

| Key | Action |
| --- | --- |
| ← / → | Previous / next |
| Shift → | Next photograph, taking this crop along |
| Home / End | First / last |
| Page Up / Page Down | Back / forward ten |
| Return | Accept the crop and go to the next |
| n | Next unreviewed |
| u | Next unusual page |
| m | Add or remove a flag |

### Cropping frame

| Key | Action |
| --- | --- |
| d | Detect this photograph; with several selected, all pending photographs |
| b | Detect all pending photographs |
| [ / ] | Previous / next proposal |
| c | Copy the previous photograph's crop |
| x | Full image |
| ; / ' | Shrink / expand the whole crop |
| h j k l | Expand the left, bottom, top, right side |
| Shift H J K L | Contract that side |
| Option h j k l | Move the whole crop; add Shift to move farther |

### Corners and edges

| Key | Action |
| --- | --- |
| 1 2 3 4 | Select the top-left, top-right, bottom-left, bottom-right corner |
| 5 6 7 8 | Select the top, left, right, bottom edge |
| Arrow keys | Nudge the selected corner or edge; add Shift for larger steps |

### Page split

| Key | Action |
| --- | --- |
| t | Propose a split between facing pages; again for the next candidate |
| Shift T | Remove the split |
| Option t | Propose a split on every page that has none |
| , / . | Move the split left / right; add Shift to move farther |

### Deskew and picture zones

| Key | Action |
| --- | --- |
| q | Deskew: level the lines of text |
| Shift Q | Remove the deskew |
| Option , / . | Turn the page counterclockwise / clockwise by 0.1° |
| w | Draw a picture zone, kept in gray on a black-and-white page |
| Shift W | Remove the picture zones |

### Smudge

| Key | Action |
| --- | --- |
| Shift B | Pick up or put down the smudge brush |
| Option Shift B | Remove the smudges |

### Output and view

| Key | Action |
| --- | --- |
| p | Corrected preview |
| v | Copy the previous photograph's image adjustments (cleanup, exposure, brightness, contrast, sharpness), with the preview on |
| r | Rotate the output clockwise |
| Shift R | Rotate the output counterclockwise |
| + / − | Zoom in / out |
| f or 0 | Zoom to fit |
| a | Send the page to Claude, OpenAI or Gemini for a second opinion |
| z / y | Undo / redo |
| / or ? | Show the shortcut reference |

### Command-key shortcuts

| Key | Action |
| --- | --- |
| ⌘N / ⌘O | New / open project |
| ⌘S / ⇧⌘S | Save / save as |
| ⌘Z / ⇧⌘Z | Undo / redo |
| ⇧⌘C / ⇧⌘V | Copy / paste a page's image adjustments and page format |
| ⇧⌘A | Select all pages |
| ⇧⌘U | Next flagged page |
| ⌘⌫ | Remove the selected pages from the project |
| ⌘J | Show deviations: pages whose crop is unlike the rest |
| ⌘. | Stop background work |
| ⌃⌘S / ⌥⌘I | Show or hide the sidebar / inspector |
| ⌃⌘L | Switch the sidebar between compact rows and large pictures |
| ⌃⌘F | Full screen |
| ⌘, | Settings |
| ⌥⌘B | Save the page on screen as a bad crop/split example, for improving the detectors |

### Mouse and trackpad

| Gesture | Action |
| --- | --- |
| Drag a corner or edge | Move it |
| Shift-drag a corner | Move it keeping the crop's angles |
| Option-drag | Move the whole crop |
| Drag the split line or its ends | Move or tilt the split |
| Drag elsewhere | Move the picture |
| Mouse wheel | Zoom about the pointer |
| Two-finger scroll / pinch | Move the picture / zoom |
| Right-click a picture zone | Remove it |

## Privacy

Everything happens on your Mac. Nothing is sent anywhere unless you ask for a second opinion on a page, which uploads a reduced copy of that page and its crop to the provider you chose, under your own API key. Exports carry no metadata from your photographs.

## API keys and security

The second-opinion feature is optional and off until you add a key. You choose a provider in **KettleStitch ▸ Settings…** and paste an API key for it:

| Provider | Models offered | Requests go to |
| --- | --- | --- |
| Claude (Anthropic) | Haiku 5.5, Sonnet 5.5, Opus 5.5 | `api.anthropic.com` |
| OpenAI | GPT-6 Luna, GPT-6.1 Sol, GPT-6 Astra | `api.openai.com` |
| Gemini (Google) | Gemini 3.5 Flash-Lite, 3.8 Flash, 3.1 Pro (preview) | `generativelanguage.googleapis.com` |

**How a key is stored**

- Keys are kept in your macOS login keychain, one item for each provider, under the service names `local.kettlestitch.app.anthropic`, `.openai` and `.gemini`. You can see or delete them in the Keychain Access app.
- A key is never written to a project file, to the app's preferences, to the usage log or to any other file, and it is never shown again after you paste it: the field is emptied and only says that a key is saved.
- **Remove Key** in Settings deletes it from the keychain.

**Where a key goes**

- A key is read from the keychain at one moment only: when you choose Send. It is put in a single header of an HTTPS request to that provider's own address, and nowhere else. It is never part of the address or the body of the request.
- The app contacts no other server, for this or anything else. It has no analytics, no update check and no telemetry.
- The connection keeps nothing on disk (no cache, no cookies) and refuses redirects, so a request cannot be passed on to another address with the key attached.

**What is sent with it**

- Two reduced JPEGs of the page on screen (longest side 1568 pixels): the photograph, and the same photograph with the crop drawn on it.
- A fixed prompt containing the crop's coordinates, and the form the answer must take.
- Not sent: the file's name or location, your other pages, the project, or anything identifying you or your Mac. The request identifies the app only as `KettleStitch (book page cropper)`.

**What is kept afterwards**

- The usage log (`~/Library/Application Support/KettleStitch/claude-usage.json`) records the time, model, file name, duration and token counts of each request, with an estimated cost at list price where the price is known. It holds no key and never leaves your Mac.

**Checking this yourself**

All of it is in three short places in the source:

| What | Where |
| --- | --- |
| Reading, writing and deleting keys in the keychain | `Keychain` in [`Sources/KettleStitch/Settings.swift`](Sources/KettleStitch/Settings.swift) |
| The only place a key is read for use | `sendToClaude` in [`Sources/KettleStitch/main.swift`](Sources/KettleStitch/main.swift) |
| The three addresses, the header the key goes in, and the no-redirect connection | `ReviewAPI` in [`Sources/CropCore/ReviewProviders.swift`](Sources/CropCore/ReviewProviders.swift) |
| The one network call in the app | `ClaudeReview.run` in [`Sources/CropCore/ClaudeReview.swift`](Sources/CropCore/ClaudeReview.swift) |

These commands, run in the repository, list every network call, every address and every use of the keychain in the app:

```sh
grep -rn 'URLSession\|URLRequest' Sources          # every network call
grep -rno 'https\?://[A-Za-z0-9./_-]*' Sources     # every address the app can contact
grep -rn 'Keychain\.\|SecItem' Sources             # every use of the keychain
```

A test, `testEachProviderGetsItsOwnRequestAndTheKeyGoesOnlyInAHeader` in `Tests/CropCoreTests/OutputTests.swift`, checks for every model that the request goes to its provider's host over HTTPS and that the key appears in exactly one header and not in the address or body. Run it with `swift test --disable-sandbox`.

Your API key is still a secret that can spend money: anyone who can unlock your Mac's keychain can read it, and each request is billed to you by the provider. Use a key with a spending limit if your provider offers one.

## Acknowledgements

Several parts of KettleStitch follow the approach of [ScanTailor](https://github.com/scantailor/scantailor), the long-standing tool for post-processing scanned pages. No ScanTailor source code is included; these parts were written afresh in Swift for photographs rather than flatbed scans, taking its methods as the model:

- **Page splitting** (`Sources/CropCore/Split.swift`) combines the two cues of ScanTailor's page-split stage, a near-vertical dark fold line and a column free of print between two bodies of content, and falls back to the centre as ScanTailor does.
- **Deskew** (`SkewDetector` in `Sources/CropCore/Features.swift`) follows its deskew stage: it tries a range of angles and keeps the one at which the lines of print give the sharpest profile.
- **Speck removal** (`Despeckle` in the same file) keeps small marks that sit beside print, such as dots and accents, as ScanTailor's despeckler does, with three levels of caution.
- **Finding unusual pages** (`Deviation` in the same file) follows the idea of ScanTailor's deviation ordering, ranking pages by how far their crop departs from the rest of the book.

## License

KettleStitch is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version. This is the same license as ScanTailor.

KettleStitch is distributed in the hope that it will be useful, but without any warranty; without even the implied warranty of merchantability or fitness for a particular purpose. See [LICENSE](LICENSE) for the full text.
