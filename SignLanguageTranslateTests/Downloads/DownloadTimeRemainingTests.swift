import XCTest
@testable import SignLanguageTranslate

final class DownloadTimeRemainingTests: XCTestCase {

    // MARK: - DownloadManager.timeRemaining

    func test_timeRemaining_usesAllRemainingBytes() {
        // Seen on device: 3.51 GB of 46.66 GB at 416 KB/s. The old estimate
        // (active parts only) read "2h 3m"; the whole queue takes ~29 h.
        let remaining: Int64 = 46_660_000_000 - 3_510_000_000
        let rate = 416.0 * 1024

        let eta = DownloadManager.timeRemaining(remainingBytes: remaining, rate: rate)

        XCTAssertNotNil(eta, "Estimates over 24 h must be shown, not hidden")
        XCTAssertEqual(eta ?? 0, Double(remaining) / rate, accuracy: 1)
        XCTAssertGreaterThan(eta ?? 0, 28 * 3600)
    }

    func test_timeRemaining_nilWithoutRate() {
        XCTAssertNil(DownloadManager.timeRemaining(remainingBytes: 1_000, rate: 0))
        XCTAssertNil(DownloadManager.timeRemaining(remainingBytes: 1_000, rate: .infinity))
    }

    func test_timeRemaining_nilWhenNothingRemains() {
        XCTAssertNil(DownloadManager.timeRemaining(remainingBytes: 0, rate: 1_000))
        XCTAssertNil(DownloadManager.timeRemaining(remainingBytes: -5, rate: 1_000))
    }

    // MARK: - DownloadProgressTracker.formatDuration

    func test_formatDuration_formats() {
        XCTAssertEqual(DownloadProgressTracker.formatDuration(45), "45s")
        XCTAssertEqual(DownloadProgressTracker.formatDuration(150), "2m 30s")
        XCTAssertEqual(DownloadProgressTracker.formatDuration(4_500), "1h 15m")
        XCTAssertEqual(DownloadProgressTracker.formatDuration(29 * 3600 + 300), "29h 5m")
    }

    func test_formatDuration_nilForMissingOrInvalid() {
        XCTAssertNil(DownloadProgressTracker.formatDuration(nil))
        XCTAssertNil(DownloadProgressTracker.formatDuration(0))
        XCTAssertNil(DownloadProgressTracker.formatDuration(.infinity))
    }
}
