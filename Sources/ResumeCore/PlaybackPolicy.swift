import Foundation

public struct LocalProgress: Equatable, Sendable {
    public var position: TimeInterval
    public var isFinished: Bool
    public var serverBaseline: Int64?
    public var isDirty: Bool

    public init(position: TimeInterval, isFinished: Bool, serverBaseline: Int64?, isDirty: Bool) {
        self.position = position
        self.isFinished = isFinished
        self.serverBaseline = serverBaseline
        self.isDirty = isDirty
    }
}

public struct ServerProgress: Codable, Equatable, Sendable {
    public var position: TimeInterval
    public var duration: TimeInterval
    public var isFinished: Bool
    public var lastUpdate: Int64

    public init(position: TimeInterval, duration: TimeInterval, isFinished: Bool, lastUpdate: Int64) {
        self.position = position
        self.duration = duration
        self.isFinished = isFinished
        self.lastUpdate = lastUpdate
    }
}

public enum PositionSource: String, Codable, Equatable, Sendable {
    case thisMac
    case audiobookshelf
}

public struct KnownPosition: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let position: TimeInterval
    public let source: PositionSource
    public let observedAt: Date

    public init(id: UUID = UUID(), position: TimeInterval, source: PositionSource, observedAt: Date) {
        self.id = id
        self.position = position
        self.source = source
        self.observedAt = observedAt
    }
}

public struct ReconciliationDecision: Equatable, Sendable {
    public let authoritativePosition: TimeInterval
    public let shouldUpload: Bool
    public let recovery: [KnownPosition]
}

public enum SynchronizationPolicy {
    public static let meaningfulDifference: TimeInterval = 30

    public static func reconcile(local: LocalProgress, server: ServerProgress, now: Date) -> ReconciliationDecision {
        let serverChanged = local.serverBaseline != server.lastUpdate
        if local.isDirty, !serverChanged {
            return .init(authoritativePosition: local.position, shouldUpload: true, recovery: [])
        }

        let differs = abs(local.position - server.position) >= meaningfulDifference
        let recovery = local.isDirty && differs
            ? [KnownPosition(position: local.position, source: .thisMac, observedAt: now)]
            : []
        return .init(authoritativePosition: server.position, shouldUpload: false, recovery: recovery)
    }
}

public enum CompletionPolicy {
    public static let threshold = 0.95
    public static let lifetime: TimeInterval = 5 * 24 * 60 * 60

    public static func shouldMarkFinished(position: TimeInterval, duration: TimeInterval, isPlaying: Bool) -> Bool {
        isPlaying && duration > 0 && position / duration >= threshold
    }

    public static func shouldReset(finishedAt: Date, server: ServerProgress, now: Date) -> Bool {
        now.timeIntervalSince(finishedAt) >= lifetime
            && server.isFinished
            && server.duration > 0
            && server.position / server.duration >= threshold
    }
}
