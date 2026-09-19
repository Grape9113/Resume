import AVFoundation
import AppKit
import Foundation
import MediaPlayer
import Testing

@testable import ResumeCore

@Suite("Resume application")
struct ResumeApplicationTests {
  @Test("printable input starts Search without losing the first character")
  func printableInputStartsSearch() {
    var application = ResumeApplication(mode: .player)

    application.send(.typed("m"))

    #expect(application.mode == .search(query: "m"))
  }

  @Test("Space controls playback only in Player mode")
  func spaceHasModeSpecificMeaning() {
    var player = ResumeApplication(mode: .player)
    player.send(.space)
    #expect(player.playbackIntent == .playing)

    var search = ResumeApplication(mode: .search(query: "ranger"))
    search.send(.space)
    #expect(search.mode == .search(query: "ranger "))
    #expect(search.playbackIntent == .paused)
  }

  @Test("Book progress is whole-book and read-only")
  func bookProgressIsReadOnly() {
    var application = ResumeApplication(
      mode: .player,
      playback: .init(position: 3_600, duration: 14_400)
    )

    application.send(.progressPointerInteraction(proposedPosition: 7_200))

    #expect(application.playback.position == 3_600)
    #expect(application.bookProgress == 0.25)
  }

  @Test("chapter navigation deliberately changes position without autoplay")
  func chapterNavigationIsDeliberate() {
    var application = ResumeApplication(
      mode: .player,
      playback: .init(position: 120, duration: 7_200),
      chapters: [.init(id: "chapter-2", title: "Chapter 2", start: 900)]
    )

    application.send(.selectChapter(id: "chapter-2"))

    #expect(application.playback.position == 900)
    #expect(application.playbackIntent == .paused)
  }
}

@Suite("Shipped application behavior")
@MainActor
struct AppModelTests {
  @Test("network recovery cannot start an item whose initial seek is still preparing")
  func networkRecoveryWaitsForPreparation() async {
    let player = TestPlayer()
    player.delayLoad = true
    let model = AppModel(
      client: TestAudiobookshelf(), player: player,
      stateStore: MemoryStateStore(), startsAutomatically: false)
    model.activeBook = fixtureBook()
    let start = Task { await model.togglePlayback() }
    await player.waitUntilLoading()
    await model.networkBecameAvailable()
    #expect(!player.playing)
    #expect(model.isLoadingPlayback)
    player.finishLoading()
    await start.value
    #expect(player.playing)
  }

  @Test("rejected credentials on pause offer inline reconnection and retain progress")
  func pauseAuthenticationFailureIsActionable() async {
    let server = TestAudiobookshelf()
    let model = AppModel(
      client: server, player: TestPlayer(),
      stateStore: MemoryStateStore(), startsAutomatically: false)
    model.activeBook = fixtureBook()
    await model.togglePlayback()
    model.position = 110
    await server.setProgressError(AudiobookshelfClientError.authenticationRequired)
    await model.togglePlayback()
    #expect(model.mode == .connection)
    #expect(model.errorMessage?.contains("password") == true)
    #expect(model.hasPendingSynchronization)
    #expect(model.position == 110)
  }

  @Test("failed media preparation stops loading and offers a retry")
  func failedPreparationStopsLoading() async {
    let player = TestPlayer()
    player.loadError = URLError(.cannotDecodeContentData)
    let model = AppModel(
      client: TestAudiobookshelf(), player: player,
      stateStore: MemoryStateStore(), startsAutomatically: false)
    model.activeBook = fixtureBook()
    await model.togglePlayback()
    #expect(!model.isLoadingPlayback)
    #expect(!model.wantsPlayback)
    #expect(model.errorMessage == "Playback couldn’t start. Try Play again.")
    #expect(!player.playing)
  }

