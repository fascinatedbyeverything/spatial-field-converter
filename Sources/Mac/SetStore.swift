import Foundation

public enum SetStoreError: Error, CustomStringConvertible {
    case localDirCreationFailed(URL, Error)
    case writeFailed(URL, Error)
    case readFailed(URL, Error)
    case r2UploadFailed(String, Int32)
    case r2FetchFailed(String, Int32)
    case decodeFailed(String, Error)

    public var description: String {
        switch self {
        case .localDirCreationFailed(let u, let e): return "Could not create \(u.path): \(e)"
        case .writeFailed(let u, let e): return "Could not write \(u.path): \(e)"
        case .readFailed(let u, let e): return "Could not read \(u.path): \(e)"
        case .r2UploadFailed(let k, let s): return "R2 upload \(k) failed (exit \(s))"
        case .r2FetchFailed(let k, let s): return "R2 fetch \(k) failed (exit \(s))"
        case .decodeFailed(let k, let e): return "Decode \(k) failed: \(e)"
        }
    }
}

/// Local + R2 persistence for curated Sets.
///
/// Local: `<appSupport>/SpatialFieldConverter/sets/<slug>.json` — eager autosave.
/// R2:    `sets/<slug>/set.json` in `cloud-to-float-on` bucket — explicit publish.
///
/// No merge logic. Last-write-wins on R2. List is derived from the local directory
/// (plus an optional R2-list fetch in `fetchRemoteSlugs()`).
@MainActor
public final class SetStore {

    private let bucket = "cloud-to-float-on"
    private let r2Endpoint = "https://6a378e6919e5a3f1cbd84db6c1ad5443.r2.cloudflarestorage.com"
    private let localDirectory: URL

    public init(localDirectory: URL? = nil) throws {
        if let d = localDirectory {
            self.localDirectory = d
        } else {
            let appSupport = try FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask,
                appropriateFor: nil, create: true)
            self.localDirectory = appSupport
                .appendingPathComponent("SpatialFieldConverter", isDirectory: true)
                .appendingPathComponent("sets", isDirectory: true)
        }
        do {
            try FileManager.default.createDirectory(
                at: self.localDirectory, withIntermediateDirectories: true)
        } catch {
            throw SetStoreError.localDirCreationFailed(self.localDirectory, error)
        }
    }

    public var localStorageURL: URL { localDirectory }

    // MARK: - Local

    public func saveLocal(_ set: SetData) throws {
        let url = localDirectory.appendingPathComponent("\(set.slug).json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        do {
            let data = try encoder.encode(set)
            try data.write(to: url, options: .atomic)
        } catch {
            throw SetStoreError.writeFailed(url, error)
        }
    }

    public func loadLocal(slug: String) throws -> SetData {
        let url = localDirectory.appendingPathComponent("\(slug).json")
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw SetStoreError.readFailed(url, error)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(SetData.self, from: data)
        } catch {
            throw SetStoreError.decodeFailed(slug, error)
        }
    }

    public func listLocalSlugs() -> [String] {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: localDirectory, includingPropertiesForKeys: nil) else {
            return []
        }
        return entries
            .filter { $0.pathExtension == "json" }
            .map { $0.deletingPathExtension().lastPathComponent }
            .sorted()
    }

    public func deleteLocal(slug: String) throws {
        let url = localDirectory.appendingPathComponent("\(slug).json")
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    // MARK: - R2 (explicit publish + fetch)

    /// Publish `set` to R2 at `sets/<slug>/set.json`. Async because it shells out.
    public func publishToR2(_ set: SetData) async throws {
        let url = localDirectory.appendingPathComponent("\(set.slug).json")
        // Ensure local is up to date first so the published copy matches what's on disk.
        try saveLocal(set)
        let r2Key = "sets/\(set.slug)/set.json"
        let status = try await Self.awsS3Cp(localPath: url.path,
                                            r2URI: "s3://\(bucket)/\(r2Key)",
                                            endpoint: r2Endpoint)
        if status != 0 {
            throw SetStoreError.r2UploadFailed(r2Key, status)
        }
    }

    /// Fetch a Set from R2 by slug, write it to the local cache, and return it.
    public func fetchFromR2(slug: String) async throws -> SetData {
        let url = localDirectory.appendingPathComponent("\(slug).json")
        let r2Key = "sets/\(slug)/set.json"
        let status = try await Self.awsS3Cp(r2URI: "s3://\(bucket)/\(r2Key)",
                                            localPath: url.path,
                                            endpoint: r2Endpoint)
        if status != 0 {
            throw SetStoreError.r2FetchFailed(r2Key, status)
        }
        return try loadLocal(slug: slug)
    }

    // MARK: - aws CLI

    /// Upload: local → R2. Returns process exit status (0 = success).
    private static func awsS3Cp(localPath: String, r2URI: String, endpoint: String) async throws -> Int32 {
        return try await runAws(["s3", "cp", localPath, r2URI, "--endpoint-url", endpoint])
    }

    /// Download: R2 → local. Returns process exit status (0 = success).
    private static func awsS3Cp(r2URI: String, localPath: String, endpoint: String) async throws -> Int32 {
        return try await runAws(["s3", "cp", r2URI, localPath, "--endpoint-url", endpoint])
    }

    private static func runAws(_ args: [String]) async throws -> Int32 {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: resolveAws())
        proc.arguments = args
        proc.environment = R2Uploader.awsEnvironment
        proc.standardError = Pipe()
        proc.standardOutput = Pipe()
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Int32, Error>) in
            proc.terminationHandler = { p in cont.resume(returning: p.terminationStatus) }
            do { try proc.run() }
            catch { cont.resume(throwing: error) }
        }
    }

    private static func resolveAws() -> String {
        for candidate in ["/opt/homebrew/bin/aws", "/usr/local/bin/aws", "/usr/bin/aws"] {
            if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
        }
        return "/usr/local/bin/aws"
    }
}
