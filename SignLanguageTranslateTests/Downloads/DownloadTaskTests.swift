import XCTest
@testable import SignLanguageTranslate

/// Unit tests for download task models
final class DownloadTaskTests: XCTestCase {

    // MARK: - DownloadTaskStatus Tests

    func test_downloadTaskStatus_displayProperties() {
        XCTAssertEqual(DownloadTaskStatus.pending.displayName, "Pending")
        XCTAssertEqual(DownloadTaskStatus.downloading.displayName, "Downloading")
        XCTAssertEqual(DownloadTaskStatus.completed.displayName, "Completed")
        XCTAssertEqual(DownloadTaskStatus.failed.displayName, "Failed")

        XCTAssertEqual(DownloadTaskStatus.pending.iconName, "clock")
        XCTAssertEqual(DownloadTaskStatus.downloading.iconName, "arrow.down.circle")
        XCTAssertEqual(DownloadTaskStatus.extracting.iconName, "archivebox")
    }

    func test_downloadTaskStatus_stateProperties() {
        // Active statuses
        XCTAssertTrue(DownloadTaskStatus.downloading.isActive)
        XCTAssertTrue(DownloadTaskStatus.extracting.isActive)
        XCTAssertTrue(DownloadTaskStatus.queued.isActive)
        XCTAssertFalse(DownloadTaskStatus.pending.isActive)
        XCTAssertFalse(DownloadTaskStatus.completed.isActive)

        // Can start
        XCTAssertTrue(DownloadTaskStatus.pending.canStart)
        XCTAssertTrue(DownloadTaskStatus.paused.canStart)
        XCTAssertTrue(DownloadTaskStatus.failed.canStart)
        XCTAssertFalse(DownloadTaskStatus.downloading.canStart)
        XCTAssertFalse(DownloadTaskStatus.completed.canStart)

        // Can pause
        XCTAssertTrue(DownloadTaskStatus.downloading.canPause)
        XCTAssertTrue(DownloadTaskStatus.queued.canPause)
        XCTAssertFalse(DownloadTaskStatus.pending.canPause)
        XCTAssertFalse(DownloadTaskStatus.paused.canPause)
        XCTAssertFalse(DownloadTaskStatus.completed.canPause)

        // Terminal states
        XCTAssertTrue(DownloadTaskStatus.completed.isTerminal)
        XCTAssertTrue(DownloadTaskStatus.failed.isTerminal)
        XCTAssertFalse(DownloadTaskStatus.downloading.isTerminal)
        XCTAssertFalse(DownloadTaskStatus.pending.isTerminal)
    }

    func test_downloadTaskStatus_caseIterable() {
        let allStatuses = DownloadTaskStatus.allCases
        XCTAssertEqual(allStatuses.count, 7)
        XCTAssertTrue(allStatuses.contains(.pending))
        XCTAssertTrue(allStatuses.contains(.queued))
        XCTAssertTrue(allStatuses.contains(.downloading))
        XCTAssertTrue(allStatuses.contains(.paused))
        XCTAssertTrue(allStatuses.contains(.extracting))
        XCTAssertTrue(allStatuses.contains(.completed))
        XCTAssertTrue(allStatuses.contains(.failed))
    }

    // MARK: - DownloadTask Creation Tests

    func test_downloadTask_creationFromManifestEntry() {
        // Given: A manifest entry
        let entry = ManifestEntry(
            category: "Animals",
            partNumber: 1,
            totalParts: 2,
            filename: "Animals_1of2.zip",
            url: URL(string: "https://zenodo.org/api/records/4010759/files/Animals_1of2.zip")!,
            estimatedSize: 1_200_000_000
        )

        // When: We create a download task from it
        let task = DownloadTask(from: entry, datasetName: "INCLUDE")

        // Then: Task should have correct properties
        XCTAssertEqual(task.url, entry.url)
        XCTAssertEqual(task.category, "Animals")
        XCTAssertEqual(task.partNumber, 1)
        XCTAssertEqual(task.totalParts, 2)
        XCTAssertEqual(task.datasetName, "INCLUDE")
        XCTAssertEqual(task.status, .pending)
        XCTAssertEqual(task.progress, 0.0)
        XCTAssertEqual(task.bytesDownloaded, 0)
        XCTAssertEqual(task.totalBytes, 1_200_000_000)
        XCTAssertNil(task.errorMessage)
        XCTAssertNil(task.resumeDataPath)
        XCTAssertNil(task.startedAt)
        XCTAssertNil(task.completedAt)
    }

