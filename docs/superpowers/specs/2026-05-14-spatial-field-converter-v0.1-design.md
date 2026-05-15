# Spatial Field Converter v0.1 — Design Spec

- **Date:** 2026-05-14
- **Status:** Approved (Chris, 2026-05-14)
- **Foundation:** Composes onto in-progress ADM BWF writer (research complete), existing field-recording suite (R2 + Cloudflare Worker + Cloud Uploader), Fascinated Field v1.38 spatial-mix playback path, and the locked Atmos pipeline.

## 1. Purpose and scope

A small, single-purpose Mac app that converts 4-channel ambisonic field recordings from a Zoom H8 (with VRH-8 360 capsule) into the existing `spatial-mix` schema used across the Clouds / FBE app suite, uploads the result to R2 via Cloud Uploader, and lets the recording play back immediately in Fascinated Field as a head-tracked spatial field recording (via the existing Atmos → AirPods head-tracking pipeline).

**v0.1 scope is deliberately narrow.** One mic (VRH-8). One workflow (drag SD card or .wav → file appears in R2 → opens in FF). One output schema (existing `spatial-mix/v1`). The decoder core is built platform-agnostic so it lifts unchanged into the future Mac field recorder, FF integration, and iPhone app.

### Explicitly out of scope for v0.1

- Sennheiser Ambeo VR decode → Phase 1.5 (same architecture, swap matrix)
- Zylia ZM-1 19-channel HOA decode → Phase 1.5 (different decoder family)
- iPhone version → Phase 3
- Live recording / multitrack capture → Phase 2 (Mac Field Recorder)
- ADM BWF export → separate in-progress feature in Fascinated Field
- True ambisonic decode in FF (rotatable field independent of head movement) → future, enabled by the `source.wav` sidecar this spec writes

## 2. Architecture

### High level

```
H8 SD card (.wav files, 4-ch A-format from VRH-8)
        │
        ▼
┌───────────────────────────┐
│ Spatial Field Converter   │  ← single Mac app, drop target
│   1. Detect input mode    │
│   2. A-format → B-format  │  AmbisonicDecoder.swift  (Sources/Core/)
│   3. Render artifacts:    │
│      - source.wav         │  (B-format AmbiX, lossless sidecar)
│      - bed.m4a            │  VirtualLoudspeakerRig.swift → AAC encoder
│      - source-meta.json   │  ManifestWriter.swift
│      - manifest.json      │
│   4. Hand off to uploader │  CloudUploaderBridge.swift
└─────────────┬─────────────┘
              │
              ▼
┌──────────────────────────────────────────┐
│ Cloud Uploader (existing app)            │
│  - R2 PUT to cloud-to-float-on bucket    │
│  - catalog.json registration             │
│  - provenance=user_uploaded enforcement  │
└──────────────────────────────────────────┘
              │
              ▼
cloud-to-float-on/stems/spatial-mix/field-recording/<slug>/
              │
              ▼
Fascinated Field (existing playback path)
  → Dolby Atmos Renderer
  → AirPods spatial (head-tracked binaural)
```

### Component boundaries

The decoder, virtual-loudspeaker rig, manifest writer, and slug generator live in `Sources/Core/` and have no Mac-specific dependencies. They are pure Swift built against `Foundation` and `AVFoundation` (which is multi-platform). The Mac UI shell, drop-target window, and Cloud Uploader bridge live in `Sources/Mac/`.

This split is load-bearing for the operating principle: when Phase 2 (Mac Field Recorder) and Phase 3 (iPhone) ship, they re-use `Sources/Core/` unchanged.

## 3. Decode pipeline

### Step 1 — Input detection

Read the .wav file header and any RIFF metadata chunks present:

