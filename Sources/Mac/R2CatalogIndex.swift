import Foundation

// ---------------------------------------------------------------------------
// R2CatalogIndex — downloads samples/index.json + per-source events.json from
// R2 and maintains a searchable in-memory list of every detected sound event.
// Cache lives under <stagingDirectory>/library-cache/ (always on external drive).
// ---------------------------------------------------------------------------

public enum R2CatalogIndexError: Error, LocalizedError {
    case awsNotFound
    case downloadFailed(Int32, String)
    case badJSON(String, Error)
    case cacheNotOnExternalDrive(String)

    public var errorDescription: String? {
        switch self {
        case .awsNotFound:
            return "AWS CLI not found. Install it via Homebrew: brew install awscli"
        case .downloadFailed(let code, let msg):
            return "Download failed (\(code)): \(msg)"
        case .badJSON(let key, let err):
            return "Could not parse \(key): \(err)"
        case .cacheNotOnExternalDrive(let path):
            return "Cache path is not on an external drive: \(path). Check staging directory settings."
        }
    }
}

@MainActor
public final class R2CatalogIndex: ObservableObject {

    // MARK: - Published state

    @Published public private(set) var allEvents: [IndexedEvent] = []
    @Published public private(set) var sources: [SourceSummary] = []
    @Published public private(set) var isLoading: Bool = false
    @Published public private(set) var lastUpdated: Date?
    @Published public private(set) var loadError: String?

    // MARK: - Types

    public struct IndexedEvent: Identifiable, Equatable, Sendable {
        public let id: UUID = UUID()
        public let sourceSlug: String
        public let sourceCategory: String   // "zoom-bounces" / "zylia-bounces"
        public let startSec: Double
        public let endSec: Double
        public let label: String            // species common name or category label
        public let scientific: String?
        public let confidence: Double
        public let source: String           // "birdnet" / "apple-soundanalysis"

        public var durationSec: Double { endSec - startSec }
    }

    public struct SourceSummary: Identifiable, Sendable {
        public let id: String               // slug
        public let sourceCategory: String
        public let durationSec: Double
        public let speciesCount: Int
        public let sampleCount: Int
    }

    // MARK: - R2 config (mirrors R2Uploader — no duplication of credentials)

    private let accountId: String = "6a378e6919e5a3f1cbd84db6c1ad5443"
    private let accessKey: String = "97545dddf4f1f07559999dceed884792"
    private let secretKey: String = "3d7187bcc70bcbe9fbd0b0ea773eb751dd13d18cb2beb8c7256835310c968de0"
    private let bucket: String = "cloud-to-float-on"
    private let region: String = "auto"
    private var endpoint: String { "https://\(accountId).r2.cloudflarestorage.com" }

    // MARK: - Cache

    /// Cache root — always on external drive (enforced in cacheDirectory).
    private let stagingDirectory: URL

    private var cacheDirectory: URL {
        stagingDirectory.appendingPathComponent("library-cache")
    }

    public init(stagingDirectory: URL) {
        self.stagingDirectory = stagingDirectory
    }

    // MARK: - Public API

    /// Download samples/index.json, then each source's events.json.
    /// Safe to call multiple times — uses on-disk cache if files exist,
    /// re-downloads only when explicitly requested via refresh().
    public func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        loadError = nil
        defer { isLoading = false }

        do {
            try ensureCacheDirectoryOnExternalDrive()
        } catch let e as R2CatalogIndexError {
            loadError = e.errorDescription
            return
        } catch {
            loadError = error.localizedDescription
            return
        }

