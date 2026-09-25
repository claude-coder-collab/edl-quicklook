# EDL Quick Look

Quick Look previews for CMX3600 Edit Decision List (`.edl`) files in macOS Finder: a summary, a timeline graphic and an event table, in light or dark mode.

Understands CMX3600 plus the extras written by Avid, Premiere Pro, DaVinci Resolve and Final Cut: clip names, source files, dissolves, wipes, keys, speed changes (M2), markers (LOC) and roll names of any length. Anything it can't parse is listed at the end rather than dropped. See [SPEC.md](SPEC.md) for details.

Requires macOS 13 or later.

## Install

1. Download `EDL-Preview.zip` from [Releases](../../releases) and unzip it.
2. Move `EDL Preview.app` to `/Applications`.
3. Builds are not notarised yet, so clear the quarantine flag:
   ```sh
   xattr -dr com.apple.quarantine "/Applications/EDL Preview.app"
   ```
4. Open the app once, then select an `.edl` in Finder and press Space.

If no preview appears, enable **EDL Preview** under System Settings → General → Login Items & Extensions → Quick Look, and run `qlmanage -r`.

## Troubleshooting

- `mdls -name kMDItemContentType file.edl` should report `com.cmx3600.edl`. If another app has claimed `.edl` files with a different type, the preview won't be used for them.
- `qlmanage -p file.edl` previews a file from Terminal and logs errors.

## Development

- `EDLKit/`: parser and HTML renderer (Swift package, no AppKit). Run its tests anywhere with `swift test --package-path EDLKit`.
- `App/`, `Extension/`: host app and Quick Look extension.
- `project.yml`: [XcodeGen](https://github.com/yonaskolb/XcodeGen) spec. Run `xcodegen generate` to get `EDLPreview.xcodeproj`.

CI (GitHub Actions) tests EDLKit on Linux and macOS, builds the app, and uploads `EDL-Preview.zip` as an artifact. Pushing a `v*` tag publishes a release.

### Notarisation

Builds are ad-hoc signed. Adding these repository secrets makes tagged releases Developer ID signed and notarised:

| Secret | Value |
|---|---|
| `MACOS_CERTIFICATE_P12` | Base64 of the exported Developer ID Application certificate (.p12) |
| `MACOS_CERTIFICATE_PASSWORD` | Password for the .p12 |
| `MACOS_SIGNING_IDENTITY` | e.g. `Developer ID Application: Name (TEAMID)` |
| `APPLE_ID` | Apple ID email |
| `APPLE_TEAM_ID` | Team ID |
| `APPLE_APP_PASSWORD` | App-specific password for notarytool |

## Licence

MIT
