import AVFoundation
import Foundation
import MediaPlayer

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
                self.publishElapsed(time.seconds.isFinite ? time.seconds : 0)
            }
        }
    }

    deinit { if let observer { player.removeTimeObserver(observer) } }

    func load(urls: [URL], bearerToken: String?, position: TimeInterval, speed: Double, title: String, author: String, bookDuration: TimeInterval) async throws {
        // Audiobookshelf accepts its access token on authenticated media URLs. AVPlayer has no
        // public per-request header API, so use the server-supported token query for streaming.
        let playableURLs = try urls.map { url in
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            if let bearerToken {
                let existing = components?.queryItems ?? []
                components?.queryItems = existing + [.init(name: "token", value: bearerToken)]
            }
            guard let result = components?.url else { throw URLError(.badURL) }
            return result
        }
        let item: AVPlayerItem
        if playableURLs.count == 1 {
            item = AVPlayerItem(url: playableURLs[0])
        } else {
            let composition = AVMutableComposition()
            guard let compositionTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else { throw URLError(.cannotDecodeContentData) }
            var cursor = CMTime.zero
            for url in playableURLs {
                let asset = AVURLAsset(url: url)
                let tracks = try await asset.loadTracks(withMediaType: .audio)
                let assetDuration = try await asset.load(.duration)
                guard let track = tracks.first else { continue }
                try compositionTrack.insertTimeRange(.init(start: .zero, duration: assetDuration), of: track, at: cursor)
                cursor = cursor + assetDuration
            }
            item = AVPlayerItem(asset: composition)
        }
        player.replaceCurrentItem(with: item)
        await player.seek(to: CMTime(seconds: position, preferredTimescale: 600))
        player.defaultRate = Float(speed)
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyArtist: author,
            MPMediaItemPropertyPlaybackDuration: bookDuration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: position,
            MPNowPlayingInfoPropertyPlaybackRate: 0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: speed,
        ]
        MPNowPlayingInfoCenter.default().playbackState = .paused
    }

    func play() { player.playImmediately(atRate: player.defaultRate); MPNowPlayingInfoCenter.default().playbackState = .playing }
    func pause() { player.pause(); MPNowPlayingInfoCenter.default().playbackState = .paused }
    func seek(to position: TimeInterval) { player.seek(to: CMTime(seconds: position, preferredTimescale: 600)) }
    func clear() { player.pause(); player.replaceCurrentItem(with: nil); MPNowPlayingInfoCenter.default().nowPlayingInfo = nil; MPNowPlayingInfoCenter.default().playbackState = .stopped }

    func configureRemoteCommands(play: @escaping @MainActor () async -> Void, pause: @escaping @MainActor () -> Void, toggle: @escaping @MainActor () async -> Void, skip: @escaping @MainActor (TimeInterval) -> Void, seek: @escaping @MainActor (TimeInterval) -> Void) {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { _ in Task { @MainActor in await play() }; return .success }
        center.pauseCommand.addTarget { _ in Task { @MainActor in pause() }; return .success }
        center.togglePlayPauseCommand.addTarget { _ in Task { @MainActor in await toggle() }; return .success }
        center.skipBackwardCommand.preferredIntervals = [15]
        center.skipBackwardCommand.addTarget { _ in Task { @MainActor in skip(-15) }; return .success }
        center.skipForwardCommand.preferredIntervals = [30]
        center.skipForwardCommand.addTarget { _ in Task { @MainActor in skip(30) }; return .success }
        center.changePlaybackPositionCommand.addTarget { event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            Task { @MainActor in seek(event.positionTime) }
            return .success
        }
    }

    private func publishElapsed(_ elapsed: TimeInterval) {
        guard var info = MPNowPlayingInfoCenter.default().nowPlayingInfo else { return }
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsed
        info[MPNowPlayingInfoPropertyPlaybackRate] = player.rate
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
