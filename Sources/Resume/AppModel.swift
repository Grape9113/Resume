import AppKit
import Observation
import ResumeCore
import ServiceManagement

@MainActor @Observable
final class AppModel {
  enum Mode { case connection, library, player, search, settings, chapters }

  var mode: Mode = .connection
  var server = ""
  var username = ""
  var password = ""
  var libraries: [ABSLibrary] = []
  var books: [Audiobook] = []
  var activeBook: Audiobook?
  var query = ""
  var searchResult: Audiobook?
  var position: TimeInterval = 0
  var duration: TimeInterval = 0
  var isPlaying = false
  var wantsPlayback = false
  var speed = 2.0
  var chapters: [Chapter] = []
  var knownPositions: [KnownPosition] = []
  var errorMessage: String?
  var hasPendingSynchronization = false
  var isBusy = false
  var launchAtLogin = SMAppService.mainApp.status == .enabled
  var selectedLibraryName = ""
  var recentlyFinishedAt: [String: Date] = [:]
  var speeds: [String: Double] = [:]

  @ObservationIgnored private let vault = KeychainStore()
  @ObservationIgnored private let stateStore = LocalStateStore()
  @ObservationIgnored private let artworkStore = ArtworkStore()
  @ObservationIgnored private let progressEvents = ProgressEventClient()
  @ObservationIgnored private lazy var systemMonitor = SystemMonitor(
    onNetworkAvailable: { [weak self] in Task { await self?.networkBecameAvailable() } },
    onOutputDeviceChanged: { [weak self] in self?.outputDeviceChanged() }
  )
  @ObservationIgnored private lazy var client = AudiobookshelfClient(vault: vault)
  @ObservationIgnored private lazy var player = AudioPlayer(
    update: { [weak self] position, duration, playing in
      Task { @MainActor in
        await self?.receivePlayerUpdate(position: position, duration: duration, playing: playing)
      }
    },
    stalled: { [weak self] in self?.playbackStalled() },
    ended: { [weak self] in self?.playbackEnded() }
  )
  @ObservationIgnored private var playbackSessionID: String?
  @ObservationIgnored private var lastSyncedPosition: TimeInterval = 0
  @ObservationIgnored private var didMarkFinished = false
  @ObservationIgnored private var localState = LocalState()
  @ObservationIgnored private var synchronization = SynchronizationState()
  @ObservationIgnored private var recoveryExpiresAt: Date?
  @ObservationIgnored private var usesRecoveredPosition = false
  @ObservationIgnored private var libraryRefreshTask: Task<Void, Never>?
  @ObservationIgnored private var lastPlaybackTickInstant: ContinuousClock.Instant?
  @ObservationIgnored private var listenedSinceSync: TimeInterval = 0
  @ObservationIgnored private var synchronizationFailureCount = 0
  @ObservationIgnored private var nextSynchronizationAttemptAt: Date?
  @ObservationIgnored private var synchronizationRetryTask: Task<Void, Never>?

  init() {
    _ = systemMonitor
    player.configureRemoteCommands(
      play: { [weak self] in
        guard let self, !self.isPlaying else { return }
        await self.togglePlayback()
      },
      pause: { [weak self] in
        guard let self, self.isPlaying else { return }
        self.wantsPlayback = false
        self.isPlaying = false
        self.player.pause()
        Task { await self.closePlaybackSession() }
      },
      toggle: { [weak self] in await self?.togglePlayback() },
      skip: { [weak self] amount in self?.skip(amount) },
      seek: { [weak self] position in
        guard let self else { return }
        self.preserve(self.position, source: .thisMac, comparedWith: position)
        self.seek(to: position)
      }
    )
    Task { await restore() }
  }