    func test_downloadTask_creationWithAllProperties() {
        // Given: All properties
        let id = UUID()
        let url = URL(string: "https://example.com/file.zip")!
        let createdAt = Date()
        let startedAt = Date().addingTimeInterval(-60)

        // When: We create a task
        let task = DownloadTask(
            id: id,
            url: url,
            category: "Test",
            partNumber: 1,
            totalParts: 1,
            datasetName: "TEST",
            status: .downloading,
            progress: 0.5,
            bytesDownloaded: 500_000_000,
            totalBytes: 1_000_000_000,
            errorMessage: nil,
            resumeDataPath: nil,
            createdAt: createdAt,
            startedAt: startedAt,
            completedAt: nil
        )

        // Then: All properties should be set
        XCTAssertEqual(task.id, id)
        XCTAssertEqual(task.url, url)
        XCTAssertEqual(task.status, .downloading)
        XCTAssertEqual(task.progress, 0.5)
        XCTAssertEqual(task.bytesDownloaded, 500_000_000)
        XCTAssertEqual(task.createdAt, createdAt)
        XCTAssertEqual(task.startedAt, startedAt)
    }

    // MARK: - Computed Properties Tests

    func test_downloadTask_filename() {
        let task = DownloadTask(
            url: URL(string: "https://example.com/path/to/Animals_1of2.zip")!,
            category: "Animals",
            partNumber: 1,
            totalParts: 2,
            datasetName: "INCLUDE"
        )

        XCTAssertEqual(task.filename, "Animals_1of2.zip")
    }

    func test_downloadTask_displayName_singlePart() {
        let task = DownloadTask(
            url: URL(string: "https://example.com/Seasons.zip")!,
            category: "Seasons",
            partNumber: 1,
            totalParts: 1,
            datasetName: "INCLUDE"
        )

        XCTAssertEqual(task.displayName, "Seasons")
        XCTAssertEqual(task.shortDisplayName, "Seasons")
    }

    func test_downloadTask_displayName_multiPart() {
        let task = DownloadTask(
            url: URL(string: "https://example.com/Animals_1of2.zip")!,
            category: "Animals",
            partNumber: 1,
            totalParts: 2,
            datasetName: "INCLUDE"
        )

        XCTAssertEqual(task.displayName, "Animals (Part 1 of 2)")
        XCTAssertEqual(task.shortDisplayName, "Animals 1/2")
    }

    func test_downloadTask_progressPercentage() {
        var task = DownloadTask(
            url: URL(string: "https://example.com/file.zip")!,
            category: "Test",
            partNumber: 1,
            totalParts: 1,
            datasetName: "TEST",
            progress: 0.0
        )

        XCTAssertEqual(task.progressPercentage, 0)

        task.progress = 0.456
        XCTAssertEqual(task.progressPercentage, 46)

        task.progress = 1.0
        XCTAssertEqual(task.progressPercentage, 100)
    }

    func test_downloadTask_progressText_withTotalBytes() {
        let task = DownloadTask(
            url: URL(string: "https://example.com/file.zip")!,
            category: "Test",
            partNumber: 1,
            totalParts: 1,
            datasetName: "TEST",
            progress: 0.5,
            bytesDownloaded: 500_000_000,
            totalBytes: 1_000_000_000
        )

        // Should format as "500.0 MB / 1.0 GB"
        let progressText = task.progressText
        XCTAssertTrue(progressText.contains("MB"))
        XCTAssertTrue(progressText.contains("GB"))
        XCTAssertTrue(progressText.contains("/"))
    }

    func test_downloadTask_progressText_withoutTotalBytes() {
        let task = DownloadTask(
            url: URL(string: "https://example.com/file.zip")!,
            category: "Test",
            partNumber: 1,
            totalParts: 1,
            datasetName: "TEST",
            progress: 0.45,
            bytesDownloaded: 0,
            totalBytes: 0
        )

        // Should show percentage
        XCTAssertEqual(task.progressText, "45%")
    }

    func test_downloadTask_isActive() {
        var task = DownloadTask(
            url: URL(string: "https://example.com/file.zip")!,
            category: "Test",
            partNumber: 1,
            totalParts: 1,
            datasetName: "TEST"
        )

        XCTAssertFalse(task.isActive)

        task.status = .downloading
        XCTAssertTrue(task.isActive)

        task.status = .extracting
        XCTAssertTrue(task.isActive)

        task.status = .completed
        XCTAssertFalse(task.isActive)
    }

