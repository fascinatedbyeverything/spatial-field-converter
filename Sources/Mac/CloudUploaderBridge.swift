import Foundation

public enum CloudUploaderBridgeError: Error, CustomStringConvertible {
    case uploaderNotFound(URL)
    case uploaderExitedNonZero(Int32, String)
    case spawnFailed(String)
    case inputFileMissing(URL)

    public var description: String {
        switch self {
        case .uploaderNotFound(let u): return "Cloud Uploader executable not found at \(u.path)"
        case .uploaderExitedNonZero(let code, let stderr): return "Cloud Uploader exited \(code): \(stderr)"
        case .spawnFailed(let m): return "Failed to spawn Cloud Uploader: \(m)"
        case .inputFileMissing(let u): return "ADM BWF input file missing: \(u.path)"
        }
    }
}

public struct CloudUploaderBridgeResult: Sendable {
    /// The R2 key prefix where the spatial-mix bundle was uploaded
    /// (e.g. "stems/spatial-mix/field-recording/<slug>/").
    public let r2Key: String
}

/// Spawns the Cloud Uploader Mac app as a subprocess with its --process-adm-bwf CLI flag.
/// The subprocess does the ADM BWF → bed.m4a + obj-NN.m4a conversion via its existing pipeline
/// and uploads the result to R2 (bucket cloud-to-float-on, prefix stems/spatial-mix/<category>/<slug>/).
///
/// Not thread-safe for concurrent invocations; create one bridge per upload OR serialize calls.
public final class CloudUploaderBridge {
    private let executableURL: URL

    public init(uploaderExecutableURL: URL) {
        self.executableURL = uploaderExecutableURL
    }

    public func uploadADMBWF(
        admBwfURL: URL,
        programmeName: String,
        category: String
    ) async throws -> CloudUploaderBridgeResult {
        guard FileManager.default.fileExists(atPath: executableURL.path) else {
            throw CloudUploaderBridgeError.uploaderNotFound(executableURL)
        }
        guard FileManager.default.fileExists(atPath: admBwfURL.path) else {
            throw CloudUploaderBridgeError.inputFileMissing(admBwfURL)
        }

        let process = Process()
        process.executableURL = executableURL
        var args: [String] = ["--process-adm-bwf", admBwfURL.path]
        if !category.isEmpty {
            args.append("--category")
            args.append(category)
        }
        if !programmeName.isEmpty {
            args.append("--name")
            args.append(programmeName)
        }
        process.arguments = args

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
        } catch {
            throw CloudUploaderBridgeError.spawnFailed(error.localizedDescription)
        }

        // Wait for process to exit on a background queue so the caller's async task suspends correctly.
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            DispatchQueue.global().async {
                process.waitUntilExit()
                cont.resume()
            }
        }

        // Read pipes AFTER the process has fully exited to avoid partial reads.
        let stdoutData = (try? outPipe.fileHandleForReading.readToEnd()) ?? Data()
        let stderrData = (try? errPipe.fileHandleForReading.readToEnd()) ?? Data()
        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""

        if process.terminationStatus != 0 {
            throw CloudUploaderBridgeError.uploaderExitedNonZero(process.terminationStatus, stderr)
        }

        // Parse the "uploaded: <key>" line from stdout. If absent, return an empty key
        // (the upload still succeeded; the caller can hit R2 to confirm).
        var r2Key = ""
        for line in stdout.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("uploaded:") {
                r2Key = String(trimmed.dropFirst("uploaded:".count)).trimmingCharacters(in: .whitespaces)
                break
            }
        }

        return CloudUploaderBridgeResult(r2Key: r2Key)
    }
}