  @Test("pause coalesces an in-flight periodic sync into one final position write")
  func pauseCoalescesProgressWrite() async {
    let server = TestAudiobookshelf()
    let player = TestPlayer()
    let model = AppModel(
      client: server, player: player,
      stateStore: MemoryStateStore(), startsAutomatically: false)
    model.activeBook = fixtureBook()
    await model.togglePlayback()
    await server.delayNextProgress()
    let tick = Task {
      await model.receivePlayerUpdate(position: 130, duration: 1_000, playing: true)
    }
    await server.waitUntilProgressRequested()
    let pause = Task { await model.togglePlayback() }
    while model.wantsPlayback { await Task.yield() }
    #expect(!player.playing)
    await server.releaseProgress()
    await tick.value
    await pause.value
    #expect(await server.writes == [130])
    #expect(await server.closedSessions == ["session-book"])
    #expect(!model.isLoadingPlayback)
  }

  @Test("background position refresh failures do not leave a persistent warning")
  func transientProgressFailureIsQuiet() async {
    let server = TestAudiobookshelf()
    let model = AppModel(
      client: server, player: TestPlayer(),
      stateStore: MemoryStateStore(), startsAutomatically: false)
    model.activeBook = fixtureBook()
    model.position = 100
    await server.setProgressError(URLError(.timedOut))
    await model.networkBecameAvailable()
    #expect(model.errorMessage == nil)
    #expect(model.position == 100)
    await server.setProgressError(nil)
    await model.networkBecameAvailable()
    #expect(model.errorMessage == nil)
  }

  @Test("startup latency trace separates service round trips and player preparation")
  func startupLatencyTrace() async {
    let server = TestAudiobookshelf()
    await server.setNetworkLatency(.milliseconds(100))
    let player = TestPlayer()
    player.loadLatency = .milliseconds(100)
    let model = AppModel(
      client: server, player: player,
      stateStore: MemoryStateStore(), startsAutomatically: false)
    model.activeBook = fixtureBook()
    let start = ContinuousClock.now
    await model.togglePlayback()
    let elapsed = start.duration(to: .now)
    print("Startup fixture: two 100ms service responses + 100ms preparation: \(elapsed)")
    #expect(player.playing)
  }

  @Test("preparing an item cannot publish its unseeked position")
  func preparingKeepsAuthoritativePosition() async {
    let player = TestPlayer()
    player.delayLoad = true
    let model = AppModel(
      client: TestAudiobookshelf(), player: player,
      stateStore: MemoryStateStore(), startsAutomatically: false)
    model.activeBook = fixtureBook()
    model.position = 100
    model.duration = 1_000
    let start = Task { await model.togglePlayback() }
    await player.waitUntilLoading()
    #expect(model.isLoadingPlayback)
    await model.receivePlayerUpdate(position: 0, duration: 0, playing: false)
    #expect(model.position == 100)
    #expect(model.duration == 1_000)
    player.finishLoading()
    await start.value
    #expect(model.isLoadingPlayback)
    await model.receivePlayerUpdate(position: 100, duration: 1_000, playing: true)
    #expect(!model.isLoadingPlayback)
  }

  @Test("pausing and resuming does not extend the original recovery hour")
  func resumeDoesNotRenewRecovery() async {
    let clock = TestClock()
    let server = TestAudiobookshelf()
    let player = TestPlayer()
    let model = AppModel(
      client: server, player: player,
      stateStore: MemoryStateStore(), now: { clock.now }, startsAutomatically: false)
    model.activeBook = fixtureBook()
    model.position = 300
    model.duration = 1_000
    await model.networkBecameAvailable()
    await model.togglePlayback()
    await model.togglePlayback()
    clock.now = clock.now.addingTimeInterval(1_800)
    await model.togglePlayback()
    clock.now = clock.now.addingTimeInterval(1_801)
    await model.receivePlayerUpdate(position: 100, duration: 1_000, playing: true)
    #expect(model.knownPositions.isEmpty)
  }