  func restore() async {
    if var local = await stateStore.load() {
      local.playback.prepareForProcessStart(now: .now)
      localState = local
      books = local.books
      activeBook = local.activeBookID.flatMap { id in books.first { $0.id == id } }
      if let activeBook {
        applyPlaybackRecord(for: activeBook)
        mode = .player
      }
      speeds = local.playback.records.mapValues(\.speed)
      recentlyFinishedAt = local.playback.records.compactMapValues(\.recentlyFinishedAt)
    }
    guard let connection = try? await vault.loadConnection() else { return }
    server = connection.server.absoluteString
    username = connection.username
    do {
      try await loadLibrary()
    } catch AudiobookshelfClientError.authenticationRequired {
      mode = .connection
      errorMessage = "Your Audiobookshelf session expired. Enter your password to reconnect."
    } catch {
      errorMessage = "Couldn’t reconnect. Check the server or sign in again."
    }
  }

  func connect() async {
    guard let url = URL(string: server), url.scheme == "https" else {
      errorMessage = "Enter the HTTPS address of your PikaPods server."
      return
    }
    isBusy = true
    defer { isBusy = false }
    do {
      try await client.login(server: url, username: username, password: password)
      password = ""
      libraries = try await client.libraries()
      let audiobookLibraries = libraries.filter { $0.mediaType == "book" }
      if audiobookLibraries.count == 1, let only = audiobookLibraries.first {
        try await chooseLibrary(only)
      } else {
        libraries = audiobookLibraries
        mode = .library
      }
      setLaunchAtLogin(true)
    } catch {
      errorMessage = "Sign-in failed. Check the address, username, and password."
    }
  }

  func chooseLibrary(_ library: ABSLibrary) async throws {
    await vault.saveSelectedLibrary(library.id)
    selectedLibraryName = library.name
    UserDefaults.standard.set(library.name, forKey: "selectedLibraryName")
    try await loadLibrary()
  }

  func loadLibrary() async throws {
    guard let libraryID = await vault.loadSelectedLibrary() else {
      libraries = try await client.libraries().filter { $0.mediaType == "book" }
      mode = libraries.count == 1 ? .player : .library
      if let only = libraries.first, libraries.count == 1 { try await chooseLibrary(only) }
      return
    }
    books = try await client.items(libraryID: libraryID)
    selectedLibraryName = UserDefaults.standard.string(forKey: "selectedLibraryName") ?? ""
    let latestServerBook = books.max {
      ($0.lastPlayedAt ?? .distantPast) < ($1.lastPlayedAt ?? .distantPast)
    }
    let cachedActiveBook = localState.activeBookID.flatMap { id in books.first { $0.id == id } }
    if let latestServerBook,
      let serverActivity = latestServerBook.lastPlayedAt,
      serverActivity > (localState.activeBookSelectedAt ?? .distantPast)
    {
      activeBook = latestServerBook
      localState.activeBookSelectedAt = serverActivity
    } else {
      activeBook = cachedActiveBook ?? latestServerBook ?? books.first
    }
    if let activeBook { applyPlaybackRecord(for: activeBook) }
    mode = .player
    if let connection = try? await vault.loadConnection() {
      progressEvents.connect(
        server: connection.server,
        token: { [client] in await client.accessToken() },
        onProgress: { [weak self] event in self?.receiveExternalProgress(event) },
        onLibraryChanged: { [weak self] in self?.scheduleLibraryRefresh() }
      )
    }
    await reconcileFinishedBooks()
    await restoreActivePosition()
    await saveLocalState()
  }

  func beginSearch(with text: String) {
    mode = .search
    query = text
    updateSearch()
  }

  func updateSearch() {
    searchResult = LibrarySearch.bestMatch(for: query, in: books)
    if query.isEmpty { cancelSearch() }
  }

  func acceptSearch() {
    guard let result = searchResult else { return }
    Task { await closePlaybackSession() }
    player.clear()
    playbackSessionID = nil
    isPlaying = false
    wantsPlayback = false
    activeBook = result
    localState.activeBookSelectedAt = .now
    applyPlaybackRecord(for: result)
    usesRecoveredPosition = false
    cancelSearch()
    Task { await restoreActivePosition() }
    Task { await saveLocalState() }
  }

  func cancelSearch() {
    query = ""
    searchResult = nil
    mode = .player
  }

