import Foundation
import AVFoundation
import Combine

public enum ComposePreviewError: Error, CustomStringConvertible {
    case engineStartFailed(Error)
    case bedLoadFailed(String, Error)
    case objectLoadFailed(String, Error)

    public var description: String {
        switch self {
        case .engineStartFailed(let e): return "AVAudioEngine.start: \(e)"
        case .bedLoadFailed(let k, let e): return "Bed load \(k): \(e)"
        case .objectLoadFailed(let k, let e): return "Object load \(k): \(e)"
        }
    }
}

/// Live 3D preview of a Composition.
///
/// One AVAudioEngine + one AVAudioEnvironmentNode (HRTFHQ). Each source clip
/// (bed + each object) gets its own AVAudioPlayerNode wired into the environment
/// node so per-source 3D position takes effect. Source files are streamed via
/// AVAudioFile (loaded once, scheduled at the planned startSec).
///
/// For v1.1: positions are static (first PositionKeyframe). Moving-object curves
/// are a v1.2 follow-up.
@MainActor
public final class ComposePreviewPlayer: ObservableObject {

    @Published public private(set) var isPlaying: Bool = false
    @Published public private(set) var currentSlug: String? = nil

    private let engine = AVAudioEngine()
    private let env = AVAudioEnvironmentNode()
    private var bedPlayer: AVAudioPlayerNode?
    private var objectPlayers: [AVAudioPlayerNode] = []
    private var startHostTime: AVAudioTime?

    private let cacheDirectory: URL

    public init(cacheDirectory: URL) throws {
        self.cacheDirectory = cacheDirectory
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)

        env.renderingAlgorithm = .HRTFHQ
        env.listenerPosition = AVAudio3DPoint(x: 0, y: 0, z: 0)
        env.listenerVectorOrientation = AVAudio3DVectorOrientation(
            forward: AVAudio3DVector(x: 0, y: 0, z: -1),
            up: AVAudio3DVector(x: 0, y: 1, z: 0))
        env.distanceAttenuationParameters.distanceAttenuationModel = .inverse
        env.distanceAttenuationParameters.referenceDistance = 1.0
        env.distanceAttenuationParameters.maximumDistance = 10.0
        env.distanceAttenuationParameters.rolloffFactor = 1.0

