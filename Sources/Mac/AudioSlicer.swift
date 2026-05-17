import Foundation

// ---------------------------------------------------------------------------
// AudioSlicer — wraps ffmpeg subprocess to extract time-range clips from
// a source bed.m4a. Output: mono 48kHz AAC 128k .m4a.
// ffmpeg path matches ADMConverter.swift convention: /opt/homebrew/bin/ffmpeg.
// ---------------------------------------------------------------------------

public enum AudioSlicerError: Error, LocalizedError {
    case ffmpegNotFound
    case sliceFailed(Int32, String)
    case silenceGenFailed(Int32, String)

    public var errorDescription: String? {
        switch self {
        case .ffmpegNotFound:
            return "ffmpeg not found. Install via Homebrew: brew install ffmpeg"
        case .sliceFailed(let code, let msg):
            return "ffmpeg slice failed (\(code)): \(msg)"
        case .silenceGenFailed(let code, let msg):
            return "ffmpeg silence generation failed (\(code)): \(msg)"
        }
    }
}

public enum AudioSlicer {

    static let ffmpegPath = "/opt/homebrew/bin/ffmpeg"

    // MARK: - Single clip extraction

    /// Slice `sourceURL` from `startSec` to `endSec`, writing mono 48kHz AAC 128k to `destinationURL`.
    /// Uses ffmpeg -ss / -to flags (fast seek then exact cut).
    public static func slice(
        source: URL,
        startSec: Double,
        endSec: Double,
        destination: URL
    ) async throws {
        guard FileManager.default.fileExists(atPath: ffmpegPath) else {
            throw AudioSlicerError.ffmpegNotFound
        }

        // Ensure destination parent directory exists
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        // Remove stale output if present
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination.path.asURL)
        }

        let duration = max(endSec - startSec, 0.1)
        let args: [String] = [
            "-y",
            "-ss", String(format: "%.3f", startSec),
            "-i", source.path,
            "-t", String(format: "%.3f", duration),
            "-ac", "1",            // mono
            "-ar", "48000",        // 48 kHz
            "-c:a", "aac",
            "-b:a", "128k",
            destination.path
        ]

        try await runFFmpeg(args: args, errorType: { AudioSlicerError.sliceFailed($0, $1) })
    }

    // MARK: - Silence clip

    /// Generate (or reuse) a 1-second mono 48kHz silence .m4a at `destination`.
    /// Creates the file once; subsequent calls skip generation if file already exists.
    public static func ensureSilenceClip(at destination: URL) async throws {
        guard FileManager.default.fileExists(atPath: ffmpegPath) else {
            throw AudioSlicerError.ffmpegNotFound
        }
        if FileManager.default.fileExists(atPath: destination.path) { return }

        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let args: [String] = [
            "-y",
            "-f", "lavfi",
            "-i", "anullsrc=channel_layout=mono:sample_rate=48000",
            "-t", "1",
            "-c:a", "aac",
            "-b:a", "128k",
            destination.path
        ]

        try await runFFmpeg(args: args, errorType: { AudioSlicerError.silenceGenFailed($0, $1) })
    }

    // MARK: - Concat multiple clips

    /// Concatenate `clips` (in order) with `silenceURL` inserted between each pair.
    /// Writes result to `destination` as mono 48kHz AAC 128k .m4a.
    /// Uses ffmpeg concat demuxer (copy codec — fast).
    public static func concat(
        clips: [URL],
        silenceURL: URL,
        destination: URL
    ) async throws {
        guard FileManager.default.fileExists(atPath: ffmpegPath) else {
            throw AudioSlicerError.ffmpegNotFound
        }
        guard !clips.isEmpty else { return }

        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        // Build concat list file in /tmp
        let listURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("gather-concat-list-\(UUID().uuidString).txt")

        var lines: [String] = []
        for (i, clip) in clips.enumerated() {
            lines.append("file '\(clip.path.replacingOccurrences(of: "'", with: "\\'"))'")
            if i < clips.count - 1 {
                lines.append("file '\(silenceURL.path.replacingOccurrences(of: "'", with: "\\'"))'")
            }
        }
        try lines.joined(separator: "\n").write(to: listURL, atomically: true, encoding: .utf8)

        defer { try? FileManager.default.removeItem(at: listURL) }

        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination.path.asURL)
        }

        let args: [String] = [
            "-y",
            "-f", "concat",
            "-safe", "0",
            "-i", listURL.path,
            "-c:a", "aac",
            "-b:a", "128k",
            destination.path
        ]

        try await runFFmpeg(args: args, errorType: { AudioSlicerError.sliceFailed($0, $1) })
    }

    // MARK: - Private

    private static func runFFmpeg(
        args: [String],
        errorType: @escaping (Int32, String) -> AudioSlicerError
    ) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpegPath)
        process.arguments = args

        var env = ProcessInfo.processInfo.environment
        let existingPath = env["PATH"] ?? ""
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:\(existingPath)"
        process.environment = env

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            process.terminationHandler = { proc in
                if proc.terminationStatus == 0 {
                    cont.resume()
                } else {
                    let data = (try? errPipe.fileHandleForReading.readToEnd()) ?? Data()
                    let stderr = String(data: data, encoding: .utf8) ?? "unknown"
                    cont.resume(throwing: errorType(proc.terminationStatus, String(stderr.suffix(400))))
                }
            }
            do {
                try process.run()
            } catch {
                cont.resume(throwing: error)
            }
        }
    }

    // MARK: - Slug helper

    /// Convert a label string to a safe filename slug.
    public static func slugify(_ text: String) -> String {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
    }
}

// MARK: - Convenience

private extension String {
    var asURL: URL { URL(fileURLWithPath: self) }
}