    func test_downloadTask_canStartAndCanPause() {
        var task = DownloadTask(
            url: URL(string: "https://example.com/file.zip")!,
            category: "Test",
            partNumber: 1,
            totalParts: 1,
            datasetName: "TEST"
        )

        // Pending: can start, can't pause
        XCTAssertTrue(task.canStart)
        XCTAssertFalse(task.canPause)

        task.status = .downloading
        // Downloading: can't start, can pause
        XCTAssertFalse(task.canStart)
        XCTAssertTrue(task.canPause)

        task.status = .paused
        // Paused: can start, can't pause
        XCTAssertTrue(task.canStart)
        XCTAssertFalse(task.canPause)

        task.status = .completed
        // Completed: can't start, can't pause
        XCTAssertFalse(task.canStart)
        XCTAssertFalse(task.canPause)
    }

    func test_downloadTask_hasResumeData() {
        var task = DownloadTask(
            url: URL(string: "https://example.com/file.zip")!,
            category: "Test",
            partNumber: 1,
            totalParts: 1,
            datasetName: "TEST"
        )

        XCTAssertFalse(task.hasResumeData)

        task.resumeDataPath = "/tmp/resume.data"
        XCTAssertTrue(task.hasResumeData)
    }

    // MARK: - State Transition Tests

    func test_downloadTask_updateProgress() {
        var task = DownloadTask(
            url: URL(string: "https://example.com/file.zip")!,
            category: "Test",
            partNumber: 1,
            totalParts: 1,
            datasetName: "TEST",
            totalBytes: 1_000_000_000
        )

        // Update progress
        task.updateProgress(bytesDownloaded: 250_000_000, totalBytes: 1_000_000_000)

        XCTAssertEqual(task.bytesDownloaded, 250_000_000)
        XCTAssertEqual(task.totalBytes, 1_000_000_000)
        XCTAssertEqual(task.progress, 0.25)
    }

    func test_downloadTask_updateProgress_withoutTotalBytes() {
        var task = DownloadTask(
            url: URL(string: "https://example.com/file.zip")!,
            category: "Test",
            partNumber: 1,
            totalParts: 1,
            datasetName: "TEST",
            totalBytes: 0
        )

        // Update progress without knowing total
        task.updateProgress(bytesDownloaded: 250_000_000, totalBytes: 0)

        XCTAssertEqual(task.bytesDownloaded, 250_000_000)
        XCTAssertEqual(task.progress, 0.0) // Can't calculate without total
    }

    func test_downloadTask_updateProgress_clampingToOne() {
        var task = DownloadTask(
            url: URL(string: "https://example.com/file.zip")!,
            category: "Test",
            partNumber: 1,
            totalParts: 1,
            datasetName: "TEST",
            totalBytes: 1_000_000_000
        )

        // Downloaded more than total (edge case)
        task.updateProgress(bytesDownloaded: 1_500_000_000, totalBytes: 1_000_000_000)

        XCTAssertEqual(task.progress, 1.0) // Should clamp to 1.0
    }

    func test_downloadTask_start() {
        var task = DownloadTask(
            url: URL(string: "https://example.com/file.zip")!,
            category: "Test",
            partNumber: 1,
            totalParts: 1,
            datasetName: "TEST",
            status: .pending
        )

        XCTAssertNil(task.startedAt)

        task.start()

        XCTAssertEqual(task.status, .downloading)
        XCTAssertNotNil(task.startedAt)
        XCTAssertNil(task.errorMessage)
    }

    func test_downloadTask_start_fromPaused() {
        var task = DownloadTask(
            url: URL(string: "https://example.com/file.zip")!,
            category: "Test",
            partNumber: 1,
            totalParts: 1,
            datasetName: "TEST",
            status: .paused,
            startedAt: Date().addingTimeInterval(-100)
        )

        let originalStartedAt = task.startedAt

        task.start()

        XCTAssertEqual(task.status, .downloading)
        XCTAssertEqual(task.startedAt, originalStartedAt) // Should preserve original start time
    }

    func test_downloadTask_start_invalidState() {
        var task = DownloadTask(
            url: URL(string: "https://example.com/file.zip")!,
            category: "Test",
            partNumber: 1,
            totalParts: 1,
            datasetName: "TEST",
            status: .completed
        )

        task.start()

        // Should not change from completed
        XCTAssertEqual(task.status, .completed)
    }

    func test_downloadTask_queue() {
        var task = DownloadTask(
            url: URL(string: "https://example.com/file.zip")!,
            category: "Test",
            partNumber: 1,
            totalParts: 1,
            datasetName: "TEST",
            status: .pending
        )

        task.queue()

        XCTAssertEqual(task.status, .queued)
    }