| Check | Action |
|---|---|
| Channel count ≠ 4 | Reject with toast: "expected 4-channel ambisonic, found N" |
| Sample rate ≠ 48000 | Warn and offer resample via `AVAudioConverter` (Atmos profile requires 48 kHz) |
| Bit depth ≠ 24 | Accept (we'll downsample to 24 on decode write) |
| iXML / BEXT chunk present | Parse for: H8 mode marker (`AMBI` in BEXT description = already AmbiX, otherwise A-format), recording timestamp, GPS coordinates if H8 had GPS module attached |
| User override | Inspector dropdown lets user force `A-format VRH-8`, `B-format AmbiX`, or `Other 4-channel (passthrough)` |

If detection determines the file is already B-format AmbiX (Zoom H8 firmware can record this directly), skip Step 2 and proceed to Step 3.

### Step 2 — A-format → B-format conversion

The Zoom VRH-8 capsule records four directional cardioid signals at the tetrahedral capsule positions, conventionally labeled:

- FLU = Front Left Up
- FRD = Front Right Down
- BLD = Back Left Down
- BRU = Back Right Up

The conversion to B-format (W, X, Y, Z) is a fixed 4×4 linear matrix per the Zoom-published VRH-8 calibration. In ACN channel order with SN3D normalization (the AmbiX standard):

```
W = (FLU + FRD + BLD + BRU) / 2     (omnidirectional)
Y = (FLU - FRD + BLD - BRU) / 2     (left-right figure-8)
Z = (FLU + FRD - BLD - BRU) / 2     (up-down figure-8)
X = (FLU - FRD - BLD + BRU) / 2     (front-back figure-8)
```

Output is written as channels 0..3 in ACN order: W, Y, Z, X.

**Implementation note:** the matrix coefficients above are the standard reference. The Zoom-published calibration may include small per-capsule trim values. v0.1 uses the reference coefficients; calibration trim is a v0.2 refinement.

Output file: 24-bit PCM, 48 kHz, 4-channel WAV with iXML chunk declaring `<AMBISONIC>AmbiX 1st-order ACN/SN3D</AMBISONIC>`.

### Step 3 — Render artifacts

From the B-format intermediate (in memory), render:

#### 3a — `source.wav` (sidecar, future-compat)
- 4-channel B-format AmbiX as decoded above
- 24-bit PCM, 48 kHz, lossless
- Written but **not** referenced by the v0.1 manifest (v0.1 FF playback uses `bed.m4a`)
- Future FF (or Phase 2 Mac recorder) will prefer this for true ambisonic decode + listener-independent rotation

#### 3b — `bed.m4a` (the v0.1 playback artifact)
- 7.1.2 Atmos bed decoded from B-format via virtual-loudspeaker rig
- Speaker positions follow the canonical Atmos 7.1.2 layout: L, R, C, LFE, Lss, Rss, Lrs, Rrs, Ltf, Rtf
- Decode method: 1st-order ambisonic basic decoder, real-valued, with **max-rE** weighting (the standard energy-vector-maximizing decoder weights for 1st-order — sharpens directional localization vs. naive in-phase decoding; reference: Daniel 2000, Politis HOA toolbox)
- LFE channel is sourced from a low-passed sum of W (omni) below 80 Hz; clamped to ITU-R BS.775 LFE level
- Encoded AAC-LC 256 kbps, 48 kHz, 7.1.2 channel mask via `AVAssetWriter` with appropriate `AVAudioChannelLayout`

**Why 7.1.2 and not 5.1 or stereo:** matches the existing FF spatial-mix bed schema, plays through the Atmos Renderer with full height information, AirPods head-tracks the full 7.1.2 layout via Apple's spatial renderer.

#### 3c — `preview.m4a` (optional, low priority — gate for v0.1)
- Stereo binaural decode for catalog-browse preview on iPhone or web
- AAC-LC 192 kbps stereo
- Uses generic HRTF (built-in `AVAudioEnvironmentNode` for v0.1; can swap to MIT KEMAR or SADIE HRTF set later)
- **Gate:** ship this in v0.1 only if implementation cost is < 4 hours. Otherwise defer to v0.2; FF can generate previews from `bed.m4a` on demand.

#### 3d — `source-meta.json`
- Original H8 file: name, byte size, BEXT timestamp, GPS lat/lng if present, original sample rate, original bit depth, original channel count
- Conversion: app version, conversion timestamp, decoder matrix version, sidecar checksum

## 4. Output bundle layout and manifest schema

### Folder layout

```
field-recording-2026-05-14-a3f9b2/
  manifest.json
  bed.m4a            # 7.1.2 AAC-LC 256k    — the v0.1 playback artifact
  source.wav         # 4-ch B-format AmbiX  — sidecar for future use
  preview.m4a        # stereo binaural      — optional, gated on cost
  source-meta.json
```

### Slug convention

`field-recording-YYYY-MM-DD-<6-char-shortuid>` where the shortuid is a base32 hash of (original filename + duration + first-1024-bytes audio hash). This makes the slug deterministic for the same source file, so re-dropping the same SD card never creates duplicates.

### R2 destination

`cloud-to-float-on/stems/spatial-mix/field-recording/<slug>/`

Matches the existing `stems/spatial-mix/<slug>/` convention (per the field-recording-suite memory). The `field-recording/` sub-prefix mirrors the existing taxonomy where `stems/spatial-mix/<category>/<slug>/` already exists for music spatial mixes.

### Manifest schema

Stays in **existing `spatial-mix/v1`** schema — no extension required for v0.1 playback in current FF. The `source.wav` and `preview.m4a` sidecars are present in the folder but not referenced by the manifest; future FF can opt-in to them by reading the folder listing or by a v2 manifest bump later.

```json
{
  "schema": "spatial-mix/v1",
  "title": "<derived from filename, user-editable in inspector>",
  "duration_sec": 312.4,
  "sample_rate": 48000,
  "bed": {
    "file": "bed.m4a",
    "layout": "7.1.2"
  },
  "objects": [],
  "provenance": "user_uploaded",
  "recorded_at": "2026-05-14T18:00:00Z",
  "source_mic": "Zoom VRH-8",
  "lat": null,
  "lng": null,
  "tags": []
}
```

**IP guard (load-bearing per field-recording-suite hard rule):** every recording the converter writes is tagged `provenance=user_uploaded` so it is shareable. The converter's UI offers no way to override this; legacy `provenance=release` recordings (Chris's existing label catalog) are not authored here.

