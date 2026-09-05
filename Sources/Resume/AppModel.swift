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
    var isBusy = false
    var launchAtLogin = SMAppService.mainApp.status == .enabled

    @ObservationIgnored private let vault = KeychainStore()
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
        Task { await restore() }
    }

    func restore() async {
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
        activeBook = books.max { ($0.lastPlayedAt ?? .distantPast) < ($1.lastPlayedAt ?? .distantPast) } ?? books.first
        duration = activeBook?.duration ?? 0
        mode = .player
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
        activeBook = result
        position = 0
        duration = result.duration
        cancelSearch()
    }

    func cancelSearch() {
        query = ""
        searchResult = nil
        mode = .player
    }

    func togglePlayback() async {
        guard let book = activeBook else { return }
        do {
            if isPlaying { player.pause() }
            else if player.hasItem { player.play() }
            else {
                let session = try await client.startPlayback(itemID: book.id)
                playbackSessionID = session.id
                chapters = session.chapters
                duration = session.duration
                position = session.currentTime
                try await player.load(url: session.streamURL, bearerToken: await client.accessToken(), position: session.currentTime, speed: speed)
                player.play()
            }
        } catch {
            errorMessage = "Playback couldn’t start."
        }
    }

    func skip(_ amount: TimeInterval) { player.seek(to: min(max(position + amount, 0), duration)) }
    func selectChapter(_ chapter: Chapter) { player.seek(to: chapter.start); mode = .player }
    func setSpeed(_ value: Double) { speed = value; player.rate = Float(value) }

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
            try await client.pushProgress(itemID: book.id, position: position, duration: duration, isFinished: didMarkFinished)
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
    }

    private func playbackTick() async {
        guard isPlaying, let book = activeBook else { return }
        if CompletionPolicy.shouldMarkFinished(position: position, duration: duration, isPlaying: true), !didMarkFinished {
            didMarkFinished = true
            try? await client.pushProgress(itemID: book.id, position: position, duration: duration, isFinished: true)
        }
        guard let playbackSessionID, abs(position - lastSyncedPosition) >= 15 else { return }
        lastSyncedPosition = position
        try? await client.sync(sessionID: playbackSessionID, position: position, duration: duration, timeListened: 15)
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
        books = []; activeBook = nil; server = ""; username = ""; password = ""
        mode = .connection
    }

    func quit() {
        player.pause()
        NSApplication.shared.terminate(nil)
    }
}
