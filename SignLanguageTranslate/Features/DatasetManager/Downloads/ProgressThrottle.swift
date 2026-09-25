import Foundation

/// Limits how often byte progress for one transfer is forwarded.
///
/// URLSession reports progress every ~16 KB — hundreds of times a second at
/// a few MB/s across three transfers. Forwarding each one hopped to the main
/// actor several times and redrew every view watching the task list, which
/// kept the CPU busy and froze the UI. This keeps the first update, then at
/// most one per `interval` per transfer, and always the final one.
///
/// A value type with no locking: `BackgroundSessionManager` only touches it
/// from the session's serial delegate queue.
struct ProgressThrottle {

    /// Minimum time between forwarded updates for one transfer.
    static let defaultInterval: TimeInterval = 0.5

    let interval: TimeInterval
    private var lastForwarded: [Int: Date] = [:]

    init(interval: TimeInterval = ProgressThrottle.defaultInterval) {
        self.interval = interval
    }

    /// Whether to forward this update, recording it if so.
    /// - Parameters:
    ///   - transfer: URLSession task identifier.
    ///   - bytes: Total bytes written so far.
    ///   - total: Expected total, or ≤ 0 if unknown.
    ///   - now: Current time; injectable for tests.
    mutating func shouldForward(transfer: Int, bytes: Int64, total: Int64, now: Date = Date()) -> Bool {
        let isFinal = total > 0 && bytes >= total
        if !isFinal, let last = lastForwarded[transfer], now.timeIntervalSince(last) < interval {
            return false
        }
        lastForwarded[transfer] = now
        return true
    }

    /// Forget a transfer once it finishes, so identifiers can be reused.
    mutating func reset(transfer: Int) {
        lastForwarded.removeValue(forKey: transfer)
    }
}
