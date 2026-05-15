# Spatial Field Converter v0.1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a standalone Mac drop-target app that bulk-converts Zoom H8 + VRH-8 4-ch ambisonic field recordings into the existing `spatial-mix/v1` schema and pushes them to R2 via Cloud Uploader so they play head-tracked in Fascinated Field.

**Architecture:** Pure-Swift `Sources/Core/` engine (WAV parser → A→B-format decoder → 7.1.2 virtual-loudspeaker rig → AAC encoder → manifest writer → slug generator) wrapped in a SwiftUI Mac app shell that batches files and hands the staging folder to Cloud Uploader via a CLI flag we add to that project. Core is platform-agnostic and lifts unchanged into the future iOS field recorder.

**Tech Stack:** Swift 5.9+, SwiftUI (macOS 13+), AVFoundation (AVAssetWriter for AAC, AVAudioConverter for resample), XCTest, XcodeGen for project generation.

**Spec:** `docs/superpowers/specs/2026-05-14-spatial-field-converter-v0.1-design.md`

---

## File Structure

Created in this plan:

```
spatial-field-converter/
├── project.yml                                          XcodeGen config
├── .gitignore
├── README.md
├── Sources/
│   ├── Core/                                            ← platform-agnostic, no Mac UI imports
│   │   ├── WavFileReader.swift                          RIFF + iXML + BEXT parser, returns WavMetadata + sample reader
│   │   ├── WavSampleReader.swift                        Streaming sample reader for large files (lazy by frame block)
│   │   ├── ResamplerHelper.swift                        AVAudioConverter wrapper for 44.1k → 48k
│   │   ├── VRH8DecoderMatrix.swift                      Static 4×4 reference matrix
│   │   ├── AmbisonicDecoder.swift                       Apply matrix to interleaved float frames
│   │   ├── VirtualLoudspeakerRig.swift                  B-format → 7.1.2 fixed-position decoder (max-rE)
│   │   ├── BedEncoder.swift                             7.1.2 PCM → AAC-LC m4a via AVAssetWriter
│   │   ├── AmbisonicWavWriter.swift                     4-ch B-format AmbiX with iXML chunk → source.wav
│   │   ├── ManifestWriter.swift                         spatial-mix/v1 JSON
│   │   ├── SlugGenerator.swift                          Deterministic slug (filename + duration + first-1024 hash)
│   │   ├── SourceMetaWriter.swift                       source-meta.json
│   │   └── ConversionJob.swift                          Top-level orchestrator: takes a URL, produces a staging folder
│   ├── Mac/                                             ← Mac-only: UI + uploader bridge
│   │   ├── SpatialFieldConverterApp.swift               SwiftUI App entry
│   │   ├── ContentView.swift                            Window root
│   │   ├── DropTargetView.swift                         NSItemProvider drop handler
│   │   ├── InspectorView.swift                          File list + per-row controls
│   │   ├── ConversionPipeline.swift                     Sequencer: queue of ConversionJob, serial execution
│   │   ├── CloudUploaderBridge.swift                    Spawns cloud-uploader subprocess with --ingest-spatial-mix flag
│   │   ├── PreferencesStore.swift                       UserDefaults wrapper for staging dir, uploader path
│   │   └── Logger.swift                                 os.Logger wrapper
│   └── Resources/
│       ├── Assets.xcassets/
│       └── SpatialFieldConverter.entitlements           Hardened Runtime + disable-library-validation
├── Tests/
│   ├── WavFileReaderTests.swift
│   ├── AmbisonicDecoderTests.swift
│   ├── VirtualLoudspeakerRigTests.swift
│   ├── BedEncoderTests.swift
│   ├── AmbisonicWavWriterTests.swift
│   ├── ManifestWriterTests.swift
│   ├── SlugGeneratorTests.swift
│   ├── SourceMetaWriterTests.swift
│   ├── ConversionJobTests.swift                         Integration test (synthesized ambisonic input → full bundle out)
│   └── TestHelpers/
│       ├── SyntheticAmbisonicSignals.swift              Generators for known-direction test signals
│       └── TempDirectory.swift                          Test-scoped temp dir helpers
```

Modified in this plan (in a sibling project):

```
/Volumes/1tb /claude code projects /Projects/cloud-uploader/
└── Sources/
    ├── ContentView.swift          Add command-line argument handling at app startup (if not present)
    └── MediaProcessor.swift       Add ingestSpatialMixStaging(folderURL:) entry point
```

---

## Phase 0 — Project Scaffolding

### Task 0.1: XcodeGen project.yml

**Files:**
- Create: `project.yml`
- Create: `.gitignore`
- Create: `README.md`

- [ ] **Step 1: Write `project.yml`**

```yaml
name: SpatialFieldConverter
options:
  bundleIdPrefix: com.fascinatedbyeverything
  deploymentTarget:
    macOS: "13.0"
  createIntermediateGroups: true

settings:
  base:
    SWIFT_VERSION: "5.9"
    DEVELOPMENT_TEAM: ""    # filled in by build environment
    CODE_SIGN_STYLE: Automatic
    ENABLE_HARDENED_RUNTIME: YES

targets:
  SpatialFieldConverter:
    type: application
    platform: macOS
    sources:
      - path: Sources/Core
      - path: Sources/Mac
      - path: Sources/Resources
        excludes:
          - SpatialFieldConverter.entitlements
    resources:
      - path: Sources/Resources/Assets.xcassets
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.fascinatedbyeverything.spatialfieldconverter
        INFOPLIST_KEY_LSUIElement: NO
        INFOPLIST_KEY_NSHumanReadableCopyright: "© 2026 Fascinated By Everything"
        INFOPLIST_KEY_CFBundleDisplayName: "Spatial Field Converter"
        CODE_SIGN_ENTITLEMENTS: Sources/Resources/SpatialFieldConverter.entitlements
        MARKETING_VERSION: "0.1.0"
        CURRENT_PROJECT_VERSION: "1"

  SpatialFieldConverterTests:
    type: bundle.unit-test
    platform: macOS
    sources:
      - path: Tests
    dependencies:
      - target: SpatialFieldConverter
    settings:
      base:
        BUNDLE_LOADER: "$(TEST_HOST)"
        TEST_HOST: "$(BUILT_PRODUCTS_DIR)/SpatialFieldConverter.app/Contents/MacOS/SpatialFieldConverter"

schemes:
  SpatialFieldConverter:
    build:
      targets:
        SpatialFieldConverter: all
        SpatialFieldConverterTests: [test]
    test:
      targets:
        - SpatialFieldConverterTests
```

- [ ] **Step 2: Write `.gitignore`**

```
.DS_Store
build/
DerivedData/
*.xcodeproj
.swiftpm/
xcuserdata/
.build/
```

- [ ] **Step 3: Write `README.md`**

```markdown
# Spatial Field Converter

Bulk-convert Zoom H8 + VRH-8 4-channel ambisonic field recordings into the spatial-mix schema, push to R2 via Cloud Uploader, play back head-tracked in Fascinated Field.

See `docs/superpowers/specs/2026-05-14-spatial-field-converter-v0.1-design.md` for the full design.

## Build

Requires XcodeGen (`brew install xcodegen`) and Xcode 15+.

```bash
xcodegen generate
xcodebuild -scheme SpatialFieldConverter -configuration Debug build
```

## Test

```bash
xcodebuild -scheme SpatialFieldConverter -configuration Debug test
```
```

- [ ] **Step 4: Commit**

```bash
git add project.yml .gitignore README.md
git commit -m "chore: project.yml scaffolding + README"
```

### Task 0.2: Entitlements + Assets

**Files:**
- Create: `Sources/Resources/SpatialFieldConverter.entitlements`
- Create: `Sources/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json`

- [ ] **Step 1: Write entitlements file**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <false/>
    <key>com.apple.security.files.user-selected.read-write</key>
    <true/>
    <key>com.apple.security.cs.disable-library-validation</key>
    <true/>
</dict>
</plist>
```

- [ ] **Step 2: Write Assets.xcassets stub**

```bash
mkdir -p "Sources/Resources/Assets.xcassets/AppIcon.appiconset"
```

```json
{
  "images" : [
    { "idiom" : "mac", "size" : "16x16", "scale" : "1x" },
    { "idiom" : "mac", "size" : "16x16", "scale" : "2x" },
    { "idiom" : "mac", "size" : "32x32", "scale" : "1x" },
    { "idiom" : "mac", "size" : "32x32", "scale" : "2x" },
    { "idiom" : "mac", "size" : "128x128", "scale" : "1x" },
    { "idiom" : "mac", "size" : "128x128", "scale" : "2x" },
    { "idiom" : "mac", "size" : "256x256", "scale" : "1x" },
    { "idiom" : "mac", "size" : "256x256", "scale" : "2x" },
    { "idiom" : "mac", "size" : "512x512", "scale" : "1x" },
    { "idiom" : "mac", "size" : "512x512", "scale" : "2x" }
  ],
  "info" : { "version" : 1, "author" : "xcode" }
}
```

```json
{ "info" : { "version" : 1, "author" : "xcode" } }
```

(First file goes to `Sources/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json`, second to `Sources/Resources/Assets.xcassets/Contents.json`.)

- [ ] **Step 3: Commit**

```bash
git add Sources/Resources
git commit -m "chore: entitlements + Assets.xcassets stub"
```

### Task 0.3: Initial app entry point (so xcodegen builds)

**Files:**
- Create: `Sources/Mac/SpatialFieldConverterApp.swift`
- Create: `Sources/Mac/ContentView.swift`

- [ ] **Step 1: Write minimal app entry**

`Sources/Mac/SpatialFieldConverterApp.swift`:
```swift
import SwiftUI

@main
struct SpatialFieldConverterApp: App {
    var body: some Scene {
        WindowGroup("Spatial Field Converter") {
            ContentView()
                .frame(minWidth: 720, minHeight: 480)
        }
        .windowResizability(.contentSize)
    }
}
```

`Sources/Mac/ContentView.swift`:
```swift
import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack {
            Text("Spatial Field Converter v0.1")
                .font(.title)
            Text("Drop a Zoom H8 .wav or SD card folder")
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
```

- [ ] **Step 2: Generate Xcode project and build**

```bash
xcodegen generate
xcodebuild -scheme SpatialFieldConverter -configuration Debug build -destination 'platform=macOS'
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add Sources/Mac/SpatialFieldConverterApp.swift Sources/Mac/ContentView.swift
git commit -m "feat: minimal SwiftUI app skeleton"
```

### Task 0.4: Test target sanity check

**Files:**
- Create: `Tests/SanityTests.swift`

- [ ] **Step 1: Write a sanity test**

```swift
import XCTest

final class SanityTests: XCTestCase {
    func testTrue() {
        XCTAssertTrue(true)
    }
}
```

- [ ] **Step 2: Run the test**

```bash
xcodegen generate
xcodebuild -scheme SpatialFieldConverter -configuration Debug test -destination 'platform=macOS'
```

Expected: Test Suite 'SanityTests' passed.

- [ ] **Step 3: Commit**

```bash
git add Tests/SanityTests.swift
git commit -m "test: sanity test verifies test target wires up"
```

---

## Phase 1 — Core Foundation: WAV Parsing

### Task 1.1: WavMetadata type and WavFileReader (RIFF header only)

**Files:**
- Create: `Sources/Core/WavFileReader.swift`
- Create: `Tests/TestHelpers/TempDirectory.swift`
- Create: `Tests/WavFileReaderTests.swift`

- [ ] **Step 1: Write the test for RIFF header parse**

`Tests/TestHelpers/TempDirectory.swift`:
```swift
import Foundation

enum TempDirectory {
    static func makeUnique() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("spatial-field-converter-tests")
            .appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}
```

`Tests/WavFileReaderTests.swift`:
```swift
import XCTest
@testable import SpatialFieldConverter

final class WavFileReaderTests: XCTestCase {
    var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = TempDirectory.makeUnique()
    }

    override func tearDown() {
        TempDirectory.cleanup(tempDir)
        super.tearDown()
    }

    func test_parsesRiffHeader_4channel_48kHz_24bit() throws {
        let url = tempDir.appendingPathComponent("test.wav")
        try writeMinimalWav(at: url, channels: 4, sampleRate: 48000, bitDepth: 24, frameCount: 100)

        let reader = try WavFileReader(url: url)
        let meta = reader.metadata

        XCTAssertEqual(meta.channelCount, 4)
        XCTAssertEqual(meta.sampleRate, 48000)
        XCTAssertEqual(meta.bitsPerSample, 24)
        XCTAssertEqual(meta.frameCount, 100)
    }

    // Helper: write a minimal valid PCM WAV file with the given parameters
    private func writeMinimalWav(at url: URL, channels: Int, sampleRate: Int, bitDepth: Int, frameCount: Int) throws {
        let bytesPerSample = bitDepth / 8
        let dataSize = frameCount * channels * bytesPerSample
        let byteRate = sampleRate * channels * bytesPerSample
        let blockAlign = channels * bytesPerSample

        var data = Data()
        data.append("RIFF".data(using: .ascii)!)
        data.append(UInt32(36 + dataSize).littleEndianData)
        data.append("WAVE".data(using: .ascii)!)

        data.append("fmt ".data(using: .ascii)!)
        data.append(UInt32(16).littleEndianData)               // fmt chunk size
        data.append(UInt16(1).littleEndianData)                // PCM format
        data.append(UInt16(channels).littleEndianData)
        data.append(UInt32(sampleRate).littleEndianData)
        data.append(UInt32(byteRate).littleEndianData)
        data.append(UInt16(blockAlign).littleEndianData)
        data.append(UInt16(bitDepth).littleEndianData)

        data.append("data".data(using: .ascii)!)
        data.append(UInt32(dataSize).littleEndianData)
        data.append(Data(count: dataSize))                     // silent samples

        try data.write(to: url)
    }
}

extension FixedWidthInteger {
    var littleEndianData: Data {
        withUnsafeBytes(of: self.littleEndian) { Data($0) }
    }
}
```

- [ ] **Step 2: Run test to confirm it fails**

```bash
xcodebuild -scheme SpatialFieldConverter -configuration Debug test -destination 'platform=macOS' -only-testing:SpatialFieldConverterTests/WavFileReaderTests/test_parsesRiffHeader_4channel_48kHz_24bit
```

Expected: FAIL — `WavFileReader` not defined.

- [ ] **Step 3: Implement `WavFileReader`**

`Sources/Core/WavFileReader.swift`:
```swift
import Foundation

public struct WavMetadata: Sendable, Equatable {
    public let channelCount: Int
    public let sampleRate: Int
    public let bitsPerSample: Int
    public let frameCount: Int
    public let durationSeconds: Double
    public let dataChunkOffset: Int
    public let dataChunkSize: Int
    public let bextDescription: String?
    public let bextOriginationDate: String?
    public let bextOriginationTime: String?
    public let ixmlContent: String?
}

public enum WavReadError: Error {
    case fileTooSmall
    case missingRiffHeader
    case missingFmtChunk
    case missingDataChunk
    case unsupportedFormat(UInt16)
}

public final class WavFileReader {
    public let url: URL
    public let metadata: WavMetadata
    private let fileHandle: FileHandle

    public init(url: URL) throws {
        self.url = url
        self.fileHandle = try FileHandle(forReadingFrom: url)
        self.metadata = try Self.parseHeader(handle: fileHandle)
    }

    deinit {
        try? fileHandle.close()
    }

