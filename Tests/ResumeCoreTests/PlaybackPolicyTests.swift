import Foundation
import Testing
@testable import ResumeCore

@Suite("Playback policy")
struct PlaybackPolicyTests {
    @Test("changed server baseline wins and preserves the Mac position")
    func serverWinsAmbiguity() {
        let decision = SynchronizationPolicy.reconcile(
            local: .init(position: 7_800, isFinished: false, serverBaseline: 100, isDirty: true),
            server: .init(position: 13_200, duration: 20_000, isFinished: false, lastUpdate: 200),
            now: Date(timeIntervalSince1970: 300)
        )

        #expect(decision.authoritativePosition == 13_200)
        #expect(decision.shouldUpload == false)
        #expect(decision.recovery.map(\.position) == [7_800])
    }

    @Test("differences below thirty seconds do not create recovery")
    func synchronizationNoise() {
        let decision = SynchronizationPolicy.reconcile(
            local: .init(position: 1_020, isFinished: false, serverBaseline: 100, isDirty: true),
            server: .init(position: 1_000, duration: 10_000, isFinished: false, lastUpdate: 200),
            now: .now
        )

        #expect(decision.recovery.isEmpty)
    }

    @Test("actual playback at ninety-five percent marks finished")
    func finishesAtThreshold() {
        #expect(CompletionPolicy.shouldMarkFinished(position: 9_500, duration: 10_000, isPlaying: true))
        #expect(!CompletionPolicy.shouldMarkFinished(position: 9_500, duration: 10_000, isPlaying: false))
    }

    @Test("expiry resets only an unchanged near-end server position")
    func guardedExpiryReset() {
        let expired = Date(timeIntervalSince1970: 0)
        let now = Date(timeIntervalSince1970: 6 * 24 * 60 * 60)

        #expect(CompletionPolicy.shouldReset(
            finishedAt: expired,
            server: .init(position: 9_700, duration: 10_000, isFinished: true, lastUpdate: 10),
            now: now
        ))
        #expect(!CompletionPolicy.shouldReset(
            finishedAt: expired,
            server: .init(position: 3_000, duration: 10_000, isFinished: true, lastUpdate: 20),
            now: now
        ))
    }
}
