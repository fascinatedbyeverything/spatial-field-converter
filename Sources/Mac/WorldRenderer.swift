import Foundation

public enum WorldRendererError: Error, CustomStringConvertible {
    case ffmpegNotFound
    case awsCliNotFound
    case ffmpegFailed(String)
    case awsFetchFailed(String, URL)
    case emptyBed
    case noObjects

    public var description: String {
        switch self {
        case .ffmpegNotFound: return "ffmpeg not found in PATH or at /opt/homebrew/bin/ffmpeg"
        case .awsCliNotFound: return "aws CLI not found"
        case .ffmpegFailed(let s): return "ffmpeg failed: \(s)"
        case .awsFetchFailed(let key, let url): return "R2 fetch failed for \(key) → \(url.path)"
        case .emptyBed: return "Composition has empty BedPlan"
        case .noObjects: return "Composition has zero objects"
        }
    }
}

public struct RenderedWorld {
    public let bundleDirectory: URL
    public let bedURL: URL
    public let objectURLs: [URL]
    public let manifestURL: URL
}

/// Renders a Composition into an on-disk spatial-mix/v2 bundle.
///
/// Output layout under `outputDirectory/<composition.slug>/`:
///   - bed.m4a           single stitched bed
///   - obj-01.m4a … obj-NN.m4a   one per ObjectPlan
///   - manifest.json     spatial-mix/v2 schema
///
/// Source clips (bed + objects) are pulled from R2 into a scratch cache and reused
/// across renders. The same clip referenced by multiple ObjectPlans is fetched once.
@MainActor
public final class WorldRenderer {

    private let bucket: String = "cloud-to-float-on"
    private let r2Endpoint: String = "https://6a378e6919e5a3f1cbd84db6c1ad5443.r2.cloudflarestorage.com"
    private let cacheDirectory: URL
    private let ffmpegPath: String

    public init(cacheDirectory: URL) throws {
        self.cacheDirectory = cacheDirectory
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        self.ffmpegPath = try Self.resolveFfmpeg()
    }

    public func render(_ composition: Composition, into outputDirectory: URL) async throws -> RenderedWorld {
        guard let slug = composition.slug else { throw WorldRendererError.emptyBed }
        guard !composition.objects.isEmpty else { throw WorldRendererError.noObjects }
        let bundle = outputDirectory.appendingPathComponent(slug)
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)

        let bedURL = try await renderBed(composition: composition, into: bundle)

        var objectURLs: [URL] = []
        for (i, plan) in composition.objects.enumerated() {
            let index = i + 1
            let outURL = bundle.appendingPathComponent(String(format: "obj-%02d.m4a", index))
            try await renderObject(plan: plan, into: outURL)
            objectURLs.append(outURL)
        }

        let manifestURL = bundle.appendingPathComponent("manifest.json")
        try writeManifest(composition: composition,
                          objectURLs: objectURLs,
                          to: manifestURL)

