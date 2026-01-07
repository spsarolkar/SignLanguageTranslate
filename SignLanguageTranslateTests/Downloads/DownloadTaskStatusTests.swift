import XCTest
@testable import SignLanguageTranslate

/// Comprehensive tests for DownloadTaskStatus enum
final class DownloadTaskStatusTests: XCTestCase {

    // MARK: - Display Properties Tests

    func test_displayName_allCasesHaveValidNames() {
        XCTAssertEqual(DownloadTaskStatus.pending.displayName, "Pending")
        XCTAssertEqual(DownloadTaskStatus.queued.displayName, "Queued")
        XCTAssertEqual(DownloadTaskStatus.downloading.displayName, "Downloading")
        XCTAssertEqual(DownloadTaskStatus.paused.displayName, "Paused")
        XCTAssertEqual(DownloadTaskStatus.extracting.displayName, "Extracting")
        XCTAssertEqual(DownloadTaskStatus.completed.displayName, "Completed")
        XCTAssertEqual(DownloadTaskStatus.failed.displayName, "Failed")
    }

    func test_iconName_allCasesHaveValidSFSymbols() {
        // Verify all cases have SF Symbol icon names
        XCTAssertEqual(DownloadTaskStatus.pending.iconName, "clock")
        XCTAssertEqual(DownloadTaskStatus.queued.iconName, "line.3.horizontal")
        XCTAssertEqual(DownloadTaskStatus.downloading.iconName, "arrow.down.circle")
        XCTAssertEqual(DownloadTaskStatus.paused.iconName, "pause.circle")
        XCTAssertEqual(DownloadTaskStatus.extracting.iconName, "archivebox")
        XCTAssertEqual(DownloadTaskStatus.completed.iconName, "checkmark.circle")
        XCTAssertEqual(DownloadTaskStatus.failed.iconName, "exclamationmark.triangle")

        // Ensure no icon name is empty
        for status in DownloadTaskStatus.allCases {
            XCTAssertFalse(status.iconName.isEmpty, "\(status) should have an icon name")
        }
    }

    func test_color_allCasesHaveAssociatedColors() {
        // Verify all cases return a Color (not testing exact color values)
        for status in DownloadTaskStatus.allCases {
            let color = status.color
            XCTAssertNotNil(color, "\(status) should have a color")
        }
    }

    // MARK: - State Properties Tests

    func test_isActive_onlyTrueForDownloadingAndExtracting() {
        // Active statuses
        XCTAssertTrue(DownloadTaskStatus.downloading.isActive)
        XCTAssertTrue(DownloadTaskStatus.extracting.isActive)
        XCTAssertTrue(DownloadTaskStatus.queued.isActive)

        // Inactive statuses
        XCTAssertFalse(DownloadTaskStatus.pending.isActive)
        XCTAssertFalse(DownloadTaskStatus.paused.isActive)
        XCTAssertFalse(DownloadTaskStatus.completed.isActive)
        XCTAssertFalse(DownloadTaskStatus.failed.isActive)
    }

    func test_canStart_trueForPendingPausedFailed() {
        // Can start
        XCTAssertTrue(DownloadTaskStatus.pending.canStart)
        XCTAssertTrue(DownloadTaskStatus.paused.canStart)
        XCTAssertTrue(DownloadTaskStatus.failed.canStart)

        // Cannot start
        XCTAssertFalse(DownloadTaskStatus.queued.canStart)
        XCTAssertFalse(DownloadTaskStatus.downloading.canStart)
        XCTAssertFalse(DownloadTaskStatus.extracting.canStart)
        XCTAssertFalse(DownloadTaskStatus.completed.canStart)
    }

    func test_canPause_onlyTrueForDownloadingAndQueued() {
        // Can pause
        XCTAssertTrue(DownloadTaskStatus.downloading.canPause)
        XCTAssertTrue(DownloadTaskStatus.queued.canPause)

        // Cannot pause
        XCTAssertFalse(DownloadTaskStatus.pending.canPause)
        XCTAssertFalse(DownloadTaskStatus.paused.canPause)
        XCTAssertFalse(DownloadTaskStatus.extracting.canPause)
        XCTAssertFalse(DownloadTaskStatus.completed.canPause)
        XCTAssertFalse(DownloadTaskStatus.failed.canPause)
    }

    func test_isTerminal_onlyTrueForCompletedAndFailed() {
        // Terminal statuses
        XCTAssertTrue(DownloadTaskStatus.completed.isTerminal)
        XCTAssertTrue(DownloadTaskStatus.failed.isTerminal)

        // Non-terminal statuses
        XCTAssertFalse(DownloadTaskStatus.pending.isTerminal)
        XCTAssertFalse(DownloadTaskStatus.queued.isTerminal)
        XCTAssertFalse(DownloadTaskStatus.downloading.isTerminal)
        XCTAssertFalse(DownloadTaskStatus.paused.isTerminal)
        XCTAssertFalse(DownloadTaskStatus.extracting.isTerminal)
    }