    func test_downloadTask_pause() {
        var task = DownloadTask(
            url: URL(string: "https://example.com/file.zip")!,
            category: "Test",
            partNumber: 1,
            totalParts: 1,
            datasetName: "TEST",
            status: .downloading
        )

        task.pause()

        XCTAssertEqual(task.status, .paused)
    }

    func test_downloadTask_startExtracting() {
        var task = DownloadTask(
            url: URL(string: "https://example.com/file.zip")!,
            category: "Test",
            partNumber: 1,
            totalParts: 1,
            datasetName: "TEST",
            status: .downloading,
            progress: 0.99,
            bytesDownloaded: 990_000_000,
            totalBytes: 1_000_000_000
        )

        task.startExtracting()

        XCTAssertEqual(task.status, .extracting)
        XCTAssertEqual(task.progress, 1.0)
        XCTAssertEqual(task.bytesDownloaded, task.totalBytes)
    }

    func test_downloadTask_complete() {
        var task = DownloadTask(
            url: URL(string: "https://example.com/file.zip")!,
            category: "Test",
            partNumber: 1,
            totalParts: 1,
            datasetName: "TEST",
            status: .extracting,
            resumeDataPath: "/tmp/resume.data"
        )

        XCTAssertNil(task.completedAt)

        task.complete()

        XCTAssertEqual(task.status, .completed)
        XCTAssertEqual(task.progress, 1.0)
        XCTAssertNotNil(task.completedAt)
        XCTAssertNil(task.errorMessage)
        XCTAssertNil(task.resumeDataPath)
    }

    func test_downloadTask_fail() {
        var task = DownloadTask(
            url: URL(string: "https://example.com/file.zip")!,
            category: "Test",
            partNumber: 1,
            totalParts: 1,
            datasetName: "TEST",
            status: .downloading,
            resumeDataPath: "/tmp/resume.data"
        )

        task.fail(with: "Network connection lost")

        XCTAssertEqual(task.status, .failed)
        XCTAssertEqual(task.errorMessage, "Network connection lost")
        XCTAssertNil(task.resumeDataPath)
    }

    func test_downloadTask_reset() {
        var task = DownloadTask(
            url: URL(string: "https://example.com/file.zip")!,
            category: "Test",
            partNumber: 1,
            totalParts: 1,
            datasetName: "TEST",
            status: .failed,
            progress: 0.45,
            bytesDownloaded: 450_000_000,
            totalBytes: 1_000_000_000,
            errorMessage: "Network error",
            resumeDataPath: "/tmp/resume.data",
            startedAt: Date().addingTimeInterval(-100),
            completedAt: Date()
        )

        task.reset()

        XCTAssertEqual(task.status, .pending)
        XCTAssertEqual(task.progress, 0.0)
        XCTAssertEqual(task.bytesDownloaded, 0)
        XCTAssertNil(task.errorMessage)
        XCTAssertNil(task.resumeDataPath)
        XCTAssertNil(task.startedAt)
        XCTAssertNil(task.completedAt)
    }

    // MARK: - Resume Data Tests

    func test_downloadTask_saveAndClearResumeData() {
        var task = DownloadTask(
            url: URL(string: "https://example.com/file.zip")!,
            category: "Test",
            partNumber: 1,
            totalParts: 1,
            datasetName: "TEST"
        )

        XCTAssertNil(task.resumeDataPath)
        XCTAssertFalse(task.hasResumeData)

        task.saveResumeData(at: "/tmp/resume.data")
        XCTAssertEqual(task.resumeDataPath, "/tmp/resume.data")
        XCTAssertTrue(task.hasResumeData)

        task.clearResumeData()
        XCTAssertNil(task.resumeDataPath)
        XCTAssertFalse(task.hasResumeData)
    }

    // MARK: - DownloadTaskGroup Tests

    func test_downloadTaskGroup_creation() {
        let tasks = [
            DownloadTask(
                url: URL(string: "https://example.com/Animals_1of2.zip")!,
                category: "Animals",
                partNumber: 1,
                totalParts: 2,
                datasetName: "INCLUDE"
            ),
            DownloadTask(
                url: URL(string: "https://example.com/Animals_2of2.zip")!,
                category: "Animals",
                partNumber: 2,
                totalParts: 2,
                datasetName: "INCLUDE"
            )
        ]

        let group = DownloadTaskGroup(category: "Animals", tasks: tasks)

        XCTAssertEqual(group.category, "Animals")
        XCTAssertEqual(group.id, "Animals")
        XCTAssertEqual(group.totalCount, 2)
    }