  func togglePlayback() async {
    guard let book = activeBook else { return }
    do {
      if isPlaying {
        wantsPlayback = false
        isPlaying = false
        player.pause()
        await closePlaybackSession()
      } else if player.hasItem {
        player.play()
      } else {
        let requestedPosition = position
        let remote = try await client.progress(itemID: book.id)
        preserve(position, source: .thisMac, comparedWith: remote.currentTime)
        synchronization.resolve(serverBaseline: remote.lastUpdate, position: remote.currentTime)
        let session = try await client.startPlayback(itemID: book.id)
        // Audiobookshelf intentionally reports a zero session start for finished items.
        // Resume keeps the near-end server position during its five-day replay window.
        let playbackPosition = usesRecoveredPosition ? requestedPosition : remote.currentTime
        usesRecoveredPosition = false
        playbackSessionID = session.id
        chapters = session.chapters
        duration = session.duration
        position = playbackPosition
        try await player.load(
          urls: session.streamURLs,
          fetch: { [client] url, range in try await client.mediaData(url: url, range: range) },
          position: playbackPosition,
          speed: speed,
          title: book.title,
          author: book.authors.joined(separator: ", "),
          bookDuration: session.duration
        )
        player.play()
        lastPlaybackTickInstant = .now
        listenedSinceSync = 0
        Task { [weak self] in
          guard let self, let image = await self.artwork(for: book) else { return }
          self.player.setArtwork(image)
        }
        lastSyncedPosition = remote.currentTime
        if abs(playbackPosition - remote.currentTime) >= SynchronizationPolicy.meaningfulDifference
        {
          synchronization.recordFailure(position: playbackPosition)
          hasPendingSynchronization = true
        }
      }
      if !isPlaying {
        wantsPlayback = true
        beginRecoveryWindowIfNeeded()
        await saveLocalState()
      }
    } catch {
      errorMessage = "Playback couldn’t start."
    }
  }

  func skip(_ amount: TimeInterval) { seek(to: position + amount) }
  func selectChapter(_ chapter: Chapter) {
    seek(to: chapter.start)
    mode = .player
  }
  func setSpeed(_ value: Double) {
    speed = value
    if let activeBook { speeds[activeBook.id] = value }
    player.rate = Float(value)
    Task { await saveLocalState() }
  }

  func forceFetch() async {
    guard let book = activeBook else { return }
    do {
      let remote = try await client.progress(itemID: book.id)
      preserve(position, source: .thisMac, comparedWith: remote.currentTime)
      player.seek(to: remote.currentTime)
      position = remote.currentTime
      duration = remote.duration > 0 ? remote.duration : book.duration
      synchronization.resolve(serverBaseline: remote.lastUpdate, position: remote.currentTime)
      usesRecoveredPosition = false
      hasPendingSynchronization = false
      resetSynchronizationBackoff()
      await saveLocalState()
    } catch { errorMessage = "Force Fetch failed." }
  }

  func forcePush() async {
    guard let book = activeBook else { return }
    do {
      let remote = try await client.progress(itemID: book.id)
      preserve(remote.currentTime, source: .audiobookshelf, comparedWith: position)
      try await client.pushProgress(
        itemID: book.id, position: position, duration: duration,
        isFinished: recentlyFinishedAt[book.id] != nil)
      let refreshed = try await client.progress(itemID: book.id)
      synchronization.resolve(serverBaseline: refreshed.lastUpdate, position: refreshed.currentTime)
      hasPendingSynchronization = false
      usesRecoveredPosition = false
      resetSynchronizationBackoff()
      await saveLocalState()
    } catch { errorMessage = "Force Push failed. Your Mac position is preserved." }
  }

  func recover(_ known: KnownPosition) {
    seek(to: known.position)
  }

  private func preserve(
    _ candidate: TimeInterval, source: PositionSource, comparedWith other: TimeInterval
  ) {
    guard abs(candidate - other) >= SynchronizationPolicy.meaningfulDifference else { return }
    knownPositions.removeAll {
      abs($0.position - candidate) < SynchronizationPolicy.meaningfulDifference
    }
    knownPositions.append(.init(position: candidate, source: source, observedAt: .now))
    if isPlaying || recoveryExpiresAt != nil { beginRecoveryWindowIfNeeded() }
    Task { await saveLocalState() }
  }

