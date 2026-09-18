import Foundation
import Testing

@testable import ResumeCore

@Suite("Synchronization state")
struct SynchronizationStateTests {
  @Test(
    "suspended synchronization exposes recovery only for distinct positions",
    arguments: [0.0, 29.0, 30.0])
  func suspensionDeduplicatesNoise(difference: Double) {
    var state = SynchronizationState(serverBaseline: 1, lastSyncedPosition: 100)
    let instruction = state.prepareUpload(
      localPosition: 100 + difference,
      server: .init(position: 100, duration: 1_000, isFinished: false, lastUpdate: 2), now: .now)
    guard case .suspend(let positions) = instruction else {
      Issue.record("A changed baseline must suspend automatic writes")
      return
    }
    #expect(positions.count == (difference >= 30 ? 2 : 0))
  }

  @Test(
    "unknown or changed server baselines never authorize a stale pending write",
    arguments: [Int64?.none, Int64?.some(99)])
  func uncertainBaselineCannotUpload(baseline: Int64?) {
    var state = SynchronizationState(serverBaseline: baseline, lastSyncedPosition: 100)
    let instruction = state.prepareUpload(
      localPosition: 900,
      server: .init(position: 110, duration: 1_000, isFinished: false, lastUpdate: 100),
      now: Date(timeIntervalSince1970: 500))
    if case .upload = instruction {
      Issue.record("Stale Mac state would overwrite newer server state")
    }
    #expect(state.isSuspended)
  }

  @Test("another client advancing playback suspends automatic writes")
  func suspendsForAnotherClient() {
    let now = Date(timeIntervalSince1970: 500)
    var state = SynchronizationState(serverBaseline: 100, lastSyncedPosition: 1_000)

    let instruction = state.prepareUpload(
      localPosition: 1_300,
      server: .init(position: 4_000, duration: 10_000, isFinished: false, lastUpdate: 200),
      now: now
    )

    #expect(
      instruction
        == .suspend([
          .init(position: 1_300, source: .thisMac, observedAt: now),
          .init(position: 4_000, source: .audiobookshelf, observedAt: now),
        ]))
    #expect(state.isSuspended)
  }

  @Test("a matching baseline permits upload and failures stay pending")
  func pendingWriteLifecycle() {
    var state = SynchronizationState(serverBaseline: 100, lastSyncedPosition: 1_000)
    let server = ServerProgress(
      position: 1_000, duration: 10_000, isFinished: false, lastUpdate: 100)

    #expect(state.prepareUpload(localPosition: 1_300, server: server, now: .now) == .upload)
    state.recordFailure(position: 1_300)
    #expect(state.pendingPosition == 1_300)

    state.recordSuccess(position: 1_300, newServerBaseline: 201)
    #expect(state.pendingPosition == nil)
    #expect(state.serverBaseline == 201)
  }

  @Test("an explicit external-progress signal holds writes even before a baseline changes")
  func explicitSuspensionHoldsWrites() {
    let now = Date(timeIntervalSince1970: 700)
    var state = SynchronizationState(serverBaseline: 100, lastSyncedPosition: 1_000)
    state.suspend(position: 1_300)

    let instruction = state.prepareUpload(
      localPosition: 1_350,
      server: .init(position: 1_020, duration: 10_000, isFinished: false, lastUpdate: 100),
      now: now)

    #expect(
      instruction
        == .suspend([
          .init(position: 1_350, source: .thisMac, observedAt: now),
          .init(position: 1_020, source: .audiobookshelf, observedAt: now),
        ]))
  }
}