    func test_downloadTaskGroup_counts() {
        let tasks = [
            DownloadTask(
                url: URL(string: "https://example.com/file1.zip")!,
                category: "Test",
                partNumber: 1,
                totalParts: 5,
                datasetName: "TEST",
                status: .completed
            ),
            DownloadTask(
                url: URL(string: "https://example.com/file2.zip")!,
                category: "Test",
                partNumber: 2,
                totalParts: 5,
                datasetName: "TEST",
                status: .downloading
            ),
            DownloadTask(
                url: URL(string: "https://example.com/file3.zip")!,
                category: "Test",
                partNumber: 3,
                totalParts: 5,
                datasetName: "TEST",
                status: .failed
            ),
            DownloadTask(
                url: URL(string: "https://example.com/file4.zip")!,
                category: "Test",
                partNumber: 4,
                totalParts: 5,
                datasetName: "TEST",
                status: .pending
            ),
            DownloadTask(
                url: URL(string: "https://example.com/file5.zip")!,
                category: "Test",
                partNumber: 5,
                totalParts: 5,
                datasetName: "TEST",
                status: .paused
            )
        ]

        let group = DownloadTaskGroup(category: "Test", tasks: tasks)

        XCTAssertEqual(group.totalCount, 5)
        XCTAssertEqual(group.completedCount, 1)
        XCTAssertEqual(group.activeCount, 1)
        XCTAssertEqual(group.failedCount, 1)
        XCTAssertEqual(group.pendingCount, 1)
        XCTAssertEqual(group.pausedCount, 1)
    }

    func test_downloadTaskGroup_statusFlags() {
        // All completed
        var tasks = [
            DownloadTask(
                url: URL(string: "https://example.com/file1.zip")!,
                category: "Test",
                partNumber: 1,
                totalParts: 2,
                datasetName: "TEST",
                status: .completed
            ),
            DownloadTask(
                url: URL(string: "https://example.com/file2.zip")!,
                category: "Test",
                partNumber: 2,
                totalParts: 2,
                datasetName: "TEST",
                status: .completed
            )
        ]
        var group = DownloadTaskGroup(category: "Test", tasks: tasks)
        XCTAssertTrue(group.allCompleted)
        XCTAssertFalse(group.anyActive)
        XCTAssertFalse(group.anyFailed)

        // Has active
        tasks[1].status = .downloading
        group = DownloadTaskGroup(category: "Test", tasks: tasks)
        XCTAssertFalse(group.allCompleted)
        XCTAssertTrue(group.anyActive)

        // Has failed
        tasks[1].status = .failed
        group = DownloadTaskGroup(category: "Test", tasks: tasks)
        XCTAssertTrue(group.anyFailed)
    }

    func test_downloadTaskGroup_totalProgress() {
        let tasks = [
            DownloadTask(
                url: URL(string: "https://example.com/file1.zip")!,
                category: "Test",
                partNumber: 1,
                totalParts: 3,
                datasetName: "TEST",
                progress: 1.0
            ),
            DownloadTask(
                url: URL(string: "https://example.com/file2.zip")!,
                category: "Test",
                partNumber: 2,
                totalParts: 3,
                datasetName: "TEST",
                progress: 0.5
            ),
            DownloadTask(
                url: URL(string: "https://example.com/file3.zip")!,
                category: "Test",
                partNumber: 3,
                totalParts: 3,
                datasetName: "TEST",
                progress: 0.0
            )
        ]

        let group = DownloadTaskGroup(category: "Test", tasks: tasks)

        // Average: (1.0 + 0.5 + 0.0) / 3 = 0.5
        XCTAssertEqual(group.totalProgress, 0.5, accuracy: 0.01)
        XCTAssertEqual(group.progressPercentage, 50)
    }

    func test_downloadTaskGroup_byteTotals() {
        let tasks = [
            DownloadTask(
                url: URL(string: "https://example.com/file1.zip")!,
                category: "Test",
                partNumber: 1,
                totalParts: 2,
                datasetName: "TEST",
                bytesDownloaded: 500_000_000,
                totalBytes: 1_000_000_000
            ),
            DownloadTask(
                url: URL(string: "https://example.com/file2.zip")!,
                category: "Test",
                partNumber: 2,
                totalParts: 2,
                datasetName: "TEST",
                bytesDownloaded: 300_000_000,
                totalBytes: 1_000_000_000
            )
        ]

        let group = DownloadTaskGroup(category: "Test", tasks: tasks)

        XCTAssertEqual(group.totalBytes, 2_000_000_000)
        XCTAssertEqual(group.downloadedBytes, 800_000_000)
    }

