# Cloud Uploader Integration Investigation — 2026-05-15

## Existing surface

### `CloudUploaderApp.swift` (lines 1–21)
Pure SwiftUI `@main` entry point. Instantiates `R2Uploader`, `VimeoCatalog`, `VimeoPipeline`, `CatalogGenerator` as `@State` properties and hands them into `ContentView`. No CLI arg parsing, no `NSApplicationDelegate`, no URL-scheme registration. No programmatic entry point at this layer.

### `ContentView.swift` (lines 1–425)
GUI only. Drop zone (`onDrop`) and file picker (`fileImporter`) both call `uploader.addFiles([url], category:)` or `uploader.addVideoFolder(url, category:)`. After upload completes, calls `catalogGenerator.generateAndUpload()` then `vimeoCatalog.loadR2Streams()`. No headless code path.

### `MediaProcessor.swift` (lines 1–633)
The conversion engine. Two relevant public functions:

- **`processADMBWF(input: URL, name: String) async throws -> URL`** (line 392)
  — The active implementation. Calls `adm_convert.py` via `/usr/bin/python3 <scriptPath> <input.path> <outputDir.path> <streamName>`. Returns the output folder (`/Volumes/1tb /claude code projects /CloudUploader_temp/spatial_<name>/`) containing `bed.m4a`, `obj-NN.m4a`, and `manifest.json`.

- **`processADMBWF_UNUSED(input: URL, name: String) async throws -> URL`** (line 420)
  — Marked UNUSED. Pure-Swift fallback that does its own ffprobe + ffmpeg stem extraction and generates a manifest inline. NOT called anywhere. Ignore it.

- **`convertToM4A(input: URL) async throws -> URL`** (line 301) — single-file audio converter.
- **`encodeVideoToHLS(input: URL, name: String, is360: Bool) async throws -> URL`** (line 33) — video pipeline, not relevant here.

Temp dir is `/Volumes/1tb /claude code projects /CloudUploader_temp/` when the external drive is mounted; falls back to system temp otherwise (line 16–23).

### `R2Uploader.swift` (lines 1–416)
Orchestrates queue processing and upload.

Key constants (lines 95–99):
- `bucket = "cloud-to-float-on"`
- `accountId = "6a378e6919e5a3f1cbd84db6c1ad5443"`
- `accessKey` / `secretKey` — hardcoded R2 credentials (NOT Keychain, NOT env vars outside the process)

`UploadCategory.spatialMix.r2Prefix` = `"stems/spatial-mix"` (line 44).

Spatial Mix pre-pass in `uploadAll()` (lines 278–297): for any queued `.wav` in the spatialMix category, calls `processor.processADMBWF(input:name:)`, removes the raw item, then calls `appendFolderItems(folderURL:category:.spatialMix, keyPrefix:"stems/spatial-mix/<folderName>")`. The resulting R2 keys are `stems/spatial-mix/<slug>/<relative-file-path>`.

Upload itself (line 341–378): `aws s3 cp <localFile> s3://cloud-to-float-on/<key> --endpoint-url https://<accountId>.r2.cloudflarestorage.com --no-progress`. Credentials injected as env vars at process launch — not stored in Keychain.

`addFiles` for `spatialMix` category (lines 141–149): queues raw files with key `stems/spatial-mix/<folderName>/<filename>` — but this is overwritten by the pre-pass above when the file is `.wav`.

### `CatalogGenerator.swift` (lines 1–402)
Lists R2 after upload and regenerates `catalog.json` at `cloud-to-float-on/catalog.json`. For `spatialMix` entries (lines 70–90), it lists sub-prefixes under `stems/spatial-mix/` and creates a `CatalogTrack` with `category = "spatialMix"`, `filename = <slug>` (the folder name). No HLS manifest — the spatial mix catalog entry points consumers to the slug folder; they fetch `manifest.json` from within it.

### `adm_convert.py` (lines 1–367)
Invoked by `processADMBWF()` as: `python3 adm_convert.py <input.wav> <output_dir> <name>`.

What it does:
1. Reads AXML chunk from BWF/BW64/RF64 (handles RF64 via ds64 — relevant for large files).
2. Probes channel count + duration via `ffprobe`.
3. Extracts stereo bed (channels 0–1) → `bed.m4a` (AAC 256k, 48kHz stereo).
4. Extracts each remaining channel as mono → `obj-01.m4a` … `obj-NN.m4a` (AAC 128k, 48kHz mono).
5. Parses ADM position data from AXML if present; falls back to circle distribution.
6. Writes `manifest.json`.

