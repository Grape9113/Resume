import Foundation

public enum RetryBackoff {
  public static func delay(afterFailure failureCount: Int, jitter: Double) -> TimeInterval {
    let exponent = max(failureCount - 1, 0)
    let base = min(pow(2, Double(exponent)), 60)
    let boundedJitter = min(max(jitter, -1), 1)
    return min(base * (1 + boundedJitter * 0.2), 60)
  }
}