  @Test("playback uses the server session start and preserves the displaced Mac position")
  func serverSessionDeterminesStart() async {
    let server = TestAudiobookshelf()
    await server.setSessionPosition(250)
    let player = TestPlayer()
    let model = AppModel(
      client: server, player: player,
      stateStore: MemoryStateStore(), startsAutomatically: false)
    model.activeBook = fixtureBook()
    model.position = 100
    await model.togglePlayback()
    #expect(model.position == 250)
    #expect(player.position == 250)
    #expect(model.knownPositions.contains { $0.position == 100 })
  }

  @Test("reconnect preserves active Mac playback while concurrent server progress suspends writes")
  func reconnectDuringConcurrentPlayback() async {
    let server = TestAudiobookshelf()
    let player = TestPlayer()
    let model = AppModel(
      client: server, player: player,
      stateStore: MemoryStateStore(), startsAutomatically: false)
    model.activeBook = fixtureBook()
    await model.togglePlayback()
    await model.receivePlayerUpdate(position: 500, duration: 1_000, playing: true)
    let previousWrites = await server.writes
    await server.setRemote(position: 300, baseline: 2)
    model.receiveExternalProgress(
      .init(
        itemID: "book", sessionID: "other-session",
        progress: .init(currentTime: 300, duration: 1_000, isFinished: false, lastUpdate: 2)))
    await model.networkBecameAvailable()
    #expect(model.position == 500)
    #expect(player.playing)
    #expect(model.hasPendingSynchronization)
    #expect(await server.writes == previousWrites)
  }

