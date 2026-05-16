import Foundation
import SwiftUI

/// The Mac-side batch sequencer.
/// Each Job represents one H8 .wav awaiting conversion.
/// Pipeline runs serially (one job at a time) to avoid R2 / subprocess thrash.
@MainActor
public final class ConversionPipeline: ObservableObject {

    public struct Job: Identifiable {
        public let id = UUID()
        public let sourceURL: URL
        public var title: String
        public var enabled: Bool = true
        public var status: JobStatus = .pending
        public var slug: String? = nil
        public var r2Key: String? = nil
        public var errorMessage: String? = nil
    }

    public enum JobStatus: String, Equatable {
        case pending
        case alreadyConverted
        case converting
        case uploading
        case done
        case failed
    }

    @Published public var jobs: [Job] = []
    @Published public var isRunning: Bool = false
    @Published public var soundAnalysisEnabled: Bool = false   // v0.2 stub — has no effect in v0.1
    @Published public var previewPlayer: PreviewPlayer = PreviewPlayer()

    private let staging: URL
    private let uploader: R2Uploader
    private let converterVersion: String = "0.1.0"

    public init(stagingDirectory: URL) {
        self.staging = stagingDirectory
        self.uploader = R2Uploader()
        try? FileManager.default.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
    }

    /// Add a list of URLs to the queue. For folders, callers should pre-expand to .wav files.
    public func addFiles(_ urls: [URL]) {
        for url in urls {
            let basename = url.deletingPathExtension().lastPathComponent
            // H8 generic filenames (Mic1234, MIC0001, ZOOM0001, etc.) get blanked so the user
            // is forced to type a meaningful name. Anything else stays as-is.
            let title = Self.isGenericRecorderName(basename) ? "" : basename
            var job = Job(sourceURL: url, title: title)

            // Pre-check: have we already converted this file? If the ADM BWF already exists
            // in staging with the deterministic slug, mark as alreadyConverted.
            if let slug = try? probableSlug(for: url, title: title) {
                let probable = staging.appendingPathComponent("\(slug).wav")
                if FileManager.default.fileExists(atPath: probable.path) {
                    job.status = .alreadyConverted
                    job.enabled = false
                    job.slug = slug
                }
            }

            jobs.append(job)
        }
    }

    public func removeAllJobs() {
        guard !isRunning else { return }
        jobs.removeAll()
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

        // Auto-detect mic type and R2 sub-prefix from channel count.
        // 4-ch → Zoom VRH-8 A-format → zoom-bounces
        // 16-ch → Zylia ZM-1 3rd-order AmbiX → zylia-bounces
        // Other → fail with a clear message.
        let mic: SourceMicType
        let r2Category: String
        do {
            let probeReader = try WavFileReader(url: snapshot.sourceURL)
            switch probeReader.metadata.channelCount {
            case 4:
                mic = PreferencesStore.defaultMicForFourChannel
                switch mic {
                case .ambeoAFormat:
                    r2Category = "field-recording/ambeo-bounces"
                default:
                    r2Category = "field-recording/zoom-bounces"
                }
            case 16:
                mic = .ambixThirdOrder
                r2Category = "field-recording/zylia-bounces"
            default:
                jobs[index].status = .failed
                jobs[index].errorMessage = "unsupported channel count: \(probeReader.metadata.channelCount) (expected 4 or 16)"
                return
            }
        } catch {
            jobs[index].status = .failed
            jobs[index].errorMessage = "could not read WAV header: \(error)"
            return
        }

        let job = ConversionJob(
            sourceFile: snapshot.sourceURL,
            outputDirectory: staging,
            mic: mic,
            programmeName: snapshot.title,
            converterVersion: converterVersion
        )

        do {
            let conv = try await job.run()
            jobs[index].slug = conv.slug
            jobs[index].status = .uploading

            // Run adm_convert.py to split ADM BWF into bed.m4a + obj-NN.m4a + manifest.json
            let stagingForSlug = staging
                .appendingPathComponent("converted")
                .appendingPathComponent(conv.slug)
            let convertedFolder = try await ADMConverter.convert(
                admBwfURL: conv.admBwfURL,
                slug: conv.slug,
                outputDirectory: stagingForSlug
            )

            // Upload to R2. Sub-prefix is mic-type-specific so conversions from different
            // sources are grouped distinctly in the bucket.
            let r2Prefix = "stems/spatial-mix/\(r2Category)/\(conv.slug)/"
            let result = try await uploader.uploadFolder(
                localFolder: convertedFolder,
                r2Prefix: r2Prefix
            )
            jobs[index].r2Key = result.r2Prefix

            // Refresh catalog.json on R2 so Fascinated Field + Presets3 can see
            // the new spatial mix without a full catalog regeneration.
            // Read duration from manifest.json written by ADMConverter.
            let durationSec = manifestDuration(in: convertedFolder)
            await uploader.refreshCatalog(
                slug: conv.slug,
                title: snapshot.title,
                durationSec: durationSec
            )

            jobs[index].status = .done
        } catch {
            jobs[index].status = .failed
            jobs[index].errorMessage = "\(error)"
        }
    }

