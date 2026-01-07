import XCTest
@testable import SignLanguageTranslate

@MainActor
final class DownloadManagerTests: XCTestCase {
    var manager: DownloadManager!
    var queue: DownloadQueueActor!

    override func setUp() async throws {
        try await super.setUp()
        queue = DownloadQueueActor()
        manager = DownloadManager(queue: queue)
    }

    override func tearDown() async throws {
        manager.stopAutoRefresh()
        manager = nil
        queue = nil
        try await super.tearDown()
    }

    // MARK: - Initialization Tests

    func test_init_createsWithEmptyQueue() async throws {
        let freshManager = DownloadManager()
        await freshManager.refresh()

        XCTAssertEqual(freshManager.totalCount, 0)
        XCTAssertEqual(freshManager.tasks.count, 0)
        XCTAssertFalse(freshManager.isDownloading)
    }

    func test_initWithQueue_usesInjectedQueue() async throws {
        let task = DownloadTask(
            url: URL(string: "https://example.com/file.zip")!,
            category: "Test",
            partNumber: 1,
            totalParts: 1,
            datasetName: "TEST"
        )

        await queue.enqueue(task)
        await manager.refresh()

        XCTAssertEqual(manager.totalCount, 1)
        XCTAssertEqual(manager.tasks.count, 1)
    }

    // MARK: - Manifest Loading Tests

    func test_loadINCLUDEManifest_creates46Tasks() async throws {
        await manager.loadINCLUDEManifest()

        XCTAssertEqual(manager.totalCount, 46)
        XCTAssertEqual(manager.tasks.count, 46)
    }

    func test_loadINCLUDEManifest_allTasksStartPending() async throws {
        await manager.loadINCLUDEManifest()

        let allPending = manager.tasks.allSatisfy { $0.status == .pending }
        XCTAssertTrue(allPending)
        XCTAssertEqual(manager.pendingCount, 46)
    }

    func test_loadINCLUDEManifest_tasksAreOrdered() async throws {
        await manager.loadINCLUDEManifest()

        // First task should be from Adjectives (first category alphabetically with multiple parts)
        let firstTask = manager.tasks.first
        XCTAssertEqual(firstTask?.category, "Adjectives")
        XCTAssertEqual(firstTask?.partNumber, 1)
    }

    func test_loadManifest_replacesExistingTasks() async throws {
        // Load first time
        await manager.loadINCLUDEManifest()
        XCTAssertEqual(manager.totalCount, 46)

        // Load again - should replace
        let customEntries = [
            ManifestEntry(
                category: "Test",
                partNumber: 1,
                totalParts: 1,
                filename: "test.zip",
                url: URL(string: "https://example.com/test.zip")!,
                estimatedSize: 1000
            )
        ]

        await manager.loadManifest(entries: customEntries, datasetName: "CUSTOM")
        XCTAssertEqual(manager.totalCount, 1)
        XCTAssertEqual(manager.tasks.first?.datasetName, "CUSTOM")
    }

    // MARK: - Published Properties Tests

    func test_tasks_updatesAfterRefresh() async throws {
        let task = DownloadTask(
            url: URL(string: "https://example.com/file.zip")!,
            category: "Test",
            partNumber: 1,
            totalParts: 1,
            datasetName: "TEST"
        )

        await queue.enqueue(task)
        XCTAssertEqual(manager.tasks.count, 0) // Not refreshed yet

        await manager.refresh()
        XCTAssertEqual(manager.tasks.count, 1)
    }

    func test_isDownloading_reflectsActiveTasks() async throws {
        let task = DownloadTask(
            url: URL(string: "https://example.com/file.zip")!,
            category: "Test",
            partNumber: 1,
            totalParts: 1,
            datasetName: "TEST",
            status: .pending
        )

        await queue.enqueue(task)
        await manager.refresh()
        XCTAssertFalse(manager.isDownloading)

        await queue.markDownloading(task.id)
        await manager.refresh()
        XCTAssertTrue(manager.isDownloading)

        await queue.markCompleted(task.id)
        await manager.refresh()
        XCTAssertFalse(manager.isDownloading)
    }