**Channel count handling:** the script hardcodes `bed_channels = min(2, channel_count)` (line 249). It extracts `channel_count - 2` mono object stems. For a 10-channel 7.1.2 input, that gives stereo bed + 8 mono objects. It does NOT preserve the full 7.1.2 bed — it collapses it to stereo L/R. The remaining 8 channels (C, LFE, Ls, Rs, Lss, Rss, Ltf, Rtf for a standard 7.1.2 layout) become individual mono object stems.

## How the existing app is invoked

**GUI only.** Drop a `.wav` file onto the drop zone with the "Spatial Mix" category selected, click "Upload All." No CLI flags, no watched folder, no IPC, no URL scheme, no NSAppleScript handler. `CloudUploaderApp.swift` uses `@main` on a `SwiftUI.App` struct with no `applicationDidFinishLaunching` or `CommandLine.arguments` parsing anywhere in the codebase.

## ADM BWF processing path

```
User drops .wav → ContentView.onDrop → R2Uploader.addFiles([url], category: .spatialMix)
  → UploadItem queued with r2Key = "stems/spatial-mix/<folderName>/<filename>"

R2Uploader.uploadAll() spatial pre-pass (R2Uploader.swift:278–297):
  - detects .wav in spatialMix queue
  - calls MediaProcessor.processADMBWF(input: url, name: folderName)
      → python3 adm_convert.py <input> <tempDir>/spatial_<name> <name>
          → bed.m4a + obj-01..obj-NN.m4a + manifest.json in tempDir
  - removes raw UploadItem
  - calls appendFolderItems(folderURL: outFolder, keyPrefix: "stems/spatial-mix/<folderName>")
      → one UploadItem per file: stems/spatial-mix/<slug>/bed.m4a, stems/spatial-mix/<slug>/obj-01.m4a, etc.

Upload pass (R2Uploader.swift:299–328):
  - aws s3 cp <localFile> s3://cloud-to-float-on/<key> --endpoint-url …

Post-upload (ContentView.swift:84–87):
  - CatalogGenerator.generateAndUpload()
      → regenerates catalog.json at cloud-to-float-on/catalog.json
```

## R2 destination

- **Bucket:** `cloud-to-float-on`
- **Prefix:** `stems/spatial-mix/<slug>/`
  - `<slug>` = input filename (without extension), lowercased, spaces/slashes → `_`
  - No `field-recording/` sub-prefix exists in the current code. The prefix is flat: `stems/spatial-mix/<slug>/`, not `stems/spatial-mix/field-recording/<slug>/`.
- **File layout produced:**
  - `stems/spatial-mix/<slug>/manifest.json`
  - `stems/spatial-mix/<slug>/bed.m4a` (stereo, AAC 256k)
  - `stems/spatial-mix/<slug>/obj-01.m4a` … `obj-NN.m4a` (mono, AAC 128k each)
  - No HLS chunks. No `.m3u8`. No `.m4s`. Single M4A stems only.

## Authentication

Hardcoded in `R2Uploader.swift` lines 95–97 and duplicated in `CatalogGenerator.swift` lines 39–41 and `VimeoCatalog.swift` line 84+:
- `accountId = "6a378e6919e5a3f1cbd84db6c1ad5443"`
- `accessKey = "97545dddf4f1f07559999dceed884792"`
- `secretKey = "3d7187bcc70bcbe9fbd0b0ea773eb751dd13d18cb2beb8c7256835310c968de0"`

Not Keychain. Not an environment variable read from the shell. Injected as `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` env vars into the `aws` subprocess at process creation time (`R2Uploader.swift:347–352`). Replicating this from Spatial Field Converter means either (a) calling Cloud Uploader as an app with the GUI path, or (b) copying the same credentials into the new app and invoking `aws s3 cp` directly — same pattern.

## Recommendation for Spatial Field Converter integration

**Option C — Add a `--process-adm-bwf` CLI flag to Cloud Uploader.**

Rationale: there is no existing CLI entry point, no watched folder, and no IPC surface. The GUI path requires a running app + human interaction. Option B (watched folder) would require adding a `FSEventStream` poller to Cloud Uploader with no existing hook point. Option C is a small, clean addition at the app entry point with zero blast radius on the existing GUI path.

### Concrete diff sketch (do not apply — description only)

**File to modify:** `Sources/CloudUploaderApp.swift`