## 5. Cloud Uploader handoff

Three integration paths to evaluate at implementation time, ranked by preference:

1. **Direct CLI / IPC entry point** — Cloud Uploader exposes (or gains) a `cloud-uploader --ingest-spatial-mix <staging-folder>` flag. The converter spawns the process and hands over the staging folder URL.
2. **Watched-folder drop target** — if Cloud Uploader already monitors a known input directory, the converter writes its staging folder there and Cloud Uploader picks it up naturally.
3. **Add the CLI flag** — if neither (1) nor (2) exists, the v0.1 implementation includes a ~half-day extension to Cloud Uploader to add `--ingest-spatial-mix`. Worth the cost since multiple future tools (Mac field recorder, iPhone Zylia recorder, FF re-export) will use the same path.

Cloud Uploader is responsible for:
- R2 PUT of every file in the staging folder to `cloud-to-float-on/stems/spatial-mix/field-recording/<slug>/`
- Updating `catalog.json` with the new entry
- Enforcing `provenance=user_uploaded` (already in place per field-recording-suite memory)
- Emitting a completion event the converter can show in its UI

The converter never speaks S3 directly. All R2 access stays funneled through Cloud Uploader for centralized auth + provenance enforcement.

## 6. UI / UX

Single-window Mac app. SwiftUI, `WindowGroup` with a single `ContentView`.

### States

```
Idle ───────────────────┐
  │ drop file/folder    │
  ▼                     │
Inspecting ─────────────┤
  │ user clicks Convert │
  ▼                     │
Converting ─────────────┤
  │ decode complete     │
  ▼                     │
Uploading ──────────────┤
  │ Cloud Uploader done │
  ▼                     │
Done ───────────────────┘ → user clicks Convert another or Open in FF
```

### Idle state
- 80% of window is a drop zone with a tetrahedral mic glyph
- Footer shows: "Drop a Zoom H8 .wav file or an SD card folder to convert"
- Menu bar item: title only (no count)

### Inspecting state (after drop)
- File list (1 item for single drop, N for folder drop) with per-row columns:
  - Filename
  - Duration
  - Channel count
  - Detected mode (`A-format VRH-8` / `B-format AmbiX (skip decode)` / `Unknown — choose`)
  - Tickbox (default checked, unchecked = skip)
  - Per-row title field (auto-filled from filename, editable)
- Footer: lat/lng input (auto-filled from BEXT GPS if present), tags chip input
- Primary button: `Convert + Upload (N files)`
- Secondary button: `Cancel`

### Converting + Uploading states
- Per-row progress bar
- Footer total: `3/47 done · 12 in queue · 32 pending`
- Menu bar item shows queue count: `SFC 3/47`
- Cancel button stops at the next file boundary (does not interrupt mid-file)

### Done state
- Per-row final state: ✓ slug + R2 key, or ✗ error reason
- Buttons: `Open in FF`, `Convert another`, `Show in R2 console` (opens the R2 web URL for the slug folder)
- Failed rows have a per-row `Retry` button

### Bulk SD card behavior

When a folder is dropped, the app recursively scans for `.wav` files and presents them all in the inspector. Files already present in R2 (slug collision check via the deterministic slug hash) are pre-unticked with a "(already converted)" annotation so re-dropping the same SD card does not re-upload.

## 7. Error handling

