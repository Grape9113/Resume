import Foundation
import Testing

@testable import ResumeCore

@Suite("Playback ledger")
struct PlaybackLedgerTests {
  @Test("updating the Active audiobook preserves every other audiobook")
  func preservesOtherBooks() {
    var ledger = PlaybackLedger(records: [
      "first": .init(position: 1_200, speed: 1.5),
      "second": .init(position: 3_600, speed: 2.5),
    ])

    ledger.update("first") { record in
      record.position = 1_800
      record.hasPendingSynchronization = true
    }

    #expect(ledger["first"]?.position == 1_800)
    #expect(ledger["first"]?.hasPendingSynchronization == true)
    #expect(ledger["second"]?.position == 3_600)
    #expect(ledger["second"]?.speed == 2.5)
  }

  @Test("recovery expires one hour after playback begins")
  func expiresRecoveryAfterPlayback() {
    let start = Date(timeIntervalSince1970: 1_000)
    var ledger = PlaybackLedger(records: [
      "book": .init(
        knownPositions: [.init(position: 9_700, source: .audiobookshelf, observedAt: start)],
        recoveryExpiresAt: start.addingTimeInterval(3_600)
      )
    ])

    ledger.expireRecovery(now: start.addingTimeInterval(3_601))

    #expect(ledger["book"]?.knownPositions.isEmpty == true)
    #expect(ledger["book"]?.recoveryExpiresAt == nil)
  }

  @Test("pre-play recovery is discarded when a new process starts")
  func discardsPrePlayRecoveryOnProcessStart() {
    var ledger = PlaybackLedger(records: [
      "book": .init(
        knownPositions: [.init(position: 2_400, source: .thisMac, observedAt: .now)]
      )
    ])

    ledger.prepareForProcessStart(now: .now)

    #expect(ledger["book"]?.knownPositions.isEmpty == true)
  }

  @Test("playback starts and ambiguity renews one shared recovery window")
  func startsAndRenewsRecoveryWindow() {
    let playbackStart = Date(timeIntervalSince1970: 5_000)
    var ledger = PlaybackLedger(records: [
      "book": .init(
        knownPositions: [.init(position: 2_400, source: .thisMac, observedAt: playbackStart)]
      )
    ])

    ledger.beginRecoveryWindow(for: "book", now: playbackStart)
    #expect(ledger["book"]?.recoveryExpiresAt == playbackStart.addingTimeInterval(3_600))

    let laterAmbiguity = playbackStart.addingTimeInterval(900)
    ledger.beginRecoveryWindow(for: "book", now: laterAmbiguity)
    #expect(ledger["book"]?.recoveryExpiresAt == laterAmbiguity.addingTimeInterval(3_600))
  }
}
