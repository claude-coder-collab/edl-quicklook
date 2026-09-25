# EDL Quick Look — Specification

Finder / Quick Look preview for Edit Decision List (`.edl`) files on macOS.

## Goals
- Pressing Space on an `.edl` in Finder (or Column view preview) shows a readable summary, a timeline graphic and an event table instead of raw text.
- Built, tested and packaged entirely by GitHub Actions on macOS runners.

## Non-goals (v1)
- Finder icon thumbnails.
- EDL dialects other than CMX3600 (GVG, Sony, etc.).
- Editing or converting EDLs.

## Supported input
CMX3600 with the common NLE extensions written by Avid, Premiere Pro, DaVinci Resolve and Final Cut exporters.

| Element | Example | Handling |
|---|---|---|
| Title | `TITLE: My Sequence` | Summary |
| Frame code mode | `FCM: DROP FRAME` / `NON-DROP FRAME` | Summary; drop-frame timecode maths; may change mid-file |
| Event line | `001  A012_C003_0915XY V  C  14:22:10:05 14:22:15:05 01:00:00:00 01:00:05:00` | Event row |
| Event number | `001`, `000123`, any number of digits | Shown as written; lines with the same number form one event |
| Roll/reel name | any length, any non-whitespace characters | Parsed from the right-hand fixed fields, so length is unrestricted |
| Tracks | `V`, `A`, `A2`, `AA`, `B`, `A/V`, `AA/V`, `A3`… | Mapped to timeline lanes |
| Transitions | `C`, `D 030`, `W001 030`, `K B`, `K O` | Two-line dissolves/wipes merged into one event |
| Clip names | `* FROM CLIP NAME:`, `* TO CLIP NAME:` | Clip name column |
| Source file | `* SOURCE FILE:` | Tooltip / detail |
| Speed change | `M2   REEL   050.0   01:00:00:00` | Speed column |
| Markers | `* LOC: 01:00:10:00 RED Note text` | Marker pins on timeline + marker list |
| Other comments | `* EFFECT NAME:`, `* ASC_SOP` … | Shown under the event |
| Unrecognised lines | anything else | Listed in an "Unparsed lines" section |

Robustness: UTF-8 with Latin-1 fallback; LF / CRLF / CR line endings; tabs or spaces; missing title.

Frame rate is not stored in CMX3600. It is inferred: drop-frame → 29.97; otherwise the largest frame value seen selects 24 / 25 / 30 (or 50 / 60). The summary labels it "assumed".

## Preview content
1. **Summary**: title, FCM, assumed frame rate, event count, record start/end, total duration, track list.
2. **Timeline graphic**: SVG, one lane per track, clips placed by record in/out, dissolves shaded, marker pins, time ruler. Fits the window at 1×; zoom buttons (1×–16×, CSS only, no JavaScript) widen it into a horizontally scrolling strip with fixed lane labels and a ruler per zoom level. Hover shows event details.
3. **Event table**: #, reel, track, transition, source in, source out, record in, record out, duration, speed, clip name. Clip comments shown beneath each row.
4. **Markers** and **Unparsed lines** sections when present.

Follows the system light/dark appearance. Target render time is under 200 ms for a 5,000-event EDL.

## Architecture
- **`EDLKit`** (Swift package): parser, timecode maths, HTML/SVG renderer. Pure Swift with no AppKit, so tests also run on Linux.
- **`EDLPreview.app`**: minimal SwiftUI host app (about/instructions window). Declares an imported UTType `com.cmx3600.edl` (extension `edl`, conforms to `public.plain-text`).
- **`EDLPreviewExtension.appex`**: Quick Look preview extension using data-based previews (`QLPreviewReply` returning HTML).
- Project file generated with XcodeGen from `project.yml` (Info.plists and entitlements are generated too); no hand-edited `.pbxproj`.
- Minimum macOS 13.

## CI / CD (GitHub Actions)
- **Pull requests and pushes**: `swift test` for EDLKit on Linux and macOS; `xcodebuild` build of the app + extension on `macos-latest`.
- **Tags `v*`**: build Release, ad-hoc sign (`codesign -s -`), zip, attach to a GitHub Release.
- **Notarization**: separate job that runs only when Developer ID secrets exist. It stays dormant until an Apple Developer account is added.

## Testing
- Fixture EDLs (hand-written plus anonymised NLE exports) covering every row in the input table, including long roll names and malformed lines.
- Unit tests: tokenizer, timecode (DF/NDF, rollover past 24 h), event merging, frame-rate inference, HTML content checks, 5,000-event performance check.
- Manual check on a Mac: `qlmanage -p sample.edl`.

## Installation (ad-hoc build)
1. Download the zip from Releases, unzip, move `EDL Preview.app` to `/Applications`.
2. `xattr -dr com.apple.quarantine "/Applications/EDL Preview.app"`
3. Open the app once; enable it under System Settings → General → Login Items & Extensions → Quick Look if needed.

## Repository
Public repo `claude-coder-collab/edl-quicklook`, MIT licence.