        return RenderedWorld(
            bundleDirectory: bundle,
            bedURL: bedURL,
            objectURLs: objectURLs,
            manifestURL: manifestURL)
    }

    // MARK: - Bed

    private func renderBed(composition: Composition, into bundle: URL) async throws -> URL {
        let outURL = bundle.appendingPathComponent("bed.m4a")
        guard !composition.bedPlan.segments.isEmpty else {
            throw WorldRendererError.emptyBed
        }

        // Fetch all source clips into the local cache.
        var localSegments: [(URL, Double, Double)] = []
        for seg in composition.bedPlan.segments {
            let local = try await fetchFromR2(key: seg.sourceClipR2Key)
            localSegments.append((local, seg.startInClipSec, seg.endInClipSec))
        }

        // Build an ffmpeg filter_complex that trims each input to its [startInClipSec, endInClipSec]
        // window and concatenates the results into a single stream.
        var args: [String] = ["-y"]
        for (url, _, _) in localSegments {
            args.append(contentsOf: ["-i", url.path])
        }

        var filterParts: [String] = []
        for (i, seg) in localSegments.enumerated() {
            let (_, start, end) = seg
            filterParts.append("[\(i):a]atrim=\(start):\(end),asetpts=PTS-STARTPTS[s\(i)]")
        }
        var concatInputs = ""
        for i in 0..<localSegments.count { concatInputs += "[s\(i)]" }
        filterParts.append("\(concatInputs)concat=n=\(localSegments.count):v=0:a=1[out]")
        let filter = filterParts.joined(separator: ";")

        args.append(contentsOf: [
            "-filter_complex", filter,
            "-map", "[out]",
            "-c:a", "aac", "-b:a", "256k",
            outURL.path
        ])
        try runFfmpeg(args: args)
        return outURL
    }

    // MARK: - Objects

    private func renderObject(plan: ObjectPlan, into outURL: URL) async throws {
        let source = try await fetchFromR2(key: plan.sourceClipR2Key)
        // Trim the source to plan.durationSec (or its natural duration, whichever is shorter).
        // The object's startSec in the manifest tells the player when to fire it.
        var args: [String] = ["-y", "-i", source.path]
        if plan.durationSec > 0 {
            args.append(contentsOf: ["-t", String(plan.durationSec)])
        }
        args.append(contentsOf: ["-c:a", "aac", "-b:a", "192k", outURL.path])
        try runFfmpeg(args: args)
    }

    // MARK: - Manifest

    private func writeManifest(composition: Composition,
                                objectURLs: [URL],
                                to url: URL) throws {
        let title = composition.title ?? composition.slug ?? "Untitled"
        let slug = composition.slug ?? "untitled"
        let templateID = composition.templateID ?? "unknown"
        let seed = composition.seed ?? 0

        let objects: [WorldManifest.ObjectRef] = composition.objects.enumerated().map { (i, plan) in
            let kf = plan.positionCurve.map {
                WorldManifest.ObjectRef.KeyframeRef(
                    timeSec: $0.timeSec, x: Double($0.x), y: Double($0.y), z: Double($0.z))
            }
            return WorldManifest.ObjectRef(
                index: i + 1,
                file: objectURLs[i].lastPathComponent,
                label: plan.label,
                scientific: plan.scientific,
                startSec: plan.startSec,
                durationSec: plan.durationSec,
                volume: Double(plan.volume),
                loop: plan.loop,
                behavior: plan.behavior.rawValue,
                positionCurve: kf)
        }

        let manifest = WorldManifest(
            schema: "spatial-mix/v2",
            title: title,
            slug: slug,
            durationSec: composition.durationSec,
            templateID: templateID,
            seed: seed,
            bed: WorldManifest.BedRef(file: "bed.m4a"),
            objects: objects)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(manifest)
        try data.write(to: url)
    }

    // MARK: - R2 fetch with cache

    private func fetchFromR2(key: String) async throws -> URL {
        // Cache by full key (slashes replaced so the filename is flat).
        let safe = key.replacingOccurrences(of: "/", with: "_")
        let cached = cacheDirectory.appendingPathComponent(safe)
        if FileManager.default.fileExists(atPath: cached.path) {
            return cached
        }

        let awsPath = Self.resolveAws()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: awsPath)
        process.arguments = ["s3", "cp",
                              "s3://\(bucket)/\(key)",
                              cached.path,
                              "--endpoint-url", r2Endpoint,
                              "--no-progress"]
        process.environment = R2Uploader.awsEnvironment
        let errPipe = Pipe()
        process.standardError = errPipe
        process.standardOutput = FileHandle.nullDevice

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            process.terminationHandler = { proc in
                if proc.terminationStatus == 0 {
                    cont.resume()
                } else {
                    cont.resume(throwing: WorldRendererError.awsFetchFailed(key, cached))
                }
            }
            do {
                try process.run()
            } catch {
                cont.resume(throwing: error)
            }
        }

        return cached
    }

    // MARK: - Tool resolution

    private static func resolveFfmpeg() throws -> String {
        for candidate in ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg", "/usr/bin/ffmpeg"] {
            if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
        }
        throw WorldRendererError.ffmpegNotFound
    }

    private static func resolveAws() -> String {
        for candidate in ["/opt/homebrew/bin/aws", "/usr/local/bin/aws", "/usr/bin/aws"] {
            if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
        }
        return "/usr/local/bin/aws"
    }

    private func runFfmpeg(args: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpegPath)
        process.arguments = args
        let errPipe = Pipe()
        process.standardError = errPipe
        process.standardOutput = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            let data = (try? errPipe.fileHandleForReading.readToEnd()) ?? Data()
            let msg = String(data: data, encoding: .utf8) ?? "exit \(process.terminationStatus)"
            throw WorldRendererError.ffmpegFailed(msg)
        }
    }
}