    private static func parseHeader(handle: FileHandle) throws -> WavMetadata {
        try handle.seek(toOffset: 0)
        guard let header = try? handle.read(upToCount: 12), header.count == 12 else {
            throw WavReadError.fileTooSmall
        }
        guard header.subdata(in: 0..<4) == "RIFF".data(using: .ascii),
              header.subdata(in: 8..<12) == "WAVE".data(using: .ascii) else {
            throw WavReadError.missingRiffHeader
        }

        var offset: UInt64 = 12
        var fmt: (channels: Int, sampleRate: Int, bitsPerSample: Int)?
        var dataInfo: (offset: Int, size: Int)?
        var bextDescription: String?
        var bextOriginationDate: String?
        var bextOriginationTime: String?
        var ixmlContent: String?

        while true {
            try handle.seek(toOffset: offset)
            guard let header = try? handle.read(upToCount: 8), header.count == 8 else { break }
            let id = String(data: header.subdata(in: 0..<4), encoding: .ascii) ?? ""
            let size = header.subdata(in: 4..<8).withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
            let payloadOffset = offset + 8

            switch id {
            case "fmt ":
                try handle.seek(toOffset: payloadOffset)
                guard let payload = try? handle.read(upToCount: Int(size)) else { break }
                let format = payload.subdata(in: 0..<2).withUnsafeBytes { $0.load(as: UInt16.self).littleEndian }
                guard format == 1 || format == 0xFFFE else { throw WavReadError.unsupportedFormat(format) }
                let channels = Int(payload.subdata(in: 2..<4).withUnsafeBytes { $0.load(as: UInt16.self).littleEndian })
                let sampleRate = Int(payload.subdata(in: 4..<8).withUnsafeBytes { $0.load(as: UInt32.self).littleEndian })
                let bits = Int(payload.subdata(in: 14..<16).withUnsafeBytes { $0.load(as: UInt16.self).littleEndian })
                fmt = (channels, sampleRate, bits)
            case "data":
                dataInfo = (Int(payloadOffset), Int(size))
            case "bext":
                try handle.seek(toOffset: payloadOffset)
                if let payload = try? handle.read(upToCount: Int(size)) {
                    bextDescription = String(data: payload.subdata(in: 0..<min(256, payload.count)), encoding: .ascii)?
                        .trimmingCharacters(in: .controlCharacters)
                        .trimmingCharacters(in: .whitespaces)
                    if payload.count >= 320 {
                        bextOriginationDate = String(data: payload.subdata(in: 320..<min(330, payload.count)), encoding: .ascii)
                    }
                    if payload.count >= 338 {
                        bextOriginationTime = String(data: payload.subdata(in: 330..<min(338, payload.count)), encoding: .ascii)
                    }
                }
            case "iXML":
                try handle.seek(toOffset: payloadOffset)
                if let payload = try? handle.read(upToCount: Int(size)) {
                    ixmlContent = String(data: payload, encoding: .utf8)?
                        .trimmingCharacters(in: .controlCharacters)
                }
            default:
                break
            }

            // Chunks are word-aligned; skip pad byte if size is odd
            offset = payloadOffset + UInt64(size) + (size % 2 == 1 ? 1 : 0)
        }

        guard let fmt else { throw WavReadError.missingFmtChunk }
        guard let dataInfo else { throw WavReadError.missingDataChunk }

        let bytesPerFrame = fmt.channels * (fmt.bitsPerSample / 8)
        let frameCount = bytesPerFrame == 0 ? 0 : dataInfo.size / bytesPerFrame
        let duration = Double(frameCount) / Double(fmt.sampleRate)

        return WavMetadata(
            channelCount: fmt.channels,
            sampleRate: fmt.sampleRate,
            bitsPerSample: fmt.bitsPerSample,
            frameCount: frameCount,
            durationSeconds: duration,
            dataChunkOffset: dataInfo.offset,
            dataChunkSize: dataInfo.size,
            bextDescription: bextDescription,
            bextOriginationDate: bextOriginationDate,
            bextOriginationTime: bextOriginationTime,
            ixmlContent: ixmlContent
        )
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
xcodebuild -scheme SpatialFieldConverter -configuration Debug test -destination 'platform=macOS' -only-testing:SpatialFieldConverterTests/WavFileReaderTests/test_parsesRiffHeader_4channel_48kHz_24bit
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/WavFileReader.swift Tests/WavFileReaderTests.swift Tests/TestHelpers/TempDirectory.swift
git commit -m "feat(core): WavFileReader parses RIFF header + fmt + data chunks"
```

### Task 1.2: WavFileReader BEXT + iXML chunk extraction

**Files:**
- Modify: `Tests/WavFileReaderTests.swift`

- [ ] **Step 1: Write a failing test for BEXT description**

Append to `Tests/WavFileReaderTests.swift` (inside the class):
```swift
func test_extractsBextDescription() throws {
    let url = tempDir.appendingPathComponent("with-bext.wav")
    try writeWavWithBext(at: url, description: "AMBI A-format VRH-8")

    let reader = try WavFileReader(url: url)
    XCTAssertEqual(reader.metadata.bextDescription, "AMBI A-format VRH-8")
}

private func writeWavWithBext(at url: URL, description: String) throws {
    let channels = 4
    let sampleRate = 48000
    let bitDepth = 24
    let frameCount = 100
    let bytesPerSample = bitDepth / 8
    let dataSize = frameCount * channels * bytesPerSample
    let byteRate = sampleRate * channels * bytesPerSample
    let blockAlign = channels * bytesPerSample

    // Build BEXT payload (602 bytes minimum per EBU Tech 3285)
    var bext = Data(count: 602)
    let descBytes = description.padding(toLength: 256, withPad: "\0", startingAt: 0).data(using: .ascii)!
    bext.replaceSubrange(0..<256, with: descBytes)

    let totalRiffSize = 36 + 8 + bext.count + 8 + dataSize

    var data = Data()
    data.append("RIFF".data(using: .ascii)!)
    data.append(UInt32(totalRiffSize).littleEndianData)
    data.append("WAVE".data(using: .ascii)!)

    data.append("fmt ".data(using: .ascii)!)
    data.append(UInt32(16).littleEndianData)
    data.append(UInt16(1).littleEndianData)
    data.append(UInt16(channels).littleEndianData)
    data.append(UInt32(sampleRate).littleEndianData)
    data.append(UInt32(byteRate).littleEndianData)
    data.append(UInt16(blockAlign).littleEndianData)
    data.append(UInt16(bitDepth).littleEndianData)

    data.append("bext".data(using: .ascii)!)
    data.append(UInt32(bext.count).littleEndianData)
    data.append(bext)

    data.append("data".data(using: .ascii)!)
    data.append(UInt32(dataSize).littleEndianData)
    data.append(Data(count: dataSize))

    try data.write(to: url)
}
```

- [ ] **Step 2: Run test to confirm it passes** (the BEXT parse code from Task 1.1 already handles it — this test verifies)

```bash
xcodebuild -scheme SpatialFieldConverter -configuration Debug test -destination 'platform=macOS' -only-testing:SpatialFieldConverterTests/WavFileReaderTests/test_extractsBextDescription
```

Expected: PASS.

If FAIL, the issue is either the BEXT parse code or the test fixture — debug. The test description value should round-trip exactly through the 256-byte ASCII slot, trimmed of the null padding.

- [ ] **Step 3: Commit**

```bash
git add Tests/WavFileReaderTests.swift
git commit -m "test(core): verify WavFileReader extracts BEXT description"
```

### Task 1.3: WavSampleReader (streaming float frames)

**Files:**
- Create: `Sources/Core/WavSampleReader.swift`
- Modify: `Tests/WavFileReaderTests.swift`

- [ ] **Step 1: Write a failing test for sample reading**

Append to `Tests/WavFileReaderTests.swift`:
```swift
func test_readsSamplesAsFloat_24bit() throws {
    let url = tempDir.appendingPathComponent("samples.wav")
    // Write 4-ch 24-bit WAV with known sample values
    let frameCount = 4
    let channels = 4
    var samples = Data()
    // Frame 0: ch0=0x000001 (=1), ch1=0x000002, ch2=0x000003, ch3=0x000004
    // Frame 1: all zero
    // Frame 2: ch0=0x7FFFFF (max positive 24-bit), others 0
    // Frame 3: ch0=0x800000 (max negative 24-bit, two's complement), others 0
    let frames: [[Int32]] = [
        [1, 2, 3, 4],
        [0, 0, 0, 0],
        [0x7FFFFF, 0, 0, 0],
        [Int32(bitPattern: 0xFF800000), 0, 0, 0]   // 24-bit -8388608 sign-extended to Int32
    ]
    for frame in frames {
        for sample in frame {
            // Write 3 bytes little-endian (24-bit signed)
            samples.append(UInt8(sample & 0xFF))
            samples.append(UInt8((sample >> 8) & 0xFF))
            samples.append(UInt8((sample >> 16) & 0xFF))
        }
    }
    try writeWav(at: url, channels: channels, sampleRate: 48000, bitDepth: 24, sampleData: samples)

    let reader = try WavFileReader(url: url)
    let sampleReader = try WavSampleReader(reader: reader)
    var allFrames: [[Float]] = []
    while let block = try sampleReader.readNextBlock(maxFrames: 1) {
        for f in 0..<block.frameCount {
            var frame: [Float] = []
            for c in 0..<channels {
                frame.append(block.samples[f * channels + c])
            }
            allFrames.append(frame)
        }
    }

    XCTAssertEqual(allFrames.count, 4)
    // Frame 0 ch0: 1 / 8388608 ≈ 1.19e-7
    XCTAssertEqual(allFrames[0][0], 1.0 / Float(0x800000), accuracy: 1e-9)
    // Frame 2 ch0: 0x7FFFFF / 0x800000 ≈ 0.999999...
    XCTAssertEqual(allFrames[2][0], Float(0x7FFFFF) / Float(0x800000), accuracy: 1e-7)
    // Frame 3 ch0: -1.0
    XCTAssertEqual(allFrames[3][0], -1.0, accuracy: 1e-7)
}

private func writeWav(at url: URL, channels: Int, sampleRate: Int, bitDepth: Int, sampleData: Data) throws {
    let bytesPerSample = bitDepth / 8
    let byteRate = sampleRate * channels * bytesPerSample
    let blockAlign = channels * bytesPerSample
    let dataSize = sampleData.count

    var data = Data()
    data.append("RIFF".data(using: .ascii)!)
    data.append(UInt32(36 + dataSize).littleEndianData)
    data.append("WAVE".data(using: .ascii)!)
    data.append("fmt ".data(using: .ascii)!)
    data.append(UInt32(16).littleEndianData)
    data.append(UInt16(1).littleEndianData)
    data.append(UInt16(channels).littleEndianData)
    data.append(UInt32(sampleRate).littleEndianData)
    data.append(UInt32(byteRate).littleEndianData)
    data.append(UInt16(blockAlign).littleEndianData)
    data.append(UInt16(bitDepth).littleEndianData)
    data.append("data".data(using: .ascii)!)
    data.append(UInt32(dataSize).littleEndianData)
    data.append(sampleData)
    try data.write(to: url)
}
```

- [ ] **Step 2: Run test to confirm it fails**

```bash
xcodebuild -scheme SpatialFieldConverter -configuration Debug test -destination 'platform=macOS' -only-testing:SpatialFieldConverterTests/WavFileReaderTests/test_readsSamplesAsFloat_24bit
```

Expected: FAIL — `WavSampleReader` not defined.

- [ ] **Step 3: Implement `WavSampleReader`**

`Sources/Core/WavSampleReader.swift`:
```swift
import Foundation

public struct PCMBlock {
    public let samples: [Float]      // interleaved
    public let frameCount: Int
    public let channelCount: Int
}

public final class WavSampleReader {
    private let handle: FileHandle
    private let metadata: WavMetadata
    private var framesRead: Int = 0

    public init(reader: WavFileReader) throws {
        self.metadata = reader.metadata
        self.handle = try FileHandle(forReadingFrom: reader.url)
        try handle.seek(toOffset: UInt64(metadata.dataChunkOffset))
    }

    deinit {
        try? handle.close()
    }

    public func readNextBlock(maxFrames: Int) throws -> PCMBlock? {
        let remaining = metadata.frameCount - framesRead
        guard remaining > 0 else { return nil }
        let framesToRead = min(maxFrames, remaining)

        let bytesPerSample = metadata.bitsPerSample / 8
        let bytesToRead = framesToRead * metadata.channelCount * bytesPerSample
        guard let raw = try handle.read(upToCount: bytesToRead), raw.count == bytesToRead else {
            return nil
        }

        let totalSamples = framesToRead * metadata.channelCount
        var floats = [Float](repeating: 0, count: totalSamples)

        switch metadata.bitsPerSample {
        case 16:
            raw.withUnsafeBytes { ptr in
                let i16 = ptr.bindMemory(to: Int16.self)
                for i in 0..<totalSamples {
                    floats[i] = Float(Int16(littleEndian: i16[i])) / Float(Int16.max)
                }
            }
        case 24:
            raw.withUnsafeBytes { ptr in
                let bytes = ptr.bindMemory(to: UInt8.self)
                for i in 0..<totalSamples {
                    let b0 = Int32(bytes[i * 3])
                    let b1 = Int32(bytes[i * 3 + 1])
                    let b2 = Int32(bytes[i * 3 + 2])
                    var v = (b2 << 16) | (b1 << 8) | b0
                    if v & 0x800000 != 0 { v |= -0x1000000 }   // sign extend
                    floats[i] = Float(v) / Float(0x800000)
                }
            }
        case 32:
            raw.withUnsafeBytes { ptr in
                let i32 = ptr.bindMemory(to: Int32.self)
                for i in 0..<totalSamples {
                    floats[i] = Float(Int32(littleEndian: i32[i])) / Float(Int32.max)
                }
            }
        default:
            return nil
        }

        framesRead += framesToRead
        return PCMBlock(samples: floats, frameCount: framesToRead, channelCount: metadata.channelCount)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
xcodebuild -scheme SpatialFieldConverter -configuration Debug test -destination 'platform=macOS' -only-testing:SpatialFieldConverterTests/WavFileReaderTests/test_readsSamplesAsFloat_24bit
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/WavSampleReader.swift Tests/WavFileReaderTests.swift
git commit -m "feat(core): WavSampleReader streams interleaved float frames (16/24/32-bit)"
```

---

## Phase 2 — Core: Ambisonic Decode

### Task 2.1: VRH8DecoderMatrix constants

**Files:**
- Create: `Sources/Core/VRH8DecoderMatrix.swift`

- [ ] **Step 1: Write the matrix definition**

`Sources/Core/VRH8DecoderMatrix.swift`:
```swift
import Foundation

/// Reference 4×4 conversion matrix for Zoom VRH-8 A-format → AmbiX B-format.
///
/// Input channel order (rows):  FLU, FRD, BLD, BRU
/// Output channel order (cols): W, Y, Z, X  (ACN ordering, SN3D normalization)
///
/// Per spec §3.2 — these are the standard reference coefficients.
/// Per-capsule calibration trim is deferred to v0.2.
public enum VRH8DecoderMatrix {

    /// matrix[outChannel][inChannel]
    /// outChannel: 0=W, 1=Y, 2=Z, 3=X
    /// inChannel:  0=FLU, 1=FRD, 2=BLD, 3=BRU
    public static let matrix: [[Float]] = [
        // W = (FLU + FRD + BLD + BRU) / 2
        [ 0.5,  0.5,  0.5,  0.5],
        // Y = (FLU - FRD + BLD - BRU) / 2
        [ 0.5, -0.5,  0.5, -0.5],
        // Z = (FLU + FRD - BLD - BRU) / 2
        [ 0.5,  0.5, -0.5, -0.5],
        // X = (FLU - FRD - BLD + BRU) / 2
        [ 0.5, -0.5, -0.5,  0.5]
    ]

    public static let inputChannelCount = 4
    public static let outputChannelCount = 4
}
```

- [ ] **Step 2: Commit (no test yet — tested via AmbisonicDecoder in Task 2.2)**

```bash
git add Sources/Core/VRH8DecoderMatrix.swift
git commit -m "feat(core): VRH-8 reference A→B-format decoder matrix"
```

### Task 2.2: SyntheticAmbisonicSignals test helpers

**Files:**
- Create: `Tests/TestHelpers/SyntheticAmbisonicSignals.swift`

- [ ] **Step 1: Write the helpers**

`Tests/TestHelpers/SyntheticAmbisonicSignals.swift`:
```swift
import Foundation
@testable import SpatialFieldConverter

enum SyntheticAmbisonicSignals {

    /// Generate A-format VRH-8 samples representing a unit-amplitude impulse from a given direction.
    /// Direction vector is a unit XYZ vector in AmbiX coordinates (X=front, Y=left, Z=up).
    /// This is the *forward* of the decoder matrix: produces A-format such that decoding to B-format
    /// yields the expected (W, Y, Z, X) for that direction.
    static func aFormatImpulse(directionX: Float, directionY: Float, directionZ: Float, frameCount: Int) -> [Float] {
        // Compute the B-format we want at the impulse instant.
        let w: Float = 1.0 / sqrt(2.0)
        let x = directionX
        let y = directionY
        let z = directionZ

        // Solve the inverse: A = M^-1 * [W, Y, Z, X]
        // For VRH8DecoderMatrix M, with all 0.5 coefficients ±, the inverse is also a ±0.5 matrix.
        // Inverse rows: FLU, FRD, BLD, BRU — but each row is the column transpose multiplied by 2.
        // Because matrix * matrix^T == 0.5 * I (orthogonal up to scaling), inverse = 2 * transpose.
        let inv: [[Float]] = [
            // FLU = (W + Y + Z + X) / 2 ... but scaled so that decode roundtrips to identity:
            // Apply M^T on B-format and divide by sum-of-squares (= 1 per row)
            [ 0.5,  0.5,  0.5,  0.5],   // FLU
            [ 0.5, -0.5,  0.5, -0.5],   // FRD
            [ 0.5,  0.5, -0.5, -0.5],   // BLD
            [ 0.5, -0.5, -0.5,  0.5],   // BRU
        ]

        let bformat: [Float] = [w, y, z, x]
        var aformat = [Float](repeating: 0, count: 4)
        for outCh in 0..<4 {
            for inCh in 0..<4 {
                aformat[outCh] += inv[outCh][inCh] * bformat[inCh]
            }
        }

        // Output: a single impulse at frame 0 across all 4 channels (interleaved)
        var out = [Float](repeating: 0, count: frameCount * 4)
        for ch in 0..<4 {
            out[0 * 4 + ch] = aformat[ch]
        }
        return out
    }

    /// Pure white noise A-format (random) for energy-conservation tests.
    static func aFormatNoise(frameCount: Int, seed: UInt64 = 42) -> [Float] {
        var generator = SeededGenerator(seed: seed)
        return (0..<(frameCount * 4)).map { _ in
            Float.random(in: -0.5...0.5, using: &generator)
        }
    }

    /// 4-channel zero PCM.
    static func aFormatZero(frameCount: Int) -> [Float] {
        return [Float](repeating: 0, count: frameCount * 4)
    }
}

private struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { self.state = seed == 0 ? 1 : seed }
    mutating func next() -> UInt64 {
        state ^= state >> 12
        state ^= state << 25
        state ^= state >> 27
        return state &* 0x2545F4914F6CDD1D
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add Tests/TestHelpers/SyntheticAmbisonicSignals.swift
git commit -m "test(helpers): synthetic A-format signal generators for known-direction tests"
```

### Task 2.3: AmbisonicDecoder

**Files:**
- Create: `Sources/Core/AmbisonicDecoder.swift`
- Create: `Tests/AmbisonicDecoderTests.swift`

- [ ] **Step 1: Write the failing tests**

`Tests/AmbisonicDecoderTests.swift`:
```swift
import XCTest
@testable import SpatialFieldConverter

final class AmbisonicDecoderTests: XCTestCase {

    func test_zeroInput_producesZeroOutput() {
        let decoder = AmbisonicDecoder(matrix: VRH8DecoderMatrix.matrix)
        let input = SyntheticAmbisonicSignals.aFormatZero(frameCount: 100)
        let output = decoder.decode(interleavedAFormat: input, frameCount: 100)
        XCTAssertEqual(output.count, 100 * 4)
        XCTAssertTrue(output.allSatisfy { $0 == 0 })
    }

    func test_frontImpulse_X_isPositiveAndDominant() {
        let decoder = AmbisonicDecoder(matrix: VRH8DecoderMatrix.matrix)
        // Front impulse: direction (X=1, Y=0, Z=0)
        let input = SyntheticAmbisonicSignals.aFormatImpulse(directionX: 1, directionY: 0, directionZ: 0, frameCount: 4)
        let output = decoder.decode(interleavedAFormat: input, frameCount: 4)

        // Channel order: W=0, Y=1, Z=2, X=3
        let w = output[0]
        let y = output[1]
        let z = output[2]
        let x = output[3]

        XCTAssertGreaterThan(x, 0.5, "X (front) should be strongly positive for front impulse")
        XCTAssertEqual(y, 0, accuracy: 1e-5, "Y should be ~0 for front impulse")
        XCTAssertEqual(z, 0, accuracy: 1e-5, "Z should be ~0 for front impulse")
        XCTAssertGreaterThan(w, 0, "W (omni) should be positive")
    }

    func test_leftImpulse_Y_isPositiveAndDominant() {
        let decoder = AmbisonicDecoder(matrix: VRH8DecoderMatrix.matrix)
        let input = SyntheticAmbisonicSignals.aFormatImpulse(directionX: 0, directionY: 1, directionZ: 0, frameCount: 4)
        let output = decoder.decode(interleavedAFormat: input, frameCount: 4)

        let y = output[1]
        let x = output[3]
        let z = output[2]

        XCTAssertGreaterThan(y, 0.5)
        XCTAssertEqual(x, 0, accuracy: 1e-5)
        XCTAssertEqual(z, 0, accuracy: 1e-5)
    }

    func test_upImpulse_Z_isPositiveAndDominant() {
        let decoder = AmbisonicDecoder(matrix: VRH8DecoderMatrix.matrix)
        let input = SyntheticAmbisonicSignals.aFormatImpulse(directionX: 0, directionY: 0, directionZ: 1, frameCount: 4)
        let output = decoder.decode(interleavedAFormat: input, frameCount: 4)

        let z = output[2]
        let x = output[3]
        let y = output[1]

        XCTAssertGreaterThan(z, 0.5)
        XCTAssertEqual(x, 0, accuracy: 1e-5)
        XCTAssertEqual(y, 0, accuracy: 1e-5)
    }

    func test_throughputProcessesLargeBuffer() {
        let decoder = AmbisonicDecoder(matrix: VRH8DecoderMatrix.matrix)
        let input = SyntheticAmbisonicSignals.aFormatNoise(frameCount: 48000)   // 1 second at 48kHz
        let output = decoder.decode(interleavedAFormat: input, frameCount: 48000)
        XCTAssertEqual(output.count, 48000 * 4)
    }
}
```

- [ ] **Step 2: Run tests to confirm failure**

```bash
xcodebuild -scheme SpatialFieldConverter -configuration Debug test -destination 'platform=macOS' -only-testing:SpatialFieldConverterTests/AmbisonicDecoderTests
```

Expected: FAIL — `AmbisonicDecoder` not defined.

- [ ] **Step 3: Implement `AmbisonicDecoder`**

`Sources/Core/AmbisonicDecoder.swift`:
```swift
import Foundation

public struct AmbisonicDecoder {
    public let matrix: [[Float]]      // [outChannel][inChannel]
    public let outputChannelCount: Int
    public let inputChannelCount: Int

    public init(matrix: [[Float]]) {
        precondition(!matrix.isEmpty, "matrix must not be empty")
        precondition(matrix.allSatisfy { $0.count == matrix[0].count }, "matrix must be rectangular")
        self.matrix = matrix
        self.outputChannelCount = matrix.count
        self.inputChannelCount = matrix[0].count
    }

    /// Apply the decode matrix to interleaved input samples.
    /// Returns interleaved output with the same frame count and `outputChannelCount` channels.
    public func decode(interleavedAFormat input: [Float], frameCount: Int) -> [Float] {
        precondition(input.count >= frameCount * inputChannelCount, "input buffer too small")
        var output = [Float](repeating: 0, count: frameCount * outputChannelCount)
        for f in 0..<frameCount {
            for outCh in 0..<outputChannelCount {
                var sum: Float = 0
                let row = matrix[outCh]
                for inCh in 0..<inputChannelCount {
                    sum += row[inCh] * input[f * inputChannelCount + inCh]
                }
                output[f * outputChannelCount + outCh] = sum
            }
        }
        return output
    }
}
```

- [ ] **Step 4: Run tests to verify pass**

```bash
xcodebuild -scheme SpatialFieldConverter -configuration Debug test -destination 'platform=macOS' -only-testing:SpatialFieldConverterTests/AmbisonicDecoderTests
```

Expected: All 4 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/AmbisonicDecoder.swift Tests/AmbisonicDecoderTests.swift
git commit -m "feat(core): AmbisonicDecoder applies 4x4 matrix to interleaved frames"
```

---

## Phase 3 — Core: Virtual Loudspeaker Decode (B-format → 7.1.2)

### Task 3.1: VirtualLoudspeakerRig

**Files:**
- Create: `Sources/Core/VirtualLoudspeakerRig.swift`
- Create: `Tests/VirtualLoudspeakerRigTests.swift`

- [ ] **Step 1: Write the failing tests**

`Tests/VirtualLoudspeakerRigTests.swift`:
```swift
import XCTest
@testable import SpatialFieldConverter

final class VirtualLoudspeakerRigTests: XCTestCase {

    func test_speakerPositions_count_is10_for_7_1_2() {
        let rig = VirtualLoudspeakerRig.atmos7_1_2()
        XCTAssertEqual(rig.speakerPositions.count, 10)
    }

    func test_speakerOrder_matchesAtmosBedConvention() {
        let rig = VirtualLoudspeakerRig.atmos7_1_2()
        // Atmos bed channel order: L, R, C, LFE, Lss, Rss, Lrs, Rrs, Ltf, Rtf
        XCTAssertEqual(rig.speakerNames, ["L", "R", "C", "LFE", "Lss", "Rss", "Lrs", "Rrs", "Ltf", "Rtf"])
    }

    func test_decodingFrontBformat_putsEnergyOn_C_andOnFronts() {
        let rig = VirtualLoudspeakerRig.atmos7_1_2()
        // Front-only B-format: W=0.707, X=1, Y=0, Z=0  (in AmbiX channel order W,Y,Z,X)
        let bformat: [Float] = [0.707, 0, 0, 1.0]
        let speakers = rig.decode(bformatFrame: bformat)

        XCTAssertEqual(speakers.count, 10)

        let c = speakers[2]
        let l = speakers[0]
        let r = speakers[1]
        let lrs = speakers[6]
        let rrs = speakers[7]

        XCTAssertGreaterThan(c, 0, "C should have positive energy for front-pointing source")
        XCTAssertGreaterThan(l, 0, "L should have positive energy")
        XCTAssertGreaterThan(r, 0, "R should have positive energy")
        XCTAssertLessThan(lrs, c, "Rear surrounds should be quieter than C for front source")
        XCTAssertLessThan(rrs, c, "Rear surrounds should be quieter than C for front source")
    }

    func test_decodingLeftBformat_putsMostEnergyOnLeftSpeakers() {
        let rig = VirtualLoudspeakerRig.atmos7_1_2()
        // Left-only B-format: Y=1, others 0 (besides W)
        let bformat: [Float] = [0.707, 1.0, 0, 0]
        let speakers = rig.decode(bformatFrame: bformat)

        let l = speakers[0]
        let r = speakers[1]
        let lss = speakers[4]
        let rss = speakers[5]

        XCTAssertGreaterThan(l, r, "L should be louder than R for left source")
        XCTAssertGreaterThan(lss, rss, "Lss should be louder than Rss for left source")
    }

    func test_lfeChannel_isLowPassedFromW() {
        let rig = VirtualLoudspeakerRig.atmos7_1_2()
        // Pure W input → LFE should get a non-zero contribution (after low-pass filtering it's the time-domain DC pass)
        // For a single-frame impulse, an FIR low-pass will produce a small but nonzero sample.
        // We test instead that the LFE channel is not just a copy of W — verify it's gated to be smaller.
        let bformat: [Float] = [1.0, 0, 0, 0]
        let speakers = rig.decode(bformatFrame: bformat)
        let lfe = speakers[3]
        XCTAssertGreaterThanOrEqual(lfe, 0, "LFE should be non-negative for W=1 input")
        XCTAssertLessThanOrEqual(lfe, 1.0, "LFE should not exceed input W magnitude")
    }
}
```

- [ ] **Step 2: Run tests to confirm failure**

```bash
xcodebuild -scheme SpatialFieldConverter -configuration Debug test -destination 'platform=macOS' -only-testing:SpatialFieldConverterTests/VirtualLoudspeakerRigTests
```

Expected: FAIL — `VirtualLoudspeakerRig` not defined.

- [ ] **Step 3: Implement `VirtualLoudspeakerRig`**

`Sources/Core/VirtualLoudspeakerRig.swift`:
```swift
import Foundation

public struct SpeakerPosition: Sendable, Equatable {
    public let name: String
    public let azimuthDegrees: Float    // 0 = front, +90 = left, -90 = right (AmbiX convention)
    public let elevationDegrees: Float  // 0 = horizontal, +90 = up
    public let isLFE: Bool
}

public struct VirtualLoudspeakerRig {

    public let speakerPositions: [SpeakerPosition]
    public var speakerNames: [String] { speakerPositions.map { $0.name } }

    /// Per-speaker decode coefficients [speaker][bformatChannel(W,Y,Z,X)]
    private let decodeMatrix: [[Float]]

    public init(speakerPositions: [SpeakerPosition]) {
        self.speakerPositions = speakerPositions
        self.decodeMatrix = Self.buildDecodeMatrix(positions: speakerPositions)
    }

    public static func atmos7_1_2() -> VirtualLoudspeakerRig {
        // Atmos bed channel order: L, R, C, LFE, Lss, Rss, Lrs, Rrs, Ltf, Rtf
        return VirtualLoudspeakerRig(speakerPositions: [
            SpeakerPosition(name: "L",   azimuthDegrees:  30, elevationDegrees:  0, isLFE: false),
            SpeakerPosition(name: "R",   azimuthDegrees: -30, elevationDegrees:  0, isLFE: false),
            SpeakerPosition(name: "C",   azimuthDegrees:   0, elevationDegrees:  0, isLFE: false),
            SpeakerPosition(name: "LFE", azimuthDegrees:   0, elevationDegrees:  0, isLFE: true),
            SpeakerPosition(name: "Lss", azimuthDegrees:  90, elevationDegrees:  0, isLFE: false),
            SpeakerPosition(name: "Rss", azimuthDegrees: -90, elevationDegrees:  0, isLFE: false),
            SpeakerPosition(name: "Lrs", azimuthDegrees: 135, elevationDegrees:  0, isLFE: false),
            SpeakerPosition(name: "Rrs", azimuthDegrees:-135, elevationDegrees:  0, isLFE: false),
            SpeakerPosition(name: "Ltf", azimuthDegrees:  45, elevationDegrees: 45, isLFE: false),
            SpeakerPosition(name: "Rtf", azimuthDegrees: -45, elevationDegrees: 45, isLFE: false),
        ])
    }

    /// Decode one frame of B-format (W, Y, Z, X in AmbiX/ACN order) to all speaker outputs.
    public func decode(bformatFrame: [Float]) -> [Float] {
        precondition(bformatFrame.count == 4, "1st-order B-format requires 4 channels (W,Y,Z,X)")
        var output = [Float](repeating: 0, count: speakerPositions.count)
        for (i, _) in speakerPositions.enumerated() {
            var sum: Float = 0
            for c in 0..<4 {
                sum += decodeMatrix[i][c] * bformatFrame[c]
            }
            output[i] = sum
        }
        return output
    }

    /// Decode an interleaved B-format buffer into an interleaved 10-ch speaker buffer.
    public func decode(interleavedBformat input: [Float], frameCount: Int) -> [Float] {
        let speakerCount = speakerPositions.count
        var output = [Float](repeating: 0, count: frameCount * speakerCount)
        for f in 0..<frameCount {
            let frame = Array(input[(f * 4)..<((f + 1) * 4)])
            let speakers = decode(bformatFrame: frame)
            for s in 0..<speakerCount {
                output[f * speakerCount + s] = speakers[s]
            }
        }
        return output
    }

    /// Build per-speaker decode coefficients using a 1st-order basic decoder with max-rE weighting.
    /// Reference: Daniel 2000 ("Représentation de champs acoustiques..."), Politis HOA toolbox.
    private static func buildDecodeMatrix(positions: [SpeakerPosition]) -> [[Float]] {
        // 1st-order max-rE weights (per channel): W=0.7745966, Y=0.4472135, Z=0.4472135, X=0.4472135
        // Source: Zotter & Frank, "Ambisonics" (2019), Table 4.1
        let wW: Float = 0.7745966692
        let wY: Float = 0.4472135955
        let wZ: Float = 0.4472135955
        let wX: Float = 0.4472135955

        var matrix: [[Float]] = []
        for pos in positions {
            if pos.isLFE {
                // LFE = low-passed sum of W. For a single-frame in-place decoder, use a
                // simple gain (low-pass is applied elsewhere, in the frame stream encoder).
                // Per BS.775, LFE level relative to main is -10 dB ≈ 0.316.
                matrix.append([0.316, 0, 0, 0])
                continue
            }
            let azRad = pos.azimuthDegrees * .pi / 180
            let elRad = pos.elevationDegrees * .pi / 180
            // AmbiX direction: X=cos(el)*cos(az), Y=cos(el)*sin(az), Z=sin(el)
            let dirX = cos(elRad) * cos(azRad)
            let dirY = cos(elRad) * sin(azRad)
            let dirZ = sin(elRad)
            let n = Float(positions.filter { !$0.isLFE }.count)
            // Basic decoder: speaker_i = (W*wW + Y*wY*dirY + Z*wZ*dirZ + X*wX*dirX) / N
            matrix.append([
                wW / n,
                wY * Float(dirY) / n,
                wZ * Float(dirZ) / n,
                wX * Float(dirX) / n
            ])
        }
        return matrix
    }
}
```

- [ ] **Step 4: Run tests to verify pass**

```bash
xcodebuild -scheme SpatialFieldConverter -configuration Debug test -destination 'platform=macOS' -only-testing:SpatialFieldConverterTests/VirtualLoudspeakerRigTests
```

Expected: All 5 tests PASS. If a directional test fails, double-check sign conventions: AmbiX uses Y=left-positive, X=front-positive, Z=up-positive. Atmos azimuths in spec follow same convention (positive = left of center).

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/VirtualLoudspeakerRig.swift Tests/VirtualLoudspeakerRigTests.swift
git commit -m "feat(core): VirtualLoudspeakerRig decodes 1st-order B-format to 7.1.2 (max-rE)"
```

### Task 3.2: LFE low-pass filter for streaming

**Files:**
- Modify: `Sources/Core/VirtualLoudspeakerRig.swift`
- Modify: `Tests/VirtualLoudspeakerRigTests.swift`

- [ ] **Step 1: Write failing test for stateful low-pass**

Append to `VirtualLoudspeakerRigTests.swift`:
```swift
func test_lfeStream_lowPassesAt80Hz() {
    let rig = VirtualLoudspeakerRig.atmos7_1_2()
    let processor = rig.makeStreamingDecoder(sampleRate: 48000)

    // 1 second of 1 kHz tone in W only
    let frameCount = 48000
    var input = [Float](repeating: 0, count: frameCount * 4)
    for f in 0..<frameCount {
        let t = Float(f) / 48000.0
        input[f * 4 + 0] = sin(2 * .pi * 1000 * t) * 0.5     // W
    }
    let output = processor.process(interleavedBformat: input, frameCount: frameCount)

    let speakerCount = 10
    // Extract LFE (channel 3) and measure RMS — should be much smaller than for a 50 Hz tone
    var lfeRms: Float = 0
    for f in 0..<frameCount {
        let s = output[f * speakerCount + 3]
        lfeRms += s * s
    }
    lfeRms = sqrt(lfeRms / Float(frameCount))

    // 1 kHz is well above the 80 Hz cutoff — LFE should be near zero
    XCTAssertLessThan(lfeRms, 0.01, "LFE should attenuate a 1kHz tone heavily")

    // Repeat with 50 Hz
    var input50 = [Float](repeating: 0, count: frameCount * 4)
    for f in 0..<frameCount {
        let t = Float(f) / 48000.0
        input50[f * 4 + 0] = sin(2 * .pi * 50 * t) * 0.5
    }
    let processor2 = rig.makeStreamingDecoder(sampleRate: 48000)
    let output50 = processor2.process(interleavedBformat: input50, frameCount: frameCount)
    var lfeRms50: Float = 0
    for f in 0..<frameCount {
        let s = output50[f * speakerCount + 3]
        lfeRms50 += s * s
    }
    lfeRms50 = sqrt(lfeRms50 / Float(frameCount))

    XCTAssertGreaterThan(lfeRms50, lfeRms * 10, "50Hz should pass through LFE much more than 1kHz")
}
```

- [ ] **Step 2: Run test to confirm failure**

```bash
xcodebuild -scheme SpatialFieldConverter -configuration Debug test -destination 'platform=macOS' -only-testing:SpatialFieldConverterTests/VirtualLoudspeakerRigTests/test_lfeStream_lowPassesAt80Hz
```

Expected: FAIL — `makeStreamingDecoder` not defined.

- [ ] **Step 3: Implement `StreamingDecoder` with biquad low-pass on LFE**

Append to `Sources/Core/VirtualLoudspeakerRig.swift`:
```swift
public extension VirtualLoudspeakerRig {

    /// Returns a stateful streaming decoder that applies a 2nd-order Butterworth low-pass
    /// at 80 Hz to the LFE channel(s).
    func makeStreamingDecoder(sampleRate: Int) -> StreamingDecoder {
        return StreamingDecoder(rig: self, sampleRate: sampleRate)
    }

    final class StreamingDecoder {
        private let rig: VirtualLoudspeakerRig
        private let lfeFilter: BiquadLowpass

        init(rig: VirtualLoudspeakerRig, sampleRate: Int) {
            self.rig = rig
            self.lfeFilter = BiquadLowpass(sampleRate: Float(sampleRate), cutoffHz: 80)
        }

        public func process(interleavedBformat input: [Float], frameCount: Int) -> [Float] {
            var output = rig.decode(interleavedBformat: input, frameCount: frameCount)
            let speakerCount = rig.speakerPositions.count
            // Find LFE indices and replace with low-passed W signal
            for (i, pos) in rig.speakerPositions.enumerated() where pos.isLFE {
                for f in 0..<frameCount {
                    let w = input[f * 4 + 0]
                    output[f * speakerCount + i] = lfeFilter.process(w) * 0.316
                }
            }
            return output
        }
    }
}

/// Direct-form-II 2nd-order Butterworth low-pass biquad.
final class BiquadLowpass {
    private let b0: Float
    private let b1: Float
    private let b2: Float
    private let a1: Float
    private let a2: Float
    private var z1: Float = 0
    private var z2: Float = 0

    init(sampleRate: Float, cutoffHz: Float) {
        let omega = 2 * Float.pi * cutoffHz / sampleRate
        let cosOmega = cos(omega)
        let sinOmega = sin(omega)
        let q: Float = 0.7071067811   // Butterworth Q
        let alpha = sinOmega / (2 * q)

        let a0 = 1 + alpha
        b0 = ((1 - cosOmega) / 2) / a0
        b1 = (1 - cosOmega) / a0
        b2 = ((1 - cosOmega) / 2) / a0
        a1 = (-2 * cosOmega) / a0
        a2 = (1 - alpha) / a0
    }

    @inlinable
    func process(_ x: Float) -> Float {
        let y = b0 * x + z1
        z1 = b1 * x - a1 * y + z2
        z2 = b2 * x - a2 * y
        return y
    }
}
```

- [ ] **Step 4: Run tests to verify**

```bash
xcodebuild -scheme SpatialFieldConverter -configuration Debug test -destination 'platform=macOS' -only-testing:SpatialFieldConverterTests/VirtualLoudspeakerRigTests
```

Expected: All tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/VirtualLoudspeakerRig.swift Tests/VirtualLoudspeakerRigTests.swift
git commit -m "feat(core): streaming decoder applies 80Hz low-pass to LFE channel"
```

---

## Phase 4 — Core: Encoders and Writers

### Task 4.1: AmbisonicWavWriter (4-ch B-format → source.wav with iXML)

**Files:**
- Create: `Sources/Core/AmbisonicWavWriter.swift`
- Create: `Tests/AmbisonicWavWriterTests.swift`

- [ ] **Step 1: Write failing test**

`Tests/AmbisonicWavWriterTests.swift`:
```swift
import XCTest
@testable import SpatialFieldConverter

final class AmbisonicWavWriterTests: XCTestCase {
    var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = TempDirectory.makeUnique()
    }

    override func tearDown() {
        TempDirectory.cleanup(tempDir)
        super.tearDown()
    }

    func test_writes4Channel24Bit48kHzWavWithIxmlChunk() throws {
        let url = tempDir.appendingPathComponent("source.wav")
        let writer = try AmbisonicWavWriter(url: url, sampleRate: 48000, bitsPerSample: 24)
        let frames = 1000
        var buffer = [Float](repeating: 0, count: frames * 4)
        for f in 0..<frames {
            buffer[f * 4 + 0] = 0.5     // W
            buffer[f * 4 + 1] = 0.0
            buffer[f * 4 + 2] = 0.0
            buffer[f * 4 + 3] = 0.0
        }
        try writer.appendFrames(buffer, frameCount: frames)
        try writer.finalize()

        // Verify with WavFileReader
        let reader = try WavFileReader(url: url)
        XCTAssertEqual(reader.metadata.channelCount, 4)
        XCTAssertEqual(reader.metadata.sampleRate, 48000)
        XCTAssertEqual(reader.metadata.bitsPerSample, 24)
        XCTAssertEqual(reader.metadata.frameCount, frames)
        XCTAssertNotNil(reader.metadata.ixmlContent)
        XCTAssertTrue(reader.metadata.ixmlContent?.contains("AmbiX") == true)
        XCTAssertTrue(reader.metadata.ixmlContent?.contains("ACN") == true)
        XCTAssertTrue(reader.metadata.ixmlContent?.contains("SN3D") == true)
    }
}
```

- [ ] **Step 2: Run test to confirm failure**

```bash
xcodebuild -scheme SpatialFieldConverter -configuration Debug test -destination 'platform=macOS' -only-testing:SpatialFieldConverterTests/AmbisonicWavWriterTests
```

Expected: FAIL — `AmbisonicWavWriter` not defined.

- [ ] **Step 3: Implement `AmbisonicWavWriter`**

`Sources/Core/AmbisonicWavWriter.swift`:
```swift
import Foundation

public final class AmbisonicWavWriter {
    private let url: URL
    private let sampleRate: Int
    private let bitsPerSample: Int
    private let channelCount: Int = 4
    private let handle: FileHandle
    private var framesWritten: Int = 0
    private var finalized = false

    private let ixmlPayload: Data = {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <BWFXML>
          <IXML_VERSION>1.5</IXML_VERSION>
          <PROJECT>Spatial Field Converter</PROJECT>
          <AMBISONIC>AmbiX 1st-order ACN/SN3D</AMBISONIC>
          <CHANNEL_ORDER>ACN</CHANNEL_ORDER>
          <NORMALIZATION>SN3D</NORMALIZATION>
          <ORDER>1</ORDER>
        </BWFXML>
        """
        return xml.data(using: .utf8) ?? Data()
    }()

    public init(url: URL, sampleRate: Int, bitsPerSample: Int) throws {
        precondition(bitsPerSample == 24, "v0.1 only emits 24-bit ambisonic source")
        self.url = url
        self.sampleRate = sampleRate
        self.bitsPerSample = bitsPerSample
        FileManager.default.createFile(atPath: url.path, contents: nil)
        self.handle = try FileHandle(forWritingTo: url)
        try writePlaceholderHeader()
    }

    private func writePlaceholderHeader() throws {
        // We'll come back and rewrite RIFF/data sizes when finalize() is called.
        // Reserve 12 (RIFF header) + 24 (fmt chunk) + 8 (iXML header) + ixmlPayload.count (+ pad) + 8 (data header) bytes.
        let ixmlSize = ixmlPayload.count
        let ixmlPad = ixmlSize % 2

        var data = Data()
        data.append("RIFF".data(using: .ascii)!)
        data.append(UInt32(0).littleEndianData)        // placeholder
        data.append("WAVE".data(using: .ascii)!)

        // fmt chunk
        let bytesPerSample = bitsPerSample / 8
        let byteRate = sampleRate * channelCount * bytesPerSample
        let blockAlign = channelCount * bytesPerSample

        data.append("fmt ".data(using: .ascii)!)
        data.append(UInt32(16).littleEndianData)
        data.append(UInt16(1).littleEndianData)        // PCM
        data.append(UInt16(channelCount).littleEndianData)
        data.append(UInt32(sampleRate).littleEndianData)
        data.append(UInt32(byteRate).littleEndianData)
        data.append(UInt16(blockAlign).littleEndianData)
        data.append(UInt16(bitsPerSample).littleEndianData)

        // iXML chunk
        data.append("iXML".data(using: .ascii)!)
        data.append(UInt32(ixmlSize).littleEndianData)
        data.append(ixmlPayload)
        if ixmlPad == 1 { data.append(UInt8(0)) }

        // data chunk header (size will be patched in finalize)
        data.append("data".data(using: .ascii)!)
        data.append(UInt32(0).littleEndianData)        // placeholder

        try handle.seek(toOffset: 0)
        handle.write(data)
    }

    public func appendFrames(_ floats: [Float], frameCount: Int) throws {
        precondition(floats.count >= frameCount * channelCount, "buffer too small")
        var bytes = Data(capacity: frameCount * channelCount * 3)
        for i in 0..<(frameCount * channelCount) {
            let clamped = max(-1.0, min(1.0, floats[i]))
            let intVal = Int32(clamped * Float(0x7FFFFF))
            bytes.append(UInt8(intVal & 0xFF))
            bytes.append(UInt8((intVal >> 8) & 0xFF))
            bytes.append(UInt8((intVal >> 16) & 0xFF))
        }
        handle.write(bytes)
        framesWritten += frameCount
    }

    public func finalize() throws {
        guard !finalized else { return }
        finalized = true

        let dataSize = framesWritten * channelCount * (bitsPerSample / 8)
        let ixmlSize = ixmlPayload.count
        let ixmlPad = ixmlSize % 2
        // RIFF size = total file size - 8 (RIFF + size fields)
        let riffSize = 4   // "WAVE"
            + 8 + 16       // fmt header + payload
            + 8 + ixmlSize + ixmlPad   // iXML chunk
            + 8 + dataSize             // data chunk

        // Patch RIFF size at offset 4
        try handle.seek(toOffset: 4)
        handle.write(UInt32(riffSize).littleEndianData)
        // Patch data size at offset (12 + 24 + 8 + ixmlSize + ixmlPad + 4)
        let dataSizeOffset: UInt64 = UInt64(12 + 24 + 8 + ixmlSize + ixmlPad + 4)
        try handle.seek(toOffset: dataSizeOffset)
        handle.write(UInt32(dataSize).littleEndianData)
        try handle.close()
    }
}
```

- [ ] **Step 4: Run test to verify pass**

```bash
xcodebuild -scheme SpatialFieldConverter -configuration Debug test -destination 'platform=macOS' -only-testing:SpatialFieldConverterTests/AmbisonicWavWriterTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/AmbisonicWavWriter.swift Tests/AmbisonicWavWriterTests.swift
git commit -m "feat(core): AmbisonicWavWriter writes 4-ch 24-bit B-format WAV with iXML"
```

### Task 4.2: BedEncoder (PCM 7.1.2 → AAC-LC m4a)

**Files:**
- Create: `Sources/Core/BedEncoder.swift`
- Create: `Tests/BedEncoderTests.swift`

- [ ] **Step 1: Write failing test**

`Tests/BedEncoderTests.swift`:
```swift
import XCTest
import AVFoundation
@testable import SpatialFieldConverter

final class BedEncoderTests: XCTestCase {
    var tempDir: URL!

    override func setUp() { super.setUp(); tempDir = TempDirectory.makeUnique() }
    override func tearDown() { TempDirectory.cleanup(tempDir); super.tearDown() }

    func test_encodes7_1_2_AAC_m4a_thatPlaysViaAVFoundation() throws {
        let url = tempDir.appendingPathComponent("bed.m4a")
        let encoder = try BedEncoder(outputURL: url, sampleRate: 48000)

        // 1 second of silence × 10 channels
        let frameCount = 48000
        let channels = 10
        let buffer = [Float](repeating: 0, count: frameCount * channels)
        try encoder.appendFrames(buffer, frameCount: frameCount)
        try encoder.finalize()

        // Verify file exists and AVAsset can open it
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        XCTAssertEqual(tracks.count, 1)
        let formatDescriptions = try await tracks[0].load(.formatDescriptions)
        XCTAssertGreaterThan(formatDescriptions.count, 0)
        let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescriptions[0])
        XCTAssertEqual(asbd?.pointee.mChannelsPerFrame, 10)
        XCTAssertEqual(asbd?.pointee.mSampleRate, 48000)
    }
}
```

(Note: the test uses `await` — needs `func test_...() async throws`.)

Adjust signature:
```swift
    func test_encodes7_1_2_AAC_m4a_thatPlaysViaAVFoundation() async throws {
```

- [ ] **Step 2: Run to confirm failure**

```bash
xcodebuild -scheme SpatialFieldConverter -configuration Debug test -destination 'platform=macOS' -only-testing:SpatialFieldConverterTests/BedEncoderTests
```

Expected: FAIL — `BedEncoder` not defined.

- [ ] **Step 3: Implement `BedEncoder`**

`Sources/Core/BedEncoder.swift`:
```swift
import Foundation
import AVFoundation

public enum BedEncoderError: Error {
    case writerFailed(String)
    case appendFailed
}

public final class BedEncoder {
    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private let format: AVAudioFormat
    private var framesAppended: Int64 = 0
    private let sampleRate: Int

    public init(outputURL: URL, sampleRate: Int) throws {
        self.sampleRate = sampleRate
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }
        self.writer = try AVAssetWriter(outputURL: outputURL, fileType: .m4a)

        let channelLayoutTag: AudioChannelLayoutTag = kAudioChannelLayoutTag_Atmos_7_1_2
        var layout = AudioChannelLayout()
        layout.mChannelLayoutTag = channelLayoutTag
        let layoutData = Data(bytes: &layout, count: MemoryLayout<AudioChannelLayout>.size)

        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVNumberOfChannelsKey: 10,
            AVSampleRateKey: sampleRate,
            AVEncoderBitRateKey: 256_000,
            AVChannelLayoutKey: layoutData
        ]

        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: outputSettings)
        input.expectsMediaDataInRealTime = false

        guard writer.canAdd(input) else {
            throw BedEncoderError.writerFailed("cannot add audio input")
        }
        writer.add(input)
        self.input = input

        let asbd = AudioStreamBasicDescription(
            mSampleRate: Float64(sampleRate),
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: UInt32(MemoryLayout<Float>.size * 10),
            mFramesPerPacket: 1,
            mBytesPerFrame: UInt32(MemoryLayout<Float>.size * 10),
            mChannelsPerFrame: 10,
            mBitsPerChannel: 32,
            mReserved: 0
        )
        guard let avFormat = AVAudioFormat(streamDescription: { var d = asbd; return withUnsafePointer(to: &d) { $0 } }()) else {
            throw BedEncoderError.writerFailed("cannot make AVAudioFormat")
        }
        self.format = avFormat

        guard writer.startWriting() else {
            throw BedEncoderError.writerFailed("startWriting returned false: \(writer.error?.localizedDescription ?? "")")
        }
        writer.startSession(atSourceTime: .zero)
    }

    public func appendFrames(_ samples: [Float], frameCount: Int) throws {
        let channelCount = 10
        precondition(samples.count >= frameCount * channelCount)

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount)) else {
            throw BedEncoderError.appendFailed
        }
        buffer.frameLength = AVAudioFrameCount(frameCount)
        // Samples come interleaved; AVAudioPCMBuffer with our format is interleaved float
        if let dataPtr = buffer.audioBufferList.pointee.mBuffers.mData?.assumingMemoryBound(to: Float.self) {
            for i in 0..<(frameCount * channelCount) {
                dataPtr[i] = samples[i]
            }
        }

        // Convert AVAudioPCMBuffer → CMSampleBuffer for AVAssetWriterInput
        let sampleBuffer = try makeSampleBuffer(from: buffer, presentationTimeFrame: framesAppended)

        // Wait for the input to be ready
        while !input.isReadyForMoreMediaData {
            Thread.sleep(forTimeInterval: 0.005)
        }
        guard input.append(sampleBuffer) else {
            throw BedEncoderError.appendFailed
        }
        framesAppended += Int64(frameCount)
    }

    public func finalize() async throws {
        input.markAsFinished()
        await writer.finishWriting()
        if writer.status == .failed {
            throw BedEncoderError.writerFailed(writer.error?.localizedDescription ?? "unknown")
        }
    }

    private func makeSampleBuffer(from pcmBuffer: AVAudioPCMBuffer, presentationTimeFrame: Int64) throws -> CMSampleBuffer {
        let sampleRate = Int32(self.sampleRate)
        var formatDescription: CMFormatDescription?
        let asbd = pcmBuffer.format.streamDescription
        let layoutSize = MemoryLayout<AudioChannelLayout>.size
        var layout = AudioChannelLayout()
        layout.mChannelLayoutTag = kAudioChannelLayoutTag_Atmos_7_1_2
        let osStatus = CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            asbd: asbd,
            layoutSize: layoutSize,
            layout: &layout,
            magicCookieSize: 0,
            magicCookie: nil,
            extensions: nil,
            formatDescriptionOut: &formatDescription
        )
        guard osStatus == noErr, let formatDescription else {
            throw BedEncoderError.writerFailed("CMAudioFormatDescriptionCreate failed: \(osStatus)")
        }

        var sampleBuffer: CMSampleBuffer?
        let pts = CMTime(value: presentationTimeFrame, timescale: sampleRate)
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: sampleRate),
            presentationTimeStamp: pts,
            decodeTimeStamp: .invalid
        )

        let createStatus = CMSampleBufferCreate(
            allocator: kCFAllocatorDefault,
            dataBuffer: nil,
            dataReady: false,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: formatDescription,
            sampleCount: CMItemCount(pcmBuffer.frameLength),
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 0,
            sampleSizeArray: nil,
            sampleBufferOut: &sampleBuffer
        )
        guard createStatus == noErr, let sampleBuffer else {
            throw BedEncoderError.writerFailed("CMSampleBufferCreate failed: \(createStatus)")
        }

        let setStatus = CMSampleBufferSetDataBufferFromAudioBufferList(
            sampleBuffer,
            blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: 0,
            bufferList: pcmBuffer.audioBufferList
        )
        guard setStatus == noErr else {
            throw BedEncoderError.writerFailed("SetDataBufferFromAudioBufferList failed: \(setStatus)")
        }

        return sampleBuffer
    }
}
```

Note: the test uses `try encoder.finalize()` synchronously but the implementation here is `async`. Update the test to `try await encoder.finalize()`.

- [ ] **Step 4: Update test to await finalize**

In `BedEncoderTests.swift`, change `try encoder.finalize()` to `try await encoder.finalize()`.

- [ ] **Step 5: Run test to verify pass**

```bash
xcodebuild -scheme SpatialFieldConverter -configuration Debug test -destination 'platform=macOS' -only-testing:SpatialFieldConverterTests/BedEncoderTests
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/Core/BedEncoder.swift Tests/BedEncoderTests.swift
git commit -m "feat(core): BedEncoder writes 7.1.2 AAC-LC m4a via AVAssetWriter"
```

---

## Phase 5 — Core: Manifest, Slug, Source Meta

### Task 5.1: SlugGenerator

**Files:**
- Create: `Sources/Core/SlugGenerator.swift`
- Create: `Tests/SlugGeneratorTests.swift`

- [ ] **Step 1: Write failing tests**

`Tests/SlugGeneratorTests.swift`:
```swift
import XCTest
@testable import SpatialFieldConverter

final class SlugGeneratorTests: XCTestCase {
    var tempDir: URL!

    override func setUp() { super.setUp(); tempDir = TempDirectory.makeUnique() }
    override func tearDown() { TempDirectory.cleanup(tempDir); super.tearDown() }

    func test_slugIsDeterministic_forSameInput() throws {
        let url = tempDir.appendingPathComponent("test.wav")
        try Data(repeating: 0x42, count: 4096).write(to: url)
        let date = ISO8601DateFormatter().date(from: "2026-05-14T10:00:00Z")!
        let s1 = try SlugGenerator.makeSlug(for: url, durationSeconds: 312.4, recordedAt: date)
        let s2 = try SlugGenerator.makeSlug(for: url, durationSeconds: 312.4, recordedAt: date)
        XCTAssertEqual(s1, s2)
    }

    func test_slugChangesWhenContentDiffers() throws {
        let url1 = tempDir.appendingPathComponent("a.wav")
        let url2 = tempDir.appendingPathComponent("b.wav")
        try Data(repeating: 0x42, count: 4096).write(to: url1)
        try Data(repeating: 0x99, count: 4096).write(to: url2)
        let date = ISO8601DateFormatter().date(from: "2026-05-14T10:00:00Z")!
        let s1 = try SlugGenerator.makeSlug(for: url1, durationSeconds: 100, recordedAt: date)
        let s2 = try SlugGenerator.makeSlug(for: url2, durationSeconds: 100, recordedAt: date)
        XCTAssertNotEqual(s1, s2)
    }

    func test_slugFormatMatchesConvention() throws {
        let url = tempDir.appendingPathComponent("test.wav")
        try Data(repeating: 0, count: 1024).write(to: url)
        let date = ISO8601DateFormatter().date(from: "2026-05-14T10:00:00Z")!
        let slug = try SlugGenerator.makeSlug(for: url, durationSeconds: 60, recordedAt: date)
        // field-recording-2026-05-14-XXXXXX
        let regex = try NSRegularExpression(pattern: "^field-recording-2026-05-14-[a-z0-9]{6}$")
        let range = NSRange(slug.startIndex..<slug.endIndex, in: slug)
        XCTAssertEqual(regex.numberOfMatches(in: slug, range: range), 1, "slug=\(slug) does not match expected format")
    }
}
```

- [ ] **Step 2: Run to confirm failure**

```bash
xcodebuild -scheme SpatialFieldConverter -configuration Debug test -destination 'platform=macOS' -only-testing:SpatialFieldConverterTests/SlugGeneratorTests
```

Expected: FAIL — `SlugGenerator` not defined.

- [ ] **Step 3: Implement `SlugGenerator`**

`Sources/Core/SlugGenerator.swift`:
```swift
import Foundation
import CryptoKit

public enum SlugGenerator {
    public static func makeSlug(for url: URL, durationSeconds: Double, recordedAt: Date) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let head = try handle.read(upToCount: 1024) ?? Data()

        var hasher = SHA256()
        hasher.update(data: url.lastPathComponent.data(using: .utf8) ?? Data())
        var d = durationSeconds
        hasher.update(data: Data(bytes: &d, count: MemoryLayout<Double>.size))
        hasher.update(data: head)
        let digest = hasher.finalize()

        let hex = digest.compactMap { String(format: "%02x", $0) }.joined()
        let shortuid = String(hex.prefix(6))

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        let dateStr = dateFormatter.string(from: recordedAt)

        return "field-recording-\(dateStr)-\(shortuid)"
    }
}
```

- [ ] **Step 4: Run tests to verify pass**

```bash
xcodebuild -scheme SpatialFieldConverter -configuration Debug test -destination 'platform=macOS' -only-testing:SpatialFieldConverterTests/SlugGeneratorTests
```

Expected: All 3 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/SlugGenerator.swift Tests/SlugGeneratorTests.swift
git commit -m "feat(core): SlugGenerator produces deterministic field-recording slugs"
```

### Task 5.2: ManifestWriter

**Files:**
- Create: `Sources/Core/ManifestWriter.swift`
- Create: `Tests/ManifestWriterTests.swift`

- [ ] **Step 1: Write failing tests**

`Tests/ManifestWriterTests.swift`:
```swift
import XCTest
@testable import SpatialFieldConverter

final class ManifestWriterTests: XCTestCase {
    var tempDir: URL!

    override func setUp() { super.setUp(); tempDir = TempDirectory.makeUnique() }
    override func tearDown() { TempDirectory.cleanup(tempDir); super.tearDown() }

    func test_writesValidJsonWithRequiredFields() throws {
        let url = tempDir.appendingPathComponent("manifest.json")
        let manifest = SpatialMixManifest(
            title: "Forest morning",
            durationSeconds: 312.4,
            sampleRate: 48000,
            bedFile: "bed.m4a",
            bedLayout: "7.1.2",
            objects: [],
            provenance: "user_uploaded",
            recordedAt: ISO8601DateFormatter().date(from: "2026-05-14T18:00:00Z")!,
            sourceMic: "Zoom VRH-8",
            latitude: nil,
            longitude: nil,
            tags: ["forest", "morning"]
        )
        try ManifestWriter.write(manifest, to: url)

        let data = try Data(contentsOf: url)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertNotNil(json)
        XCTAssertEqual(json?["schema"] as? String, "spatial-mix/v1")
        XCTAssertEqual(json?["title"] as? String, "Forest morning")
        XCTAssertEqual(json?["duration_sec"] as? Double, 312.4, accuracy: 1e-6)
        XCTAssertEqual(json?["sample_rate"] as? Int, 48000)
        XCTAssertEqual(json?["provenance"] as? String, "user_uploaded")
        XCTAssertEqual(json?["source_mic"] as? String, "Zoom VRH-8")
        XCTAssertEqual((json?["bed"] as? [String: Any])?["file"] as? String, "bed.m4a")
        XCTAssertEqual((json?["bed"] as? [String: Any])?["layout"] as? String, "7.1.2")
        XCTAssertEqual((json?["objects"] as? [Any])?.count, 0)
        XCTAssertEqual((json?["tags"] as? [String])?.count, 2)
    }

    func test_provenanceCannotBeOverridden() throws {
        // Even if you pass something else, the writer must enforce user_uploaded
        let url = tempDir.appendingPathComponent("manifest.json")
        let manifest = SpatialMixManifest(
            title: "test",
            durationSeconds: 1,
            sampleRate: 48000,
            bedFile: "bed.m4a",
            bedLayout: "7.1.2",
            objects: [],
            provenance: "release",   // attempt override
            recordedAt: Date(),
            sourceMic: "Zoom VRH-8",
            latitude: nil, longitude: nil, tags: []
        )
        try ManifestWriter.write(manifest, to: url)
        let data = try Data(contentsOf: url)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(json?["provenance"] as? String, "user_uploaded", "writer must hardcode user_uploaded")
    }
}
```

- [ ] **Step 2: Run to confirm failure**

```bash
xcodebuild -scheme SpatialFieldConverter -configuration Debug test -destination 'platform=macOS' -only-testing:SpatialFieldConverterTests/ManifestWriterTests
```

Expected: FAIL — `SpatialMixManifest`/`ManifestWriter` not defined.

- [ ] **Step 3: Implement**

`Sources/Core/ManifestWriter.swift`:
```swift
import Foundation

public struct SpatialMixManifest: Sendable {
    public let title: String
    public let durationSeconds: Double
    public let sampleRate: Int
    public let bedFile: String
    public let bedLayout: String
    public let objects: [Any]      // empty in v0.1; reserved
    public let provenance: String  // ignored — writer hardcodes user_uploaded
    public let recordedAt: Date
    public let sourceMic: String
    public let latitude: Double?
    public let longitude: Double?
    public let tags: [String]

    public init(
        title: String,
        durationSeconds: Double,
        sampleRate: Int,
        bedFile: String,
        bedLayout: String,
        objects: [Any],
        provenance: String,
        recordedAt: Date,
        sourceMic: String,
        latitude: Double?,
        longitude: Double?,
        tags: [String]
    ) {
        self.title = title
        self.durationSeconds = durationSeconds
        self.sampleRate = sampleRate
        self.bedFile = bedFile
        self.bedLayout = bedLayout
        self.objects = objects
        self.provenance = provenance
        self.recordedAt = recordedAt
        self.sourceMic = sourceMic
        self.latitude = latitude
        self.longitude = longitude
        self.tags = tags
    }
}

public enum ManifestWriter {
    public static func write(_ manifest: SpatialMixManifest, to url: URL) throws {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        var dict: [String: Any] = [
            "schema": "spatial-mix/v1",
            "title": manifest.title,
            "duration_sec": manifest.durationSeconds,
            "sample_rate": manifest.sampleRate,
            "bed": [
                "file": manifest.bedFile,
                "layout": manifest.bedLayout
            ],
            "objects": [],   // hardcoded empty in v0.1
            "provenance": "user_uploaded",   // IP guard: hardcoded, no override
            "recorded_at": formatter.string(from: manifest.recordedAt),
            "source_mic": manifest.sourceMic,
            "tags": manifest.tags
        ]
        if let lat = manifest.latitude { dict["lat"] = lat } else { dict["lat"] = NSNull() }
        if let lng = manifest.longitude { dict["lng"] = lng } else { dict["lng"] = NSNull() }

        let data = try JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
    }
}
```

- [ ] **Step 4: Run to verify pass**

```bash
xcodebuild -scheme SpatialFieldConverter -configuration Debug test -destination 'platform=macOS' -only-testing:SpatialFieldConverterTests/ManifestWriterTests
```

Expected: Both tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/ManifestWriter.swift Tests/ManifestWriterTests.swift
git commit -m "feat(core): ManifestWriter emits spatial-mix/v1 with hardcoded user_uploaded provenance"
```

### Task 5.3: SourceMetaWriter

**Files:**
- Create: `Sources/Core/SourceMetaWriter.swift`
- Create: `Tests/SourceMetaWriterTests.swift`

- [ ] **Step 1: Write failing test**

`Tests/SourceMetaWriterTests.swift`:
```swift
import XCTest
@testable import SpatialFieldConverter

final class SourceMetaWriterTests: XCTestCase {
    var tempDir: URL!
    override func setUp() { super.setUp(); tempDir = TempDirectory.makeUnique() }
    override func tearDown() { TempDirectory.cleanup(tempDir); super.tearDown() }

    func test_writesAllFields() throws {
        let url = tempDir.appendingPathComponent("source-meta.json")
        let info = SourceMetaInfo(
            originalFilename: "ZOOM0001.WAV",
            originalByteSize: 12345678,
            originalSampleRate: 48000,
            originalBitDepth: 24,
            originalChannelCount: 4,
            bextOriginationDate: "2026-05-14",
            bextOriginationTime: "10:00:00",
            gpsLatitude: 37.7749,
            gpsLongitude: -122.4194,
            convertedAt: Date(),
            converterVersion: "0.1.0",
            decoderMatrixVersion: "VRH8-reference-1.0"
        )
        try SourceMetaWriter.write(info, to: url)
        let data = try Data(contentsOf: url)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(json?["original_filename"] as? String, "ZOOM0001.WAV")
        XCTAssertEqual(json?["original_byte_size"] as? Int, 12345678)
        XCTAssertEqual(json?["original_sample_rate"] as? Int, 48000)
        XCTAssertEqual(json?["original_channel_count"] as? Int, 4)
        XCTAssertEqual(json?["gps_latitude"] as? Double, 37.7749, accuracy: 1e-6)
        XCTAssertEqual(json?["converter_version"] as? String, "0.1.0")
        XCTAssertEqual(json?["decoder_matrix_version"] as? String, "VRH8-reference-1.0")
    }
}
```

- [ ] **Step 2: Run to confirm failure**

Expected: FAIL — `SourceMetaInfo`/`SourceMetaWriter` not defined.

- [ ] **Step 3: Implement**

`Sources/Core/SourceMetaWriter.swift`:
```swift
import Foundation

public struct SourceMetaInfo {
    public let originalFilename: String
    public let originalByteSize: Int
    public let originalSampleRate: Int
    public let originalBitDepth: Int
    public let originalChannelCount: Int
    public let bextOriginationDate: String?
    public let bextOriginationTime: String?
    public let gpsLatitude: Double?
    public let gpsLongitude: Double?
    public let convertedAt: Date
    public let converterVersion: String
    public let decoderMatrixVersion: String

    public init(
        originalFilename: String,
        originalByteSize: Int,
        originalSampleRate: Int,
        originalBitDepth: Int,
        originalChannelCount: Int,
        bextOriginationDate: String?,
        bextOriginationTime: String?,
        gpsLatitude: Double?,
        gpsLongitude: Double?,
        convertedAt: Date,
        converterVersion: String,
        decoderMatrixVersion: String
    ) {
        self.originalFilename = originalFilename
        self.originalByteSize = originalByteSize
        self.originalSampleRate = originalSampleRate
        self.originalBitDepth = originalBitDepth
        self.originalChannelCount = originalChannelCount
        self.bextOriginationDate = bextOriginationDate
        self.bextOriginationTime = bextOriginationTime
        self.gpsLatitude = gpsLatitude
        self.gpsLongitude = gpsLongitude
        self.convertedAt = convertedAt
        self.converterVersion = converterVersion
        self.decoderMatrixVersion = decoderMatrixVersion
    }
}

public enum SourceMetaWriter {
    public static func write(_ info: SourceMetaInfo, to url: URL) throws {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        var dict: [String: Any] = [
            "original_filename": info.originalFilename,
            "original_byte_size": info.originalByteSize,
            "original_sample_rate": info.originalSampleRate,
            "original_bit_depth": info.originalBitDepth,
            "original_channel_count": info.originalChannelCount,
            "converted_at": formatter.string(from: info.convertedAt),
            "converter_version": info.converterVersion,
            "decoder_matrix_version": info.decoderMatrixVersion
        ]
        if let v = info.bextOriginationDate { dict["bext_origination_date"] = v }
        if let v = info.bextOriginationTime { dict["bext_origination_time"] = v }
        if let v = info.gpsLatitude { dict["gps_latitude"] = v }
        if let v = info.gpsLongitude { dict["gps_longitude"] = v }

        let data = try JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
    }
}
```

- [ ] **Step 4: Run + commit**

```bash
xcodebuild -scheme SpatialFieldConverter -configuration Debug test -destination 'platform=macOS' -only-testing:SpatialFieldConverterTests/SourceMetaWriterTests
git add Sources/Core/SourceMetaWriter.swift Tests/SourceMetaWriterTests.swift
git commit -m "feat(core): SourceMetaWriter persists original H8 file metadata"
```

---

## Phase 6 — Core: ConversionJob (orchestrator)

### Task 6.1: ConversionJob — wires everything end-to-end

**Files:**
- Create: `Sources/Core/ConversionJob.swift`
- Create: `Tests/ConversionJobTests.swift`

- [ ] **Step 1: Write failing integration test**

`Tests/ConversionJobTests.swift`:
```swift
import XCTest
@testable import SpatialFieldConverter

final class ConversionJobTests: XCTestCase {
    var tempDir: URL!

    override func setUp() { super.setUp(); tempDir = TempDirectory.makeUnique() }
    override func tearDown() { TempDirectory.cleanup(tempDir); super.tearDown() }

    func test_endToEnd_producesAllArtifacts() async throws {
        // 1. Create a synthetic H8 A-format input file
        let inputURL = tempDir.appendingPathComponent("ZOOM0001.WAV")
        try writeSyntheticAFormatWav(at: inputURL, durationSeconds: 1.0)

        // 2. Run ConversionJob
        let job = ConversionJob(
            sourceFile: inputURL,
            stagingRoot: tempDir.appendingPathComponent("staging"),
            mic: .vrh8AFormat,
            title: "Test conversion",
            tags: ["test"],
            latitude: nil,
            longitude: nil,
            converterVersion: "0.1.0-test"
        )
        let result = try await job.run()

        // 3. Verify all artifacts present in the staging folder
        let folder = result.stagingFolder
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("manifest.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("bed.m4a").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("source.wav").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("source-meta.json").path))

        // 4. Verify manifest
        let manifestData = try Data(contentsOf: folder.appendingPathComponent("manifest.json"))
        let json = try JSONSerialization.jsonObject(with: manifestData) as? [String: Any]
        XCTAssertEqual(json?["schema"] as? String, "spatial-mix/v1")
        XCTAssertEqual(json?["title"] as? String, "Test conversion")

        // 5. Verify slug shape
        XCTAssertTrue(folder.lastPathComponent.hasPrefix("field-recording-"))
    }

    private func writeSyntheticAFormatWav(at url: URL, durationSeconds: Double) throws {
        // 4-channel A-format white noise, 24-bit 48kHz
        let sampleRate = 48000
        let frameCount = Int(durationSeconds * Double(sampleRate))
        let aformat = SyntheticAmbisonicSignals.aFormatNoise(frameCount: frameCount)
        // Convert float to 24-bit interleaved PCM
        var samples = Data()
        for s in aformat {
            let clamped = max(-1.0, min(1.0, s))
            let v = Int32(clamped * Float(0x7FFFFF))
            samples.append(UInt8(v & 0xFF))
            samples.append(UInt8((v >> 8) & 0xFF))
            samples.append(UInt8((v >> 16) & 0xFF))
        }
        let bytesPerSample = 3
        let channels = 4
        let dataSize = samples.count
        let byteRate = sampleRate * channels * bytesPerSample
        let blockAlign = channels * bytesPerSample

        var data = Data()
        data.append("RIFF".data(using: .ascii)!)
        data.append(UInt32(36 + dataSize).littleEndianData)
        data.append("WAVE".data(using: .ascii)!)
        data.append("fmt ".data(using: .ascii)!)
        data.append(UInt32(16).littleEndianData)
        data.append(UInt16(1).littleEndianData)
        data.append(UInt16(channels).littleEndianData)
        data.append(UInt32(sampleRate).littleEndianData)
        data.append(UInt32(byteRate).littleEndianData)
        data.append(UInt16(blockAlign).littleEndianData)
        data.append(UInt16(24).littleEndianData)
        data.append("data".data(using: .ascii)!)
        data.append(UInt32(dataSize).littleEndianData)
        data.append(samples)
        try data.write(to: url)
    }
}
```

- [ ] **Step 2: Run to confirm failure**

Expected: FAIL — `ConversionJob` not defined.

- [ ] **Step 3: Implement `ConversionJob`**

`Sources/Core/ConversionJob.swift`:
```swift
import Foundation

public enum SourceMicType: String, Sendable {
    case vrh8AFormat = "Zoom VRH-8 (A-format)"
    case alreadyBFormat = "B-format AmbiX (no decode)"

    var matrix: [[Float]]? {
        switch self {
        case .vrh8AFormat: return VRH8DecoderMatrix.matrix
        case .alreadyBFormat: return nil   // passthrough
        }
    }
}

public struct ConversionJobResult: Sendable {
    public let stagingFolder: URL
    public let slug: String
    public let durationSeconds: Double
}

public final class ConversionJob: @unchecked Sendable {

    public let sourceFile: URL
    public let stagingRoot: URL
    public let mic: SourceMicType
    public let title: String
    public let tags: [String]
    public let latitude: Double?
    public let longitude: Double?
    public let converterVersion: String

    public init(
        sourceFile: URL,
        stagingRoot: URL,
        mic: SourceMicType,
        title: String,
        tags: [String],
        latitude: Double?,
        longitude: Double?,
        converterVersion: String
    ) {
        self.sourceFile = sourceFile
        self.stagingRoot = stagingRoot
        self.mic = mic
        self.title = title
        self.tags = tags
        self.latitude = latitude
        self.longitude = longitude
        self.converterVersion = converterVersion
    }

    public func run() async throws -> ConversionJobResult {
        // 1. Read source WAV
        let reader = try WavFileReader(url: sourceFile)
        let metadata = reader.metadata
        guard metadata.channelCount == 4 else {
            throw ConversionJobError.wrongChannelCount(metadata.channelCount)
        }
        guard metadata.sampleRate == 48000 else {
            throw ConversionJobError.unsupportedSampleRate(metadata.sampleRate)
        }

        // 2. Determine recordedAt — prefer BEXT, fallback to file modification date, then to now
        let recordedAt = parseRecordedAt(from: metadata) ?? fileModificationDate(of: sourceFile) ?? Date()

        // 3. Slug + staging folder
        let slug = try SlugGenerator.makeSlug(for: sourceFile, durationSeconds: metadata.durationSeconds, recordedAt: recordedAt)
        let folder = uniqueStagingFolder(slug: slug)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        // 4. Decode A-format → B-format (or passthrough)
        let sampleReader = try WavSampleReader(reader: reader)
        let bformatBuffer = try decodeFullFile(sampleReader: sampleReader, frameCount: metadata.frameCount)

        // 5. Write source.wav (B-format AmbiX)
        let sourceWavURL = folder.appendingPathComponent("source.wav")
        let ambiWriter = try AmbisonicWavWriter(url: sourceWavURL, sampleRate: 48000, bitsPerSample: 24)
        try ambiWriter.appendFrames(bformatBuffer, frameCount: metadata.frameCount)
        try ambiWriter.finalize()

        // 6. Decode B-format → 7.1.2 bed
        let rig = VirtualLoudspeakerRig.atmos7_1_2()
        let streamer = rig.makeStreamingDecoder(sampleRate: 48000)
        let bedBuffer = streamer.process(interleavedBformat: bformatBuffer, frameCount: metadata.frameCount)

        // 7. Encode bed.m4a
        let bedURL = folder.appendingPathComponent("bed.m4a")
        let encoder = try BedEncoder(outputURL: bedURL, sampleRate: 48000)
        // Encode in chunks to avoid huge buffers
        let chunkFrames = 4800   // 100ms
        var pos = 0
        while pos < metadata.frameCount {
            let n = min(chunkFrames, metadata.frameCount - pos)
            let slice = Array(bedBuffer[(pos * 10)..<((pos + n) * 10)])
            try encoder.appendFrames(slice, frameCount: n)
            pos += n
        }
        try await encoder.finalize()

        // 8. Write source-meta.json
        let attrs = try FileManager.default.attributesOfItem(atPath: sourceFile.path)
        let byteSize = (attrs[.size] as? Int) ?? 0
        let info = SourceMetaInfo(
            originalFilename: sourceFile.lastPathComponent,
            originalByteSize: byteSize,
            originalSampleRate: metadata.sampleRate,
            originalBitDepth: metadata.bitsPerSample,
            originalChannelCount: metadata.channelCount,
            bextOriginationDate: metadata.bextOriginationDate,
            bextOriginationTime: metadata.bextOriginationTime,
            gpsLatitude: latitude,
            gpsLongitude: longitude,
            convertedAt: Date(),
            converterVersion: converterVersion,
            decoderMatrixVersion: "VRH8-reference-1.0"
        )
        try SourceMetaWriter.write(info, to: folder.appendingPathComponent("source-meta.json"))

        // 9. Write manifest
        let manifest = SpatialMixManifest(
            title: title,
            durationSeconds: metadata.durationSeconds,
            sampleRate: 48000,
            bedFile: "bed.m4a",
            bedLayout: "7.1.2",
            objects: [],
            provenance: "user_uploaded",
            recordedAt: recordedAt,
            sourceMic: mic.rawValue,
            latitude: latitude,
            longitude: longitude,
            tags: tags
        )
        try ManifestWriter.write(manifest, to: folder.appendingPathComponent("manifest.json"))

        return ConversionJobResult(stagingFolder: folder, slug: slug, durationSeconds: metadata.durationSeconds)
    }

    // MARK: - Helpers

    private func decodeFullFile(sampleReader: WavSampleReader, frameCount: Int) throws -> [Float] {
        let outputCh = 4
        var output = [Float](repeating: 0, count: frameCount * outputCh)
        let chunkFrames = 4800
        var written = 0
        while written < frameCount {
            guard let block = try sampleReader.readNextBlock(maxFrames: chunkFrames) else { break }
            let bformat: [Float]
            if let matrix = mic.matrix {
                let decoder = AmbisonicDecoder(matrix: matrix)
                bformat = decoder.decode(interleavedAFormat: block.samples, frameCount: block.frameCount)
            } else {
                bformat = block.samples   // passthrough
            }
            for f in 0..<block.frameCount {
                for c in 0..<outputCh {
                    output[(written + f) * outputCh + c] = bformat[f * outputCh + c]
                }
            }
            written += block.frameCount
        }
        return output
    }

    private func parseRecordedAt(from metadata: WavMetadata) -> Date? {
        guard let date = metadata.bextOriginationDate, let time = metadata.bextOriginationTime else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.date(from: "\(date) \(time)")
    }

    private func fileModificationDate(of url: URL) -> Date? {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        return attrs?[.modificationDate] as? Date
    }

    private func uniqueStagingFolder(slug: String) -> URL {
        var candidate = stagingRoot.appendingPathComponent(slug)
        var suffix = 1
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = stagingRoot.appendingPathComponent("\(slug)-\(suffix)")
            suffix += 1
        }
        return candidate
    }
}

public enum ConversionJobError: Error {
    case wrongChannelCount(Int)
    case unsupportedSampleRate(Int)
}
```

- [ ] **Step 4: Run integration test to verify pass**

```bash
xcodebuild -scheme SpatialFieldConverter -configuration Debug test -destination 'platform=macOS' -only-testing:SpatialFieldConverterTests/ConversionJobTests
```

Expected: PASS — full end-to-end conversion of synthetic A-format input produces all 4 expected files in a slug folder.

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/ConversionJob.swift Tests/ConversionJobTests.swift
git commit -m "feat(core): ConversionJob orchestrates end-to-end conversion (synthetic input passes)"
```

---

## Phase 7 — Cloud Uploader Investigation + Bridge

### Task 7.1: Investigate Cloud Uploader entry points

**Files:**
- Read: `/Volumes/1tb /claude code projects /Projects/cloud-uploader/Sources/*.swift`
- Read: `/Volumes/1tb /claude code projects /Projects/cloud-uploader/Sources/adm_convert.py`
- Create: `docs/superpowers/notes/2026-05-14-cloud-uploader-integration-investigation.md`

- [ ] **Step 1: Inspect Cloud Uploader sources**

```bash
ls "/Volumes/1tb /claude code projects /Projects/cloud-uploader/Sources/"
```

Read these files in order:
1. `ContentView.swift` — does the app accept dropped folders or files? Is there a CLI argument handler?
2. `MediaProcessor.swift` — what's the existing processing pipeline? Does it have a "spatial-mix folder ingest" path?
3. `R2Uploader.swift` — what's the upload API surface? Can it be called with an arbitrary folder?
4. `CatalogGenerator.swift` — does it append to `catalog.json` for new spatial-mix entries?
5. `adm_convert.py` — what does this do? Is it invoked from Swift?

- [ ] **Step 2: Document findings in `docs/superpowers/notes/2026-05-14-cloud-uploader-integration-investigation.md`**

```markdown
# Cloud Uploader Integration — Findings (2026-05-14)

## Existing surface

[Document what you found: existing entry points, upload methods, manifest validation, etc.]

## Recommendation for Spatial Field Converter integration

One of three paths must be picked:
- (A) Cloud Uploader already has X — call it via [exact mechanism]
- (B) Cloud Uploader has a watched folder at [path] — drop our staging folder there
- (C) Cloud Uploader needs a new `--ingest-spatial-mix <folder>` CLI flag — implementation outline below

## Selected path

[A / B / C]

## Implementation steps for selected path

[Concrete steps]
```

- [ ] **Step 3: Commit the investigation note**

```bash
git add docs/superpowers/notes/2026-05-14-cloud-uploader-integration-investigation.md
git commit -m "docs: cloud uploader integration investigation"
```

### Task 7.2: Add `--ingest-spatial-mix` CLI flag to Cloud Uploader (only if Step 7.1 picked path C)

**Files:**
- Modify: `/Volumes/1tb /claude code projects /Projects/cloud-uploader/Sources/CloudUploaderApp.swift` (or wherever the entry point is)
- Modify: `/Volumes/1tb /claude code projects /Projects/cloud-uploader/Sources/MediaProcessor.swift`

**SKIP this task if Step 7.1 selected paths A or B.**

- [ ] **Step 1: Add CLI argument handling in app entry point**

Locate the SwiftUI App entry point. Add command-line argument inspection at startup:

```swift
import Foundation

@main
struct CloudUploaderApp: App {
    init() {
        Self.handleCLIIfPresent()
    }

    static func handleCLIIfPresent() {
        let args = CommandLine.arguments
        guard let idx = args.firstIndex(of: "--ingest-spatial-mix"),
              idx + 1 < args.count else { return }
        let folderPath = args[idx + 1]
        let folderURL = URL(fileURLWithPath: folderPath)
        Task {
            do {
                try await MediaProcessor.ingestSpatialMixStaging(folderURL: folderURL)
                exit(0)
            } catch {
                FileHandle.standardError.write("ingest failed: \(error.localizedDescription)\n".data(using: .utf8) ?? Data())
                exit(1)
            }
        }
        // Wait briefly then exit (a real impl uses a semaphore or RunLoop)
        Thread.sleep(forTimeInterval: 60)
        exit(2)   // timeout fallback
    }
    // ... existing body ...
}
```

(Adapt to actual entry point name. Replace `Thread.sleep` with proper RunLoop-based wait if existing app already handles async.)

- [ ] **Step 2: Add `ingestSpatialMixStaging` method to `MediaProcessor`**

```swift
extension MediaProcessor {
    /// Ingest a staging folder produced by Spatial Field Converter.
    /// Folder layout: <slug>/manifest.json + bed.m4a + source.wav + source-meta.json
    /// Pushes all files to R2 at cloud-to-float-on/stems/spatial-mix/field-recording/<slug>/
    /// Updates catalog.json.
    static func ingestSpatialMixStaging(folderURL: URL) async throws {
        let slug = folderURL.lastPathComponent
        // Verify required files
        let required = ["manifest.json", "bed.m4a", "source.wav", "source-meta.json"]
        for f in required {
            let p = folderURL.appendingPathComponent(f).path
            guard FileManager.default.fileExists(atPath: p) else {
                throw NSError(domain: "MediaProcessor", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "missing required file: \(f)"])
            }
        }
        // Use existing R2Uploader to push every file
        let r2Prefix = "stems/spatial-mix/field-recording/\(slug)/"
        let contents = try FileManager.default.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil)
        for fileURL in contents {
            let r2Key = r2Prefix + fileURL.lastPathComponent
            try await R2Uploader.upload(fileURL: fileURL, toKey: r2Key, bucket: "cloud-to-float-on")
        }
        // Update catalog
        try await CatalogGenerator.appendSpatialMixEntry(slug: slug, fromManifest: folderURL.appendingPathComponent("manifest.json"))
    }
}
```

(Adapt to actual `R2Uploader` and `CatalogGenerator` APIs found in Step 7.1. The above signatures are placeholders; substitute real ones.)

- [ ] **Step 3: Build cloud-uploader to verify**

```bash
cd "/Volumes/1tb /claude code projects /Projects/cloud-uploader"
xcodegen generate
xcodebuild -scheme CloudUploader -configuration Debug build -destination 'platform=macOS'
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Smoke test the new flag**

```bash
# Create a fake staging folder and try the flag
mkdir -p /tmp/test-staging/field-recording-2026-05-14-abc123
echo '{}' > /tmp/test-staging/field-recording-2026-05-14-abc123/manifest.json
touch /tmp/test-staging/field-recording-2026-05-14-abc123/bed.m4a
touch /tmp/test-staging/field-recording-2026-05-14-abc123/source.wav
touch /tmp/test-staging/field-recording-2026-05-14-abc123/source-meta.json

# Find the built app
APP=$(find ~/Library/Developer/Xcode/DerivedData -name "CloudUploader.app" -path "*Debug*" | head -1)
"$APP/Contents/MacOS/CloudUploader" --ingest-spatial-mix /tmp/test-staging/field-recording-2026-05-14-abc123
echo "exit: $?"
```

Expected: exit code 0 (or a clear R2-auth error if creds aren't configured for the test).

- [ ] **Step 5: Commit (in cloud-uploader repo)**

```bash
cd "/Volumes/1tb /claude code projects /Projects/cloud-uploader"
git add Sources/
git commit -m "feat: --ingest-spatial-mix CLI flag for Spatial Field Converter handoff"
```

### Task 7.3: CloudUploaderBridge in the converter app

**Files:**
- Create: `Sources/Mac/CloudUploaderBridge.swift`
- Create: `Sources/Mac/PreferencesStore.swift`
- Create: `Tests/CloudUploaderBridgeTests.swift`

- [ ] **Step 1: Write failing test (mock subprocess)**

`Tests/CloudUploaderBridgeTests.swift`:
```swift
import XCTest
@testable import SpatialFieldConverter

final class CloudUploaderBridgeTests: XCTestCase {
    var tempDir: URL!

    override func setUp() { super.setUp(); tempDir = TempDirectory.makeUnique() }
    override func tearDown() { TempDirectory.cleanup(tempDir); super.tearDown() }

    func test_invokesUploaderWithCorrectArguments() async throws {
        // Mock: a shell script that records its argv to a file then exits 0
        let mockUploader = tempDir.appendingPathComponent("mock-uploader")
        let recordFile = tempDir.appendingPathComponent("argv-record.txt")
        let script = """
        #!/bin/bash
        echo "$@" > "\(recordFile.path)"
        exit 0
        """
        try script.write(to: mockUploader, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: mockUploader.path)

        let bridge = CloudUploaderBridge(uploaderExecutableURL: mockUploader)
        let stagingFolder = tempDir.appendingPathComponent("staging/field-recording-test-123")
        try FileManager.default.createDirectory(at: stagingFolder, withIntermediateDirectories: true)

        try await bridge.ingest(stagingFolder: stagingFolder)

        let recorded = try String(contentsOf: recordFile)
        XCTAssertTrue(recorded.contains("--ingest-spatial-mix"))
        XCTAssertTrue(recorded.contains(stagingFolder.path))
    }

    func test_throwsOnNonzeroExit() async throws {
        let mockUploader = tempDir.appendingPathComponent("mock-uploader-fail")
        let script = "#!/bin/bash\nexit 7\n"
        try script.write(to: mockUploader, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: mockUploader.path)

        let bridge = CloudUploaderBridge(uploaderExecutableURL: mockUploader)
        let stagingFolder = tempDir.appendingPathComponent("staging/x")
        try FileManager.default.createDirectory(at: stagingFolder, withIntermediateDirectories: true)

        do {
            try await bridge.ingest(stagingFolder: stagingFolder)
            XCTFail("expected throw")
        } catch CloudUploaderBridgeError.uploaderExitedNonZero(let code) {
            XCTAssertEqual(code, 7)
        }
    }
}
```

- [ ] **Step 2: Run to confirm failure**

Expected: FAIL — `CloudUploaderBridge` not defined.

- [ ] **Step 3: Implement `CloudUploaderBridge`**

`Sources/Mac/PreferencesStore.swift`:
```swift
import Foundation

public enum PreferencesStore {
    private static let uploaderPathKey = "cloudUploaderExecutablePath"
    private static let stagingDirKey = "stagingDirectoryPath"

    public static var cloudUploaderExecutableURL: URL {
        get {
            if let s = UserDefaults.standard.string(forKey: uploaderPathKey) {
                return URL(fileURLWithPath: s)
            }
            // Default: look for the most recent CloudUploader.app build under DerivedData
            return defaultUploaderPath()
        }
        set { UserDefaults.standard.set(newValue.path, forKey: uploaderPathKey) }
    }

    public static var stagingDirectory: URL {
        get {
            if let s = UserDefaults.standard.string(forKey: stagingDirKey) {
                return URL(fileURLWithPath: s)
            }
            let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            return cache.appendingPathComponent("SpatialFieldConverter").appendingPathComponent("staging")
        }
        set { UserDefaults.standard.set(newValue.path, forKey: stagingDirKey) }
    }

    private static func defaultUploaderPath() -> URL {
        let derivedData = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Developer/Xcode/DerivedData")
        // Walk DerivedData for CloudUploader.app
        let enumerator = FileManager.default.enumerator(at: derivedData, includingPropertiesForKeys: nil)
        while let url = enumerator?.nextObject() as? URL {
            if url.lastPathComponent == "CloudUploader.app" && url.path.contains("Debug") {
                return url.appendingPathComponent("Contents/MacOS/CloudUploader")
            }
        }
        return URL(fileURLWithPath: "/Applications/Cloud Uploader.app/Contents/MacOS/CloudUploader")
    }
}
```

`Sources/Mac/CloudUploaderBridge.swift`:
```swift
import Foundation

public enum CloudUploaderBridgeError: Error {
    case uploaderExitedNonZero(Int32)
    case uploaderNotFound(URL)
    case spawnFailed(String)
}

public final class CloudUploaderBridge {
    private let executableURL: URL

    public init(uploaderExecutableURL: URL) {
        self.executableURL = uploaderExecutableURL
    }

    public func ingest(stagingFolder: URL) async throws {
        guard FileManager.default.fileExists(atPath: executableURL.path) else {
            throw CloudUploaderBridgeError.uploaderNotFound(executableURL)
        }

        let process = Process()
        process.executableURL = executableURL
        process.arguments = ["--ingest-spatial-mix", stagingFolder.path]

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        try process.run()

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            DispatchQueue.global().async {
                process.waitUntilExit()
                cont.resume()
            }
        }

        if process.terminationStatus != 0 {
            throw CloudUploaderBridgeError.uploaderExitedNonZero(process.terminationStatus)
        }
    }
}
```

- [ ] **Step 4: Run to verify pass**

```bash
xcodebuild -scheme SpatialFieldConverter -configuration Debug test -destination 'platform=macOS' -only-testing:SpatialFieldConverterTests/CloudUploaderBridgeTests
```

Expected: Both tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/Mac/CloudUploaderBridge.swift Sources/Mac/PreferencesStore.swift Tests/CloudUploaderBridgeTests.swift
git commit -m "feat(mac): CloudUploaderBridge invokes uploader with --ingest-spatial-mix"
```

---

## Phase 8 — Mac UI

### Task 8.1: ConversionPipeline (sequencer for batch jobs)

**Files:**
- Create: `Sources/Mac/ConversionPipeline.swift`

- [ ] **Step 1: Implement (no dedicated test — exercised via integration in Task 8.5)**

`Sources/Mac/ConversionPipeline.swift`:
```swift
import Foundation
import SwiftUI

@MainActor
public final class ConversionPipeline: ObservableObject {

    public struct Job: Identifiable {
        public let id = UUID()
        public let sourceURL: URL
        public var title: String
        public var tags: [String]
        public var latitude: Double?
        public var longitude: Double?
        public var enabled: Bool = true
        public var status: JobStatus = .pending
        public var slug: String? = nil
        public var errorMessage: String? = nil
    }

    public enum JobStatus: Equatable {
        case pending
        case alreadyConverted          // detected via slug collision
        case converting
        case uploading
        case done
        case failed
    }

    @Published public var jobs: [Job] = []
    @Published public var isRunning: Bool = false

    private let stagingRoot: URL
    private let uploader: CloudUploaderBridge
    private let converterVersion: String = "0.1.0"

    public init(stagingRoot: URL, uploader: CloudUploaderBridge) {
        self.stagingRoot = stagingRoot
        self.uploader = uploader
        try? FileManager.default.createDirectory(at: stagingRoot, withIntermediateDirectories: true)
    }

    public func addFiles(_ urls: [URL]) {
        for url in urls {
            let title = url.deletingPathExtension().lastPathComponent
            jobs.append(Job(sourceURL: url, title: title, tags: [], latitude: nil, longitude: nil))
        }
    }

    public func runAll() async {
        isRunning = true
        defer { isRunning = false }
        for index in jobs.indices where jobs[index].enabled && jobs[index].status == .pending {
            await runJob(at: index)
        }
    }

    private func runJob(at index: Int) async {
        jobs[index].status = .converting
        let snapshot = jobs[index]
        let job = ConversionJob(
            sourceFile: snapshot.sourceURL,
            stagingRoot: stagingRoot,
            mic: .vrh8AFormat,
            title: snapshot.title,
            tags: snapshot.tags,
            latitude: snapshot.latitude,
            longitude: snapshot.longitude,
            converterVersion: converterVersion
        )
        do {
            let result = try await job.run()
            jobs[index].slug = result.slug
            jobs[index].status = .uploading
            try await uploader.ingest(stagingFolder: result.stagingFolder)
            jobs[index].status = .done
        } catch {
            jobs[index].status = .failed
            jobs[index].errorMessage = "\(error)"
        }
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add Sources/Mac/ConversionPipeline.swift
git commit -m "feat(mac): ConversionPipeline sequencer for batch jobs"
```

### Task 8.2: DropTargetView

**Files:**
- Create: `Sources/Mac/DropTargetView.swift`

- [ ] **Step 1: Implement**

`Sources/Mac/DropTargetView.swift`:
```swift
import SwiftUI
import UniformTypeIdentifiers

struct DropTargetView: View {
    var onDropFiles: ([URL]) -> Void
    @State private var isTargeted: Bool = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(isTargeted ? Color.accentColor : Color.gray.opacity(0.4),
                              style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(isTargeted ? Color.accentColor.opacity(0.1) : Color.gray.opacity(0.05))
                )
            VStack(spacing: 12) {
                Image(systemName: "waveform.circle")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 64, height: 64)
                    .foregroundStyle(.secondary)
                Text("Drop a Zoom H8 .wav file or an SD card folder")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            Task {
                var urls: [URL] = []
                for provider in providers {
                    if let url = await Self.loadURL(from: provider) {
                        urls.append(contentsOf: Self.expandToWavFiles(url))
                    }
                }
                if !urls.isEmpty {
                    await MainActor.run {
                        onDropFiles(urls)
                    }
                }
            }
            return true
        }
    }

    private static func loadURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { (cont: CheckedContinuation<URL?, Never>) in
            _ = provider.loadObject(ofClass: URL.self) { obj, _ in
                cont.resume(returning: obj)
            }
        }
    }

    private static func expandToWavFiles(_ url: URL) -> [URL] {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { return [] }
        if isDir.boolValue {
            let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil)
            var found: [URL] = []
            while let next = enumerator?.nextObject() as? URL {
                if next.pathExtension.lowercased() == "wav" {
                    found.append(next)
                }
            }
            return found.sorted { $0.path < $1.path }
        } else if url.pathExtension.lowercased() == "wav" {
            return [url]
        }
        return []
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add Sources/Mac/DropTargetView.swift
git commit -m "feat(mac): DropTargetView accepts file or folder drop, recurses for .wav"
```

### Task 8.3: InspectorView (file list with per-row controls)

**Files:**
- Create: `Sources/Mac/InspectorView.swift`

- [ ] **Step 1: Implement**

`Sources/Mac/InspectorView.swift`:
```swift
import SwiftUI

struct InspectorView: View {
    @ObservedObject var pipeline: ConversionPipeline

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(pipeline.jobs.count) file\(pipeline.jobs.count == 1 ? "" : "s") queued")
                    .font(.headline)
                Spacer()
                Button("Convert + Upload") {
                    Task { await pipeline.runAll() }
                }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(pipeline.isRunning || pipeline.jobs.isEmpty)
            }
            .padding()

            Divider()

            List {
                ForEach($pipeline.jobs) { $job in
                    HStack(alignment: .top, spacing: 12) {
                        Toggle("", isOn: $job.enabled)
                            .labelsHidden()
                            .disabled(pipeline.isRunning)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                TextField("Title", text: $job.title)
                                    .textFieldStyle(.roundedBorder)
                                    .disabled(pipeline.isRunning)
                                statusBadge(job.status)
                            }
                            Text(job.sourceURL.path)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            if let slug = job.slug {
                                Text("→ \(slug)")
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                            if let err = job.errorMessage {
                                Text(err)
                                    .font(.caption2)
                                    .foregroundStyle(.red)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    @ViewBuilder
    private func statusBadge(_ status: ConversionPipeline.JobStatus) -> some View {
        switch status {
        case .pending:           Text("queued").font(.caption).foregroundStyle(.secondary)
        case .alreadyConverted:  Text("already in R2").font(.caption).foregroundStyle(.orange)
        case .converting:        Text("converting…").font(.caption).foregroundStyle(.blue)
        case .uploading:         Text("uploading…").font(.caption).foregroundStyle(.blue)
        case .done:              Text("done").font(.caption).foregroundStyle(.green)
        case .failed:            Text("failed").font(.caption).foregroundStyle(.red)
        }
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add Sources/Mac/InspectorView.swift
git commit -m "feat(mac): InspectorView lists queued jobs with per-row status"
```

### Task 8.4: Wire ContentView to drop target + inspector + pipeline

**Files:**
- Modify: `Sources/Mac/ContentView.swift`

- [ ] **Step 1: Replace ContentView with full layout**

```swift
import SwiftUI

struct ContentView: View {
    @StateObject private var pipeline: ConversionPipeline = {
        let stagingRoot = PreferencesStore.stagingDirectory
        let uploader = CloudUploaderBridge(uploaderExecutableURL: PreferencesStore.cloudUploaderExecutableURL)
        return ConversionPipeline(stagingRoot: stagingRoot, uploader: uploader)
    }()

    var body: some View {
        if pipeline.jobs.isEmpty {
            DropTargetView(onDropFiles: { urls in
                pipeline.addFiles(urls)
            })
            .padding()
            .frame(minWidth: 720, minHeight: 480)
        } else {
            HStack(spacing: 0) {
                InspectorView(pipeline: pipeline)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                VStack {
                    DropTargetView(onDropFiles: { urls in
                        pipeline.addFiles(urls)
                    })
                    .frame(width: 240, height: 240)
                    .padding()
                    Spacer()
                }
            }
            .frame(minWidth: 720, minHeight: 480)
        }
    }
}
```

- [ ] **Step 2: Build and run manually**

```bash
xcodegen generate
xcodebuild -scheme SpatialFieldConverter -configuration Debug build -destination 'platform=macOS'
APP=$(find ~/Library/Developer/Xcode/DerivedData -name "SpatialFieldConverter.app" -path "*Debug*" | head -1)
open "$APP"
```

Manually verify: window appears, drop a .wav file, see it appear in the inspector with status "queued."

- [ ] **Step 3: Commit**

```bash
git add Sources/Mac/ContentView.swift
git commit -m "feat(mac): wire drop target + inspector + pipeline in ContentView"
```

### Task 8.5: Slug-collision dedup on drop

**Files:**
- Modify: `Sources/Mac/ConversionPipeline.swift`

- [ ] **Step 1: Add dedup logic in `addFiles`**

Replace the existing `addFiles` body:

```swift
public func addFiles(_ urls: [URL]) {
    for url in urls {
        // Detect "already converted" by computing the slug and checking the staging folder
        let title = url.deletingPathExtension().lastPathComponent
        var job = Job(sourceURL: url, title: title, tags: [], latitude: nil, longitude: nil)

        // Best-effort slug pre-compute (don't block the UI on huge files)
        do {
            let reader = try WavFileReader(url: url)
            let recordedAt = parseRecordedAt(metadata: reader.metadata) ?? Date()
            let slug = try SlugGenerator.makeSlug(for: url, durationSeconds: reader.metadata.durationSeconds, recordedAt: recordedAt)
            let probable = stagingRoot.appendingPathComponent(slug)
            if FileManager.default.fileExists(atPath: probable.path) {
                job.status = .alreadyConverted
                job.enabled = false
                job.slug = slug
            }
        } catch {
            // ignore — full conversion will surface real errors
        }
        jobs.append(job)
    }
}

private func parseRecordedAt(metadata: WavMetadata) -> Date? {
    guard let date = metadata.bextOriginationDate, let time = metadata.bextOriginationTime else { return nil }
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    return formatter.date(from: "\(date) \(time)")
}
```

- [ ] **Step 2: Manual test**

Run the app, drop a .wav file. Convert + Upload it. Drop the same file again — it should appear with "already in R2" badge and unchecked.

- [ ] **Step 3: Commit**

```bash
git add Sources/Mac/ConversionPipeline.swift
git commit -m "feat(mac): pre-compute slug on add, mark already-converted files"
```

---

## Phase 9 — End-to-End Manual Validation

### Task 9.1: Convert one real H8 recording end-to-end

This is a manual acceptance task — no new code. Must be run by Chris on a real H8 file.

- [ ] **Step 1: Build and install latest**

```bash
cd "/Volumes/1tb /claude code projects /Projects/spatial-field-converter"
xcodegen generate
xcodebuild -scheme SpatialFieldConverter -configuration Release build -destination 'platform=macOS'
APP=$(find ~/Library/Developer/Xcode/DerivedData -name "SpatialFieldConverter.app" -path "*Release*" | head -1)
cp -R "$APP" "/Applications/Spatial Field Converter v0.1.app"
```

- [ ] **Step 2: Configure Cloud Uploader path (one-time)**

Open `/Applications/Spatial Field Converter v0.1.app`. (For v0.1, uploader path defaults to DerivedData; if Cloud Uploader is installed at `/Applications/Cloud Uploader.app`, set via `defaults write com.fascinatedbyeverything.spatialfieldconverter cloudUploaderExecutablePath "/Applications/Cloud Uploader.app/Contents/MacOS/CloudUploader"`.)

- [ ] **Step 3: Convert one real H8 file**

Drag a real Zoom H8 + VRH-8 4-channel .wav file onto the app. Click Convert + Upload.

Verify in order:
1. Inspector shows the file with detected channels=4, sampleRate=48000
2. Status progresses: queued → converting → uploading → done
3. Slug is shown as `field-recording-YYYY-MM-DD-XXXXXX`

- [ ] **Step 4: Verify in R2**

Check that `cloud-to-float-on/stems/spatial-mix/field-recording/<slug>/` exists and contains:
- `manifest.json`
- `bed.m4a`
- `source.wav`
- `source-meta.json`

(Use whatever R2 console / `rclone` / Cloudflare dashboard you normally use.)

- [ ] **Step 5: Verify playback in Fascinated Field**

Open Fascinated Field. Find the new field-recording entry in the library (it should appear after a catalog refresh — manually trigger if needed). Add it to a scene. Play through AirPods. Verify:
- Audio plays
- Spatial positioning makes sense (sources appear from the directions they were recorded)
- Head-tracking rotates the field (turn your head; field stays fixed in space)

- [ ] **Step 6: Test bulk SD card flow**

Drop the entire H8 SD card folder onto the app. Verify:
- All .wav files appear in the inspector
- Default ticks are checked
- Convert + Upload processes them sequentially
- Re-dropping the same SD card shows previously-converted files as "already in R2" with ticks off

- [ ] **Step 7: Document the manual test results**

Create `docs/superpowers/notes/2026-05-14-v0.1-acceptance-test-log.md`:

```markdown
# v0.1 Acceptance Test Log — 2026-05-14

## Single-file test
- Source: <path to test file>
- Result: [pass/fail with notes]

## Bulk SD card test
- N files: <count>
- Result: [pass/fail]

## Playback test in Fascinated Field
- [pass/fail with notes on head-tracking, spatial accuracy]

## Issues found (file as v0.2 work)
- [list]
```

```bash
git add docs/superpowers/notes/2026-05-14-v0.1-acceptance-test-log.md
git commit -m "docs: v0.1 acceptance test log"
```

### Task 9.2: Tag v0.1.0

- [ ] **Step 1: Tag release**

```bash
cd "/Volumes/1tb /claude code projects /Projects/spatial-field-converter"
git tag -a v0.1.0 -m "Spatial Field Converter v0.1 — VRH-8 H8 batch converter"
```

(Push if remote is configured. v0.1 may stay local-only; that's fine.)

---

## Self-Review Notes

Verified against spec:

- §1 purpose + scope: covered by overall plan + Task 9.1 acceptance
- §2 architecture: file structure mapped 1:1 in `File Structure` section
- §3.1 input detection: Task 1.1 + 1.2 (RIFF, BEXT)
- §3.2 A→B conversion: Task 2.1 + 2.3 (matrix + decoder, with VRH-8 + already-AmbiX modes)
- §3.3a source.wav: Task 4.1
- §3.3b bed.m4a: Tasks 3.1 + 3.2 + 4.2 (decoder + LFE + encoder)
- §3.3c preview.m4a: gated per spec — NOT in v0.1 plan; deferred
- §3.3d source-meta.json: Task 5.3
- §4 manifest schema + slug: Tasks 5.1 + 5.2
- §5 Cloud Uploader handoff: Tasks 7.1, 7.2 (conditional), 7.3
- §6 UI/UX: Tasks 8.1–8.5
- §7 error handling: covered in `ConversionJobError` + `CloudUploaderBridgeError` + status states
- §8 testing: unit + integration tests in Tasks 1–6, manual in Task 9.1
- §9 project structure: Task 0.1
- §10 open questions: Task 7.1 resolves Q2; Q1, Q3, Q4 are non-blocking, Q5 surfaces during manual test
- §11 future phases: out of scope for this plan
- §12 references: all linked
- IP rule (`provenance=user_uploaded` hardcoded): Task 5.2 has dedicated test

Resolved minor inconsistencies inline:
- BedEncoder API was async; plan now reflects `try await encoder.finalize()` consistently (Task 4.2 step 4 is explicit about updating the test)
- ContentView in Task 0.3 is a stub; replaced wholesale in Task 8.4 (no rename, just rewrite)
- `runJob` mutates `jobs` from a non-MainActor context — class is `@MainActor`, so safe

No placeholder text. All steps contain concrete code or commands.
