import AppKit
import Observation
import ResumeCore
import ServiceManagement

@MainActor @Observable
final class AppModel {
  enum Mode { case connection, library, player, search, chapters }

  var mode: Mode = .connection
  var server = ""
  var username = ""
  var password = ""
  var libraries: [ABSLibrary] = []
  var books: [Audiobook] = []
  var activeBook: Audiobook? {
    didSet {
      if oldValue?.id != activeBook?.id {
        recoveryGeneration = UUID()
        isResolvingPosition = false
        recoveryError = nil
      }
    }
  }
  var query = ""
  var searchResult: Audiobook?
  var position: TimeInterval = 0
  var duration: TimeInterval = 0
  var isPlaying = false
  var wantsPlayback = false
  var isLoadingPlayback: Bool { wantsPlayback && !isPlaying }
  private var isPreparingPlayback = false
  var speed = 2.0
  var chapters: [Chapter] = []
  var knownPositions: [KnownPosition] = []
  var needsPositionRecovery: Bool { synchronization.isSuspended && !knownPositions.isEmpty }
  private(set) var isResolvingPosition = false
  private(set) var recoveryError: String?
  var errorMessage: String?
  var hasPendingSynchronization = false
  var isBusy = false
  var launchAtLogin = SMAppService.mainApp.status == .enabled
  var selectedLibraryName = ""
  var recentlyFinishedAt: [String: Date] = [:]
  var speeds: [String: Double] = [:]

  @ObservationIgnored private let now: () -> Date
  @ObservationIgnored private let vault: any ConnectionStoring
  @ObservationIgnored private let stateStore: any LocalStatePersisting
  @ObservationIgnored private let artworkStore: ArtworkStore
  @ObservationIgnored private let preferences: UserDefaults
  @ObservationIgnored private let progressEvents = ProgressEventClient()
  @ObservationIgnored private lazy var systemMonitor = SystemMonitor(
    onNetworkAvailable: { [weak self] in Task { await self?.networkBecameAvailable() } },
    onOutputDeviceRemoved: { [weak self] in self?.outputDeviceRemoved() }
  )
  @ObservationIgnored private lazy var client: any AudiobookshelfServing =
    suppliedClient ?? AudiobookshelfClient(vault: vault)
  @ObservationIgnored private let suppliedClient: (any AudiobookshelfServing)?
  @ObservationIgnored private let suppliedPlayer: (any PlaybackControlling)?
  @ObservationIgnored private lazy var player: any PlaybackControlling =
    suppliedPlayer
    ?? AudioPlayer(
      update: { [weak self] position, duration, playing in
        Task { @MainActor in
          await self?.receivePlayerUpdate(position: position, duration: duration, playing: playing)
        }
      },
      stalled: { [weak self] in self?.playbackStalled() },
      ended: { [weak self] in self?.playbackEnded() },
      failed: { [weak self] in self?.playbackFailed() }
    )
  @ObservationIgnored private var playbackGeneration = UUID()
  @ObservationIgnored private var recoveryGeneration = UUID()
  @ObservationIgnored private var playbackSessionID: String?
  @ObservationIgnored private var progressSynchronizationTask: Task<Void, Never>?
  @ObservationIgnored private var sessionCloseTask: Task<Void, Never>?
  @ObservationIgnored private var lastSyncedPosition: TimeInterval = 0
  @ObservationIgnored private var didMarkFinished = false
  @ObservationIgnored private var localState = LocalState()
  private var synchronization = SynchronizationState()
  @ObservationIgnored private var recoveryExpiresAt: Date?
  @ObservationIgnored private var usesRecoveredPosition = false
  @ObservationIgnored private var libraryRefreshTask: Task<Void, Never>?
  @ObservationIgnored private var lastPlaybackTickInstant: ContinuousClock.Instant?
  @ObservationIgnored private var listenedSinceSync: TimeInterval = 0
  @ObservationIgnored private var synchronizationFailureCount = 0
  @ObservationIgnored private var nextSynchronizationAttemptAt: Date?
  @ObservationIgnored private var synchronizationRetryTask: Task<Void, Never>?
  @ObservationIgnored private var recoveryExpiryTask: Task<Void, Never>?

