import Foundation

public struct Chapter: Equatable, Sendable, Identifiable, Codable {
    public let id: String
    public let title: String
    public let start: TimeInterval

    public init(id: String, title: String, start: TimeInterval) {
        self.id = id
        self.title = title
        self.start = start
    }
}

public struct PlaybackState: Equatable, Sendable, Codable {
    public var position: TimeInterval
    public var duration: TimeInterval

    public init(position: TimeInterval = 0, duration: TimeInterval = 0) {
        self.position = position
        self.duration = duration
    }
}

public enum PlaybackIntent: Equatable, Sendable {
    case paused
    case playing
}

public enum PanelMode: Equatable, Sendable {
    case connection
    case player
    case search(query: String)
    case settings
    case chapters
    case positionRecovery
}

public enum ApplicationAction: Equatable, Sendable {
    case typed(String)
    case space
    case backspace
    case escape
    case toggleSettings
    case selectChapter(id: String)
    case progressPointerInteraction(proposedPosition: TimeInterval)
}

public struct ResumeApplication: Equatable, Sendable {
    public private(set) var mode: PanelMode
    public private(set) var playbackIntent: PlaybackIntent
    public private(set) var playback: PlaybackState
    public private(set) var chapters: [Chapter]

    public init(
        mode: PanelMode = .connection,
        playbackIntent: PlaybackIntent = .paused,
        playback: PlaybackState = .init(),
        chapters: [Chapter] = []
    ) {
        self.mode = mode
        self.playbackIntent = playbackIntent
        self.playback = playback
        self.chapters = chapters
    }

    public var bookProgress: Double {
        guard playback.duration > 0 else { return 0 }
        return min(max(playback.position / playback.duration, 0), 1)
    }

    public mutating func send(_ action: ApplicationAction) {
        switch (mode, action) {
        case (.player, .typed(let text)) where !text.isEmpty:
            mode = .search(query: text)
        case (.search(let query), .typed(let text)):
            mode = .search(query: query + text)
        case (.player, .space):
            playbackIntent = playbackIntent == .playing ? .paused : .playing
        case (.search(let query), .space):
            mode = .search(query: query + " ")
        case (.search(let query), .backspace):
            let shortened = String(query.dropLast())
            mode = shortened.isEmpty ? .player : .search(query: shortened)
        case (.search, .escape), (.settings, .escape), (.chapters, .escape), (.positionRecovery, .escape):
            mode = .player
        case (_, .toggleSettings):
            mode = mode == .settings ? .player : .settings
        case (_, .selectChapter(let id)):
            guard let chapter = chapters.first(where: { $0.id == id }) else { return }
            playback.position = min(max(chapter.start, 0), playback.duration)
            mode = .player
        case (_, .progressPointerInteraction):
            break
        default:
            break
        }
    }
}