    func test_isInProgress_onlyTrueForDownloadingAndExtracting() {
        // In progress
        XCTAssertTrue(DownloadTaskStatus.downloading.isInProgress)
        XCTAssertTrue(DownloadTaskStatus.extracting.isInProgress)

        // Not in progress
        XCTAssertFalse(DownloadTaskStatus.pending.isInProgress)
        XCTAssertFalse(DownloadTaskStatus.queued.isInProgress)
        XCTAssertFalse(DownloadTaskStatus.paused.isInProgress)
        XCTAssertFalse(DownloadTaskStatus.completed.isInProgress)
        XCTAssertFalse(DownloadTaskStatus.failed.isInProgress)
    }

    func test_canRetry_onlyTrueForFailed() {
        // Can retry
        XCTAssertTrue(DownloadTaskStatus.failed.canRetry)

        // Cannot retry
        XCTAssertFalse(DownloadTaskStatus.pending.canRetry)
        XCTAssertFalse(DownloadTaskStatus.queued.canRetry)
        XCTAssertFalse(DownloadTaskStatus.downloading.canRetry)
        XCTAssertFalse(DownloadTaskStatus.paused.canRetry)
        XCTAssertFalse(DownloadTaskStatus.extracting.canRetry)
        XCTAssertFalse(DownloadTaskStatus.completed.canRetry)
    }

    func test_isWaiting_onlyTrueForPendingAndQueued() {
        // Waiting
        XCTAssertTrue(DownloadTaskStatus.pending.isWaiting)
        XCTAssertTrue(DownloadTaskStatus.queued.isWaiting)

        // Not waiting
        XCTAssertFalse(DownloadTaskStatus.downloading.isWaiting)
        XCTAssertFalse(DownloadTaskStatus.paused.isWaiting)
        XCTAssertFalse(DownloadTaskStatus.extracting.isWaiting)
        XCTAssertFalse(DownloadTaskStatus.completed.isWaiting)
        XCTAssertFalse(DownloadTaskStatus.failed.isWaiting)
    }

    // MARK: - CaseIterable Tests

    func test_caseIterable_returnsAllSevenCases() {
        let allCases = DownloadTaskStatus.allCases

        XCTAssertEqual(allCases.count, 7, "Should have exactly 7 status cases")

        XCTAssertTrue(allCases.contains(.pending))
        XCTAssertTrue(allCases.contains(.queued))
        XCTAssertTrue(allCases.contains(.downloading))
        XCTAssertTrue(allCases.contains(.paused))
        XCTAssertTrue(allCases.contains(.extracting))
        XCTAssertTrue(allCases.contains(.completed))
        XCTAssertTrue(allCases.contains(.failed))
    }

    func test_caseIterable_noDuplicates() {
        let allCases = DownloadTaskStatus.allCases
        let uniqueCases = Set(allCases)

        XCTAssertEqual(allCases.count, uniqueCases.count, "Should have no duplicate cases")
    }

    // MARK: - Codable Tests

    func test_codable_encodingAndDecoding_pending() throws {
        let status = DownloadTaskStatus.pending
        let encoded = try JSONEncoder().encode(status)
        let decoded = try JSONDecoder().decode(DownloadTaskStatus.self, from: encoded)

        XCTAssertEqual(decoded, status)
    }

    func test_codable_encodingAndDecoding_downloading() throws {
        let status = DownloadTaskStatus.downloading
        let encoded = try JSONEncoder().encode(status)
        let decoded = try JSONDecoder().decode(DownloadTaskStatus.self, from: encoded)

        XCTAssertEqual(decoded, status)
    }

    func test_codable_encodingAndDecoding_completed() throws {
        let status = DownloadTaskStatus.completed
        let encoded = try JSONEncoder().encode(status)
        let decoded = try JSONDecoder().decode(DownloadTaskStatus.self, from: encoded)

        XCTAssertEqual(decoded, status)
    }

    func test_codable_encodingAndDecoding_failed() throws {
        let status = DownloadTaskStatus.failed
        let encoded = try JSONEncoder().encode(status)
        let decoded = try JSONDecoder().decode(DownloadTaskStatus.self, from: encoded)

        XCTAssertEqual(decoded, status)
    }

    func test_codable_allCasesCanBeEncoded() throws {
        for status in DownloadTaskStatus.allCases {
            XCTAssertNoThrow(try JSONEncoder().encode(status))
        }
    }