  private func seek(to requestedPosition: TimeInterval) {
    let clamped = min(max(requestedPosition, 0), duration)
    position = clamped
    if playbackSessionID == nil { usesRecoveredPosition = true }
    player.seek(to: clamped)
    Task { await saveLocalState() }
  }

  private func playbackTick() async {
    guard isPlaying, let book = activeBook else { return }
    if let nextSynchronizationAttemptAt, nextSynchronizationAttemptAt > .now { return }
    expireRecoveryIfNeeded()
    if CompletionPolicy.shouldMarkFinished(position: position, duration: duration, isPlaying: true),
      !didMarkFinished
    {
      do {
        let remote = try await client.progress(itemID: book.id)
        let snapshot = ServerProgress(
          position: remote.currentTime, duration: remote.duration, isFinished: remote.isFinished,
          lastUpdate: remote.lastUpdate)
        switch synchronization.prepareUpload(localPosition: position, server: snapshot, now: .now) {
        case .suspend(let alternatives):
          knownPositions = alternatives
          beginRecoveryWindowIfNeeded()
          hasPendingSynchronization = true
          errorMessage = "Another listening position is available. Choose which one to keep."
          await saveLocalState()
          return
        case .upload:
          break
        }
        if !remote.isFinished {
          try await client.pushProgress(
            itemID: book.id, position: position, duration: duration, isFinished: true)
        }
        let confirmed = try await client.progress(itemID: book.id)
        synchronization.recordSuccess(position: position, newServerBaseline: confirmed.lastUpdate)
        hasPendingSynchronization = false
        didMarkFinished = true
        recentlyFinishedAt[book.id] =
          recentlyFinishedAt[book.id]
          ?? Date(timeIntervalSince1970: Double(confirmed.lastUpdate) / 1_000)
        await saveLocalState()
      } catch {
        scheduleSynchronizationRetry(position: position)
        errorMessage = "Finishing this book is saved on this Mac and will be retried."
      }
    }
    guard let playbackSessionID, abs(position - lastSyncedPosition) >= 15 else { return }
    do {
      let remote = try await client.progress(itemID: book.id)
      let snapshot = ServerProgress(
        position: remote.currentTime, duration: remote.duration, isFinished: remote.isFinished,
        lastUpdate: remote.lastUpdate)
      switch synchronization.prepareUpload(localPosition: position, server: snapshot, now: .now) {
      case .suspend(let alternatives):
        knownPositions = alternatives
        hasPendingSynchronization = true
        errorMessage = "Another listening position is available. Choose which one to keep."
        await saveLocalState()
        return
      case .upload:
        break
      }
      try await client.sync(
        sessionID: playbackSessionID, position: position, duration: duration,
        timeListened: listenedSinceSync)
      let confirmed = try await client.progress(itemID: book.id)
      synchronization.recordSuccess(position: position, newServerBaseline: confirmed.lastUpdate)
      lastSyncedPosition = position
      listenedSinceSync = 0
      hasPendingSynchronization = false
      resetSynchronizationBackoff()
      await saveLocalState()
    } catch {
      scheduleSynchronizationRetry(position: position)
      errorMessage = "Progress is saved on this Mac and will be retried."
    }
  }

