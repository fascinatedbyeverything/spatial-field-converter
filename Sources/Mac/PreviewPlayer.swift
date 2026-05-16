import Foundation
import AVFoundation

/// Plays a single audio file via AVPlayer (NOT AVAudioPlayer).
///
/// Why AVPlayer: it ties into the system Spatial Audio rendering path, so when the user
/// has AirPods Max/Pro selected with Spatial Audio enabled (Control Center → Spatial Audio),
/// multichannel surround content (5.1/7.1) gets binauralized with HRTF + head tracking
/// automatically — no per-app HRTF or motion-manager code needed.
/// AVAudioPlayer does NOT engage this path; it just plays raw channels.
///
/// Not thread-safe.
@MainActor
public final class PreviewPlayer: ObservableObject {

    @Published public private(set) var isPlaying: Bool = false
    @Published public private(set) var currentFile: URL? = nil

    private var player: AVPlayer?
    private var endObserver: NSObjectProtocol?
    private var statusObserver: NSKeyValueObservation?
    private var boundaryObserver: Any?

    public init() {}

    /// Begin playback of the given file from the beginning.
    /// If something else is playing, it is stopped first.
    public func play(_ url: URL) throws {
        stop()

        let item = AVPlayerItem(url: url)
        let p = AVPlayer(playerItem: item)
        // Allow external playback engines (Spatial Audio) to handle the routing.
        p.allowsExternalPlayback = true
        p.appliesMediaSelectionCriteriaAutomatically = true

        // Fires when playback reaches the end.
        let token = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleEnd() }
        }

        // Observe rate so isPlaying stays accurate if playback stalls or system pauses.
        let kvo = p.observe(\.rate, options: [.new]) { [weak self] player, _ in
            Task { @MainActor in
                self?.isPlaying = player.rate != 0
                if player.rate == 0 && player.currentItem?.currentTime() == player.currentItem?.duration {
                    self?.handleEnd()
                }
            }
        }

        p.play()

        self.player = p
        self.endObserver = token
        self.statusObserver = kvo
        self.isPlaying = true
        self.currentFile = url
    }

    /// Begin playback of the given file, seeked to `startSec`.
    /// If `autoStopAfter` is given, playback stops at startSec + autoStopAfter + 2 seconds.
    /// If something else is playing, it is stopped first.
    public func play(_ url: URL, startAt startSec: Double, autoStopAfter durationSec: Double?) throws {
        stop()

        let item = AVPlayerItem(url: url)
        let p = AVPlayer(playerItem: item)
        p.allowsExternalPlayback = true
        p.appliesMediaSelectionCriteriaAutomatically = true

        // End-of-file observer
        let token = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleEnd() }
        }

        // Rate observer
        let kvo = p.observe(\.rate, options: [.new]) { [weak self] player, _ in
            Task { @MainActor in
                self?.isPlaying = player.rate != 0
                if player.rate == 0 && player.currentItem?.currentTime() == player.currentItem?.duration {
                    self?.handleEnd()
                }
            }
        }

        // Seek before play
        let seekTime = CMTime(seconds: startSec, preferredTimescale: 600)
        p.seek(to: seekTime, toleranceBefore: .zero, toleranceAfter: .zero)

        // Optional auto-stop boundary (event duration + 2 sec post-padding)
        if let stopAfterSec = durationSec {
            let stopAt = startSec + stopAfterSec + 2.0
            let stopTime = CMTime(seconds: stopAt, preferredTimescale: 600)
            let boundary = boundaryObserver(for: p, at: stopTime)
            self.boundaryObserver = boundary
        }

        p.play()

        self.player = p
        self.endObserver = token
        self.statusObserver = kvo
        self.isPlaying = true
        self.currentFile = url
    }

    public func stop() {
        if let token = endObserver {
            NotificationCenter.default.removeObserver(token)
            endObserver = nil
        }
        statusObserver?.invalidate()
        statusObserver = nil
        if let obs = boundaryObserver {
            player?.removeTimeObserver(obs)
            boundaryObserver = nil
        }
        player?.pause()
        player = nil
        isPlaying = false
        currentFile = nil
    }

    private func handleEnd() {
        if let token = endObserver {
            NotificationCenter.default.removeObserver(token)
            endObserver = nil
        }
        statusObserver?.invalidate()
        statusObserver = nil
        if let obs = boundaryObserver {
            player?.removeTimeObserver(obs)
            boundaryObserver = nil
        }
        player = nil
        isPlaying = false
        currentFile = nil
    }

    /// Registers a boundary-time observer on `player` that calls stop() when `time` is reached.
    private func boundaryObserver(for player: AVPlayer, at time: CMTime) -> Any {
        player.addBoundaryTimeObserver(
            forTimes: [NSValue(time: time)],
            queue: .main
        ) { [weak self] in
            Task { @MainActor in self?.stop() }
        }
    }
}