  @Test("sign-out unloads audio and abandons pending resets without server writes")
  func signOutForgetsPlayback() async throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let domain = "ResumeTests." + UUID().uuidString
    let preferences = try #require(UserDefaults(suiteName: domain))
    defer { preferences.removePersistentDomain(forName: domain) }
    let player = TestPlayer()
    let server = TestAudiobookshelf()
    let vault = TestConnectionStore()
    let storage = MemoryStateStore()
    let model = AppModel(
      client: server, player: player, stateStore: storage, vault: vault,
      artworkStore: ArtworkStore(directory: directory), preferences: preferences,
      startsAutomatically: false)
    model.activeBook = fixtureBook()
    await model.togglePlayback()
    model.recentlyFinishedAt["book"] = .distantPast
    await model.signOut()
    #expect(!player.hasItem)
    #expect(!player.playing)
    #expect(model.activeBook == nil)
    #expect(model.knownPositions.isEmpty && model.speeds.isEmpty)
    #expect(model.recentlyFinishedAt.isEmpty)
    #expect(await storage.load() == nil)
    #expect(await server.writes.isEmpty)
  }

  @Test(
    "only actual playback at or above 95 percent marks finished",
    arguments: [949.0, 950.0, 951.0], [false, true])
  func completionRequiresPlayback(position: Double, playing: Bool) async {
    let server = TestAudiobookshelf()
    let player = TestPlayer()
    let model = AppModel(
      client: server, player: player,
      stateStore: MemoryStateStore(), startsAutomatically: false)
    model.activeBook = fixtureBook()
    await model.togglePlayback()
    if !playing { await model.togglePlayback() }
    model.selectChapter(.init(id: "ending", title: "Ending", start: position))
    await model.receivePlayerUpdate(position: position, duration: 1_000, playing: playing)
    #expect(await server.remote.isFinished == (playing && position >= 950))
    #expect(player.playing == playing)
  }

  @Test("choosing a conflict position resolves ambiguity without autoplay or a forced write")
  func recoveryResolvesConflict() async {
    let server = TestAudiobookshelf()
    let player = TestPlayer()
    let model = AppModel(
      client: server, player: player,
      stateStore: MemoryStateStore(), startsAutomatically: false)
    model.activeBook = fixtureBook()
    model.position = 300
    model.duration = 1_000
    model.wantsPlayback = true
    model.receiveExternalProgress(
      .init(
        itemID: "book", sessionID: nil,
        progress: .init(currentTime: 100, duration: 1_000, isFinished: false, lastUpdate: 1)))
    model.wantsPlayback = false
    let choice = model.knownPositions.first { $0.source == .thisMac }!
    #expect(model.needsPositionRecovery)
    await model.recover(choice)
    #expect(!model.needsPositionRecovery)
    #expect(model.position == 300)
    #expect(!player.playing)
    #expect(await server.writes.isEmpty)
    // Automatic reconciliation can now write the chosen position, rather than re-suspend.
    await model.networkBecameAvailable()
    #expect(await server.remote.currentTime == 300)
    #expect(!model.hasPendingSynchronization)
  }

  @Test("starting after recovery does not authorize overwriting newly moved server progress")
  func recoveredChoiceChecksServerAgainAtStart() async {
    let server = TestAudiobookshelf()
    let model = AppModel(
      client: server, player: TestPlayer(),
      stateStore: MemoryStateStore(), startsAutomatically: false)
    model.activeBook = fixtureBook()
    model.duration = 1_000
    model.position = 300
    await model.networkBecameAvailable()
    await model.recover(model.knownPositions.first { $0.position == 300 }!)
    await server.setRemote(position: 500, baseline: 2)
    await model.togglePlayback()
    await model.togglePlayback()
    #expect(await server.writes.isEmpty)
    #expect(model.knownPositions.contains { $0.position == 300 })
  }

  @Test("a replay protected from an expired reset can become Recently finished again")
  func replayAfterExpiredFinishCanFinishAgain() async {
    let instant = Date(timeIntervalSince1970: 1_000_000)
    var saved = LocalState()
    saved.books = [fixtureBook()]
    saved.activeBookID = "book"
    saved.playback.update("book") {
      $0.position = 970
      $0.recentlyFinishedAt = instant.addingTimeInterval(-CompletionPolicy.lifetime)
    }
    let server = TestAudiobookshelf()
    await server.setRemote(position: 200, finished: false, baseline: 1_000_000_000)
    let player = TestPlayer()
    let model = AppModel(
      client: server, player: player,
      stateStore: MemoryStateStore(saved), vault: TestConnectionStore(),
      now: { instant }, startsAutomatically: false)
    await model.restore()
    await model.systemDidWake()
    #expect(await server.writes.isEmpty)
    #expect(model.position == 200)
    await model.togglePlayback()
    await model.receivePlayerUpdate(position: 950, duration: 1_000, playing: true)
    #expect(await server.remote.isFinished)
    #expect(model.isRecentlyFinished(fixtureBook()))
  }

  @Test("external progress while paused adopts server state and preserves the Mac position")
  func pausedExternalProgress() {
    let model = AppModel(
      client: TestAudiobookshelf(), player: TestPlayer(),
      stateStore: MemoryStateStore(), startsAutomatically: false)
    model.activeBook = fixtureBook()
    model.position = 100
    model.duration = 1_000
    model.receiveExternalProgress(
      .init(
        itemID: "book", sessionID: nil,
        progress: .init(currentTime: 300, duration: 1_000, isFinished: false, lastUpdate: 2)))
    #expect(model.position == 300)
    #expect(model.knownPositions.contains { $0.position == 100 && $0.source == .thisMac })
    #expect(!model.wantsPlayback)
  }

  @Test("a delayed recovery response cannot change a newly selected book")
  func staleRecoveryDoesNotChangeNewBook() async {
    let server = TestAudiobookshelf()
    let model = AppModel(
      client: server, player: TestPlayer(),
      stateStore: MemoryStateStore(), startsAutomatically: false)
    model.activeBook = fixtureBook("first")
    let choice = KnownPosition(position: 200, source: .thisMac, observedAt: .now)
    model.knownPositions = [choice]
    await server.delayNextProgress()
    let recovery = Task { await model.recover(choice) }
    await server.waitUntilProgressRequested()
    await server.setRemote(position: 300)
    model.books = [fixtureBook("second")]
    model.beginSearch(with: "ranger")
    await model.acceptSearch()
    await server.releaseProgress()
    await recovery.value
    #expect(model.activeBook?.id == "second")
    #expect(model.position == 300)
  }

  @Test("a moved server position refreshes recovery choices before accepting an older choice")
  func recoveryChecksLatestServer() async {
    let server = TestAudiobookshelf()
    let player = TestPlayer()
    let model = AppModel(
      client: server, player: player,
      stateStore: MemoryStateStore(), startsAutomatically: false)
    model.activeBook = fixtureBook()
    model.duration = 1_000
    model.position = 300
    model.wantsPlayback = true
    model.receiveExternalProgress(
      .init(
        itemID: "book", sessionID: nil,
        progress: .init(currentTime: 100, duration: 1_000, isFinished: false, lastUpdate: 1)))
    model.wantsPlayback = false
    #expect(model.needsPositionRecovery)
    let choice = model.knownPositions.first { $0.source == .thisMac }!
    await server.setRemote(position: 500, baseline: 2)
    await model.recover(choice)
    #expect(model.needsPositionRecovery)
    #expect(model.position == 300)
    #expect(model.knownPositions.contains { $0.position == 500 && $0.source == .audiobookshelf })
    #expect(await server.writes.isEmpty)
    let refreshedChoice = model.knownPositions.first { $0.source == .thisMac }!
    await model.recover(refreshedChoice)
    #expect(!model.needsPositionRecovery)
    #expect(!player.playing)
    await model.networkBecameAvailable()
    #expect(await server.remote.currentTime == 300)
  }

  @Test("an unloaded player cannot erase the cached position or duration")
  func unloadedPlayerUpdateIsIgnored() async {
    let player = TestPlayer()
    let model = AppModel(
      client: TestAudiobookshelf(), player: player,
      stateStore: MemoryStateStore(), startsAutomatically: false)
    model.activeBook = fixtureBook()
    model.position = 500
    model.duration = 1_000
    await model.receivePlayerUpdate(position: 0, duration: 0, playing: false)
    #expect(model.position == 500)
    #expect(model.duration == 1_000)
  }

  @Test("wake retries pending progress against its baseline without autoplay")
  func wakePreservesPendingProgress() async {
    let server = TestAudiobookshelf()
    let player = TestPlayer()
    var saved = LocalState()
    saved.books = [fixtureBook()]
    saved.activeBookID = "book"
    saved.playback.update("book") {
      $0.position = 250
      $0.synchronization = .init(serverBaseline: 1, lastSyncedPosition: 100, pendingPosition: 250)
    }
    let model = AppModel(
      client: server, player: player,
      stateStore: MemoryStateStore(saved), vault: TestConnectionStore(), startsAutomatically: false)
    await model.restore()
    await model.systemDidWake()
    #expect(await server.writes == [250])
    #expect(model.position == 250)
    #expect(!player.playing)
    #expect(!model.hasPendingSynchronization)
  }

  @Test("accepting Search closes the previous session before changing books and stays paused")
  func selectionClosesPreviousSession() async {
    let server = TestAudiobookshelf()
    let player = TestPlayer()
    let model = AppModel(
      client: server, player: player,
      stateStore: MemoryStateStore(), startsAutomatically: false)
    model.activeBook = fixtureBook("first")
    await model.togglePlayback()
    model.books = [fixtureBook("second")]
    model.beginSearch(with: "ranger")
    await model.acceptSearch()
    #expect(await server.closedSessions == ["session-first"])
    #expect(model.activeBook?.id == "second")
    #expect(!model.wantsPlayback)
    #expect(!player.playing)
  }

  @Test("a second toggle cancels a pending play request without surprise audio")
  func pauseDuringLoading() async {
    let player = TestPlayer()
    player.delayLoad = true
    let model = AppModel(
      client: TestAudiobookshelf(), player: player,
      stateStore: MemoryStateStore(), startsAutomatically: false)
    model.activeBook = fixtureBook()
    let start = Task { await model.togglePlayback() }
    await player.waitUntilLoading()
    await model.togglePlayback()
    player.finishLoading()
    await start.value
    #expect(!model.wantsPlayback)
    #expect(!player.playing)
  }

  @Test("pausing clears playing intent so reconnection cannot resume playback")
  func pauseClearsIntent() async {
    let player = TestPlayer()
    player.hasItem = true
    player.play()
    let model = AppModel(
      client: TestAudiobookshelf(), player: player,
      stateStore: MemoryStateStore(), startsAutomatically: false)
    model.activeBook = fixtureBook()
    model.isPlaying = true
    model.wantsPlayback = true
    await model.togglePlayback()
    #expect(!model.wantsPlayback)
    #expect(!model.isPlaying)
    #expect(!player.playing)
  }

  @Test("opening Settings cancels Search without changing playback")
  func settingsCancelsSearch() {
    let model = AppModel(stateStore: MemoryStateStore(), startsAutomatically: false)
    model.mode = .player
    model.beginSearch(with: "ranger")
    model.prepareForSettings()
    #expect(model.mode == .player)
    #expect(model.query.isEmpty)
    #expect(model.searchResult == nil)
    model.prepareForSettings()
    #expect(model.mode == .player)
  }
}

