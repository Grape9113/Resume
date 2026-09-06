import Foundation

public struct AudiobookPlaybackRecord: Codable, Equatable, Sendable {
  public var position: TimeInterval
  public var speed: Double
  public var knownPositions: [KnownPosition]
  public var recoveryExpiresAt: Date?
  public var recentlyFinishedAt: Date?
  public var synchronization: SynchronizationState
  public var hasPendingSynchronization: Bool {
    get { synchronization.pendingPosition != nil }
    set {
      if newValue {
        synchronization.recordFailure(position: position)
      } else if let baseline = synchronization.serverBaseline {
        synchronization.recordSuccess(position: position, newServerBaseline: baseline)
      }
    }
  }

  public init(
    position: TimeInterval = 0,
    speed: Double = 2,
    knownPositions: [KnownPosition] = [],
    recoveryExpiresAt: Date? = nil,
    recentlyFinishedAt: Date? = nil,
    synchronization: SynchronizationState = .init(),
    hasPendingSynchronization: Bool = false
  ) {
    self.position = position
    self.speed = speed
    self.knownPositions = knownPositions
    self.recoveryExpiresAt = recoveryExpiresAt
    self.recentlyFinishedAt = recentlyFinishedAt
    self.synchronization = synchronization
    if hasPendingSynchronization { self.synchronization.recordFailure(position: position) }
  }
}

public struct PlaybackLedger: Codable, Equatable, Sendable {
  public static let recoveryLifetime: TimeInterval = 60 * 60
  public private(set) var records: [String: AudiobookPlaybackRecord]

  public init(records: [String: AudiobookPlaybackRecord] = [:]) {
    self.records = records
  }

  public subscript(id: String) -> AudiobookPlaybackRecord? { records[id] }

  public mutating func update(_ id: String, _ change: (inout AudiobookPlaybackRecord) -> Void) {
    var record = records[id] ?? .init()
    change(&record)
    records[id] = record
  }

  public mutating func removeAll() { records.removeAll() }

  public mutating func prepareForProcessStart(now: Date) {
    for id in records.keys {
      guard let expiresAt = records[id]?.recoveryExpiresAt else {
        records[id]?.knownPositions = []
        continue
      }
      if expiresAt <= now {
        records[id]?.knownPositions = []
        records[id]?.recoveryExpiresAt = nil
      }
    }
  }

  public mutating func beginRecoveryWindow(for id: String, now: Date) {
    guard records[id]?.knownPositions.isEmpty == false else { return }
    records[id]?.recoveryExpiresAt = now.addingTimeInterval(Self.recoveryLifetime)
  }

  public mutating func expireRecovery(now: Date) {
    for id in records.keys {
      guard let expiresAt = records[id]?.recoveryExpiresAt, expiresAt <= now else { continue }
      records[id]?.knownPositions = []
      records[id]?.recoveryExpiresAt = nil
    }
  }
}
