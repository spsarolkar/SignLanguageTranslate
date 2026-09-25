import XCTest
@testable import SignLanguageTranslate

final class ProgressThrottleTests: XCTestCase {

    private let start = Date(timeIntervalSinceReferenceDate: 0)
    private let total: Int64 = 1_000_000

    func test_firstUpdate_isForwarded() {
        var throttle = ProgressThrottle(interval: 0.5)

        XCTAssertTrue(throttle.shouldForward(transfer: 1, bytes: 16_384, total: total, now: start))
    }

    func test_burstWithinInterval_forwardsOnlyOnce() {
        var throttle = ProgressThrottle(interval: 0.5)
        var forwarded = 0

        // 100 callbacks, 16 KB apart, all inside 0.4 s.
        for i in 0..<100 {
            let now = start.addingTimeInterval(Double(i) * 0.004)
            if throttle.shouldForward(transfer: 1, bytes: Int64(i + 1) * 16_384, total: total * 10, now: now) {
                forwarded += 1
            }
        }

        XCTAssertEqual(forwarded, 1)
    }

    func test_steadyStream_forwardsAboutOncePerInterval() {
        var throttle = ProgressThrottle(interval: 0.5)
        var forwarded = 0

        // 5 seconds of callbacks every 1/64 s (exact in binary, so no drift).
        for i in 0..<320 {
            let now = start.addingTimeInterval(Double(i) / 64)
            if throttle.shouldForward(transfer: 1, bytes: Int64(i + 1), total: total, now: now) {
                forwarded += 1
            }
        }

        XCTAssertEqual(forwarded, 10)
    }

    func test_finalUpdate_isAlwaysForwarded() {
        var throttle = ProgressThrottle(interval: 0.5)
        XCTAssertTrue(throttle.shouldForward(transfer: 1, bytes: 10, total: total, now: start))

        let finalNow = start.addingTimeInterval(0.01)
        XCTAssertTrue(throttle.shouldForward(transfer: 1, bytes: total, total: total, now: finalNow))
    }

    func test_unknownTotal_isThrottledNotTreatedAsFinal() {
        var throttle = ProgressThrottle(interval: 0.5)
        XCTAssertTrue(throttle.shouldForward(transfer: 1, bytes: 10, total: -1, now: start))

        XCTAssertFalse(throttle.shouldForward(transfer: 1, bytes: 20, total: -1, now: start.addingTimeInterval(0.1)))
    }

    func test_transfersAreThrottledIndependently() {
        var throttle = ProgressThrottle(interval: 0.5)
        XCTAssertTrue(throttle.shouldForward(transfer: 1, bytes: 10, total: total, now: start))

        XCTAssertTrue(throttle.shouldForward(transfer: 2, bytes: 10, total: total, now: start.addingTimeInterval(0.1)))
        XCTAssertFalse(throttle.shouldForward(transfer: 1, bytes: 20, total: total, now: start.addingTimeInterval(0.1)))
    }

    func test_reset_letsNextUpdateThrough() {
        var throttle = ProgressThrottle(interval: 0.5)
        XCTAssertTrue(throttle.shouldForward(transfer: 1, bytes: 10, total: total, now: start))

        throttle.reset(transfer: 1)

        XCTAssertTrue(throttle.shouldForward(transfer: 1, bytes: 20, total: total, now: start.addingTimeInterval(0.1)))
    }
}