  private func restoreActivePosition() async {
    guard let book = activeBook else { return }
    do {
      let remote = try await client.progress(itemID: book.id)
      let snapshot = ServerProgress(
        position: remote.currentTime, duration: remote.duration, isFinished: remote.isFinished,
        lastUpdate: remote.lastUpdate)
      if let pending = synchronization.pendingPosition {
        switch synchronization.prepareUpload(localPosition: pending, server: snapshot, now: .now) {
        case .upload:
          try await client.pushProgress(
            itemID: book.id, position: pending, duration: remote.duration,
            isFinished: recentlyFinishedAt[book.id] != nil)
          let confirmed = try await client.progress(itemID: book.id)
          synchronization.recordSuccess(position: pending, newServerBaseline: confirmed.lastUpdate)
          position = pending
          duration = confirmed.duration > 0 ? confirmed.duration : book.duration
          hasPendingSynchronization = false
        case .suspend(let alternatives):
          knownPositions = alternatives
          position = remote.currentTime
          duration = remote.duration > 0 ? remote.duration : book.duration
          hasPendingSynchronization = true
        }
      } else {
        preserve(position, source: .thisMac, comparedWith: remote.currentTime)
        position = remote.currentTime
        duration = remote.duration > 0 ? remote.duration : book.duration
        synchronization.resolve(serverBaseline: remote.lastUpdate, position: remote.currentTime)
      }
      if remote.isFinished,
        remote.duration > 0,
        remote.currentTime / remote.duration >= CompletionPolicy.threshold,
        recentlyFinishedAt[book.id] == nil
      {
        recentlyFinishedAt[book.id] = Date(timeIntervalSince1970: Double(remote.lastUpdate) / 1_000)
        didMarkFinished = true
      }
      resetSynchronizationBackoff()
      await saveLocalState()
    } catch {
      if synchronization.pendingPosition != nil { scheduleSynchronizationRetry(position: position) }
      errorMessage = "The server position is temporarily unavailable."
    }
  }

  func showSettings() { mode = mode == .settings ? .player : .settings }

  func setLaunchAtLogin(_ enabled: Bool) {
    do {
      if enabled {
        try SMAppService.mainApp.register()
      } else {
        try SMAppService.mainApp.unregister()
      }
      launchAtLogin = enabled
    } catch { errorMessage = "Launch at Login could not be changed." }
  }

  func signOut() async {
    wantsPlayback = false
    isPlaying = false
    player.pause()
    progressEvents.disconnect()
    try? await client.logout()
    try? await vault.clear()
    await stateStore.clear()
    await artworkStore.clear()
    UserDefaults.standard.removeObject(forKey: "selectedLibraryName")
    localState = LocalState()
    synchronization = .init()
    libraries = []
    books = []
    activeBook = nil
    chapters = []
    knownPositions = []
    speeds = [:]
    recentlyFinishedAt = [:]
    position = 0
    duration = 0
    speed = 2
    hasPendingSynchronization = false
    recoveryExpiresAt = nil
    selectedLibraryName = ""
    server = ""
    username = ""
    password = ""
    usesRecoveredPosition = false
    mode = .connection
  }

  private func receiveExternalProgress(_ event: ExternalProgressEvent) {
    if event.itemID != activeBook?.id, !isPlaying,
      let book = books.first(where: { $0.id == event.itemID })
    {
      player.clear()
      activeBook = book
      localState.activeBookSelectedAt = Date(
        timeIntervalSince1970: Double(event.progress.lastUpdate) / 1_000)
      applyPlaybackRecord(for: book)
      position = event.progress.currentTime
      duration = event.progress.duration
      synchronization.resolve(
        serverBaseline: event.progress.lastUpdate, position: event.progress.currentTime)
      wantsPlayback = false
      Task { await saveLocalState() }
      return
    }
    guard let book = activeBook, event.itemID == book.id, event.sessionID != playbackSessionID
    else { return }
    guard abs(event.progress.currentTime - position) >= SynchronizationPolicy.meaningfulDifference
    else { return }
    preserve(position, source: .thisMac, comparedWith: event.progress.currentTime)
    preserve(event.progress.currentTime, source: .audiobookshelf, comparedWith: position)
    synchronization.recordFailure(position: position)
    hasPendingSynchronization = true
    errorMessage = "Another listening position is available. Choose which one to keep."
    Task { await saveLocalState() }
  }

  func artwork(for book: Audiobook) async -> NSImage? {
    if let cached = await artworkStore.image(itemID: book.id, revision: book.coverRevision) {
      return cached
    }
    guard let data = try? await client.coverData(itemID: book.id) else { return nil }
    return try? await artworkStore.save(data, itemID: book.id, revision: book.coverRevision)
  }

  func isRecentlyFinished(_ book: Audiobook) -> Bool {
    guard let date = recentlyFinishedAt[book.id] else { return false }
    return Date().timeIntervalSince(date) < CompletionPolicy.lifetime
  }

