import Foundation

public enum WorldUploaderError: Error, CustomStringConvertible {
    case uploadFailed(String, Int32)
    case catalogRefreshFailed(Error)

    public var description: String {
        switch self {
        case .uploadFailed(let key, let code): return "Upload of \(key) failed (exit \(code))"
        case .catalogRefreshFailed(let e): return "Catalog refresh failed: \(e)"
        }
    }
}

/// Uploads a RenderedWorld (local bundle from WorldRenderer) to R2 and refreshes
/// catalog.json so existing players (Fascinated Field, Presets3) see the new World.
///
/// Layout in `cloud-to-float-on`:
///   stems/spatial-mix/composed/<slug>/bed.m4a
///   stems/spatial-mix/composed/<slug>/obj-NN.m4a
///   stems/spatial-mix/composed/<slug>/manifest.json
///
/// The catalog entry `filename` is set to `composed/<slug>/manifest.json` so
/// Fascinated Field resolves the full key as:
///   stems/spatial-mix/composed/<slug>/manifest.json
@MainActor
public final class WorldUploader {

    private let uploader: R2Uploader

    public init() {
        self.uploader = R2Uploader()
    }

    /// Uploads every file in `rendered.bundleDirectory` to
    /// `stems/spatial-mix/composed/<slug>/`, then updates catalog.json.
    ///
    /// Returns the R2 prefix on success.
    public func uploadRendered(_ rendered: RenderedWorld,
                               title: String,
                               durationSec: Double) async throws -> String {
        let slug = rendered.bundleDirectory.lastPathComponent
        let r2Prefix = "stems/spatial-mix/composed/\(slug)/"
        let result = try await uploader.uploadFolder(
            localFolder: rendered.bundleDirectory,
            r2Prefix: r2Prefix)
        // refreshCatalog for composed worlds — pass the slug and title;
        // the slug is used to build the composed-specific manifest path.
        await refreshComposedCatalog(slug: slug, title: title, durationSec: durationSec)
        return result.r2Prefix
    }

    // MARK: - Composed-world catalog refresh

    /// Patches catalog.json with a `composed/<slug>/manifest.json` filename —
    /// distinct from the field-recording path that R2Uploader.refreshCatalog writes.
    private func refreshComposedCatalog(slug: String, title: String, durationSec: Double) async {
        let awsPath = findAWS()
        guard let awsPath else {
            print("[WorldUploader] aws CLI not found — skipping catalog update")
            return
        }

        let bucket = "cloud-to-float-on"
        let accountId = "6a378e6919e5a3f1cbd84db6c1ad5443"
        let endpoint = "https://\(accountId).r2.cloudflarestorage.com"
        let catalogKey = "catalog.json"
        let s3CatalogPath = "s3://\(bucket)/\(catalogKey)"
        let localTemp = FileManager.default.temporaryDirectory
            .appendingPathComponent("catalog_wu_\(UUID().uuidString).json")

        defer { try? FileManager.default.removeItem(at: localTemp) }

        // 1. Download existing catalog.json
        do {
            try await runAWS(awsPath: awsPath, endpoint: endpoint, arguments: [
                "s3", "cp", s3CatalogPath, localTemp.path,
                "--endpoint-url", endpoint, "--no-progress"
            ])
        } catch {
            print("[WorldUploader] Could not download catalog.json: \(error) — skipping")
            return
        }

        // 2. Parse
        guard let rawData = try? Data(contentsOf: localTemp),
              var root = (try? JSONSerialization.jsonObject(with: rawData)) as? [String: Any] else {
            print("[WorldUploader] catalog.json parse error — skipping")
            return
        }

        // 3. Merge entry — filename points to `composed/<slug>/manifest.json` so FF
        //    resolves it under stems/spatial-mix/
        var tracks = root["tracks"] as? [[String: Any]] ?? []
        let filename = "composed/\(slug)/manifest.json"
        let newEntry: [String: Any] = [
            "id": slug,
            "name": title,
            "filename": filename,
            "category": "spatialMix"
        ]
        tracks.removeAll { ($0["id"] as? String) == slug }
        tracks.append(newEntry)
        tracks.sort {
            let a = $0["id"] as? String ?? ""
            let b = $1["id"] as? String ?? ""
            return a < b
        }
        root["tracks"] = tracks

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        root["updated"] = iso.string(from: Date())

        // 4. Write back
        guard let updatedData = try? JSONSerialization.data(
            withJSONObject: root, options: [.prettyPrinted, .sortedKeys]) else {
            print("[WorldUploader] JSON encode error — skipping")
            return
        }
        do { try updatedData.write(to: localTemp) } catch {
            print("[WorldUploader] Write temp failed: \(error) — skipping")
            return
        }

        // 5. Upload catalog.json
        do {
            try await runAWS(awsPath: awsPath, endpoint: endpoint, arguments: [
                "s3", "cp", localTemp.path, s3CatalogPath,
                "--endpoint-url", endpoint,
                "--content-type", "application/json",
                "--no-progress"
            ])
            print("[WorldUploader] catalog.json updated: slug=\(slug)")
        } catch {
            print("[WorldUploader] catalog.json upload failed: \(error)")
        }
    }

    // MARK: - Helpers

    private func runAWS(awsPath: String, endpoint: String, arguments: [String]) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: awsPath)
        process.arguments = arguments
        process.environment = R2Uploader.awsEnvironment
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
                    cont.resume(throwing: WorldUploaderError.uploadFailed(
                        arguments.last ?? "?", proc.terminationStatus))
                    _ = stderr
                }
            }
            do { try process.run() } catch { cont.resume(throwing: error) }
        }
    }

    private func findAWS() -> String? {
        let candidates = ["/opt/homebrew/bin/aws", "/usr/local/bin/aws", "/usr/bin/aws"]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}