@Suite("Playback adapter", .serialized)
@MainActor
struct AudioPlayerTests {
  @Test("Play reaches observed native playback with stable progress and truthful loading")
  func applicationToNativePlayback() async throws {
    let media = SilentAudiobookServer()
    let service = TestAudiobookshelf()
    await service.setNetworkLatency(.milliseconds(100))
    await service.setMediaProvider { url, range in try await media.response(url: url, range: range)
    }
    var model: AppModel?
    let player = AudioPlayer(
      update: { position, duration, playing in
        Task {
          await model?.receivePlayerUpdate(position: position, duration: duration, playing: playing)
        }
      }, stalled: {}, ended: {})
    defer { player.clear() }
    let application = AppModel(
      client: service, player: player,
      stateStore: MemoryStateStore(), startsAutomatically: false)
    model = application
    application.activeBook = fixtureBook()
    application.position = 100
    application.duration = 1_000
    let start = ContinuousClock.now
    await application.togglePlayback()
    let preparation = start.duration(to: .now)
    while !application.isPlaying && start.duration(to: .now) < .seconds(3) {
      #expect(application.position >= 100)
      try await Task.sleep(for: .milliseconds(10))
    }
    print("Full Play path: prepared \(preparation); observed playback \(start.duration(to: .now))")
    #expect(application.isPlaying)
    #expect(!application.isLoadingPlayback)
    #expect(application.position >= 100)
  }