    func test_downloadTaskGroup_overallStatus() {
        var tasks = [
            DownloadTask(
                url: URL(string: "https://example.com/file1.zip")!,
                category: "Test",
                partNumber: 1,
                totalParts: 2,
                datasetName: "TEST",
                status: .completed
            ),
            DownloadTask(
                url: URL(string: "https://example.com/file2.zip")!,
                category: "Test",
                partNumber: 2,
                totalParts: 2,
                datasetName: "TEST",
                status: .completed
            )
        ]
        var group = DownloadTaskGroup(category: "Test", tasks: tasks)
        XCTAssertEqual(group.overallStatus, .completed)

        tasks[1].status = .downloading
        group = DownloadTaskGroup(category: "Test", tasks: tasks)
        XCTAssertEqual(group.overallStatus, .downloading)

        tasks[1].status = .failed
        group = DownloadTaskGroup(category: "Test", tasks: tasks)
        XCTAssertEqual(group.overallStatus, .failed)
    }

    func test_downloadTaskGroup_grouping() {
        let tasks = [
            DownloadTask(
                url: URL(string: "https://example.com/Animals_1of2.zip")!,
                category: "Animals",
                partNumber: 1,
                totalParts: 2,
                datasetName: "INCLUDE"
            ),
            DownloadTask(
                url: URL(string: "https://example.com/Animals_2of2.zip")!,
                category: "Animals",
                partNumber: 2,
                totalParts: 2,
                datasetName: "INCLUDE"
            ),
            DownloadTask(
                url: URL(string: "https://example.com/Seasons.zip")!,
                category: "Seasons",
                partNumber: 1,
                totalParts: 1,
                datasetName: "INCLUDE"
            )
        ]

        let groups = tasks.groupedByCategory()

        XCTAssertEqual(groups.count, 2)
        XCTAssertTrue(groups.contains { $0.category == "Animals" && $0.totalCount == 2 })
        XCTAssertTrue(groups.contains { $0.category == "Seasons" && $0.totalCount == 1 })
    }

    // MARK: - Additional Computed Properties Tests

    func test_downloadTask_progressText_zeroBytes() {
        let task = DownloadTask(
            url: URL(string: "https://example.com/file.zip")!,
            category: "Test",
            partNumber: 1,
            totalParts: 1,
            datasetName: "TEST",
            progress: 0.0,
            bytesDownloaded: 0,
            totalBytes: 0
        )

        // Should show "0%" when no bytes
        XCTAssertEqual(task.progressText, "0%")
    }

    func test_downloadTask_progressText_withDownloadedButNoTotal() {
        let task = DownloadTask(
            url: URL(string: "https://example.com/file.zip")!,
            category: "Test",
            partNumber: 1,
            totalParts: 1,
            datasetName: "TEST",
            progress: 0.0,
            bytesDownloaded: 100_000_000,
            totalBytes: 0
        )

        // Should show formatted bytes when downloaded but total unknown
        let progressText = task.progressText
        XCTAssertTrue(progressText.contains("MB") || progressText.contains("KB"))
    }

    func test_downloadTask_estimatedTimeRemaining_calculatesCorrectly() {
        let startedAt = Date().addingTimeInterval(-60) // Started 60 seconds ago
        var task = DownloadTask(
            url: URL(string: "https://example.com/file.zip")!,
            category: "Test",
            partNumber: 1,
            totalParts: 1,
            datasetName: "TEST",
            status: .downloading,
            progress: 0.5,
            bytesDownloaded: 500_000_000,
            totalBytes: 1_000_000_000,
            startedAt: startedAt
        )

        // Downloaded 500 MB in 60 seconds = ~8.3 MB/s
        // 500 MB remaining at 8.3 MB/s = ~60 seconds
        let timeRemaining = task.estimatedTimeRemaining
        XCTAssertNotNil(timeRemaining)
        if let time = timeRemaining {
            XCTAssertGreaterThan(time, 0)
            XCTAssertLessThan(time, 120) // Should be around 60 seconds
        }
    }

    func test_downloadTask_estimatedTimeRemaining_returnsNilWhenNotDownloading() {
        let task = DownloadTask(
            url: URL(string: "https://example.com/file.zip")!,
            category: "Test",
            partNumber: 1,
            totalParts: 1,
            datasetName: "TEST",
            status: .pending
        )

        XCTAssertNil(task.estimatedTimeRemaining)
    }

    func test_downloadTask_estimatedTimeRemainingText_formatsCorrectly() {
        let startedAt = Date().addingTimeInterval(-60)
        var task = DownloadTask(
            url: URL(string: "https://example.com/file.zip")!,
            category: "Test",
            partNumber: 1,
            totalParts: 1,
            datasetName: "TEST",
            status: .downloading,
            progress: 0.5,
            bytesDownloaded: 500_000_000,
            totalBytes: 1_000_000_000,
            startedAt: startedAt
        )

        let timeText = task.estimatedTimeRemainingText
        XCTAssertNotNil(timeText)
        if let text = timeText {
            // Should contain either "m" for minutes or "s" for seconds
            XCTAssertTrue(text.contains("m") || text.contains("s"))
        }
    }

