import Foundation

public enum SynchronizationInstruction: Sendable, Equatable {
  case upload
  case suspend([KnownPosition])

  public static func == (lhs: Self, rhs: Self) -> Bool {
    switch (lhs, rhs) {
    case (.upload, .upload): return true
    case (.suspend(let left), .suspend(let right)):
      return left.map {
        [$0.position, $0.source == .thisMac ? 0 : 1, $0.observedAt.timeIntervalSince1970]
      }
        == right.map {
          [$0.position, $0.source == .thisMac ? 0 : 1, $0.observedAt.timeIntervalSince1970]
        }
    default: return false
    }
  }
}

public struct SynchronizationState: Codable, Equatable, Sendable {
  public private(set) var serverBaseline: Int64?
  public private(set) var lastSyncedPosition: TimeInterval
  public private(set) var pendingPosition: TimeInterval?
  public private(set) var isSuspended: Bool

  public init(
    serverBaseline: Int64? = nil,
    lastSyncedPosition: TimeInterval = 0,
    pendingPosition: TimeInterval? = nil,
    isSuspended: Bool = false
  ) {
    self.serverBaseline = serverBaseline
    self.lastSyncedPosition = lastSyncedPosition
    self.pendingPosition = pendingPosition
    self.isSuspended = isSuspended
  }

  public mutating func prepareUpload(localPosition: TimeInterval, server: ServerProgress, now: Date)
    -> SynchronizationInstruction
  {
    if let serverBaseline,
      server.lastUpdate != serverBaseline,
      abs(server.position - lastSyncedPosition) >= SynchronizationPolicy.meaningfulDifference
    {
      isSuspended = true
      pendingPosition = localPosition
      return .suspend([
        .init(position: localPosition, source: .thisMac, observedAt: now),
        .init(position: server.position, source: .audiobookshelf, observedAt: now),
      ])
    }
    pendingPosition = localPosition
    return .upload
  }

  public mutating func recordFailure(position: TimeInterval) {
    pendingPosition = position
  }

  public mutating func recordSuccess(position: TimeInterval, newServerBaseline: Int64) {
    lastSyncedPosition = position
    serverBaseline = newServerBaseline
    pendingPosition = nil
    isSuspended = false
  }

  public mutating func resolve(serverBaseline: Int64, position: TimeInterval) {
    self.serverBaseline = serverBaseline
    lastSyncedPosition = position
    pendingPosition = nil
    isSuspended = false
  }
}