  @Test("real playback starts promptly at the book position", arguments: [1, 3])
  func realPlaybackStartup(parts: Int) async throws {
    let server = SilentAudiobookServer()
    let position: Double = parts == 1 ? 1800 : 4500
    var lastPosition: Double = 0
    var observedPositions: [Double] = []
    let player = AudioPlayer(
      update: { time, _, _ in
        lastPosition = time
        observedPositions.append(time)
      }, stalled: {}, ended: {})
    defer { player.clear() }
    // Also bounds a broken seek: unloading resolves AVPlayer's pending seek completion.
    let deadline = Task {
      try await Task.sleep(for: .seconds(3))
      player.clear()
    }
    defer { deadline.cancel() }
    let start = ContinuousClock.now
    try await player.load(
      urls: (0..<parts).map { URL(string: "https://example.test/part-\($0).wav")! },
      fetch: { url, range in try await server.response(url: url, range: range) },
      position: position, speed: 2, title: "Silent fixture", author: "Test",
      bookDuration: Double(parts * 3600))
    let preparation = start.duration(to: .now)
    print("Native \(parts)-part preparation: \(preparation)")
    #expect(preparation < .seconds(1))
    let startupBytes = await server.bytesSent
    #expect(startupBytes < parts * 4 * 1024 * 1024)
    player.play()
    while lastPosition <= position && start.duration(to: .now) < .seconds(3) {
      try await Task.sleep(for: .milliseconds(25))
    }
    print("Native \(parts)-part time-to-advancing-playback: \(start.duration(to: .now))")
    #expect(observedPositions.allSatisfy { $0 >= position - 1 })
    #expect(lastPosition > position)
    #expect(lastPosition < position + 6)
    player.clear()
    try await Task.sleep(for: .milliseconds(100))
    let stoppedBytes = await server.bytesSent
    try await Task.sleep(for: .milliseconds(100))
    #expect(await server.bytesSent == stoppedBytes)
  }