  private func saveLocalState() async {
    localState.books = books
    localState.activeBookID = activeBook?.id
    if let activeBook {
      localState.playback.update(activeBook.id) { record in
        record.position = position
        record.speed = speed
        record.knownPositions = knownPositions
        record.recoveryExpiresAt = recoveryExpiresAt
        record.recentlyFinishedAt = recentlyFinishedAt[activeBook.id]
        record.synchronization = synchronization
      }
    }
    do {
      try await stateStore.save(localState)
    } catch {
      errorMessage = "Progress could not be saved on this Mac."
    }
  }

  private func reconcileFinishedBooks() async {
    let expired = recentlyFinishedAt.filter {
      Date().timeIntervalSince($0.value) >= CompletionPolicy.lifetime
    }
    for (bookID, finishedAt) in expired {
      guard let remote = try? await client.progress(itemID: bookID) else { continue }
      let snapshot = ServerProgress(
        position: remote.currentTime, duration: remote.duration, isFinished: remote.isFinished,
        lastUpdate: remote.lastUpdate)
      if CompletionPolicy.shouldReset(finishedAt: finishedAt, server: snapshot, now: .now) {
        do {
          try await client.pushProgress(
            itemID: bookID, position: 0, duration: remote.duration, isFinished: false)
          let ending = KnownPosition(
            position: remote.currentTime, source: .audiobookshelf, observedAt: .now)
          localState.playback.update(bookID) { record in
            record.position = 0
            record.recentlyFinishedAt = nil
            record.knownPositions = [ending]
            record.recoveryExpiresAt = Date().addingTimeInterval(PlaybackLedger.recoveryLifetime)
          }
          if activeBook?.id == bookID {
            preserve(remote.currentTime, source: .audiobookshelf, comparedWith: 0)
            recoveryExpiresAt = Date().addingTimeInterval(PlaybackLedger.recoveryLifetime)
            position = 0
            player.seek(to: 0)
            didMarkFinished = false
          }
          recentlyFinishedAt.removeValue(forKey: bookID)
        } catch {
          errorMessage = "The finished-book reset will be retried later."
        }
      } else {
        recentlyFinishedAt.removeValue(forKey: bookID)
        localState.playback.update(bookID) { $0.recentlyFinishedAt = nil }
      }
    }
    await saveLocalState()
  }

  func quit() {
    player.pause()
    Task {
      await saveLocalState()
      await closePlaybackSession()
      NSApplication.shared.terminate(nil)
    }
  }

  func systemWillSleep() {
    wantsPlayback = false
    isPlaying = false
    player.pause()
    Task {
      await saveLocalState()
      await closePlaybackSession()
    }
  }

  func systemDidWake() async {
    guard !isPlaying else { return }
    await forceFetch()
  }

  private func networkBecameAvailable() async {
    guard activeBook != nil else { return }
    nextSynchronizationAttemptAt = nil
    if hasPendingSynchronization { await restoreActivePosition() }
    if wantsPlayback, player.hasItem { player.play() } else if !isPlaying { await forceFetch() }
  }

  private func outputDeviceChanged() {
    guard isPlaying else { return }
    wantsPlayback = false
    isPlaying = false
    player.pause()
    Task { await closePlaybackSession() }
  }

  private func playbackStalled() {
    errorMessage = "Playback is waiting for the network."
  }

  private func receivePlayerUpdate(position: TimeInterval, duration: TimeInterval, playing: Bool)
    async
  {
    let now = ContinuousClock.now
    if isPlaying, let lastPlaybackTickInstant {
      let elapsed = lastPlaybackTickInstant.duration(to: now).components
      listenedSinceSync +=
        Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1_000_000_000_000_000_000
    }
    self.lastPlaybackTickInstant = now
    self.position = position
    self.duration = duration
    isPlaying = playing
    await playbackTick()
  }

  private func playbackEnded() {
    wantsPlayback = false
    isPlaying = false
    Task { await closePlaybackSession() }
  }

