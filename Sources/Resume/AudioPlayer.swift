import AVFoundation
import AppKit
import Foundation
import MediaPlayer

@MainActor
protocol PlaybackControlling: AnyObject {
  var hasItem: Bool { get }
  var rate: Float { get set }
  func load(
    urls: [URL],
    fetch: @escaping @Sendable (URL, String?) async throws -> AuthenticatedMediaResponse,
    position: TimeInterval, speed: Double, title: String, author: String, bookDuration: TimeInterval
  ) async throws
  func play()
  func pause()
  func seek(to position: TimeInterval)
  func setArtwork(_ image: NSImage)
  func unloadKeepingNowPlaying()
  func clear()
  func configureRemoteCommands(
    play: @escaping @MainActor () async -> Void,
    pause: @escaping @MainActor () -> Void, toggle: @escaping @MainActor () async -> Void,
    skip: @escaping @MainActor (TimeInterval) -> Void,
    seek: @escaping @MainActor (TimeInterval) -> Void)
}

@MainActor
final class AudioPlayer: PlaybackControlling {
  private let player = AVPlayer()
  nonisolated(unsafe) private var observer: Any?
  nonisolated(unsafe) private var stallObserver: NSObjectProtocol?
  nonisolated(unsafe) private var endObserver: NSObjectProtocol?
  private let update: (TimeInterval, TimeInterval, Bool) -> Void
  private let stalled: () -> Void
  private let ended: () -> Void
  private var loadGeneration = UUID()
  private var preparedItem: AVPlayerItem?
  private var playbackObservation: NSKeyValueObservation?
  private var failureObservation: NSKeyValueObservation?
  private let failed: () -> Void
  private var assetLoaders: [AuthenticatedAssetLoader] = []
  var hasItem: Bool { player.currentItem != nil }
  var rate: Float {
    get { player.defaultRate }
    set {
      player.defaultRate = newValue
      if player.rate != 0 { player.rate = newValue }
      if var info = MPNowPlayingInfoCenter.default().nowPlayingInfo {
        info[MPNowPlayingInfoPropertyDefaultPlaybackRate] = newValue
        info[MPNowPlayingInfoPropertyPlaybackRate] = player.rate
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
      }
    }
  }

  init(
    update: @escaping (TimeInterval, TimeInterval, Bool) -> Void, stalled: @escaping () -> Void,
    ended: @escaping () -> Void, failed: @escaping () -> Void = {}
  ) {
    self.update = update
    self.stalled = stalled
    self.ended = ended
    self.failed = failed
    observer = player.addPeriodicTimeObserver(
      forInterval: CMTime(seconds: 0.5, preferredTimescale: 2), queue: .main
    ) { [weak self] time in
      Task { @MainActor [weak self] in
        guard let self, let item = self.preparedItem, item === self.player.currentItem else {
          return
        }
        let time = self.player.currentTime()
        let duration = self.player.currentItem?.duration.seconds ?? 0
        self.update(
          time.seconds.isFinite ? time.seconds : 0, duration.isFinite ? duration : 0,
          self.player.timeControlStatus == .playing)
        self.publishElapsed(time.seconds.isFinite ? time.seconds : 0)
      }
    }
    playbackObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] _, _ in
      Task { @MainActor [weak self] in
        guard let self, let item = self.preparedItem, item === self.player.currentItem else {
          return
        }
        let time = self.player.currentTime().seconds
        let duration = item.duration.seconds
        self.update(
          time.isFinite ? time : 0, duration.isFinite ? duration : 0,
          self.player.timeControlStatus == .playing)
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
    cancelLoading()
    let generation = loadGeneration
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
      // Load a bounded batch concurrently; assemble in book order after metadata is ready.
      // No progress/session requests or authority decisions are reordered here.
      var cursor = CMTime.zero
      for start in stride(from: 0, to: assets.count, by: 4) {
        let end = min(start + 4, assets.count)
        try await withThrowingTaskGroup(of: Void.self) { group in
          for asset in assets[start..<end] {
            group.addTask {
              _ = try await asset.load(.tracks, .duration)
            }
          }
          try await group.waitForAll()
        }
        guard generation == loadGeneration else { throw CancellationError() }
        // Read the now-loaded properties on the owning actor; AVAssetTrack is not Sendable.
        for asset in assets[start..<end] {
          let (tracks, duration) = try await asset.load(.tracks, .duration)
          guard generation == loadGeneration else { throw CancellationError() }
          guard let track = tracks.first(where: { $0.mediaType == .audio }) else { continue }
          try compositionTrack.insertTimeRange(
            .init(start: .zero, duration: duration), of: track, at: cursor)
          cursor = cursor + duration
        }
      }
      item = AVPlayerItem(asset: composition)
    }
    guard generation == loadGeneration else { throw CancellationError() }
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
    failureObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
      guard item.status == .failed else { return }
      Task { @MainActor [weak self] in
        guard let self, generation == self.loadGeneration else { return }
        self.failed()
      }
    }
    let sought = await player.seek(to: CMTime(seconds: position, preferredTimescale: 600))
    guard generation == loadGeneration else { throw CancellationError() }
    guard sought, item.status != .failed else { throw URLError(.cannotDecodeContentData) }
    preparedItem = item
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
    guard let pixels = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
    info[MPMediaItemPropertyArtwork] = Self.makeArtwork(pixels: pixels, size: image.size)
    MPNowPlayingInfoCenter.default().nowPlayingInfo = info
  }
  // MediaPlayer invokes this synchronous callback on its own queue. Capture immutable
  // pixels and create a fresh image there; never inherit MainActor or dispatch back to it.
  nonisolated private static func makeArtwork(pixels: CGImage, size: CGSize) -> MPMediaItemArtwork {
    MPMediaItemArtwork(boundsSize: size) { _ in NSImage(cgImage: pixels, size: size) }
  }

  func unloadKeepingNowPlaying() {
    player.pause()
    player.replaceCurrentItem(with: nil)
    cancelLoading()
    MPNowPlayingInfoCenter.default().playbackState = .paused
  }
  func clear() {
    player.pause()
    player.replaceCurrentItem(with: nil)
    cancelLoading()
    MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    MPNowPlayingInfoCenter.default().playbackState = .stopped
  }

  private func cancelLoading() {
    preparedItem = nil
    failureObservation = nil
    loadGeneration = UUID()
    for loader in assetLoaders { loader.cancel() }
    assetLoaders = []
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
