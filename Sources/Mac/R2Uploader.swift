import Foundation

public enum R2UploaderError: Error, CustomStringConvertible {
    case awsNotFound
    case awsFailed(Int32, String)
    case missingResource(String)

    public var description: String {
        switch self {
        case .awsNotFound: return "AWS CLI not found on PATH"
        case .awsFailed(let code, let stderr): return "aws s3 cp failed (\(code)): \(stderr)"
        case .missingResource(let name): return "missing resource: \(name)"
        }
    }
}

public struct R2UploadResult: Sendable {
    public let r2Prefix: String
}

/// Uploads a staging folder (manifest.json + bed.m4a + obj-NN.m4a) to R2 and
/// updates catalog.json. Uses the same hardcoded R2 credentials as Cloud Uploader.
///
/// Not thread-safe for concurrent invocations; create one uploader per upload.
public final class R2Uploader {

    // R2 / S3-compatible endpoint — same as Cloud Uploader.
    // Credentials extracted from cloud-uploader/Sources/R2Uploader.swift lines 95-97.
    private let accountId: String = "6a378e6919e5a3f1cbd84db6c1ad5443"
    private let accessKey: String = "97545dddf4f1f07559999dceed884792"
    private let secretKey: String = "3d7187bcc70bcbe9fbd0b0ea773eb751dd13d18cb2beb8c7256835310c968de0"
    private let bucket: String = "cloud-to-float-on"
    private let region: String = "auto"

    private var endpoint: String { "https://\(accountId).r2.cloudflarestorage.com" }

    public init() {}

    /// Upload a folder full of files (recursively) to s3://<bucket>/<prefix>.
    /// Returns the prefix on success.
    public func uploadFolder(localFolder: URL, r2Prefix: String) async throws -> R2UploadResult {
        let awsPath = findAWS() ?? "/opt/homebrew/bin/aws"
        guard FileManager.default.fileExists(atPath: awsPath) else {
            throw R2UploaderError.awsNotFound
        }

        let destination = "s3://\(bucket)/\(r2Prefix)"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: awsPath)
        process.arguments = [
            "s3", "cp", "--recursive",
            "--endpoint-url", endpoint,
            "--region", region,
            "--no-progress",
            localFolder.path, destination
        ]
        process.environment = [
            "AWS_ACCESS_KEY_ID": accessKey,
            "AWS_SECRET_ACCESS_KEY": secretKey,
            "AWS_DEFAULT_REGION": region,
            "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        ]
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

        let stderr = (try? errPipe.fileHandleForReading.readToEnd())
            .flatMap { String(data: $0, encoding: .utf8) } ?? ""
        if process.terminationStatus != 0 {
            throw R2UploaderError.awsFailed(process.terminationStatus, stderr)
        }

        print("[R2Uploader] Uploaded \(localFolder.path) → \(destination)")
        return R2UploadResult(r2Prefix: r2Prefix)
    }

    private func findAWS() -> String? {
        let candidates = ["/opt/homebrew/bin/aws", "/usr/local/bin/aws"]
        return candidates.first { FileManager.default.fileExists(atPath: $0) }
    }
}
