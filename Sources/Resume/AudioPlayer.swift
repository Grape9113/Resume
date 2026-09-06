import AVFoundation
import AppKit
import Foundation
import MediaPlayer

@MainActor
final class AudioPlayer {
  private let player = AVPlayer()
  nonisolated(unsafe) private var observer: Any?
  nonisolated(unsafe) private var stallObserver: NSObjectProtocol?
  nonisolated(unsafe) private var endObserver: NSObjectProtocol?
  private let update: (TimeInterval, TimeInterval, Bool) -> Void
  private let stalled: () -> Void
  private let ended: () -> Void
  private var assetLoaders: [AuthenticatedAssetLoader] = []
  var hasItem: Bool { player.currentItem != nil }
  var rate: Float {
    get { player.rate }
    set { if player.rate != 0 { player.rate = newValue } }
  }

  init(
    update: @escaping (TimeInterval, TimeInterval, Bool) -> Void, stalled: @escaping () -> Void,
    ended: @escaping () -> Void
  ) {
    self.update = update
    self.stalled = stalled
    self.ended = ended
    observer = player.addPeriodicTimeObserver(
      forInterval: CMTime(seconds: 0.5, preferredTimescale: 2), queue: .main
    ) { [weak self] time in
      Task { @MainActor [weak self] in
        guard let self else { return }
        let duration = self.player.currentItem?.duration.seconds ?? 0
        self.update(
          time.seconds.isFinite ? time.seconds : 0, duration.isFinite ? duration : 0,
          self.player.rate != 0)
        self.publishElapsed(time.seconds.isFinite ? time.seconds : 0)
      }
    }
  }

  deinit {
    if let observer { player.removeTimeObserver(observer) }
    if let stallObserver { NotificationCenter.default.removeObserver(stallObserver) }
    if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
  }

  func load(
    urls: [URL],
    fetch: @escaping @Sendable (URL, String?) async throws -> AuthenticatedMediaResponse,
    position: TimeInterval, speed: Double, title: String, author: String, bookDuration: TimeInterval
  ) async throws {
    assetLoaders = try urls.map { try AuthenticatedAssetLoader(url: $0, fetch: fetch) }
    let assets = assetLoaders.map(\.asset)
    let item: AVPlayerItem
    if assets.count == 1 {
      item = AVPlayerItem(asset: assets[0])
    } else {
      let composition = AVMutableComposition()
      guard
        let compositionTrack = composition.addMutableTrack(
          withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
      else { throw URLError(.cannotDecodeContentData) }
      var cursor = CMTime.zero
      for asset in assets {
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        let assetDuration = try await asset.load(.duration)
        guard let track = tracks.first else { continue }
        try compositionTrack.insertTimeRange(
          .init(start: .zero, duration: assetDuration), of: track, at: cursor)
        cursor = cursor + assetDuration
      }
      item = AVPlayerItem(asset: composition)
    }
    player.replaceCurrentItem(with: item)
    if let stallObserver { NotificationCenter.default.removeObserver(stallObserver) }
    if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
    stallObserver = NotificationCenter.default.addObserver(
      forName: AVPlayerItem.playbackStalledNotification, object: item, queue: .main
    ) { [weak self] _ in
      Task { @MainActor in self?.stalled() }
    }
    endObserver = NotificationCenter.default.addObserver(
      forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main
    ) { [weak self] _ in
      Task { @MainActor in self?.ended() }
    }
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

  func play() {
    player.playImmediately(atRate: player.defaultRate)
    MPNowPlayingInfoCenter.default().playbackState = .playing
  }
  func pause() {
    player.pause()
    MPNowPlayingInfoCenter.default().playbackState = .paused
  }
  func seek(to position: TimeInterval) {
    if player.currentItem != nil {
      player.seek(to: CMTime(seconds: position, preferredTimescale: 600))
    }
    publishElapsed(position)
  }
  func setArtwork(_ image: NSImage) {
    guard var info = MPNowPlayingInfoCenter.default().nowPlayingInfo else { return }
    info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    MPNowPlayingInfoCenter.default().nowPlayingInfo = info
  }
  func unloadKeepingNowPlaying() {
    player.pause()
    player.replaceCurrentItem(with: nil)
    assetLoaders = []
    MPNowPlayingInfoCenter.default().playbackState = .paused
  }
  func clear() {
    player.pause()
    player.replaceCurrentItem(with: nil)
    assetLoaders = []
    MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    MPNowPlayingInfoCenter.default().playbackState = .stopped
  }

  func configureRemoteCommands(
    play: @escaping @MainActor () async -> Void, pause: @escaping @MainActor () -> Void,
    toggle: @escaping @MainActor () async -> Void,
    skip: @escaping @MainActor (TimeInterval) -> Void,
    seek: @escaping @MainActor (TimeInterval) -> Void
  ) {
    let center = MPRemoteCommandCenter.shared()
    center.playCommand.addTarget { _ in
      Task { @MainActor in await play() }
      return .success
    }
    center.pauseCommand.addTarget { _ in
      Task { @MainActor in pause() }
      return .success
    }
    center.togglePlayPauseCommand.addTarget { _ in
      Task { @MainActor in await toggle() }
      return .success
    }
    center.skipBackwardCommand.preferredIntervals = [15]
    center.skipBackwardCommand.addTarget { _ in
      Task { @MainActor in skip(-15) }
      return .success
    }
    center.skipForwardCommand.preferredIntervals = [30]
    center.skipForwardCommand.addTarget { _ in
      Task { @MainActor in skip(30) }
      return .success
    }
    center.changePlaybackPositionCommand.addTarget { event in
      guard let event = event as? MPChangePlaybackPositionCommandEvent else {
        return .commandFailed
      }
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
