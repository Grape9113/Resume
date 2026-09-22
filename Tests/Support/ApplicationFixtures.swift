#if DEBUG
  import AppKit
  import Foundation
  import ResumeCore

  actor MemoryStateStore: LocalStatePersisting {
    var state: LocalState?
    init(_ state: LocalState? = nil) { self.state = state }
    func load() -> LocalState? { state }
    func save(_ state: LocalState) { self.state = state }
    func clear() { state = nil }
  }

  @MainActor
  final class TestPlayer: PlaybackControlling {
    var delayLoad = false
    var loadLatency: Duration = .zero
    var loadError: URLError?
    var onPlaybackChange: ((TimeInterval, Bool) -> Void)?
    private var loading: CheckedContinuation<Void, Never>?
    private var loadObserver: CheckedContinuation<Void, Never>?
    func waitUntilLoading() async {
      if loading != nil { return }
      await withCheckedContinuation { loadObserver = $0 }
    }
    func finishLoading() {
      loading?.resume()
      loading = nil
    }
    var hasItem = false
    var rate: Float = 0
    var playing = false
    var position: TimeInterval = 0
    func load(
      urls: [URL],
      fetch: @escaping @Sendable (URL, String?) async throws -> AuthenticatedMediaResponse,
      position: TimeInterval, speed: Double, title: String, author: String,
      bookDuration: TimeInterval
    ) async throws {
      try await Task.sleep(for: loadLatency)
      if let loadError { throw loadError }
      hasItem = true
      self.position = position
      rate = Float(speed)
      if delayLoad {
        await withCheckedContinuation { continuation in
          loading = continuation
          loadObserver?.resume()
          loadObserver = nil
        }
      }
    }
    func play() {
      playing = true
      onPlaybackChange?(position, true)
    }
    func pause() {
      playing = false
      onPlaybackChange?(position, false)
    }
    func seek(to position: TimeInterval) { self.position = position }
    func setArtwork(_ image: NSImage) {}
    func unloadKeepingNowPlaying() {
      hasItem = false
      playing = false
    }
    func clear() { unloadKeepingNowPlaying() }
    func configureRemoteCommands(
      play: @escaping @MainActor () async -> Void,
      pause: @escaping @MainActor () -> Void, toggle: @escaping @MainActor () async -> Void,
      skip: @escaping @MainActor (TimeInterval) -> Void,
      seek: @escaping @MainActor (TimeInterval) -> Void
    ) {}
  }

  actor TestAudiobookshelf: AudiobookshelfServing {
    private let fixtureCover: Data?
    init(coverData: Data? = nil) { fixtureCover = coverData }
    var remote = ABSProgress(currentTime: 100, duration: 1_000, isFinished: false, lastUpdate: 1)
    var mediaProvider: (@Sendable (URL, String?) async throws -> AuthenticatedMediaResponse)?
    func setMediaProvider(
      _ provider: @escaping @Sendable (URL, String?) async throws -> AuthenticatedMediaResponse
    ) {
      mediaProvider = provider
    }
    var networkLatency: Duration = .zero
    var progressError: (any Error)?
    func setNetworkLatency(_ delay: Duration) { networkLatency = delay }
    func setProgressError(_ error: (any Error)?) { progressError = error }
    var sessionPosition: Double?
    func setSessionPosition(_ position: Double) { sessionPosition = position }
    var writes: [Double] = []
    var closedSessions: [String] = []
    private var shouldDelayProgress = false
    private var pendingProgress: CheckedContinuation<Void, Never>?
    private var progressObserver: CheckedContinuation<Void, Never>?
    func setRemote(position: Double, finished: Bool = false, baseline: Int64 = 1) {
      remote = .init(
        currentTime: position, duration: 1_000, isFinished: finished, lastUpdate: baseline)
    }
    func delayNextProgress() { shouldDelayProgress = true }
    func waitUntilProgressRequested() async {
      if pendingProgress != nil { return }
      await withCheckedContinuation { progressObserver = $0 }
    }
    func releaseProgress() {
      pendingProgress?.resume()
      pendingProgress = nil
    }
    func login(server: URL, username: String, password: String) {}
    func accessToken() -> String? { nil }
    func libraries() -> [ABSLibrary] { [] }
    func items(libraryID: String) -> [Audiobook] { [] }
    func startPlayback(itemID: String) async throws -> PlaybackSession {
      try await Task.sleep(for: networkLatency)
      return .init(
        id: "session-" + itemID, currentTime: sessionPosition ?? remote.currentTime,
        duration: remote.duration,
        chapters: [], streamURLs: [URL(string: "https://example.test/audio")!])
    }
    func chapters(itemID: String) -> [Chapter] { [] }
    func progress(itemID: String) async throws -> ABSProgress {
      try await Task.sleep(for: networkLatency)
      if let progressError { throw progressError }
      let snapshot = remote
      if shouldDelayProgress {
        shouldDelayProgress = false
        await withCheckedContinuation { continuation in
          pendingProgress = continuation
          progressObserver?.resume()
          progressObserver = nil
        }
      }
      return snapshot
    }
    func coverData(itemID: String) throws -> Data {
      if let fixtureCover { return fixtureCover }
      throw URLError(.notConnectedToInternet)
    }
    func mediaData(url: URL, range: String?) async throws -> AuthenticatedMediaResponse {
      if let mediaProvider { return try await mediaProvider(url, range) }
      throw URLError(.notConnectedToInternet)
    }
    func pushProgress(
      itemID: String, position: TimeInterval, duration: TimeInterval, isFinished: Bool
    ) {
      writes.append(position)
      remote = .init(
        currentTime: position, duration: duration, isFinished: isFinished,
        lastUpdate: remote.lastUpdate + 1)
    }
    func sync(
      sessionID: String, position: TimeInterval, duration: TimeInterval, timeListened: TimeInterval
    ) { writes.append(position) }
    func close(
      sessionID: String, position: TimeInterval, duration: TimeInterval, timeListened: TimeInterval
    ) {
      closedSessions.append(sessionID)
      writes.append(position)
    }
    func logout() {}
  }

  @MainActor
  func fixtureBook(_ id: String = "book") -> Audiobook {
    .init(
      id: id, title: "Ranger's Apprentice", authors: ["John Flanagan"], series: [],
      lastPlayedAt: nil, duration: 1_000)
  }

  // Synthetic artwork exercises fitting and contrast without shipping a book-cover asset.
  @MainActor
  func fixtureCover(portrait: Bool) -> Data? {
    let size = NSSize(width: portrait ? 180 : 260, height: 260)
    let image = NSImage(size: size)
    image.lockFocus()
    NSColor(red: 0.08, green: 0.18, blue: 0.24, alpha: 1).setFill()
    NSRect(origin: .zero, size: size).fill()
    NSColor(red: 0.88, green: 0.68, blue: 0.34, alpha: 1).setFill()
    NSBezierPath(ovalIn: NSRect(x: size.width / 2 - 48, y: 78, width: 96, height: 96)).fill()
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    let title = "RANGER'S\nAPPRENTICE"
    title.draw(
      in: NSRect(x: 8, y: 177, width: size.width - 16, height: 60),
      withAttributes: [
        .font: NSFont.systemFont(ofSize: 19, weight: .bold), .foregroundColor: NSColor.white,
        .paragraphStyle: paragraph,
      ])
    "JOHN FLANAGAN".draw(
      in: NSRect(x: 8, y: 25, width: size.width - 16, height: 20),
      withAttributes: [
        .font: NSFont.systemFont(ofSize: 11, weight: .medium), .foregroundColor: NSColor.white,
        .paragraphStyle: paragraph,
      ])
    image.unlockFocus()
    return image.tiffRepresentation
  }

  actor TestConnectionStore: ConnectionStoring {
    var connection: StoredCredentials?
    var tokens: AuthenticationTokens?
    var library: String?
    func save(connection: StoredCredentials, tokens: AuthenticationTokens) {
      self.connection = connection
      self.tokens = tokens
    }
    func loadConnection() -> StoredCredentials? { connection }
    func loadCredentials() -> StoredCredentials? { connection }
    func loadTokens() -> AuthenticationTokens? { tokens }
    func save(tokens: AuthenticationTokens) { self.tokens = tokens }
    func clearTokens() { tokens = nil }
    func saveSelectedLibrary(_ id: String) { library = id }
    func loadSelectedLibrary() -> String? { library }
    func clear() {
      connection = nil
      tokens = nil
      library = nil
    }
  }

#endif