  private func scheduleLibraryRefresh() {
    libraryRefreshTask?.cancel()
    libraryRefreshTask = Task { [weak self] in
      try? await Task.sleep(for: .milliseconds(500))
      guard !Task.isCancelled else { return }
      await self?.refreshLibraryIndex()
    }
  }

  private func refreshLibraryIndex() async {
    guard let libraryID = await vault.loadSelectedLibrary() else { return }
    do {
      let updated = try await client.items(libraryID: libraryID)
      let activeID = activeBook?.id
      books = updated
      if let activeID, let refreshedActive = updated.first(where: { $0.id == activeID }) {
        activeBook = refreshedActive
        duration = refreshedActive.duration
      }
      await saveLocalState()
    } catch {
      // The cached index remains available; another event or network recovery retries it.
    }
  }

  private func closePlaybackSession() async {
    guard let sessionID = playbackSessionID else { return }
    do {
      guard let book = activeBook else { return }
      let remote = try await client.progress(itemID: book.id)
      let snapshot = ServerProgress(
        position: remote.currentTime, duration: remote.duration, isFinished: remote.isFinished,
        lastUpdate: remote.lastUpdate)
      switch synchronization.prepareUpload(localPosition: position, server: snapshot, now: .now) {
      case .suspend(let alternatives):
        knownPositions = alternatives
        beginRecoveryWindowIfNeeded()
        hasPendingSynchronization = true
        playbackSessionID = nil
        player.unloadKeepingNowPlaying()
        await saveLocalState()
        return
      case .upload:
        break
      }
      try await client.close(
        sessionID: sessionID, position: position, duration: duration,
        timeListened: listenedSinceSync)
      let confirmed = try await client.progress(itemID: book.id)
      synchronization.recordSuccess(position: position, newServerBaseline: confirmed.lastUpdate)
      playbackSessionID = nil
      hasPendingSynchronization = false
      listenedSinceSync = 0
      resetSynchronizationBackoff()
      player.unloadKeepingNowPlaying()
    } catch {
      playbackSessionID = nil
      player.unloadKeepingNowPlaying()
      scheduleSynchronizationRetry(position: position)
      errorMessage = "Progress is saved on this Mac and will be retried."
    }
  }

  private func applyPlaybackRecord(for book: Audiobook) {
    let record = localState.playback[book.id] ?? .init(speed: speeds[book.id] ?? 2)
    position = record.position
    duration = book.duration
    speed = record.speed
    knownPositions = record.knownPositions
    recoveryExpiresAt = record.recoveryExpiresAt
    synchronization = record.synchronization
    hasPendingSynchronization = record.hasPendingSynchronization
    didMarkFinished = record.recentlyFinishedAt != nil
    lastSyncedPosition = record.synchronization.lastSyncedPosition
  }

  private func beginRecoveryWindowIfNeeded() {
    guard !knownPositions.isEmpty else { return }
    recoveryExpiresAt = Date().addingTimeInterval(PlaybackLedger.recoveryLifetime)
  }

  private func expireRecoveryIfNeeded() {
    guard let recoveryExpiresAt, recoveryExpiresAt <= .now else { return }
    knownPositions = []
    self.recoveryExpiresAt = nil
  }

  private func scheduleSynchronizationRetry(position: TimeInterval) {
    synchronization.recordFailure(position: position)
    hasPendingSynchronization = true
    synchronizationFailureCount += 1
    let delay = RetryBackoff.delay(
      afterFailure: synchronizationFailureCount, jitter: .random(in: -1...1))
    nextSynchronizationAttemptAt = Date().addingTimeInterval(delay)
    synchronizationRetryTask?.cancel()
    synchronizationRetryTask = Task { [weak self] in
      try? await Task.sleep(for: .milliseconds(Int64(delay * 1_000)))
      guard !Task.isCancelled, let self else { return }
      if self.isPlaying { await self.playbackTick() } else { await self.restoreActivePosition() }
    }
    Task { await saveLocalState() }
  }

  private func resetSynchronizationBackoff() {
    synchronizationFailureCount = 0
    nextSynchronizationAttemptAt = nil
    synchronizationRetryTask?.cancel()
    synchronizationRetryTask = nil
  }
}
