import Foundation
import AVFoundation

/// Plays a single audio file via AVAudioPlayer.
/// macOS handles binauralization + head tracking automatically when output device is
/// AirPods Max/Pro with Spatial Audio enabled. We don't need to do anything special —
/// just play the multichannel file.
///
/// Not thread-safe.
@MainActor
public final class PreviewPlayer: ObservableObject {

    @Published public private(set) var isPlaying: Bool = false
    @Published public private(set) var currentFile: URL? = nil

    private var player: AVAudioPlayer?
    private var delegateBox: DelegateBox?

    public init() {}

    /// Begin playback of the given file. If something else is playing, it's stopped first.
    public func play(_ url: URL) throws {
        stop()
        let p = try AVAudioPlayer(contentsOf: url)
        let box = DelegateBox { [weak self] in
            Task { @MainActor in
                self?.isPlaying = false
                self?.currentFile = nil
            }
        }
        p.delegate = box
        p.prepareToPlay()
        guard p.play() else {
            throw NSError(domain: "PreviewPlayer", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "AVAudioPlayer.play() returned false"])
        }
        self.player = p
        self.delegateBox = box
        self.isPlaying = true
        self.currentFile = url
    }

    public func stop() {
        player?.stop()
        player = nil
        delegateBox = nil
        isPlaying = false
        currentFile = nil
    }
}

/// AVAudioPlayer requires an NSObject delegate; we wrap a callback closure.
private final class DelegateBox: NSObject, AVAudioPlayerDelegate {
    let onFinish: () -> Void
    init(onFinish: @escaping () -> Void) { self.onFinish = onFinish }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        onFinish()
    }
    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        onFinish()
    }
}
