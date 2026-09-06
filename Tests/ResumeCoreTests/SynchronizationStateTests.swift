import Foundation
import Testing

@testable import ResumeCore

@Suite("Synchronization state")
struct SynchronizationStateTests {
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
}
