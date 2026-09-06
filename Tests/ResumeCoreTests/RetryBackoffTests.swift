import Testing

@testable import ResumeCore

@Suite("Retry backoff")
struct RetryBackoffTests {
  @Test("failures back off exponentially and stay bounded")
  func exponentialBoundedDelay() {
    #expect(RetryBackoff.delay(afterFailure: 1, jitter: 0) == 1)
    #expect(RetryBackoff.delay(afterFailure: 4, jitter: 0) == 8)
    #expect(RetryBackoff.delay(afterFailure: 20, jitter: 0) == 60)
  }

  @Test("jitter is capped to a small fraction of the base delay")
  func boundedJitter() {
    #expect(RetryBackoff.delay(afterFailure: 3, jitter: 1) == 4.8)
    #expect(RetryBackoff.delay(afterFailure: 3, jitter: -1) == 3.2)
  }
}