    // MARK: - Default Values Tests

    func test_downloadTask_defaultValuesAreSensible() {
        let task = DownloadTask(
            url: URL(string: "https://example.com/file.zip")!,
            category: "Test",
            partNumber: 1,
            totalParts: 1,
            datasetName: "TEST"
        )

        XCTAssertEqual(task.status, .pending)
        XCTAssertEqual(task.progress, 0.0)
        XCTAssertEqual(task.bytesDownloaded, 0)
        XCTAssertEqual(task.totalBytes, 0)
        XCTAssertNil(task.errorMessage)
        XCTAssertNil(task.resumeDataPath)
        XCTAssertNil(task.startedAt)
        XCTAssertNil(task.completedAt)
    }

    func test_downloadTask_creationFromManifestEntry_copiesAllProperties() {
        let entry = ManifestEntry(
            category: "Greetings",
            partNumber: 2,
            totalParts: 3,
            filename: "Greetings_2of3.zip",
            url: URL(string: "https://example.com/Greetings_2of3.zip")!,
            estimatedSize: 2_500_000_000
        )

        let task = DownloadTask(from: entry, datasetName: "INCLUDE")

        XCTAssertEqual(task.url, entry.url)
        XCTAssertEqual(task.category, entry.category)
        XCTAssertEqual(task.partNumber, entry.partNumber)
        XCTAssertEqual(task.totalParts, entry.totalParts)
        XCTAssertEqual(task.datasetName, "INCLUDE")
        XCTAssertEqual(task.totalBytes, entry.estimatedSize)
    }

    // MARK: - Progress Edge Cases Tests

    func test_downloadTask_updateProgress_handlesNegativeBytes() {
        var task = DownloadTask(
            url: URL(string: "https://example.com/file.zip")!,
            category: "Test",
            partNumber: 1,
            totalParts: 1,
            datasetName: "TEST",
            totalBytes: 1_000_000_000
        )

        // Negative bytes should be handled gracefully
        task.updateProgress(bytesDownloaded: -100, totalBytes: 1_000_000_000)

        // Progress should be clamped to 0
        XCTAssertEqual(task.progress, 0.0)
    }

    func test_downloadTask_updateProgress_updatesTotalBytesWhenHigher() {
        var task = DownloadTask(
            url: URL(string: "https://example.com/file.zip")!,
            category: "Test",
            partNumber: 1,
            totalParts: 1,
            datasetName: "TEST",
            totalBytes: 1_000_000_000
        )

        // Update with higher total
        task.updateProgress(bytesDownloaded: 500_000_000, totalBytes: 2_000_000_000)

        XCTAssertEqual(task.totalBytes, 2_000_000_000)
        XCTAssertEqual(task.progress, 0.25, accuracy: 0.01)
    }

    // MARK: - Codable Tests

