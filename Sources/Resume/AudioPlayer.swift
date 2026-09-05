import AVFoundation
import Foundation

@MainActor
final class AudioPlayer {
    private let player = AVPlayer()
    nonisolated(unsafe) private var observer: Any?
    private let update: (TimeInterval, TimeInterval, Bool) -> Void
    var hasItem: Bool { player.currentItem != nil }
    var rate: Float { get { player.rate } set { if player.rate != 0 { player.rate = newValue } } }

    init(update: @escaping (TimeInterval, TimeInterval, Bool) -> Void) {
        self.update = update
        observer = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 2), queue: .main) { [weak self] time in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let duration = self.player.currentItem?.duration.seconds ?? 0
                self.update(time.seconds.isFinite ? time.seconds : 0, duration.isFinite ? duration : 0, self.player.rate != 0)
            }
        }
    }

    deinit { if let observer { player.removeTimeObserver(observer) } }

    func load(url: URL, bearerToken: String?, position: TimeInterval, speed: Double) async throws {
        // Audiobookshelf accepts its access token on authenticated media URLs. AVPlayer has no
        // public per-request header API, so use the server-supported token query for streaming.
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        if let bearerToken {
            let existing = components?.queryItems ?? []
            components?.queryItems = existing + [.init(name: "token", value: bearerToken)]
        }
        guard let playableURL = components?.url else { throw URLError(.badURL) }
        let item = AVPlayerItem(url: playableURL)
        player.replaceCurrentItem(with: item)
        await player.seek(to: CMTime(seconds: position, preferredTimescale: 600))
        player.defaultRate = Float(speed)
    }

    func play() { player.playImmediately(atRate: player.defaultRate) }
    func pause() { player.pause() }
    func seek(to position: TimeInterval) { player.seek(to: CMTime(seconds: position, preferredTimescale: 600)) }
}