| Condition | Behavior |
|---|---|
| Wrong channel count (not 4) | Error toast on that row, leave file alone, continue with others |
| Sample rate ≠ 48 kHz | Warn in inspector, offer per-row resample toggle, default off |
| Bit depth other than 16/24/32 | Accept all common rates, downsample to 24 internally |
| BEXT chunk corrupted or absent | Default to `A-format VRH-8` mode, surface in the row for user override |
| Decode produces NaN or clipping | Abort that row, show diagnostic, continue with others |
| AAC encode fails | Retry once with software encoder, then fail row with diagnostic |
| Slug collision in R2 | Auto-suffix `-1`, `-2`, never overwrite |
| Cloud Uploader process crash | Keep staging folder on disk, surface "uploader offline" state, retry button |
| Network failure mid-upload | Cloud Uploader handles retry (existing behavior); converter shows pending state |
| User clicks Cancel mid-batch | Finish the current file, do not start the next, keep partial output staging folder for resume |

**Never silently destructive:** the original H8 .wav file on the SD card is never modified, moved, or deleted by this app. Output goes to staging folder under `~/Library/Caches/SpatialFieldConverter/staging/<slug>/`, then to R2. Staging folders persist after upload until the user clicks "Clear staging" in app menu (manual operation).

## 8. Testing

### Unit tests (Sources/Core)

- `AmbisonicDecoderTests.swift`
  - Impulse in known direction → expected W/Y/Z/X energy distribution (e.g., front impulse → X positive, Y zero, Z zero, W positive)
  - 4-channel zero input → 4-channel zero output
  - Roundtrip stability: A → B → A via inverse matrix → recovers original within numerical precision
- `VirtualLoudspeakerRigTests.swift`
  - Pan a known B-format source to a single direction → verify expected speaker channels light up at expected gain
  - Energy preservation: total speaker energy ≈ total B-format energy within 0.5 dB
- `ManifestWriterTests.swift`
  - Schema validates against an existing FF spatial-mix manifest (use one from `cloud-uploader/test_output/` if present)
  - Slug determinism: same input → same slug across runs
  - JSON shape exactly matches `spatial-mix/v1`
- `SlugGeneratorTests.swift`
  - Deterministic for same input
  - Collision-free for different inputs (test corpus of 1000 random inputs)

### Integration tests

- End-to-end convert of a known H8 sample fixture (committed to repo as a small ~10 second clip)
  - Verify all artifacts present in staging folder
  - Verify manifest validates
  - Verify `bed.m4a` plays back in `afplay -v 1` without error
  - Verify `source.wav` decodes back to expected B-format channel order

### Manual / acceptance

- Convert one of Chris's existing H8 recordings (e.g. from the SD card)
- Verify it appears in R2 at the expected slug path via Cloud Uploader
- Open it in FF → confirm it plays through the existing spatial-mix path
- Listen on AirPods → confirm head-tracking rotates the field as expected (this is the "spatial head tracking" Chris asked for)

## 9. Project structure

```
/Volumes/1tb /claude code projects /Projects/spatial-field-converter/
├── docs/superpowers/specs/
│   └── 2026-05-14-spatial-field-converter-v0.1-design.md   ← this file
├── Sources/
│   ├── Core/                                  ← platform-agnostic (iOS-portable)
│   │   ├── AmbisonicDecoder.swift               A→B matrix per mic + dispatch
│   │   ├── VRH8DecoderMatrix.swift              VRH-8 reference coefficients
│   │   ├── VirtualLoudspeakerRig.swift          B-format → 7.1.2 speaker layout
│   │   ├── BinauralRenderer.swift               B-format → stereo via HRTF (gated)
│   │   ├── BedEncoder.swift                     7.1.2 PCM → AAC-LC m4a via AVAssetWriter
│   │   ├── ManifestWriter.swift                 spatial-mix/v1 JSON
│   │   ├── SlugGenerator.swift                  deterministic slug from filename + audio hash
│   │   ├── WavFileReader.swift                  RIFF + iXML + BEXT parser
│   │   └── ResamplerHelper.swift                AVAudioConverter wrapper for 44.1k → 48k
│   ├── Mac/                                   ← Mac-only UI + uploader bridge
│   │   ├── SpatialFieldConverterApp.swift       SwiftUI App entry
│   │   ├── ContentView.swift                    main window view
│   │   ├── DropTargetView.swift                 NSItemProvider drop handler
│   │   ├── InspectorView.swift                  file list + per-row controls
│   │   ├── ConversionPipeline.swift             Sequencer for batch conversion
│   │   ├── CloudUploaderBridge.swift            CLI/IPC handoff to Cloud Uploader
│   │   ├── MenuBarExtra.swift                   queue count menu bar item
│   │   └── Logger.swift                         os.Logger wrapper
│   └── Resources/
│       └── Assets.xcassets/                     app icon, drop-target glyph
├── Tests/
│   ├── AmbisonicDecoderTests.swift
│   ├── VirtualLoudspeakerRigTests.swift
│   ├── ManifestWriterTests.swift
│   ├── SlugGeneratorTests.swift
│   └── Fixtures/
│       └── h8_vrh8_chirp_10s_a-format.wav       small committed test fixture
├── project.yml                                  XcodeGen
├── .gitignore
└── README.md                                    one-liner pointing at this spec
```