        engine.attach(env)
        engine.connect(env, to: engine.mainMixerNode, format: nil)
    }

    /// Start playback. `bedURL` is a local source clip for the bed (first segment for cheap
    /// preview — caller is responsible for fetching it). `objects` pairs each ObjectPlan with
    /// its pre-fetched local URL (use `prefetchObjects(_:)` below).
    ///
    /// All players share a t0 anchor so object startSec offsets are sample-accurate.
    public func start(bedURL: URL,
                      objects: [(plan: ObjectPlan, localURL: URL)],
                      slug: String) throws {
        stop()

        let sr = 48_000.0

        // Bed — single player at origin, mono so HRTF (spatial env) engages
        let bedPlayerNode = AVAudioPlayerNode()
        engine.attach(bedPlayerNode)
        let monoFmt = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 1)!
        engine.connect(bedPlayerNode, to: env, format: monoFmt)
        bedPlayerNode.position = AVAudio3DPoint(x: 0, y: 0, z: 0)

        let bedFile: AVAudioFile
        do { bedFile = try AVAudioFile(forReading: bedURL) }
        catch { throw ComposePreviewError.bedLoadFailed(bedURL.lastPathComponent, error) }

        do {
            try bedPlayerNode.scheduleFile(bedFile, at: nil,
                                           completionCallbackType: .dataPlayedBack) { _ in }
        } catch {
            throw ComposePreviewError.bedLoadFailed(bedURL.lastPathComponent, error)
        }
        self.bedPlayer = bedPlayerNode

        // Objects — one player each, positioned at first PositionKeyframe
        var nodes: [AVAudioPlayerNode] = []
        for (plan, localURL) in objects {
            let p = AVAudioPlayerNode()
            engine.attach(p)
            let mono = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 1)!
            engine.connect(p, to: env, format: mono)

            let pos = plan.positionCurve.first
            p.position = AVAudio3DPoint(
                x: Float(pos?.x ?? 0),
                y: Float(pos?.y ?? 0),
                z: Float(pos?.z ?? -1))
            p.volume = plan.volume

            let file: AVAudioFile
            do { file = try AVAudioFile(forReading: localURL) }
            catch { throw ComposePreviewError.objectLoadFailed(plan.sourceClipR2Key, error) }

            do {
                try p.scheduleFile(file, at: nil,
                                   completionCallbackType: .dataPlayedBack) { _ in }
            } catch {
                throw ComposePreviewError.objectLoadFailed(plan.sourceClipR2Key, error)
            }
            nodes.append(p)
        }
        self.objectPlayers = nodes

        // Start engine before scheduling play times
        do { try engine.start() }
        catch {
            stop()
            throw ComposePreviewError.engineStartFailed(error)
        }

        // Schedule all players against a shared anchor (t0 = 200 ms from now)
        let hostNow = mach_absolute_time()
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        let hostTicksPerSec = Double(info.denom) * 1_000_000_000.0 / Double(info.numer)
        let offsetTicks = UInt64(0.2 * hostTicksPerSec)
        let t0Host = hostNow + offsetTicks
        let t0 = AVAudioTime(hostTime: t0Host)

        bedPlayerNode.play(at: t0)
        for (i, p) in nodes.enumerated() {
            let plan = objects[i].plan
            let offsetSamples = AVAudioFramePosition(plan.startSec * sr)
            let sampleTime = t0.sampleTime + offsetSamples
            let when = AVAudioTime(sampleTime: sampleTime, atRate: sr)
            p.play(at: when)
        }

        startHostTime = t0
        currentSlug = slug
        isPlaying = true
    }

    public func stop() {
        bedPlayer?.stop()
        objectPlayers.forEach { $0.stop() }

        if let p = bedPlayer {
            engine.detach(p)
        }
        bedPlayer = nil

        for p in objectPlayers {
            engine.detach(p)
        }
        objectPlayers.removeAll()

        engine.stop()

        // Re-attach env for the next start (detach happens implicitly with stop; re-wire it)
        if !engine.attachedNodes.contains(env) {
            engine.attach(env)
            engine.connect(env, to: engine.mainMixerNode, format: nil)
        }

        isPlaying = false
        currentSlug = nil
        startHostTime = nil
    }

    /// Live-update the 3D position for an already-playing object index.
    /// Used by SpaceView when the user drags an object dot during preview.
    public func updateObjectPosition(index: Int, x: Float, y: Float, z: Float) {
        guard objectPlayers.indices.contains(index) else { return }
        objectPlayers[index].position = AVAudio3DPoint(x: x, y: y, z: z)
    }

    // MARK: - R2 prefetch with cache

    /// Fetch every distinct ObjectPlan source clip into the local cache and return
    /// (plan, localURL) pairs in the same order as `plans`.
    public func prefetchObjects(_ plans: [ObjectPlan]) async throws -> [(plan: ObjectPlan, localURL: URL)] {
        var out: [(ObjectPlan, URL)] = []
        for plan in plans {
            let local = try await fetchFromR2(key: plan.sourceClipR2Key)
            out.append((plan, local))
        }
        return out
    }

    /// Fetch a bed segment source clip into the local cache and return its local URL.
    public func prefetchBedSegment(r2Key: String) async throws -> URL {
        try await fetchFromR2(key: r2Key)
    }

    /// Same shell-out pattern WorldRenderer uses; cached by sanitized full key.
    private func fetchFromR2(key: String) async throws -> URL {
        let safe = key.replacingOccurrences(of: "/", with: "_")
        let cached = cacheDirectory.appendingPathComponent(safe)
        if FileManager.default.fileExists(atPath: cached.path) { return cached }

        let bucket = "cloud-to-float-on"
        let endpoint = "https://6a378e6919e5a3f1cbd84db6c1ad5443.r2.cloudflarestorage.com"

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: Self.resolveAws())
        proc.arguments = ["s3", "cp",
                          "s3://\(bucket)/\(key)",
                          cached.path,
                          "--endpoint-url", endpoint,
                          "--no-progress"]
        proc.environment = R2Uploader.awsEnvironment
        proc.standardError = Pipe()
        proc.standardOutput = FileHandle.nullDevice

        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<URL, Error>) in
            proc.terminationHandler = { p in
                if p.terminationStatus == 0 {
                    cont.resume(returning: cached)
                } else {
                    cont.resume(throwing: ComposePreviewError.objectLoadFailed(key,
                        NSError(domain: "R2", code: Int(p.terminationStatus), userInfo: nil)))
                }
            }
            do { try proc.run() } catch { cont.resume(throwing: error) }
        }
    }

    private static func resolveAws() -> String {
        for candidate in ["/opt/homebrew/bin/aws", "/usr/local/bin/aws", "/usr/bin/aws"] {
            if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
        }
        return "/usr/local/bin/aws"
    }
}