    /// Read `duration` from the manifest.json that ADMConverter wrote into `folder`.
    /// Returns 0 if the file is missing or unparseable — catalog refresh will still proceed.
    private func manifestDuration(in folder: URL) -> Double {
        let manifestURL = folder.appendingPathComponent("manifest.json")
        guard let data = try? Data(contentsOf: manifestURL),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let duration = root["duration"] as? Double else {
            return 0
        }
        return duration
    }

    /// True if `name` matches a generic field-recorder default (Mic1234, MIC0001, ZOOM0123,
    /// or Zylia's Recording_20200103_15_31_(ACN-SN3D-3) pattern).
    /// Used to blank the inspector title field so the user must enter something meaningful
    /// before Convert+Upload becomes enabled.
    static func isGenericRecorderName(_ name: String) -> Bool {
        let range = NSRange(name.startIndex..<name.endIndex, in: name)

        // Pattern 1: H8 / generic recorders — letters followed by digits.
        let genericPattern = #"^(mic|zoom|tr|track|file|rec)[_-]?\d+$"#
        if let re = try? NSRegularExpression(pattern: genericPattern, options: [.caseInsensitive]),
           re.firstMatch(in: name, range: range) != nil {
            return true
        }

        // Pattern 2: Zylia — Recording_<date8>[_]<time4-6>[_(<suffix>)]
        // e.g. Recording_20200103_15_31_(ACN-SN3D-3) or Recording_20200103_153100
        let zyliaPattern = #"^recording[_-]?\d{8}[_-]?\d{4,6}(_\(.+\))?$"#
        if let re = try? NSRegularExpression(pattern: zyliaPattern, options: [.caseInsensitive]),
           re.firstMatch(in: name, range: range) != nil {
            return true
        }

        return false
    }

    /// Compute the probable slug for the source file using the default (filename-derived)
    /// title. Best-effort — if the user later edits the title before Convert+Upload, the
    /// real slug will differ; this is used only for the "already converted" badge.
    private func probableSlug(for url: URL, title: String) throws -> String {
        let reader = try WavFileReader(url: url)
        let recordedAt = ConversionJob.parseRecordedAt(metadata: reader.metadata)
            ?? ConversionJob.fileModificationDate(of: url)
            ?? Date()
        return ConversionJob.makeSlug(for: url, title: title, recordedAt: recordedAt)
    }

    /// Runs the convert phase only (ConversionJob + ADMConverter) without uploading.
    /// Returns the URL of the resulting bed.m4a.
    /// Caches: if bed.m4a already exists from a prior run, returns it immediately.
    public func prepareForPreview(at index: Int) async throws -> URL {
        guard jobs.indices.contains(index) else {
            throw NSError(domain: "ConversionPipeline", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "invalid index"])
        }
        let snapshot = jobs[index]

        // Determine the slug (use cached slug if available)
        let slug: String
        if let cached = snapshot.slug {
            slug = cached
        } else {
            slug = try probableSlug(for: snapshot.sourceURL, title: snapshot.title)
        }
        let convertedFolder = staging
            .appendingPathComponent("converted")
            .appendingPathComponent(slug)
        let bedURL = convertedFolder.appendingPathComponent("bed.m4a")

        // Cache hit: bed.m4a already exists from a prior convert run
        if FileManager.default.fileExists(atPath: bedURL.path) {
            jobs[index].slug = slug
            return bedURL
        }

        // Cache miss: run the convert phase and restore status afterward (no upload)
        let priorStatus = jobs[index].status
        jobs[index].status = .converting

        do {
            let probeReader = try WavFileReader(url: snapshot.sourceURL)
            let previewMic: SourceMicType
            switch probeReader.metadata.channelCount {
            case 16: previewMic = .ambixThirdOrder
            default: previewMic = PreferencesStore.defaultMicForFourChannel
            }
            let job = ConversionJob(
                sourceFile: snapshot.sourceURL,
                outputDirectory: staging,
                mic: previewMic,
                programmeName: snapshot.title,
                converterVersion: converterVersion
            )
            let conv = try await job.run()
            jobs[index].slug = conv.slug

            let actualSlugFolder = staging
                .appendingPathComponent("converted")
                .appendingPathComponent(conv.slug)
            _ = try await ADMConverter.convert(
                admBwfURL: conv.admBwfURL,
                slug: conv.slug,
                outputDirectory: actualSlugFolder
            )

            let actualBedURL = actualSlugFolder.appendingPathComponent("bed.m4a")
            // Restore prior status — we didn't upload, so don't mark as done
            jobs[index].status = priorStatus
            return actualBedURL
        } catch {
            jobs[index].status = .failed
            jobs[index].errorMessage = "preview convert failed: \(error)"
            throw error
        }
    }
}