    func test_counts_areAccurate() async throws {
        let tasks = [
            DownloadTask(
                url: URL(string: "https://example.com/file1.zip")!,
                category: "Test",
                partNumber: 1,
                totalParts: 3,
                datasetName: "TEST",
                status: .pending
            ),
            DownloadTask(
                url: URL(string: "https://example.com/file2.zip")!,
                category: "Test",
                partNumber: 2,
                totalParts: 3,
                datasetName: "TEST",
                status: .downloading
            ),
            DownloadTask(
                url: URL(string: "https://example.com/file3.zip")!,
                category: "Test",
                partNumber: 3,
                totalParts: 3,
                datasetName: "TEST",
                status: .completed
            )
        ]

        await queue.enqueueAll(tasks)
        await manager.refresh()

        XCTAssertEqual(manager.totalCount, 3)
        XCTAssertEqual(manager.pendingCount, 1)
        XCTAssertEqual(manager.activeCount, 1)
        XCTAssertEqual(manager.completedCount, 1)
        XCTAssertEqual(manager.failedCount, 0)
    }

    func test_progressCalculations_areCorrect() async throws {
        let task = DownloadTask(
            url: URL(string: "https://example.com/file.zip")!,
            category: "Test",
            partNumber: 1,
            totalParts: 1,
            datasetName: "TEST",
            status: .downloading,
            progress: 0.5,
            bytesDownloaded: 500_000_000,
            totalBytes: 1_000_000_000
        )

        await queue.enqueue(task)
        await manager.refresh()

        XCTAssertEqual(manager.overallProgress, 0.5, accuracy: 0.01)
        XCTAssertEqual(manager.downloadedBytes, 500_000_000)
        XCTAssertEqual(manager.totalBytes, 1_000_000_000)
    }

    func test_progressText_formatsCorrectly() async throws {
        let task = DownloadTask(
            url: URL(string: "https://example.com/file.zip")!,
            category: "Test",
            partNumber: 1,
            totalParts: 1,
            datasetName: "TEST",
            bytesDownloaded: 1_500_000_000, // 1.5 GB
            totalBytes: 5_000_000_000 // 5 GB
        )

        await queue.enqueue(task)
        await manager.refresh()

        // Check that it contains GB units
        XCTAssertTrue(manager.progressText.contains("GB"))
    }

    func test_statusText_describesCurrentState() async throws {
        // Empty queue
        await manager.refresh()
        XCTAssertEqual(manager.statusText, "No downloads")

        // With pending tasks
        let task = DownloadTask(
            url: URL(string: "https://example.com/file.zip")!,
            category: "Test",
            partNumber: 1,
            totalParts: 1,
            datasetName: "TEST",
            status: .pending
        )
        await queue.enqueue(task)
        await manager.refresh()
        XCTAssertTrue(manager.statusText.contains("Ready to download"))

        // While downloading
        await queue.markDownloading(task.id)
        await manager.refresh()
        XCTAssertTrue(manager.statusText.contains("Downloading"))

        // Completed
        await queue.markCompleted(task.id)
        await manager.refresh()
        XCTAssertTrue(manager.statusText.contains("complete"))
    }

    // MARK: - Download Control Tests

    func test_startDownloads_marksTasksAsDownloading() async throws {
        let tasks = (1...5).map { i in
            DownloadTask(
                url: URL(string: "https://example.com/file\(i).zip")!,
                category: "Test",
                partNumber: i,
                totalParts: 5,
                datasetName: "TEST",
                status: .pending
            )
        }

        await queue.enqueueAll(tasks)
        try await manager.startDownloads()

        // Should start up to maxConcurrent (default 3)
        let maxConcurrent = await queue.getMaxConcurrentDownloads()
        XCTAssertEqual(manager.activeCount, maxConcurrent)
    }

