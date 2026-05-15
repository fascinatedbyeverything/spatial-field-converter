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
            let title = url.deletingPathExtension().lastPathComponent
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

        let job = ConversionJob(
            sourceFile: snapshot.sourceURL,
            outputDirectory: staging,
            mic: .vrh8AFormat,
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

            // Upload to R2 at stems/spatial-mix/field-recording/zoom-bounces/<slug>/
            // The zoom-bounces sub-prefix groups Zoom H8 + VRH-8 conversions distinctly;
            // future Ambeo / Zylia decoders will get their own sub-prefixes.
            let r2Prefix = "stems/spatial-mix/field-recording/zoom-bounces/\(conv.slug)/"
            let result = try await uploader.uploadFolder(
                localFolder: convertedFolder,
                r2Prefix: r2Prefix
            )
            jobs[index].r2Key = result.r2Prefix
            jobs[index].status = .done
        } catch {
            jobs[index].status = .failed
            jobs[index].errorMessage = "\(error)"
        }
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
            let job = ConversionJob(
                sourceFile: snapshot.sourceURL,
                outputDirectory: staging,
                mic: .vrh8AFormat,
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
