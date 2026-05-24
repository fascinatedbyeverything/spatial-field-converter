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
            // 1. One list-objects-v2 call to discover slug → category mapping.
            //    This avoids requiring a "category" field in samples/index.json,
            //    which the analyzer does not currently emit.
            let slugCategoryMap = try await discoverSlugCategories()
            print("[R2CatalogIndex] Discovered \(slugCategoryMap.count) slugs from R2 listing")

            // 2. Download samples/index.json
            let indexKey = "samples/index.json"
            let localIndex = cacheDirectory.appendingPathComponent("samples-index.json")
            try await downloadR2Key(indexKey, to: localIndex)

            // 3. Parse index to get source slugs + metadata
            let indexData = try Data(contentsOf: localIndex)
            guard let indexRoot = try JSONSerialization.jsonObject(with: indexData) as? [String: Any] else {
                throw R2CatalogIndexError.badJSON("samples/index.json", NSError(domain: "R2CatalogIndex", code: 0))
            }

            // Build SourceSummary from the R2 listing (source of truth for which
            // bundles exist), enriched by samples/index.json if the analyzer
            // metadata is present. Slugs without analyzer metadata still appear
            // — they just show zero events / unknown duration until the analyzer
            // pass runs on them.
            var newSources: [SourceSummary] = []
            var newEvents: [IndexedEvent] = []

            // Optional metadata enrichment from samples/index.json
            let sourcesArray = (indexRoot["sources"] as? [[String: Any]])
                ?? (indexRoot["recordings"] as? [[String: Any]])
                ?? []
            var indexMeta: [String: [String: Any]] = [:]
            for d in sourcesArray {
                if let slug = d["slug"] as? String { indexMeta[slug] = d }
            }

            // Primary iteration: every slug discovered in R2
            for (slug, category) in slugCategoryMap.sorted(by: { $0.key < $1.key }) {
                let meta = indexMeta[slug]
                let durationSec = meta?["durationSec"] as? Double
                    ?? meta?["duration_sec"] as? Double
                    ?? meta?["duration"] as? Double
                    ?? 0.0
                let speciesCount = meta?["speciesCount"] as? Int
                    ?? meta?["species_count"] as? Int
                    ?? 0
                let sampleCount = meta?["sampleCount"] as? Int
                    ?? meta?["sample_count"] as? Int
                    ?? 0

                // Source is added regardless of whether events.json exists.
                newSources.append(SourceSummary(
                    id: slug,
                    sourceCategory: category,
                    durationSec: durationSec,
                    speciesCount: speciesCount,
                    sampleCount: sampleCount
                ))

                // Best-effort events.json download — missing is fine.
                let eventsKey = "stems/spatial-mix/field-recording/\(category)/\(slug)/events.json"
                let localEvents = cacheDirectory
                    .appendingPathComponent(slug)
                    .appendingPathComponent("events.json")
                do {
                    try await downloadR2Key(eventsKey, to: localEvents)
                    let events = try parseEventsJSON(at: localEvents, slug: slug, category: category)
                    newEvents.append(contentsOf: events)
                } catch {
                    print("[R2CatalogIndex] No events.json for \(slug) (analyzer not run yet): \(error.localizedDescription)")
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

    /// Issue a single list-objects-v2 call under `stems/spatial-mix/field-recording/`
    /// and return a slug → category map derived from the keys that end in `/events.json`.
    /// Key shape: stems/spatial-mix/field-recording/<category>/<slug>/events.json (6 components)
    private func discoverSlugCategories() async throws -> [String: String] {
        let awsPath = findAWS() ?? "/opt/homebrew/bin/aws"
        guard FileManager.default.fileExists(atPath: awsPath) else {
            throw R2CatalogIndexError.awsNotFound
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: awsPath)
        process.arguments = [
            "s3api", "list-objects-v2",
            "--bucket", bucket,
            "--prefix", "stems/spatial-mix/field-recording/",
            "--endpoint-url", endpoint,
            "--region", region,
            "--output", "json"
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

        let outputData = (try? outPipe.fileHandleForReading.readToEnd()) ?? Data()
        guard let root = try JSONSerialization.jsonObject(with: outputData) as? [String: Any],
              let contents = root["Contents"] as? [[String: Any]] else {
            // Empty bucket prefix — return empty map, not an error
            return [:]
        }

        var map: [String: String] = [:]
        for obj in contents {
            // Discover slugs by manifest.json — every converted bundle has one.
            // events.json (analyzer output) is optional and may not exist yet.
            guard let key = obj["Key"] as? String,
                  key.hasSuffix("/manifest.json") else { continue }
            // stems/spatial-mix/field-recording/<category>/<slug>/manifest.json
            let parts = key.split(separator: "/", omittingEmptySubsequences: false)
            guard parts.count == 6 else { continue }
            let category = String(parts[3])
            let slug = String(parts[4])
            map[slug] = category
        }
        return map
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

    // MARK: - Timeline JSON

    /// Decoded timeline.json for a source recording.
    public struct TimelineData: Sendable {
        public struct Scene: Sendable {
            public let startSec: Double
            public let endSec: Double
            public let label: String
            public let dominantCategories: [String]
            public let speciesInScene: [String]
        }
        public struct Event: Sendable {
            public let timeSec: Double
            public let timeDisplay: String
            public let kind: String          // "species" | "category"
            public let label: String
            public let scientific: String?
            public let source: String
            public let confidence: Double
            public let durationSec: Double
        }
        public let scenes: [Scene]
        public let events: [Event]
    }

    /// Download timeline.json for `slug` from R2 (caches locally).
    /// R2 key: stems/spatial-mix/field-recording/<category>/<slug>/timeline.json
    public func downloadTimeline(slug: String, category: String) async throws -> TimelineData {
        let r2Key = "stems/spatial-mix/field-recording/\(category)/\(slug)/timeline.json"
        let localURL = cacheDirectory
            .appendingPathComponent(slug)
            .appendingPathComponent("timeline.json")

        if !FileManager.default.fileExists(atPath: localURL.path) {
            try await downloadR2Key(r2Key, to: localURL)
        }

        let data = try Data(contentsOf: localURL)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw R2CatalogIndexError.badJSON("timeline.json", NSError(domain: "R2CatalogIndex", code: 2))
        }
        return parseTimelineJSON(root)
    }

    /// Download the raw timeline.md for `slug` from R2. Returns local URL.
    public func downloadTimelineMD(slug: String, category: String) async throws -> URL {
        let r2Key = "stems/spatial-mix/field-recording/\(category)/\(slug)/timeline.md"
        let localURL = cacheDirectory
            .appendingPathComponent(slug)
            .appendingPathComponent("timeline.md")
        if !FileManager.default.fileExists(atPath: localURL.path) {
            try await downloadR2Key(r2Key, to: localURL)
        }
        return localURL
    }

    // MARK: - Sample clip cache

    /// Returns the local cache URL for a pre-extracted sample clip.
    /// Derives the filename from the BirdNET convention:
    ///   <species-slug>__<source-slug>__t<startInt>s__c<confPct>.m4a
    public func sampleClipLocalURL(event: IndexedEvent) -> URL {
        let speciesSlug = slugify(event.label)
        let confPct = Int(event.confidence * 100)
        let tStart = Int(event.startSec)
        let filename = "\(speciesSlug)__\(event.sourceSlug)__t\(tStart)s__c\(String(format: "%03d", confPct)).m4a"
        return cacheDirectory
            .appendingPathComponent("samples")
            .appendingPathComponent(speciesSlug)
            .appendingPathComponent(filename)
    }

    /// Returns the R2 key for the pre-extracted sample clip.
    public func sampleClipR2Key(event: IndexedEvent) -> String {
        let speciesSlug = slugify(event.label)
        let confPct = Int(event.confidence * 100)
        let tStart = Int(event.startSec)
        let filename = "\(speciesSlug)__\(event.sourceSlug)__t\(tStart)s__c\(String(format: "%03d", confPct)).m4a"
        return "samples/birds/\(speciesSlug)/\(filename)"
    }

    /// Download a pre-extracted sample clip from R2 to the library cache.
    /// Returns the local URL.
    public func downloadSampleClip(event: IndexedEvent) async throws -> URL {
        let r2Key = sampleClipR2Key(event: event)
        let localURL = sampleClipLocalURL(event: event)
        try await downloadR2Key(r2Key, to: localURL)
        return localURL
    }

    // MARK: - Private parse helpers

    private func parseTimelineJSON(_ root: [String: Any]) -> TimelineData {
        var scenes: [TimelineData.Scene] = []
        if let scenesArr = root["scenes"] as? [[String: Any]] {
            for s in scenesArr {
                // Accept both camelCase (legacy) and snake_case (analyzer output)
                let startSec = s["startSec"] as? Double
                    ?? s["start_sec"] as? Double
                    ?? s["start"] as? Double
                    ?? 0.0
                let endSec = s["endSec"] as? Double
                    ?? s["end_sec"] as? Double
                    ?? s["end"] as? Double
                    ?? 0.0
                let label = s["label"] as? String ?? ""
                let cats = s["dominantCategories"] as? [String]
                    ?? s["dominant_categories"] as? [String]
                    ?? []
                let species = s["speciesInScene"] as? [String]
                    ?? s["species_in_scene"] as? [String]
                    ?? []
                scenes.append(TimelineData.Scene(startSec: startSec, endSec: endSec,
                                                  label: label, dominantCategories: cats,
                                                  speciesInScene: species))
            }
        }

        var events: [TimelineData.Event] = []
        let eventsArr = (root["events"] as? [[String: Any]]) ?? []
        for e in eventsArr {
            // Accept both camelCase (legacy) and snake_case (analyzer output)
            let timeSec = e["timeSec"] as? Double
                ?? e["time_sec"] as? Double
                ?? e["startSec"] as? Double
                ?? e["start_sec"] as? Double
                ?? 0.0
            let timeDisplay = e["timeDisplay"] as? String
                ?? e["time_display"] as? String
                ?? formatTimeline(timeSec)
            let kind = e["kind"] as? String ?? (e["scientific"] != nil ? "species" : "category")
            let label = e["label"] as? String ?? ""
            let scientific = e["scientific"] as? String
            let source = e["source"] as? String ?? ""
            let confidence = e["confidence"] as? Double ?? 1.0
            let duration = e["durationSec"] as? Double
                ?? e["duration_sec"] as? Double
                ?? e["duration"] as? Double
                ?? 0.0
            events.append(TimelineData.Event(timeSec: timeSec, timeDisplay: timeDisplay,
                                              kind: kind, label: label, scientific: scientific,
                                              source: source, confidence: confidence,
                                              durationSec: duration))
        }
        return TimelineData(scenes: scenes, events: events)
    }

    private func formatTimeline(_ sec: Double) -> String {
        let total = Int(sec)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }

    private func slugify(_ text: String) -> String {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
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