  @Test("system artwork requests work off the main actor")
  func backgroundArtworkRequest() async throws {
    let player = AudioPlayer(update: { _, _, _ in }, stalled: {}, ended: {})
    MPNowPlayingInfoCenter.default().nowPlayingInfo = [MPMediaItemPropertyTitle: "Test book"]
    let bitmap = try #require(
      NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: 32, pixelsHigh: 32,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 128, bitsPerPixel: 32))
    bitmap.bitmapData?.initialize(repeating: 0, count: 4096)
    let image = NSImage(cgImage: try #require(bitmap.cgImage), size: NSSize(width: 32, height: 32))
    player.setArtwork(image)
    let artwork = try #require(
      MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPMediaItemPropertyArtwork]
        as? MPMediaItemArtwork)
    let request = BackgroundArtworkRequest(artwork: artwork)
    let size = await Task.detached {
      request.artwork.image(at: NSSize(width: 32, height: 32))?.size
    }.value
    #expect(size == NSSize(width: 32, height: 32))
    player.clear()
  }

  @Test("speed chosen while paused remains the speed used on resume")
  func pausedSpeedIsRemembered() {
    let player = AudioPlayer(update: { _, _, _ in }, stalled: {}, ended: {})
    player.rate = 2.5
    #expect(player.rate == 2.5)
    player.pause()
    #expect(player.rate == 2.5)
  }
}

@MainActor
private final class TestClock {
  var now = Date(timeIntervalSince1970: 1_000_000)
}

@Suite("Artwork cache")
@MainActor
struct ArtworkStoreTests {
  @Test("concurrent cover decoding is safe and bounded to display size")
  func concurrentCoverDecoding() async throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let bitmap = try #require(
      NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: 2048, pixelsHigh: 64,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 8192, bitsPerPixel: 32))
    bitmap.bitmapData?.initialize(repeating: 0, count: 8192 * 64)
    let data = try #require(bitmap.representation(using: .png, properties: [:]))
    try await withThrowingTaskGroup(of: Void.self) { group in
      for index in 0..<12 {
        group.addTask {
          let store = ArtworkStore(directory: directory.appending(path: "\(index)"))
          let saved = try await store.save(data, itemID: "book", revision: "1")
          let cached = try #require(await store.image(itemID: "book", revision: "1"))
          await MainActor.run {
            #expect(saved.size == NSSize(width: 1024, height: 32))
            #expect(cached.size == saved.size)
          }
        }
      }
      try await group.waitForAll()
    }
  }

  @Test("artwork can be cached again after sign-out clears the cache")
  func cacheWorksAfterClear() async throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let bitmap = try #require(
      NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: 1, pixelsHigh: 1,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 4, bitsPerPixel: 32))
    bitmap.bitmapData?.initialize(repeating: 0, count: 4)
    let data = try #require(bitmap.representation(using: .png, properties: [:]))
    let cache = ArtworkStore(directory: directory)
    _ = try await cache.save(data, itemID: "first", revision: "1")
    await cache.clear()
    _ = try await cache.save(data, itemID: "second", revision: "1")
    #expect(await cache.image(itemID: "second", revision: "1") != nil)
  }
}