        do {
            // 1. Download samples/index.json
            let indexKey = "samples/index.json"
            let localIndex = cacheDirectory.appendingPathComponent("samples-index.json")
            try await downloadR2Key(indexKey, to: localIndex)

            // 2. Parse index to get source slugs + categories
            let indexData = try Data(contentsOf: localIndex)
            guard let indexRoot = try JSONSerialization.jsonObject(with: indexData) as? [String: Any] else {
                throw R2CatalogIndexError.badJSON("samples/index.json", NSError(domain: "R2CatalogIndex", code: 0))
            }

            // Build SourceSummary from the index
            var newSources: [SourceSummary] = []
            var newEvents: [IndexedEvent] = []

            // The index has a "sources" array with { slug, category, duration, speciesCount, sampleCount }
            // OR it may have a "recordings" array — handle both gracefully.
            let sourcesArray = (indexRoot["sources"] as? [[String: Any]])
                ?? (indexRoot["recordings"] as? [[String: Any]])
                ?? []

            for sourceDict in sourcesArray {
                guard let slug = sourceDict["slug"] as? String,
                      let category = sourceDict["category"] as? String else { continue }

                let durationSec = sourceDict["durationSec"] as? Double
                    ?? sourceDict["duration"] as? Double
                    ?? 0.0
                let speciesCount = sourceDict["speciesCount"] as? Int ?? 0
                let sampleCount = sourceDict["sampleCount"] as? Int ?? 0

                let summary = SourceSummary(
                    id: slug,
                    sourceCategory: category,
                    durationSec: durationSec,
                    speciesCount: speciesCount,
                    sampleCount: sampleCount
                )
                newSources.append(summary)

                // 3. Download events.json for this source
                // Key pattern: stems/spatial-mix/field-recording/<category>/<slug>/events.json
                let eventsKey = "stems/spatial-mix/field-recording/\(category)/\(slug)/events.json"
                let localEvents = cacheDirectory
                    .appendingPathComponent(slug)
                    .appendingPathComponent("events.json")

                do {
                    try await downloadR2Key(eventsKey, to: localEvents)
                    let events = try parseEventsJSON(at: localEvents, slug: slug, category: category)
                    newEvents.append(contentsOf: events)
                } catch {
                    // Non-fatal: if events.json is missing for a source, skip it
                    print("[R2CatalogIndex] Could not load events for \(slug): \(error)")
                }
            }

            // If sources array was empty in index, try deriving sources from top-level slugs list
            if newSources.isEmpty {
                if let slugs = indexRoot["slugs"] as? [String] {
                    for slug in slugs {
                        // Default category — zoom-bounces for backward compat
                        let category = "zoom-bounces"
                        let eventsKey = "stems/spatial-mix/field-recording/\(category)/\(slug)/events.json"
                        let localEvents = cacheDirectory
                            .appendingPathComponent(slug)
                            .appendingPathComponent("events.json")
                        do {
                            try await downloadR2Key(eventsKey, to: localEvents)
                            let events = try parseEventsJSON(at: localEvents, slug: slug, category: category)
                            newEvents.append(contentsOf: events)
                            let summary = SourceSummary(
                                id: slug,
                                sourceCategory: category,
                                durationSec: 0,
                                speciesCount: Set(events.map { $0.label }).count,
                                sampleCount: events.count
                            )
                            newSources.append(summary)
                        } catch {
                            print("[R2CatalogIndex] Could not load events for \(slug): \(error)")
                        }
                    }
                }
            }

            self.sources = newSources.sorted { $0.id < $1.id }
            self.allEvents = newEvents.sorted { $0.startSec < $1.startSec }
            self.lastUpdated = Date()
            print("[R2CatalogIndex] Loaded \(newSources.count) sources, \(newEvents.count) events")

        } catch {
            loadError = error.localizedDescription
            print("[R2CatalogIndex] refresh failed: \(error)")
        }
    }

    /// Filter allEvents by query, confidence, and optional source slug.
    public func filtered(query: String, minConfidence: Double, sourceSlug: String?) -> [IndexedEvent] {
        allEvents.filter { event in
            (minConfidence == 0 || event.confidence >= minConfidence)
            && (sourceSlug == nil || event.sourceSlug == sourceSlug!)
            && (query.isEmpty
                || event.label.localizedCaseInsensitiveContains(query)
                || (event.scientific?.localizedCaseInsensitiveContains(query) ?? false)
                || event.sourceSlug.localizedCaseInsensitiveContains(query))
        }
    }

    // MARK: - Local bed.m4a lookup

    /// Returns the URL of bed.m4a for `slug`, either from the local convert cache
    /// (staging/converted/<slug>/bed.m4a) or the library download cache.
    /// If neither exists, returns the library-cache URL where it should be downloaded.
    public func bedURL(for slug: String, category: String) -> (url: URL, isLocal: Bool) {
        let convertedBed = stagingDirectory
            .appendingPathComponent("converted")
            .appendingPathComponent(slug)
            .appendingPathComponent("bed.m4a")
        if FileManager.default.fileExists(atPath: convertedBed.path) {
            return (convertedBed, true)
        }
        let cacheBed = cacheDirectory
            .appendingPathComponent(slug)
            .appendingPathComponent("bed.m4a")
        return (cacheBed, FileManager.default.fileExists(atPath: cacheBed.path))
    }

    /// Download bed.m4a for `slug` from R2 to the library cache.
    /// Returns the local URL.
    public func downloadBed(slug: String, category: String) async throws -> URL {
        let r2Key = "stems/spatial-mix/field-recording/\(category)/\(slug)/bed.m4a"
        let localURL = cacheDirectory
            .appendingPathComponent(slug)
            .appendingPathComponent("bed.m4a")
        try await downloadR2Key(r2Key, to: localURL)
        return localURL
    }

    // MARK: - Private helpers

    private func ensureCacheDirectoryOnExternalDrive() throws {
        let path = cacheDirectory.path
        // Verify the cache path is on an external volume (not internal SSD)
        let isExternal = path.hasPrefix("/Volumes/")
        guard isExternal else {
            throw R2CatalogIndexError.cacheNotOnExternalDrive(path)
        }
        try FileManager.default.createDirectory(at: cacheDirectory,
                                                 withIntermediateDirectories: true)
    }

    /// Download a single R2 key to a local path, creating parent directories as needed.
    private func downloadR2Key(_ key: String, to localURL: URL) async throws {
        let awsPath = findAWS() ?? "/opt/homebrew/bin/aws"
        guard FileManager.default.fileExists(atPath: awsPath) else {
            throw R2CatalogIndexError.awsNotFound
        }

        try FileManager.default.createDirectory(
            at: localURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let s3Path = "s3://\(bucket)/\(key)"
        try await runAWS(awsPath: awsPath, arguments: [
            "s3", "cp",
            "--endpoint-url", endpoint,
            "--region", region,
            "--no-progress",
            s3Path, localURL.path
        ])
    }

    private func parseEventsJSON(at url: URL,
                                 slug: String,
                                 category: String) throws -> [IndexedEvent] {
        let data = try Data(contentsOf: url)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw R2CatalogIndexError.badJSON(url.lastPathComponent, NSError(domain: "R2CatalogIndex", code: 1))
        }

        // events.json shape: { "events": [ { "label", "scientific"?, "confidence", "startSec", "endSec", "source" }, ... ] }
        // OR a top-level array.
        let eventDicts: [[String: Any]]
        if let arr = root["events"] as? [[String: Any]] {
            eventDicts = arr
        } else if let arr = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            eventDicts = arr
        } else {
            return []
        }

        return eventDicts.compactMap { dict -> IndexedEvent? in
            guard let label = dict["label"] as? String,
                  let startSec = dict["startSec"] as? Double,
                  let endSec = dict["endSec"] as? Double else { return nil }

            let confidence = dict["confidence"] as? Double ?? 1.0
            let source = dict["source"] as? String ?? "birdnet"
            let scientific = dict["scientific"] as? String

            return IndexedEvent(
                sourceSlug: slug,
                sourceCategory: category,
                startSec: startSec,
                endSec: endSec,
                label: label,
                scientific: scientific,
                confidence: confidence,
                source: source
            )
        }
    }

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
                    cont.resume(throwing: R2CatalogIndexError.downloadFailed(
                        proc.terminationStatus,
                        String(stderr.prefix(300))
                    ))
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
        ["/opt/homebrew/bin/aws", "/usr/local/bin/aws"]
            .first { FileManager.default.fileExists(atPath: $0) }
    }
}
