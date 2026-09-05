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
    @ObservationIgnored private lazy var client = AudiobookshelfClient(vault: vault)
    @ObservationIgnored private lazy var player = AudioPlayer { [weak self] position, duration, playing in
        Task { @MainActor in
            self?.position = position
            self?.duration = duration
            self?.isPlaying = playing
            await self?.playbackTick()
        }
    }
    @ObservationIgnored private var playbackSessionID: String?
    @ObservationIgnored private var lastSyncedPosition: TimeInterval = 0
    @ObservationIgnored private var didMarkFinished = false

    init() {
        player.configureRemoteCommands(
            play: { [weak self] in
                guard let self, !self.isPlaying else { return }
                await self.togglePlayback()
            },
            pause: { [weak self] in
                guard let self, self.isPlaying else { return }
                self.player.pause()
            },
            toggle: { [weak self] in await self?.togglePlayback() },
            skip: { [weak self] amount in self?.skip(amount) },
            seek: { [weak self] position in
                guard let self else { return }
                self.preserve(self.position, source: .thisMac, comparedWith: position)
                self.player.seek(to: position)
            }
        )
        Task { await restore() }
    }

    func restore() async {
        if let local = await stateStore.load() {
            books = local.books
            activeBook = local.activeBookID.flatMap { id in books.first { $0.id == id } }
            if let activeBook {
                position = local.positions[activeBook.id] ?? 0
                duration = activeBook.duration
                speed = local.speeds[activeBook.id] ?? 2
                knownPositions = local.knownPositions[activeBook.id] ?? []
                mode = .player
            }
            speeds = local.speeds
            recentlyFinishedAt = local.recentlyFinishedAt
        }
        guard let connection = try? await vault.loadConnection() else { return }
        server = connection.server.absoluteString
        username = connection.username
        do {
            try await loadLibrary()
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
        activeBook = books.max { ($0.lastPlayedAt ?? .distantPast) < ($1.lastPlayedAt ?? .distantPast) } ?? books.first
        duration = activeBook?.duration ?? 0
        mode = .player
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
        activeBook = result
        position = 0
        duration = result.duration
        speed = speeds[result.id] ?? 2
        didMarkFinished = recentlyFinishedAt[result.id] != nil
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
            if isPlaying { player.pause(); await closePlaybackSession() }
            else if player.hasItem { player.play() }
            else {
                let session = try await client.startPlayback(itemID: book.id)
                playbackSessionID = session.id
                chapters = session.chapters
                duration = session.duration
                position = session.currentTime
                try await player.load(
                    urls: session.streamURLs,
                    bearerToken: await client.accessToken(),
                    position: session.currentTime,
                    speed: speed,
                    title: book.title,
                    author: book.authors.joined(separator: ", "),
                    bookDuration: session.duration
                )
                player.play()
            }
        } catch {
            errorMessage = "Playback couldn’t start."
        }
    }

    func skip(_ amount: TimeInterval) { player.seek(to: min(max(position + amount, 0), duration)) }
    func selectChapter(_ chapter: Chapter) { player.seek(to: chapter.start); mode = .player }
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
            duration = remote.duration
        } catch { errorMessage = "Force Fetch failed." }
    }

    func forcePush() async {
        guard let book = activeBook else { return }
        do {
            if let remote = try? await client.progress(itemID: book.id) { preserve(remote.currentTime, source: .audiobookshelf, comparedWith: position) }
            try await client.pushProgress(itemID: book.id, position: position, duration: duration, isFinished: recentlyFinishedAt[book.id] != nil)
        } catch { errorMessage = "Force Push failed. Your Mac position is preserved." }
    }

    func recover(_ known: KnownPosition) {
        player.seek(to: known.position)
        position = known.position
    }

    private func preserve(_ candidate: TimeInterval, source: PositionSource, comparedWith other: TimeInterval) {
        guard abs(candidate - other) >= SynchronizationPolicy.meaningfulDifference else { return }
        knownPositions.removeAll { abs($0.position - candidate) < SynchronizationPolicy.meaningfulDifference }
        knownPositions.append(.init(position: candidate, source: source, observedAt: .now))
        Task { await saveLocalState() }
    }

    private func playbackTick() async {
        guard isPlaying, let book = activeBook else { return }
        knownPositions.removeAll { Date().timeIntervalSince($0.observedAt) >= 60 * 60 }
        if CompletionPolicy.shouldMarkFinished(position: position, duration: duration, isPlaying: true), !didMarkFinished {
            didMarkFinished = true
            recentlyFinishedAt[book.id] = recentlyFinishedAt[book.id] ?? .now
            try? await client.pushProgress(itemID: book.id, position: position, duration: duration, isFinished: true)
        }
        guard let playbackSessionID, abs(position - lastSyncedPosition) >= 15 else { return }
        do {
            try await client.sync(sessionID: playbackSessionID, position: position, duration: duration, timeListened: 15)
            lastSyncedPosition = position
            hasPendingSynchronization = false
            await saveLocalState()
        } catch {
            hasPendingSynchronization = true
            errorMessage = "Progress is saved on this Mac and will be retried."
        }
    }

    private func restoreActivePosition() async {
        guard let book = activeBook else { return }
        do {
            let remote = try await client.progress(itemID: book.id)
            preserve(position, source: .thisMac, comparedWith: remote.currentTime)
            position = remote.currentTime
            duration = remote.duration
        } catch { errorMessage = "The server position is temporarily unavailable." }
    }

    func showSettings() { mode = mode == .settings ? .player : .settings }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            launchAtLogin = enabled
        } catch { errorMessage = "Launch at Login could not be changed." }
    }

    func signOut() async {
        player.pause()
        try? await client.logout()
        try? await vault.clear()
        await stateStore.clear()
        await artworkStore.clear()
        books = []; activeBook = nil; server = ""; username = ""; password = ""
        mode = .connection
    }

    func artwork(for book: Audiobook) async -> NSImage? {
        if let cached = await artworkStore.image(itemID: book.id, revision: book.coverRevision) { return cached }
        guard let data = try? await client.coverData(itemID: book.id) else { return nil }
        return try? await artworkStore.save(data, itemID: book.id, revision: book.coverRevision)
    }

    func isRecentlyFinished(_ book: Audiobook) -> Bool {
        guard let date = recentlyFinishedAt[book.id] else { return false }
        return Date().timeIntervalSince(date) < CompletionPolicy.lifetime
    }

    private func saveLocalState() async {
        var positions: [String: TimeInterval] = [:]
        var recovery: [String: [KnownPosition]] = [:]
        if let activeBook {
            positions[activeBook.id] = position
            recovery[activeBook.id] = knownPositions
        }
        try? await stateStore.save(.init(
            books: books,
            activeBookID: activeBook?.id,
            positions: positions,
            speeds: speeds,
            knownPositions: recovery,
            recentlyFinishedAt: recentlyFinishedAt
        ))
    }

    private func reconcileFinishedBooks() async {
        for (bookID, finishedAt) in recentlyFinishedAt where Date().timeIntervalSince(finishedAt) >= CompletionPolicy.lifetime {
            guard let remote = try? await client.progress(itemID: bookID) else { continue }
            let snapshot = ServerProgress(position: remote.currentTime, duration: remote.duration, isFinished: remote.isFinished, lastUpdate: remote.lastUpdate)
            if CompletionPolicy.shouldReset(finishedAt: finishedAt, server: snapshot, now: .now) {
                if activeBook?.id == bookID {
                    preserve(remote.currentTime, source: .audiobookshelf, comparedWith: 0)
                    position = 0
                    player.seek(to: 0)
                }
                try? await client.pushProgress(itemID: bookID, position: 0, duration: remote.duration, isFinished: false)
            }
            recentlyFinishedAt.removeValue(forKey: bookID)
        }
    }

    func quit() {
        player.pause()
        Task {
            await saveLocalState()
            await closePlaybackSession()
            if hasPendingSynchronization { await forcePush() }
            NSApplication.shared.terminate(nil)
        }
    }

    func systemWillSleep() {
        Task {
            await saveLocalState()
            if isPlaying { await closePlaybackSession() }
        }
    }

    func systemDidWake() async {
        guard !isPlaying else { return }
        await forceFetch()
    }

    private func closePlaybackSession() async {
        guard let sessionID = playbackSessionID else { return }
        do {
            try await client.close(sessionID: sessionID, position: position, duration: duration, timeListened: max(position - lastSyncedPosition, 0))
            playbackSessionID = nil
            hasPendingSynchronization = false
        } catch {
            hasPendingSynchronization = true
            errorMessage = "Progress is saved on this Mac and will be retried."
        }
    }
}