@Suite("Streaming startup")
struct StreamingStartupTests {
  @Test("cancelling media preparation cancels its network request")
  func cancellationStopsNetwork() async throws {
    let probe = CancelledMediaRequest()
    let loader = try AuthenticatedAssetLoader(url: URL(string: "https://example.test/book.wav")!) {
      _, _ in try await probe.fetch()
    }
    let load = Task { try await loader.asset.load(.duration) }
    let start = ContinuousClock.now
    while !(await probe.started) && start.duration(to: .now) < .seconds(1) {
      try await Task.sleep(for: .milliseconds(10))
    }
    #expect(await probe.started)
    loader.cancel()
    while !(await probe.cancelled) && start.duration(to: .now) < .seconds(2) {
      try await Task.sleep(for: .milliseconds(10))
    }
    #expect(await probe.cancelled)
    _ = await load.result
  }

  @Test("a long audiobook becomes readable without downloading the whole file")
  func boundedStartup() async throws {
    let server = SilentAudiobookServer()
    let loader = try AuthenticatedAssetLoader(url: URL(string: "https://example.test/book.wav")!) {
      url, range in try await server.response(url: url, range: range)
    }
    defer { loader.cancel() }
    let duration = try await loader.asset.load(.duration)
    #expect(abs(duration.seconds - 3600) < 1)
    #expect(await server.bytesSent < 1024 * 1024)
  }
}

private actor SilentAudiobookServer {
  private(set) var bytesSent = 0
  func response(url: URL, range: String?) async throws -> AuthenticatedMediaResponse {
    // One hour of PCM silence, generated by range rather than allocating a full book.
    let length = 44 + 3600 * 8000 * 2
    var header = Data("RIFF".utf8)
    func append(_ value: UInt32, bytes: Int = 4) {
      for index in 0..<bytes { header.append(UInt8(truncatingIfNeeded: value >> (index * 8))) }
    }
    append(UInt32(length - 8))
    header.append(Data("WAVEfmt ".utf8))
    append(16)
    append(1, bytes: 2)
    append(1, bytes: 2)
    append(8000)
    append(16000)
    append(2, bytes: 2)
    append(16, bytes: 2)
    header.append(Data("data".utf8))
    append(UInt32(length - 44))
    let bounds = (range ?? "").replacingOccurrences(of: "bytes=", with: "")
      .split(separator: "-", omittingEmptySubsequences: false)
    let start = bounds.first.flatMap { Int($0) } ?? 0
    let end = bounds.count == 2 ? (Int(bounds[1]) ?? length - 1) : length - 1
    guard end - start + 1 <= 256 * 1024 else {
      Issue.record(
        "Startup requested \(range ?? "the entire book") instead of bounded streaming bytes")
      throw URLError(.timedOut)
    }
    try await Task.sleep(for: .milliseconds(10))
    let upper = min(end + 1, length)
    var data = Data(repeating: 0, count: max(0, upper - start))
    if start < header.count {
      data.replaceSubrange(
        0..<min(data.count, header.count - start),
        with: header[start..<min(upper, header.count)])
    }
    bytesSent += data.count
    return AuthenticatedMediaResponse(
      data: data, statusCode: 206,
      expectedContentLength: Int64(data.count), mimeType: "audio/wav",
      contentRange: "bytes \(start)-\(upper - 1)/\(length)", acceptsRanges: true)
  }
}

// The system invokes this immutable artwork object from its own queue.
private struct BackgroundArtworkRequest: @unchecked Sendable {
  let artwork: MPMediaItemArtwork
}

private actor CancelledMediaRequest {
  private(set) var started = false
  private(set) var cancelled = false
  func fetch() async throws -> AuthenticatedMediaResponse {
    started = true
    do { try await Task.sleep(for: .seconds(30)) } catch {
      cancelled = true
      throw error
    }
    throw URLError(.timedOut)
  }
}