**Change:** Replace the pure `SwiftUI.App` `@main` struct with a thin dispatch layer that checks `CommandLine.arguments` for `--process-adm-bwf <path>`. If detected, run the headless pipeline and exit; otherwise fall through to the normal SwiftUI window.

```swift
// CloudUploaderApp.swift — proposed addition

import SwiftUI
import Foundation

// Check for headless CLI mode before launching SwiftUI
// Called from a synthetic @main entry point (see note below)
func runHeadlessIfNeeded() async -> Bool {
    let args = CommandLine.arguments
    guard let idx = args.firstIndex(of: "--process-adm-bwf"),
          args.count > idx + 1 else { return false }

    let inputPath = args[idx + 1]
    let inputURL = URL(fileURLWithPath: inputPath)
    let name = inputURL.deletingPathExtension().lastPathComponent
        .lowercased()
        .replacingOccurrences(of: " ", with: "_")

    print("[CLI] processADMBWF: \(inputPath)")

    // Reuse existing objects directly
    let processor = MediaProcessor()
    let uploader = R2Uploader()
    let catalogGen = CatalogGenerator()

    do {
        // 1. Convert ADM BWF → stems + manifest in temp dir
        let outFolder = try await processor.processADMBWF(input: inputURL, name: name)

        // 2. Queue folder items under stems/spatial-mix/<name>/
        uploader.appendFolderItems(folderURL: outFolder, category: .spatialMix,
                                   keyPrefix: "stems/spatial-mix/\(name)")
        // Note: appendFolderItems is currently private — change to internal

        // 3. Upload
        await uploader.uploadAll()

        // 4. Regenerate catalog
        await catalogGen.generateAndUpload()

        print("[CLI] Done: stems/spatial-mix/\(name)/")
    } catch {
        print("[CLI] FAILED: \(error)")
        exit(1)
    }
    return true
}
```

**The one blocker:** `appendFolderItems` is `private` in `R2Uploader.swift` (line 200). Change its access modifier to `internal` (or add a public wrapper). That is the only change needed in `R2Uploader.swift`.

**SwiftUI `@main` conflict:** Swift only allows one `@main` type. The standard pattern is to remove `@main` from `CloudUploaderApp`, add a separate `main.swift` file that calls `runHeadlessIfNeeded()` and conditionally calls `CloudUploaderApp.main()` — or use `NSApplicationMain` as a fallback. The `main.swift` approach is the cleanest.

**Invocation from Spatial Field Converter:**
```swift
// In SpatialFieldConverter, after ADM BWF export completes:
let cloudUploaderURL = URL(fileURLWithPath: "/Applications/Cloud Uploader.app/Contents/MacOS/Cloud Uploader")
let proc = Process()
proc.executableURL = cloudUploaderURL
proc.arguments = ["--process-adm-bwf", admBwfOutputPath]
try proc.run()
proc.waitUntilExit()
```
No IPC framework needed. No app-group entitlements. The subprocess inherits the file system.

## Open questions

1. **7.1.2 bed collapse is intentional?** The Python script extracts only channels 0–1 as a stereo bed and treats all remaining channels as mono objects. For a 7.1.2 source, channels 2–9 (C, LFE, Ls, Rs, Lss, Rss, Ltf, Rtf) become `obj-01` through `obj-08`. This loses the multi-channel bed structure. If Fascinated Field's player expects a true 7.1.2 bed for spatial rendering, the script needs modification — confirm the player's `manifest.json` `bed` schema supports multichannel M4A or expects stereo-only.

2. **`field-recording/` sub-prefix:** the task description mentions the target should be `stems/spatial-mix/field-recording/<slug>/`, but the existing pipeline writes to `stems/spatial-mix/<slug>/` (no `field-recording/` sub-prefix). Either the description is aspirational (needs to be added), or the existing prefix is correct and the description should be updated. Confirm which is authoritative before implementing.

3. **`main.swift` vs `@main` restructure:** the SwiftUI `@main` on `CloudUploaderApp` must be removed for a `main.swift` file to coexist. This is a mechanical change but may affect how Xcode generates the Info.plist entry point. Confirm no signing/entitlement side-effects before applying.

4. **Python dependency at CLI invocation time:** `processADMBWF()` calls `/usr/bin/python3` and assumes `ffprobe`/`ffmpeg` are at `/opt/homebrew/bin/`. Spatial Field Converter's subprocess call will inherit the environment, but confirm Homebrew's bin is in PATH when launched from an app bundle (it typically is not without explicit `PATH` injection).
