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

    private let staging: URL
    private let uploader: CloudUploaderBridge
    private let converterVersion: String = "0.1.0"

    public init(stagingDirectory: URL, uploader: CloudUploaderBridge) {
        self.staging = stagingDirectory
        self.uploader = uploader
        try? FileManager.default.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
    }

    /// Add a list of URLs to the queue. For folders, callers should pre-expand to .wav files.
    public func addFiles(_ urls: [URL]) {
        for url in urls {
            let title = url.deletingPathExtension().lastPathComponent
            var job = Job(sourceURL: url, title: title)

            // Pre-check: have we already converted this file? If the ADM BWF already exists
            // in staging with the deterministic slug, mark as alreadyConverted.
            if let slug = try? probableSlug(for: url) {
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

            let result = try await uploader.uploadADMBWF(
                admBwfURL: conv.admBwfURL,
                programmeName: snapshot.title,
                category: "field-recording"
            )
            jobs[index].r2Key = result.r2Key
            jobs[index].status = .done
        } catch {
            jobs[index].status = .failed
            jobs[index].errorMessage = "\(error)"
        }
    }

    /// Compute the probable slug for the source file. Uses the same logic as ConversionJob
    /// but here it's "best effort" — only used to mark already-converted files.
    private func probableSlug(for url: URL) throws -> String {
        let reader = try WavFileReader(url: url)
        let recordedAt = ConversionJob.parseRecordedAt(metadata: reader.metadata)
            ?? ConversionJob.fileModificationDate(of: url)
            ?? Date()
        return ConversionJob.makeSlug(for: url, recordedAt: recordedAt)
    }
}