    func test_downloadTask_codable() throws {
        let original = DownloadTask(
            url: URL(string: "https://example.com/file.zip")!,
            category: "Test",
            partNumber: 1,
            totalParts: 1,
            datasetName: "TEST",
            status: .downloading,
            progress: 0.45,
            bytesDownloaded: 450_000_000,
            totalBytes: 1_000_000_000
        )

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(DownloadTask.self, from: encoded)

        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.url, original.url)
        XCTAssertEqual(decoded.category, original.category)
        XCTAssertEqual(decoded.status, original.status)
        XCTAssertEqual(decoded.progress, original.progress)
        XCTAssertEqual(decoded.bytesDownloaded, original.bytesDownloaded)
    }

    func test_downloadTask_codable_preservesAllProperties() throws {
        let createdAt = Date()
        let startedAt = Date().addingTimeInterval(-60)
        let completedAt = Date()

        let original = DownloadTask(
            id: UUID(),
            url: URL(string: "https://example.com/file.zip")!,
            category: "Test",
            partNumber: 2,
            totalParts: 5,
            datasetName: "TEST",
            status: .failed,
            progress: 0.67,
            bytesDownloaded: 670_000_000,
            totalBytes: 1_000_000_000,
            errorMessage: "Network error",
            resumeDataPath: "/tmp/resume.data",
            createdAt: createdAt,
            startedAt: startedAt,
            completedAt: completedAt
        )

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(DownloadTask.self, from: encoded)

        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.url, original.url)
        XCTAssertEqual(decoded.category, original.category)
        XCTAssertEqual(decoded.partNumber, original.partNumber)
        XCTAssertEqual(decoded.totalParts, original.totalParts)
        XCTAssertEqual(decoded.datasetName, original.datasetName)
        XCTAssertEqual(decoded.status, original.status)
        XCTAssertEqual(decoded.progress, original.progress)
        XCTAssertEqual(decoded.bytesDownloaded, original.bytesDownloaded)
        XCTAssertEqual(decoded.totalBytes, original.totalBytes)
        XCTAssertEqual(decoded.errorMessage, original.errorMessage)
        XCTAssertEqual(decoded.resumeDataPath, original.resumeDataPath)
    }

    func test_downloadTask_jsonRepresentation_isReasonable() throws {
        let task = DownloadTask(
            url: URL(string: "https://example.com/file.zip")!,
            category: "Test",
            partNumber: 1,
            totalParts: 1,
            datasetName: "TEST",
            status: .downloading
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let jsonData = try encoder.encode(task)
        let jsonString = String(data: jsonData, encoding: .utf8)!

        // Verify JSON contains expected fields
        XCTAssertTrue(jsonString.contains("url"))
        XCTAssertTrue(jsonString.contains("category"))
        XCTAssertTrue(jsonString.contains("status"))
        XCTAssertTrue(jsonString.contains("progress"))
    }

    // MARK: - Hashable/Equatable Tests

    func test_downloadTask_hashable_sameIDHasSameHash() {
        let id = UUID()
        let task1 = DownloadTask(
            id: id,
            url: URL(string: "https://example.com/file.zip")!,
            category: "Test",
            partNumber: 1,
            totalParts: 1,
            datasetName: "TEST"
        )
        let task2 = DownloadTask(
            id: id,
            url: URL(string: "https://example.com/different.zip")!,
            category: "Different",
            partNumber: 2,
            totalParts: 3,
            datasetName: "OTHER"
        )

        XCTAssertEqual(task1.hashValue, task2.hashValue)
    }

    func test_downloadTask_equatable_sameIDIsEqual() {
        let id = UUID()
        let task1 = DownloadTask(
            id: id,
            url: URL(string: "https://example.com/file.zip")!,
            category: "Test",
            partNumber: 1,
            totalParts: 1,
            datasetName: "TEST"
        )
        let task2 = DownloadTask(
            id: id,
            url: URL(string: "https://example.com/file.zip")!,
            category: "Test",
            partNumber: 1,
            totalParts: 1,
            datasetName: "TEST"
        )

        XCTAssertEqual(task1, task2)
    }

    func test_downloadTask_equatable_differentIDIsNotEqual() {
        let task1 = DownloadTask(
            url: URL(string: "https://example.com/file.zip")!,
            category: "Test",
            partNumber: 1,
            totalParts: 1,
            datasetName: "TEST"
        )
        let task2 = DownloadTask(
            url: URL(string: "https://example.com/file.zip")!,
            category: "Test",
            partNumber: 1,
            totalParts: 1,
            datasetName: "TEST"
        )

        XCTAssertNotEqual(task1, task2)
    }

    func test_downloadTask_canBeUsedInSet() {
        let task1 = DownloadTask(
            url: URL(string: "https://example.com/file1.zip")!,
            category: "Test",
            partNumber: 1,
            totalParts: 2,
            datasetName: "TEST"
        )
        let task2 = DownloadTask(
            url: URL(string: "https://example.com/file2.zip")!,
            category: "Test",
            partNumber: 2,
            totalParts: 2,
            datasetName: "TEST"
        )

        let taskSet: Set<DownloadTask> = [task1, task2]

        XCTAssertEqual(taskSet.count, 2)
        XCTAssertTrue(taskSet.contains(task1))
        XCTAssertTrue(taskSet.contains(task2))
    }

    func test_downloadTask_canBeUsedAsDictionaryKey() {
        let task1 = DownloadTask(
            url: URL(string: "https://example.com/file1.zip")!,
            category: "Test",
            partNumber: 1,
            totalParts: 1,
            datasetName: "TEST"
        )
        let task2 = DownloadTask(
            url: URL(string: "https://example.com/file2.zip")!,
            category: "Test",
            partNumber: 2,
            totalParts: 2,
            datasetName: "TEST"
        )

        var taskDict: [DownloadTask: String] = [:]
        taskDict[task1] = "First"
        taskDict[task2] = "Second"

        XCTAssertEqual(taskDict[task1], "First")
        XCTAssertEqual(taskDict[task2], "Second")
    }
}