    func test_codable_roundTripForAllCases() throws {
        for status in DownloadTaskStatus.allCases {
            let encoded = try JSONEncoder().encode(status)
            let decoded = try JSONDecoder().decode(DownloadTaskStatus.self, from: encoded)
            XCTAssertEqual(decoded, status, "\(status) should round-trip correctly")
        }
    }

    // MARK: - CustomStringConvertible Tests

    func test_description_matchesDisplayName() {
        for status in DownloadTaskStatus.allCases {
            XCTAssertEqual(status.description, status.displayName)
        }
    }

    // MARK: - Helper Collections Tests

    func test_activeStatuses_excludesTerminalStatuses() {
        let activeStatuses = DownloadTaskStatus.activeStatuses

        XCTAssertFalse(activeStatuses.contains(.completed))
        XCTAssertFalse(activeStatuses.contains(.failed))

        // Should include non-terminal
        XCTAssertTrue(activeStatuses.contains(.pending))
        XCTAssertTrue(activeStatuses.contains(.queued))
        XCTAssertTrue(activeStatuses.contains(.downloading))
        XCTAssertTrue(activeStatuses.contains(.paused))
        XCTAssertTrue(activeStatuses.contains(.extracting))
    }

    func test_terminalStatuses_onlyCompletedAndFailed() {
        let terminalStatuses = DownloadTaskStatus.terminalStatuses

        XCTAssertEqual(terminalStatuses.count, 2)
        XCTAssertTrue(terminalStatuses.contains(.completed))
        XCTAssertTrue(terminalStatuses.contains(.failed))
    }

    func test_progressStatuses_onlyDownloadingAndExtracting() {
        let progressStatuses = DownloadTaskStatus.progressStatuses

        XCTAssertEqual(progressStatuses.count, 2)
        XCTAssertTrue(progressStatuses.contains(.downloading))
        XCTAssertTrue(progressStatuses.contains(.extracting))
    }

    // MARK: - Hashable Tests

    func test_hashable_sameStatusHasSameHash() {
        let status1 = DownloadTaskStatus.downloading
        let status2 = DownloadTaskStatus.downloading

        XCTAssertEqual(status1.hashValue, status2.hashValue)
    }

    func test_hashable_canBeUsedInSet() {
        let statusSet: Set<DownloadTaskStatus> = [.pending, .downloading, .completed]

        XCTAssertEqual(statusSet.count, 3)
        XCTAssertTrue(statusSet.contains(.pending))
        XCTAssertTrue(statusSet.contains(.downloading))
        XCTAssertTrue(statusSet.contains(.completed))
    }

    func test_hashable_canBeUsedAsDictionaryKey() {
        var statusCounts: [DownloadTaskStatus: Int] = [:]

        statusCounts[.pending] = 5
        statusCounts[.downloading] = 2
        statusCounts[.completed] = 10

        XCTAssertEqual(statusCounts[.pending], 5)
        XCTAssertEqual(statusCounts[.downloading], 2)
        XCTAssertEqual(statusCounts[.completed], 10)
    }

    // MARK: - Equatable Tests

    func test_equatable_sameStatusAreEqual() {
        XCTAssertEqual(DownloadTaskStatus.pending, DownloadTaskStatus.pending)
        XCTAssertEqual(DownloadTaskStatus.downloading, DownloadTaskStatus.downloading)
        XCTAssertEqual(DownloadTaskStatus.completed, DownloadTaskStatus.completed)
    }

    func test_equatable_differentStatusAreNotEqual() {
        XCTAssertNotEqual(DownloadTaskStatus.pending, DownloadTaskStatus.downloading)
        XCTAssertNotEqual(DownloadTaskStatus.downloading, DownloadTaskStatus.completed)
        XCTAssertNotEqual(DownloadTaskStatus.completed, DownloadTaskStatus.failed)
    }

    // MARK: - State Transition Logic Tests

    /// Verify that state transition logic is consistent
    func test_stateTransitionLogic_canStartAndCanPauseMutuallyExclusive() {
        // For most statuses, canStart and canPause should be mutually exclusive
        // Exception: none (they are always mutually exclusive in current design)

        for status in DownloadTaskStatus.allCases {
            if status.canStart {
                XCTAssertFalse(status.canPause, "\(status) cannot both be startable and pausable")
            }
        }
    }

    func test_stateTransitionLogic_terminalStatusesCannotStart() {
        for status in DownloadTaskStatus.allCases where status.isTerminal {
            XCTAssertFalse(status.canStart, "Terminal status \(status) should not be startable")
        }
    }

    func test_stateTransitionLogic_activeStatusesCannotStart() {
        // Active statuses should not be startable (already running)
        for status in DownloadTaskStatus.allCases where status.isActive {
            XCTAssertFalse(status.canStart, "Active status \(status) should not be startable")
        }
    }
}
