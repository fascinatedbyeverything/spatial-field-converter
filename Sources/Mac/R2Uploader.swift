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

    /// Environment dictionary for aws CLI subprocesses — exposes the R2 credentials
    /// so WorldRenderer (and any future tool that shells out to aws) can share the
    /// same source-of-truth without duplicating credential values.
    public static var awsEnvironment: [String: String] {
        let instance = R2Uploader()
        return [
            "AWS_ACCESS_KEY_ID": instance.accessKey,
            "AWS_SECRET_ACCESS_KEY": instance.secretKey,
            "AWS_DEFAULT_REGION": instance.region,
            "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        ]
    }

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

    // MARK: - Catalog Refresh

    /// Download catalog.json from R2, merge a new spatial-mix entry for `slug`,
    /// and upload catalog.json back. If anything fails, the error is logged but
    /// the upload is NOT marked as failed — the files are already in R2.
    ///
    /// - Parameters:
    ///   - slug: The identifier used as the R2 folder name (e.g. "backyard-…-d53c1b")
    ///   - title: Human-readable display name (e.g. "backyard woodland hills may 14 2026")
    ///   - durationSec: Duration in seconds (read from manifest.json)
    ///
    /// The entry is stored with:
    ///   `id`       = slug
    ///   `name`     = title (localizedCapitalized)
    ///   `filename` = "field-recording/zoom-bounces/<slug>/manifest.json"
    ///   `category` = "spatialMix"
    ///
    /// `filename` intentionally includes the sub-path and `/manifest.json` so
    /// Fascinated Field's `downloadSpatialMix(_:)` can build the correct R2 key:
    ///   `stems/spatial-mix/field-recording/zoom-bounces/<slug>/manifest.json`
    public func refreshCatalog(slug: String, title: String, durationSec: Double) async {
        let awsPath = findAWS() ?? "/opt/homebrew/bin/aws"
        guard FileManager.default.fileExists(atPath: awsPath) else {
            print("[CatalogRefresh] aws CLI not found — skipping catalog update")
            return
        }

        let catalogKey = "catalog.json"
        let s3CatalogPath = "s3://\(bucket)/\(catalogKey)"
        let localTemp = FileManager.default.temporaryDirectory
            .appendingPathComponent("catalog_sfc_\(UUID().uuidString).json")

        defer { try? FileManager.default.removeItem(at: localTemp) }

        // 1. Download existing catalog.json
        do {
            try await runAWS(awsPath: awsPath, arguments: [
                "s3", "cp", s3CatalogPath, localTemp.path,
                "--endpoint-url", endpoint,
                "--region", region,
                "--no-progress"
            ])
            print("[CatalogRefresh] Downloaded catalog.json")
        } catch {
            print("[CatalogRefresh] Could not download catalog.json: \(error) — skipping catalog update")
            return
        }

        // 2. Parse as raw JSON to preserve unknown fields
        let rawData: Data
        do {
            rawData = try Data(contentsOf: localTemp)
        } catch {
            print("[CatalogRefresh] Could not read local catalog.json: \(error) — skipping")
            return
        }

        var root: [String: Any]
        do {
            guard let parsed = try JSONSerialization.jsonObject(with: rawData) as? [String: Any] else {
                print("[CatalogRefresh] catalog.json is not a JSON object — skipping")
                return
            }
            root = parsed
        } catch {
            print("[CatalogRefresh] JSON parse error: \(error) — skipping")
            return
        }

        // 3. Merge the new entry into the tracks array
        var tracks = root["tracks"] as? [[String: Any]] ?? []
        let entryBefore = tracks.count

        // The filename encodes the full sub-path so FF can resolve:
        //   stems/spatial-mix/<filename>  →  stems/spatial-mix/field-recording/zoom-bounces/<slug>/manifest.json
        let filename = "field-recording/zoom-bounces/\(slug)/manifest.json"

        let newEntry: [String: Any] = [
            "id": slug,
            "name": title,
            "filename": filename,
            "category": "spatialMix"
        ]

        // Remove any existing entry with the same slug (update in place, not duplicate)
        tracks.removeAll { ($0["id"] as? String) == slug }
        tracks.append(newEntry)

        // Re-sort alphabetically by id (matches CatalogGenerator behavior)
        tracks.sort {
            let a = $0["id"] as? String ?? ""
            let b = $1["id"] as? String ?? ""
            return a < b
        }

        let entryAfter = tracks.count
        root["tracks"] = tracks

        // Update the `updated` timestamp
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        root["updated"] = iso.string(from: Date())

        // 4. Write back to temp file
        do {
            let updatedData = try JSONSerialization.data(withJSONObject: root,
                                                          options: [.prettyPrinted, .sortedKeys])
            try updatedData.write(to: localTemp)
        } catch {
            print("[CatalogRefresh] JSON encode error: \(error) — skipping")
            return
        }

        // 5. Upload catalog.json back to R2
        do {
            try await runAWS(awsPath: awsPath, arguments: [
                "s3", "cp", localTemp.path, s3CatalogPath,
                "--endpoint-url", endpoint,
                "--region", region,
                "--content-type", "application/json",
                "--no-progress"
            ])
            print("[CatalogRefresh] Uploaded catalog.json: \(entryBefore) → \(entryAfter) tracks, slug=\(slug)")
        } catch {
            print("[CatalogRefresh] Upload of catalog.json failed: \(error)")
        }
    }

    // MARK: - Private Helpers

    /// Run aws CLI with the given arguments. Throws on non-zero exit.
    private func runAWS(awsPath: String, arguments: [String]) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: awsPath)
        process.arguments = arguments
        process.environment = [
            "AWS_ACCESS_KEY_ID": accessKey,
            "AWS_SECRET_ACCESS_KEY": secretKey,
            "AWS_DEFAULT_REGION": region,
            "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        ]
        let errPipe = Pipe()
        process.standardError = errPipe
        process.standardOutput = FileHandle.nullDevice

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            process.terminationHandler = { proc in
                if proc.terminationStatus == 0 {
                    cont.resume()
                } else {
                    let data = (try? errPipe.fileHandleForReading.readToEnd()) ?? Data()
                    let stderr = String(data: data, encoding: .utf8) ?? "unknown"
                    cont.resume(throwing: R2UploaderError.awsFailed(proc.terminationStatus, String(stderr.prefix(300))))
                }
            }
            do {
                try process.run()
            } catch {
                cont.resume(throwing: error)
            }
        }
    }

    private func findAWS() -> String? {
        let candidates = ["/opt/homebrew/bin/aws", "/usr/local/bin/aws"]
        return candidates.first { FileManager.default.fileExists(atPath: $0) }
    }
}