    func test_startDownloads_throwsWhenAlreadyDownloading() async throws {
        let task = DownloadTask(
            url: URL(string: "https://example.com/file.zip")!,
            category: "Test",
            partNumber: 1,
            totalParts: 1,
            datasetName: "TEST",
            status: .downloading
        )

        await queue.enqueue(task)
        await manager.refresh()

        do {
            try await manager.startDownloads()
            XCTFail("Expected error to be thrown")
        } catch DownloadManagerError.alreadyDownloading {
            // Expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func test_startDownloads_throwsWhenQueueEmpty() async throws {
        do {
            try await manager.startDownloads()
            XCTFail("Expected error to be thrown")
        } catch DownloadManagerError.queueEmpty {
            // Expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func test_pauseAll_pausesActiveTasks() async throws {
        let task = DownloadTask(
            url: URL(string: "https://example.com/file.zip")!,
            category: "Test",
            partNumber: 1,
            totalParts: 1,
            datasetName: "TEST",
            status: .downloading
        )

        await queue.enqueue(task)
        await manager.refresh()
        XCTAssertFalse(manager.isPaused)

        await manager.pauseAll()
        XCTAssertTrue(manager.isPaused)

        let pausedTask = await queue.getTask(task.id)
        XCTAssertEqual(pausedTask?.status, .paused)
    }

    func test_resumeAll_clearsGlobalPause() async throws {
        await queue.pauseAll()
        await manager.refresh()
        XCTAssertTrue(manager.isPaused)

        await manager.resumeAll()
        XCTAssertFalse(manager.isPaused)
    }

    func test_cancelAll_clearsQueue() async throws {
        let task = DownloadTask(
            url: URL(string: "https://example.com/file.zip")!,
            category: "Test",
            partNumber: 1,
            totalParts: 1,
            datasetName: "TEST"
        )

        await queue.enqueue(task)
        await manager.refresh()
        XCTAssertEqual(manager.totalCount, 1)

        await manager.cancelAll()
        XCTAssertEqual(manager.totalCount, 0)
    }

    func test_retryFailed_resetsFailedTasks() async throws {
        let task = DownloadTask(
            url: URL(string: "https://example.com/file.zip")!,
            category: "Test",
            partNumber: 1,
            totalParts: 1,
            datasetName: "TEST",
            status: .failed
        )

        await queue.enqueue(task)
        await manager.refresh()
        XCTAssertEqual(manager.failedCount, 1)

        await manager.retryFailed()
        XCTAssertEqual(manager.failedCount, 0)
        XCTAssertEqual(manager.pendingCount, 1)
    }

    // MARK: - Individual Task Control Tests

    func test_pauseTask_pausesSpecificTask() async throws {
        let task = DownloadTask(
            url: URL(string: "https://example.com/file.zip")!,
            category: "Test",
            partNumber: 1,
            totalParts: 1,
            datasetName: "TEST",
            status: .downloading
        )

        await queue.enqueue(task)
        try await manager.pauseTask(task.id)

        let pausedTask = await queue.getTask(task.id)
        XCTAssertEqual(pausedTask?.status, .paused)
    }

    func test_resumeTask_resumesSpecificTask() async throws {
        let task = DownloadTask(
            url: URL(string: "https://example.com/file.zip")!,
            category: "Test",
            partNumber: 1,
            totalParts: 1,
            datasetName: "TEST",
            status: .paused
        )

        await queue.enqueue(task)
        try await manager.resumeTask(task.id)

        let resumedTask = await queue.getTask(task.id)
        XCTAssertEqual(resumedTask?.status, .pending)
    }

    func test_prioritizeTask_movesToFront() async throws {
        let tasks = (1...3).map { i in
            DownloadTask(
                url: URL(string: "https://example.com/file\(i).zip")!,
                category: "Test",
                partNumber: i,
                totalParts: 3,
                datasetName: "TEST"
            )
        }

        await queue.enqueueAll(tasks)
        let thirdTask = tasks[2]

        try await manager.prioritizeTask(thirdTask.id)

        let firstInQueue = manager.tasks.first
        XCTAssertEqual(firstInQueue?.id, thirdTask.id)
    }

    func test_removeTask_removesFromQueue() async throws {
        let task = DownloadTask(
            url: URL(string: "https://example.com/file.zip")!,
            category: "Test",
            partNumber: 1,
            totalParts: 1,
            datasetName: "TEST"
        )

        await queue.enqueue(task)
        await manager.refresh()
        XCTAssertEqual(manager.totalCount, 1)

        try await manager.removeTask(task.id)
        XCTAssertEqual(manager.totalCount, 0)
    }

    func test_taskControl_throwsOnInvalidID() async throws {
        let invalidID = UUID()

        do {
            try await manager.pauseTask(invalidID)
            XCTFail("Expected error")
        } catch DownloadManagerError.taskNotFound {
            // Expected
        }

        do {
            try await manager.resumeTask(invalidID)
            XCTFail("Expected error")
        } catch DownloadManagerError.taskNotFound {
            // Expected
        }

        do {
            try await manager.retryTask(invalidID)
            XCTFail("Expected error")
        } catch DownloadManagerError.taskNotFound {
            // Expected
        }

        do {
            try await manager.prioritizeTask(invalidID)
            XCTFail("Expected error")
        } catch DownloadManagerError.taskNotFound {
            // Expected
        }

        do {
            try await manager.removeTask(invalidID)
            XCTFail("Expected error")
        } catch DownloadManagerError.taskNotFound {
            // Expected
        }
    }

    // MARK: - Simulation Tests

    func test_simulateDownloadProgress_increasesProgress() async throws {
        let task = DownloadTask(
            url: URL(string: "https://example.com/file.zip")!,
            category: "Test",
            partNumber: 1,
            totalParts: 1,
            datasetName: "TEST",
            status: .downloading,
            progress: 0.1,
            totalBytes: 1_000_000_000
        )

        await queue.enqueue(task)
        await manager.refresh()

        let initialProgress = manager.overallProgress
        await manager.simulateDownloadProgress()

        XCTAssertGreaterThan(manager.overallProgress, initialProgress)
    }

    func test_simulateCompleteTask_marksComplete() async throws {
        let task = DownloadTask(
            url: URL(string: "https://example.com/file.zip")!,
            category: "Test",
            partNumber: 1,
            totalParts: 1,
            datasetName: "TEST",
            status: .downloading
        )

        await queue.enqueue(task)
        try await manager.simulateCompleteTask(task.id)

        let completedTask = await queue.getTask(task.id)
        XCTAssertEqual(completedTask?.status, .completed)
        XCTAssertEqual(manager.completedCount, 1)
    }

    func test_simulateFailTask_marksFailedWithError() async throws {
        let task = DownloadTask(
            url: URL(string: "https://example.com/file.zip")!,
            category: "Test",
            partNumber: 1,
            totalParts: 1,
            datasetName: "TEST",
            status: .downloading
        )

        await queue.enqueue(task)
        try await manager.simulateFailTask(task.id, error: "Network timeout")

        let failedTask = await queue.getTask(task.id)
        XCTAssertEqual(failedTask?.status, .failed)
        XCTAssertEqual(failedTask?.errorMessage, "Network timeout")
        XCTAssertEqual(manager.failedCount, 1)
    }

    // MARK: - Persistence Tests

    func test_saveState_createsFile() async throws {
        let task = DownloadTask(
            url: URL(string: "https://example.com/file.zip")!,
            category: "Test",
            partNumber: 1,
            totalParts: 1,
            datasetName: "TEST"
        )

        await queue.enqueue(task)
        try await manager.saveState()

        XCTAssertTrue(FileManager.default.fileExists(atPath: manager.stateFileURL.path))

        // Cleanup
        try? FileManager.default.removeItem(at: manager.stateFileURL)
    }

    func test_restoreState_loadsFile() async throws {
        let task = DownloadTask(
            url: URL(string: "https://example.com/file.zip")!,
            category: "Test",
            partNumber: 1,
            totalParts: 1,
            datasetName: "TEST"
        )

        await queue.enqueue(task)
        try await manager.saveState()

        // Create new manager and restore
        let newQueue = DownloadQueueActor()
        let newManager = DownloadManager(queue: newQueue)
        try await newManager.restoreState()

        XCTAssertEqual(newManager.totalCount, 1)
        XCTAssertEqual(newManager.tasks.first?.datasetName, "TEST")

        // Cleanup
        try? FileManager.default.removeItem(at: manager.stateFileURL)
    }

    func test_roundTrip_preservesState() async throws {
        let task = DownloadTask(
            url: URL(string: "https://example.com/file.zip")!,
            category: "Test",
            partNumber: 1,
            totalParts: 1,
            datasetName: "TEST",
            status: .downloading,
            progress: 0.5,
            bytesDownloaded: 500_000_000,
            totalBytes: 1_000_000_000
        )

        await queue.enqueue(task)
        try await manager.saveState()

        let newQueue = DownloadQueueActor()
        let newManager = DownloadManager(queue: newQueue)
        try await newManager.restoreState()

        let restored = newManager.tasks.first
        XCTAssertEqual(restored?.id, task.id)
        XCTAssertEqual(restored?.status, task.status)
        XCTAssertEqual(restored?.progress ?? 0, task.progress ?? 0, accuracy: 0.01)

        // Cleanup
        try? FileManager.default.removeItem(at: manager.stateFileURL)
    }

    func test_restoreWithNoFile_doesNotCrash() async throws {
        // Ensure no file exists
        try? FileManager.default.removeItem(at: manager.stateFileURL)

        // Should not throw or crash
        try await manager.restoreState()
        XCTAssertEqual(manager.totalCount, 0)
    }

    // MARK: - Grouped Tasks Tests

    func test_tasksGroupedByCategory_groupsCorrectly() async throws {
        let tasks = [
            DownloadTask(
                url: URL(string: "https://example.com/animals1.zip")!,
                category: "Animals",
                partNumber: 1,
                totalParts: 2,
                datasetName: "TEST"
            ),
            DownloadTask(
                url: URL(string: "https://example.com/animals2.zip")!,
                category: "Animals",
                partNumber: 2,
                totalParts: 2,
                datasetName: "TEST"
            ),
            DownloadTask(
                url: URL(string: "https://example.com/colors.zip")!,
                category: "Colors",
                partNumber: 1,
                totalParts: 1,
                datasetName: "TEST"
            )
        ]

        await queue.enqueueAll(tasks)
        await manager.refresh()

        let groups = manager.tasksGroupedByCategory
        XCTAssertEqual(groups.count, 2)

        let animalsGroup = groups.first { $0.category == "Animals" }
        XCTAssertEqual(animalsGroup?.tasks.count, 2)

        let colorsGroup = groups.first { $0.category == "Colors" }
        XCTAssertEqual(colorsGroup?.tasks.count, 1)
    }

    func test_tasksGroupedByCategory_sortedAlphabetically() async throws {
        let tasks = [
            DownloadTask(
                url: URL(string: "https://example.com/zebra.zip")!,
                category: "Zebra",
                partNumber: 1,
                totalParts: 1,
                datasetName: "TEST"
            ),
            DownloadTask(
                url: URL(string: "https://example.com/apple.zip")!,
                category: "Apple",
                partNumber: 1,
                totalParts: 1,
                datasetName: "TEST"
            )
        ]

        await queue.enqueueAll(tasks)
        await manager.refresh()

        let groups = manager.tasksGroupedByCategory
        XCTAssertEqual(groups.first?.category, "Apple")
        XCTAssertEqual(groups.last?.category, "Zebra")
    }

    // MARK: - Computed Properties Tests

    func test_hasFailedTasks_returnsCorrectValue() async throws {
        await manager.refresh()
        XCTAssertFalse(manager.hasFailedTasks)

        let task = DownloadTask(
            url: URL(string: "https://example.com/file.zip")!,
            category: "Test",
            partNumber: 1,
            totalParts: 1,
            datasetName: "TEST",
            status: .failed
        )

        await queue.enqueue(task)
        await manager.refresh()
        XCTAssertTrue(manager.hasFailedTasks)
    }

    func test_isComplete_returnsCorrectValue() async throws {
        await manager.refresh()
        XCTAssertFalse(manager.isComplete) // Empty queue

        let task = DownloadTask(
            url: URL(string: "https://example.com/file.zip")!,
            category: "Test",
            partNumber: 1,
            totalParts: 1,
            datasetName: "TEST",
            status: .pending
        )

        await queue.enqueue(task)
        await manager.refresh()
        XCTAssertFalse(manager.isComplete) // Not complete

        await queue.markCompleted(task.id)
        await manager.refresh()
        XCTAssertTrue(manager.isComplete) // All complete
    }
}