  init(
    client: (any AudiobookshelfServing)? = nil,
    player: (any PlaybackControlling)? = nil,
    stateStore: any LocalStatePersisting = LocalStateStore(),
    vault: any ConnectionStoring = KeychainStore(),
    artworkStore: ArtworkStore = ArtworkStore(),
    preferences: UserDefaults = .standard,
    now: @escaping () -> Date = Date.init,
    startsAutomatically: Bool = true
  ) {
    self.suppliedClient = client
    self.suppliedPlayer = player
    self.stateStore = stateStore
    self.artworkStore = artworkStore
    self.preferences = preferences
    self.vault = vault
    self.now = now
    guard startsAutomatically else { return }
    _ = systemMonitor
    self.player.configureRemoteCommands(
      play: { [weak self] in
        guard let self, !self.isPlaying else { return }
        await self.togglePlayback()
      },
      pause: { [weak self] in
        guard let self, self.isPlaying || self.wantsPlayback else { return }
        self.playbackGeneration = UUID()
        self.wantsPlayback = false
        self.isPreparingPlayback = false
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
      local.playback.prepareForProcessStart(now: now())
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
    guard let url = ServerAddress.normalized(server) else {
      errorMessage = "Enter your PikaPods server address."
      return
    }
    server = url.absoluteString
    isBusy = true
    defer { isBusy = false }
    do {
      errorMessage = nil
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
    } catch AudiobookshelfClientError.invalidCredentials {
      errorMessage = "That username or password was not accepted."
    } catch AudiobookshelfClientError.serverUnavailable {
      errorMessage = "Resume couldn’t reach that PikaPods server. Check the address and try again."
    } catch {
      errorMessage =
        "The server replied unexpectedly. Check that Audiobookshelf is running and try again."
    }
  }

  func chooseLibrary(_ library: ABSLibrary) async throws {
    await vault.saveSelectedLibrary(library.id)
    selectedLibraryName = library.name
    preferences.set(library.name, forKey: "selectedLibraryName")
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
    selectedLibraryName = preferences.string(forKey: "selectedLibraryName") ?? ""
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
    if let activeBook { await loadChapters(for: activeBook) }
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

  func acceptSearch() async {
    guard let result = searchResult else { return }
    playbackGeneration = UUID()
    let generation = playbackGeneration
    wantsPlayback = false
    isPlaying = false
    player.pause()
    await closePlaybackSession()
    guard playbackGeneration == generation else { return }
    await saveLocalState()
    player.clear()
    playbackSessionID = nil
    isPlaying = false
    wantsPlayback = false
    activeBook = result
    localState.activeBookSelectedAt = now()
    applyPlaybackRecord(for: result)
    usesRecoveredPosition = false
    cancelSearch()
    await loadChapters(for: result)
    guard playbackGeneration == generation else { return }
    await restoreActivePosition()
    await saveLocalState()
  }

  func cancelSearch() {
    query = ""
    searchResult = nil
    mode = .player
  }

  func togglePlayback() async {
    guard let book = activeBook else { return }
    if !isPlaying && !wantsPlayback { playbackGeneration = UUID() }
    let generation = playbackGeneration
    do {
      if isPlaying || wantsPlayback {
        playbackGeneration = UUID()
        wantsPlayback = false
        isPreparingPlayback = false
        isPlaying = false
        player.pause()
        await closePlaybackSession()
        await saveLocalState()
        return
      } else {
        wantsPlayback = true
        errorMessage = nil
        isPreparingPlayback = true
        defer { if playbackGeneration == generation { isPreparingPlayback = false } }
        if let sessionCloseTask { await sessionCloseTask.value }
        guard playbackGeneration == generation, activeBook?.id == book.id, wantsPlayback else {
          return
        }
        if player.hasItem {
          player.play()
          return
        }
        let requestedPosition = position
        // Establish the baseline before creating a session: a concurrent newer progress
        // response must never authorize writing an older session position over it.
        let remote = try await client.progress(itemID: book.id)
        guard playbackGeneration == generation, activeBook?.id == book.id, wantsPlayback else {
          return
        }
        preserve(position, source: .thisMac, comparedWith: remote.currentTime)
        if usesRecoveredPosition, synchronization.pendingPosition != nil,
          synchronization.serverBaseline != remote.lastUpdate
        {
          synchronization.suspend(position: requestedPosition)
          preserve(remote.currentTime, source: .audiobookshelf, comparedWith: requestedPosition)
          hasPendingSynchronization = true
        }
        if !synchronization.isSuspended {
          synchronization.resolve(serverBaseline: remote.lastUpdate, position: remote.currentTime)
        }
        let session = try await client.startPlayback(itemID: book.id)
        guard playbackGeneration == generation, activeBook?.id == book.id, wantsPlayback else {
          try? await client.close(
            sessionID: session.id, position: session.currentTime,
            duration: session.duration, timeListened: 0)
          return
        }
        // Audiobookshelf intentionally reports a zero session start for finished items.
        // Resume keeps the near-end server position during its five-day replay window.
        let keepsEnding =
          remote.isFinished && remote.duration > 0
          && remote.currentTime / remote.duration >= CompletionPolicy.threshold
        let serverPosition = keepsEnding ? remote.currentTime : session.currentTime
        let playbackPosition = min(
          max(usesRecoveredPosition ? requestedPosition : serverPosition, 0), session.duration)
        preserve(requestedPosition, source: .thisMac, comparedWith: playbackPosition)
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
        guard playbackGeneration == generation, activeBook?.id == book.id, wantsPlayback else {
          return
        }
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
      if wantsPlayback {
        if recoveryExpiresAt == nil { beginRecoveryWindowIfNeeded() }
        await saveLocalState()
      }
    } catch {
      guard playbackGeneration == generation else { return }
      wantsPlayback = false
      isPreparingPlayback = false
      if !presentAuthenticationFailure(error) {
        errorMessage = "Playback couldn’t start. Try Play again."
      }
      await closePlaybackSession()
      guard playbackGeneration == generation, activeBook?.id == book.id else { return }
      player.unloadKeepingNowPlaying()
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

  func recover(_ known: KnownPosition) async {
    expireRecoveryIfNeeded()
    guard !isResolvingPosition, !isPreparingPlayback, let book = activeBook,
      knownPositions.contains(where: { $0.id == known.id })
    else { return }
    let generation = playbackGeneration
    let recovery = recoveryGeneration
    let presentedServerPosition =
      synchronization.isSuspended
      ? (knownPositions.last { $0.source == .audiobookshelf }?.position
        ?? synchronization.lastSyncedPosition)
      : synchronization.lastSyncedPosition
    isResolvingPosition = true
    recoveryError = nil
    defer { if recoveryGeneration == recovery { isResolvingPosition = false } }
    if let progressSynchronizationTask { await progressSynchronizationTask.value }
    if let sessionCloseTask { await sessionCloseTask.value }
    do {
      let remote = try await client.progress(itemID: book.id)
      guard recoveryGeneration == recovery, activeBook?.id == book.id,
        playbackGeneration == generation,
        knownPositions.contains(where: { $0.id == known.id })
      else { return }
      if abs(remote.currentTime - presentedServerPosition)
        >= SynchronizationPolicy.meaningfulDifference,
        abs(remote.currentTime - known.position) >= SynchronizationPolicy.meaningfulDifference
      {
        synchronization.suspend(position: known.position)
        knownPositions = [
          .init(position: known.position, source: known.source, observedAt: now()),
          .init(position: remote.currentTime, source: .audiobookshelf, observedAt: now()),
        ]
        hasPendingSynchronization = true
        await saveLocalState()
        return
      }
      preserve(position, source: .thisMac, comparedWith: known.position)
      duration = remote.duration > 0 ? remote.duration : book.duration
      synchronization.resolve(serverBaseline: remote.lastUpdate, position: remote.currentTime)
      seek(to: known.position)
      hasPendingSynchronization =
        abs(position - remote.currentTime) >= SynchronizationPolicy.meaningfulDifference
      if hasPendingSynchronization { synchronization.recordFailure(position: position) }
      resetSynchronizationBackoff()
      await saveLocalState()
    } catch {
      guard recoveryGeneration == recovery, activeBook?.id == book.id,
        playbackGeneration == generation
      else { return }
      if !presentAuthenticationFailure(error) {
        recoveryError = "Couldn’t check the server position. Try your choice again."
      }
    }
  }

  private func preserve(
    _ candidate: TimeInterval, source: PositionSource, comparedWith other: TimeInterval
  ) {
    guard abs(candidate - other) >= SynchronizationPolicy.meaningfulDifference else { return }
    knownPositions.removeAll {
      abs($0.position - candidate) < SynchronizationPolicy.meaningfulDifference
    }
    knownPositions.append(.init(position: candidate, source: source, observedAt: now()))
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
    guard progressSynchronizationTask == nil, sessionCloseTask == nil else { return }
    let task = Task { await synchronizePlaybackTick() }
    progressSynchronizationTask = task
    await task.value
    progressSynchronizationTask = nil
  }

  private func synchronizePlaybackTick() async {
    guard isPlaying, let book = activeBook else { return }
    if let nextSynchronizationAttemptAt, nextSynchronizationAttemptAt > now() { return }
    expireRecoveryIfNeeded()
    if CompletionPolicy.shouldMarkFinished(position: position, duration: duration, isPlaying: true),
      !didMarkFinished
    {
      do {
        let remote = try await client.progress(itemID: book.id)
        guard isPlaying, activeBook?.id == book.id else { return }
        let snapshot = ServerProgress(
          position: remote.currentTime, duration: remote.duration, isFinished: remote.isFinished,
          lastUpdate: remote.lastUpdate)
        switch synchronization.prepareUpload(localPosition: position, server: snapshot, now: now())
        {
        case .suspend(let alternatives):
          knownPositions = alternatives
          beginRecoveryWindowIfNeeded()
          hasPendingSynchronization = true
          // The player exposes choices only while a material conflict remains unresolved.
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
        presentAuthenticationFailure(error)
        // Local progress remains pending; retry without interrupting the player.
      }
    }
    guard let playbackSessionID, abs(position - lastSyncedPosition) >= 15 else { return }
    do {
      let remote = try await client.progress(itemID: book.id)
      guard isPlaying, activeBook?.id == book.id else { return }
      let snapshot = ServerProgress(
        position: remote.currentTime, duration: remote.duration, isFinished: remote.isFinished,
        lastUpdate: remote.lastUpdate)
      switch synchronization.prepareUpload(localPosition: position, server: snapshot, now: now()) {
      case .suspend(let alternatives):
        knownPositions = alternatives
        beginRecoveryWindowIfNeeded()
        hasPendingSynchronization = true
        // The player exposes choices only while a material conflict remains unresolved.
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
      presentAuthenticationFailure(error)
      // Local progress remains pending; retry without interrupting the player.
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
        switch synchronization.prepareUpload(localPosition: pending, server: snapshot, now: now()) {
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
          if isPlaying { beginRecoveryWindowIfNeeded() }
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
      presentAuthenticationFailure(error)
      // Background transport failures are retried without a persistent warning.
    }
  }

  func prepareForSettings() {
    query = ""
    searchResult = nil
    if mode == .search { mode = .player }
  }

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
    playbackGeneration = UUID()
    wantsPlayback = false
    isPlaying = false
    player.pause()
    player.clear()
    playbackSessionID = nil
    libraryRefreshTask?.cancel()
    resetSynchronizationBackoff()
    progressEvents.disconnect()
    try? await client.logout()
    do {
      try await vault.clear()
    } catch {
      errorMessage = "Resume could not remove its saved Keychain credentials. Try Sign Out again."
      return
    }
    await stateStore.clear()
    await artworkStore.clear()
    preferences.removeObject(forKey: "selectedLibraryName")
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
    recoveryExpiryTask?.cancel()
    selectedLibraryName = ""
    server = ""
    username = ""
    password = ""
    usesRecoveredPosition = false
    mode = .connection
  }

  func receiveExternalProgress(_ event: ExternalProgressEvent) {
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
    guard let book = activeBook, event.itemID == book.id else { return }
    if let sessionID = event.sessionID, sessionID == playbackSessionID { return }
    if let baseline = synchronization.serverBaseline, event.progress.lastUpdate <= baseline {
      return
    }
    if !isPlaying && !wantsPlayback {
      preserve(position, source: .thisMac, comparedWith: event.progress.currentTime)
      position = min(max(event.progress.currentTime, 0), duration)
      player.seek(to: position)
      synchronization.resolve(serverBaseline: event.progress.lastUpdate, position: position)
      hasPendingSynchronization = false
      Task { await saveLocalState() }
      return
    }
    guard abs(event.progress.currentTime - position) >= SynchronizationPolicy.meaningfulDifference
    else { return }
    preserve(position, source: .thisMac, comparedWith: event.progress.currentTime)
    preserve(event.progress.currentTime, source: .audiobookshelf, comparedWith: position)
    synchronization.suspend(position: position)
    hasPendingSynchronization = true
    // The player exposes choices only while a material conflict remains unresolved.
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
    return now().timeIntervalSince(date) < CompletionPolicy.lifetime
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
      now().timeIntervalSince($0.value) >= CompletionPolicy.lifetime
    }
    for (bookID, finishedAt) in expired {
      guard let remote = try? await client.progress(itemID: bookID) else { continue }
      let snapshot = ServerProgress(
        position: remote.currentTime, duration: remote.duration, isFinished: remote.isFinished,
        lastUpdate: remote.lastUpdate)
      if CompletionPolicy.shouldReset(finishedAt: finishedAt, server: snapshot, now: now()) {
        do {
          try await client.pushProgress(
            itemID: bookID, position: 0, duration: remote.duration, isFinished: false)
          let ending = KnownPosition(
            position: remote.currentTime, source: .audiobookshelf, observedAt: now())
          localState.playback.update(bookID) { record in
            record.position = 0
            record.recentlyFinishedAt = nil
            record.knownPositions = [ending]
            record.recoveryExpiresAt = now().addingTimeInterval(PlaybackLedger.recoveryLifetime)
          }
          if activeBook?.id == bookID {
            preserve(remote.currentTime, source: .audiobookshelf, comparedWith: 0)
            recoveryExpiresAt = now().addingTimeInterval(PlaybackLedger.recoveryLifetime)
            scheduleRecoveryExpiry()
            position = 0
            player.seek(to: 0)
            didMarkFinished = false
          }
          recentlyFinishedAt.removeValue(forKey: bookID)
        } catch {
          presentAuthenticationFailure(error)
          // Local progress remains pending; retry without interrupting the player.
        }
      } else {
        recentlyFinishedAt.removeValue(forKey: bookID)
        localState.playback.update(bookID) { $0.recentlyFinishedAt = nil }
        if activeBook?.id == bookID { didMarkFinished = false }
      }
    }
    await saveLocalState()
  }

  func quit() {
    player.pause()
    Task {
      await saveLocalState()
      await boundedClosePlaybackSession()
      NSApplication.shared.terminate(nil)
    }
  }

  func systemWillSleep() {
    playbackGeneration = UUID()
    wantsPlayback = false
    isPlaying = false
    player.pause()
    Task {
      await saveLocalState()
      await boundedClosePlaybackSession()
    }
  }

  func systemDidWake() async {
    guard !isPlaying else { return }
    await reconcileFinishedBooks()
    await restoreActivePosition()
  }

  func networkBecameAvailable() async {
    guard let book = activeBook else { return }
    let generation = playbackGeneration
    nextSynchronizationAttemptAt = nil
    if wantsPlayback, player.hasItem, !isPreparingPlayback {
      await playbackTick()
      guard playbackGeneration == generation, activeBook?.id == book.id, wantsPlayback else {
        return
      }
      player.play()
    } else if !isPlaying && !wantsPlayback {
      await reconcileFinishedBooks()
      guard playbackGeneration == generation, activeBook?.id == book.id else { return }
      await restoreActivePosition()
    }
  }

  private func outputDeviceRemoved() {
    guard isPlaying || wantsPlayback else { return }
    playbackGeneration = UUID()
    wantsPlayback = false
    isPlaying = false
    player.pause()
    Task { await closePlaybackSession() }
  }

  private func playbackStalled() {
    isPlaying = false
  }

  @discardableResult
  private func presentAuthenticationFailure(_ error: Error) -> Bool {
    guard case AudiobookshelfClientError.authenticationRequired = error else { return false }
    resetSynchronizationBackoff()
    mode = .connection
    errorMessage = "Your Audiobookshelf session expired. Enter your password to reconnect."
    return true
  }

  private func playbackFailed() {
    wantsPlayback = false
    isPlaying = false
    isPreparingPlayback = false
    player.pause()
    errorMessage = "Playback stopped. Try Play again."
    Task { await closePlaybackSession() }
  }

  func receivePlayerUpdate(position: TimeInterval, duration: TimeInterval, playing: Bool)
    async
  {
    guard player.hasItem, !isPreparingPlayback else { return }
    let now = ContinuousClock.now
    if isPlaying, let lastPlaybackTickInstant {
      let elapsed = lastPlaybackTickInstant.duration(to: now).components
      listenedSinceSync +=
        Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1_000_000_000_000_000_000
    }
    self.lastPlaybackTickInstant = now
    self.position = position
    if duration.isFinite && duration > 0 { self.duration = duration }
    isPlaying = playing && wantsPlayback
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
    if let sessionCloseTask {
      await sessionCloseTask.value
      return
    }
    let task = Task {
      if let progressSynchronizationTask { await progressSynchronizationTask.value }
      await finishPlaybackSession()
    }
    sessionCloseTask = task
    await task.value
    sessionCloseTask = nil
  }

  private func finishPlaybackSession() async {
    guard let sessionID = playbackSessionID else { return }
    do {
      guard let book = activeBook else { return }
      let remote = try await client.progress(itemID: book.id)
      guard playbackSessionID == sessionID, activeBook?.id == book.id else { return }
      let snapshot = ServerProgress(
        position: remote.currentTime, duration: remote.duration, isFinished: remote.isFinished,
        lastUpdate: remote.lastUpdate)
      switch synchronization.prepareUpload(localPosition: position, server: snapshot, now: now()) {
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
      guard playbackSessionID == sessionID, activeBook?.id == book.id else { return }
      synchronization.recordSuccess(position: position, newServerBaseline: confirmed.lastUpdate)
      playbackSessionID = nil
      hasPendingSynchronization = false
      listenedSinceSync = 0
      resetSynchronizationBackoff()
      player.unloadKeepingNowPlaying()
    } catch {
      guard playbackSessionID == sessionID else { return }
      playbackSessionID = nil
      player.unloadKeepingNowPlaying()
      scheduleSynchronizationRetry(position: position)
      presentAuthenticationFailure(error)
      // Local progress remains pending; retry without interrupting the player.
    }
  }

  private func boundedClosePlaybackSession() async {
    guard playbackSessionID != nil else { return }
    await withTaskGroup(of: Void.self) { group in
      group.addTask { [weak self] in await self?.closePlaybackSession() }
      group.addTask { try? await Task.sleep(for: .seconds(2)) }
      _ = await group.next()
      group.cancelAll()
    }
  }

  private func loadChapters(for book: Audiobook) async {
    if !book.chapters.isEmpty {
      chapters = book.chapters
      return
    }
    guard let loaded = try? await client.chapters(itemID: book.id) else { return }
    chapters = loaded
    guard let index = books.firstIndex(where: { $0.id == book.id }) else { return }
    books[index].chapters = loaded
    if activeBook?.id == book.id { activeBook = books[index] }
    await saveLocalState()
  }

  private func applyPlaybackRecord(for book: Audiobook) {
    let record = localState.playback[book.id] ?? .init(speed: speeds[book.id] ?? 2)
    position = record.position
    duration = book.duration
    speed = record.speed
    chapters = book.chapters
    knownPositions = record.knownPositions
    recoveryExpiresAt = record.recoveryExpiresAt
    scheduleRecoveryExpiry()
    synchronization = record.synchronization
    hasPendingSynchronization = record.hasPendingSynchronization
    didMarkFinished = record.recentlyFinishedAt != nil
    lastSyncedPosition = record.synchronization.lastSyncedPosition
  }

  private func beginRecoveryWindowIfNeeded() {
    guard !knownPositions.isEmpty else { return }
    recoveryExpiresAt = now().addingTimeInterval(PlaybackLedger.recoveryLifetime)
    scheduleRecoveryExpiry()
  }

  private func expireRecoveryIfNeeded() {
    guard let recoveryExpiresAt, recoveryExpiresAt <= now() else { return }
    knownPositions = []
    self.recoveryExpiresAt = nil
    recoveryExpiryTask?.cancel()
    recoveryExpiryTask = nil
    Task { await saveLocalState() }
  }

  private func scheduleRecoveryExpiry() {
    recoveryExpiryTask?.cancel()
    guard let expiry = recoveryExpiresAt else { return }
    let delay = max(expiry.timeIntervalSince(now()), 0)
    recoveryExpiryTask = Task { [weak self] in
      try? await Task.sleep(for: .milliseconds(Int64(delay * 1_000)))
      guard !Task.isCancelled, let self, self.recoveryExpiresAt == expiry else { return }
      self.expireRecoveryIfNeeded()
    }
  }

  private func scheduleSynchronizationRetry(position: TimeInterval) {
    synchronization.recordFailure(position: position)
    hasPendingSynchronization = true
    synchronizationFailureCount += 1
    let delay = RetryBackoff.delay(
      afterFailure: synchronizationFailureCount, jitter: .random(in: -1...1))
    nextSynchronizationAttemptAt = now().addingTimeInterval(delay)
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