- Bundle ID: `com.fascinatedbyeverything.spatialfieldconverter`
- App bundle: `/Applications/Spatial Field Converter v0.1.app`
- Hardened Runtime: enabled, with `com.apple.security.cs.disable-library-validation` entitlement (per the locked rule for any FBE Mac app that may host third-party AUs in future — not strictly required for v0.1 but cheap to add now)
- Code signing: Apple Developer Team
- macOS minimum: 13.0 (matches FF and Cloud Uploader)

## 10. Open questions for implementation

These are not blockers for spec approval. They get resolved as the first investigative steps in the implementation plan.

1. **VRH-8 calibration trim** — the 4×4 matrix in §3.2 is the standard reference. Per §3.2, v0.1 ships with the reference matrix and defers per-capsule calibration trim to v0.2. The implementation step here is just to confirm Zoom publishes such trim values at all (so we know what v0.2 will need); v0.1 is not blocked.
2. **Cloud Uploader entry point** — confirm whether `MediaProcessor.swift` or a CLI flag exists for spatial-mix ingest, or whether we add `--ingest-spatial-mix`. Inspect `cloud-uploader/Sources/MediaProcessor.swift` and `ContentView.swift` first.
3. **iXML / BEXT mode marker on H8** — verify the exact string Zoom writes in BEXT description for ambisonic mode vs A-format mode. Test by reading one of Chris's existing H8 files.
4. **`preview.m4a` cost gate** — implement only if `AVAudioEnvironmentNode`-based binaural decode comes in under 4 hours. Otherwise defer.
5. **Existing FF spatial-mix manifest example** — find a real `manifest.json` from `cloud-to-float-on/stems/spatial-mix/<existing-slug>/` to validate the v1 schema example in §4 against actuality.

## 11. Future phases this unblocks

| Phase | What | How v0.1 helps |
|---|---|---|
| 1.5a | Sennheiser Ambeo support | Add second `AmbisonicDecoder` matrix entry, dropdown in inspector |
| 1.5b | Zylia ZM-1 19-ch HOA support | New `HOAAmbisonicDecoder` for 3rd-order; new `VirtualLoudspeakerRig` config; same manifest schema |
| 2 | Mac Field Recorder | Re-uses `Sources/Core/` decoder + `BedEncoder` + `ManifestWriter`; adds live capture from audio interface; same R2 path |
| 3 | iPhone Field Recorder | Re-uses `Sources/Core/` unchanged; adds iOS capture (Zylia over USB-C if class-compliant) |
| FF v0.2 | True ambisonic decode + rotatable field | Reads the `source.wav` sidecars this v0.1 wrote; no archive re-conversion needed |
| AirPods Spatial deliverables | Encoded Atmos AAC for distribution | Feeds `bed.m4a` (or `source.wav`) into Apple Spatial Audio Renderer / existing Atmos Renderer pipeline |

## 12. Related references (memory)

- `reference_field-recording-suite-architecture-2026-05-12.md` — 8-component suite, R2 buckets, schemas, IP rule
- `reference_adm-bwf-export-research-2026-05-14.md` — ADM BWF writer design (sibling work, separate output format)
- `project_fascinated-field-atmos-MILESTONE-2026-05-14.md` — verified Atmos pipeline this leverages
- `reference_atmos-object-number-convention-locked-2026-05-14.md` — Atmos channel/object mapping
- `reference_hardened-runtime-library-validation-blocks-third-party-AUs-2026-05-14.md` — entitlement to add
- `user_operating-principle-build-on-foundation-then-extend-2026-05-14.md` — the operating frame this respects

## 13. Approval log

- 2026-05-14: Brainstorm complete (Chris). Approach 1 (standalone Mac app), VRH-8 capsule, head-tracked playback via existing spatial-mix schema + Cloud Uploader handoff, bulk SD card flow, source.wav sidecar. Spec written and committed.
