import XCTest
@testable import SignLanguageTranslate

/// Unit tests for DownloadQueueActor
final class DownloadQueueActorTests: XCTestCase {

    // MARK: - Queue Management Tests

    func test_enqueue_addsSingleTask() async throws {
        let queue = DownloadQueueActor()
        let task = DownloadTask(
            url: URL(string: "https://example.com/file.zip")!,
            category: "Test",
            partNumber: 1,
            totalParts: 1,
            datasetName: "TEST"
        )

        await queue.enqueue(task)

        let allTasks = await queue.getAllTasks()
        XCTAssertEqual(allTasks.count, 1)
        XCTAssertEqual(allTasks.first?.id, task.id)
    }

    func test_enqueue_preventsDuplicates() async throws {
        let queue = DownloadQueueActor()
        let task = DownloadTask(
            url: URL(string: "https://example.com/file.zip")!,
            category: "Test",
            partNumber: 1,
            totalParts: 1,
            datasetName: "TEST"
        )

        await queue.enqueue(task)
        await queue.enqueue(task) // Try to add again

        let allTasks = await queue.getAllTasks()
        XCTAssertEqual(allTasks.count, 1)
    }

    func test_enqueueAll_addsMultipleTasks() async throws {
        let queue = DownloadQueueActor()
        let tasks = [
            DownloadTask(
                url: URL(string: "https://example.com/file1.zip")!,
                category: "Test",
                partNumber: 1,
                totalParts: 3,
                datasetName: "TEST"
            ),
            DownloadTask(
                url: URL(string: "https://example.com/file2.zip")!,
                category: "Test",
                partNumber: 2,
                totalParts: 3,
                datasetName: "TEST"
            ),
            DownloadTask(
                url: URL(string: "https://example.com/file3.zip")!,
                category: "Test",
                partNumber: 3,
                totalParts: 3,
                datasetName: "TEST"
            )
        ]

        await queue.enqueueAll(tasks)

        let allTasks = await queue.getAllTasks()
        XCTAssertEqual(allTasks.count, 3)
    }

    func test_remove_removesTask() async throws {
        let queue = DownloadQueueActor()
        let task = DownloadTask(
            url: URL(string: "https://example.com/file.zip")!,
            category: "Test",
            partNumber: 1,
            totalParts: 1,
            datasetName: "TEST"
        )

        await queue.enqueue(task)
        XCTAssertEqual(await queue.getTotalCount(), 1)

        await queue.remove(task.id)
        XCTAssertEqual(await queue.getTotalCount(), 0)
    }

    func test_clear_removesAllTasks() async throws {
        let queue = DownloadQueueActor()
        let tasks = [
            DownloadTask(
                url: URL(string: "https://example.com/file1.zip")!,
                category: "Test",
                partNumber: 1,
                totalParts: 2,
                datasetName: "TEST"
            ),
            DownloadTask(
                url: URL(string: "https://example.com/file2.zip")!,
                category: "Test",
                partNumber: 2,
                totalParts: 2,
                datasetName: "TEST"
            )
        ]

        await queue.enqueueAll(tasks)
        XCTAssertEqual(await queue.getTotalCount(), 2)

        await queue.clear()
        XCTAssertEqual(await queue.getTotalCount(), 0)
    }

    func test_reorder_movesTaskToNewIndex() async throws {
        let queue = DownloadQueueActor()
        let task1 = DownloadTask(
            url: URL(string: "https://example.com/file1.zip")!,
            category: "Test",
            partNumber: 1,
            totalParts: 3,
            datasetName: "TEST"
        )
        let task2 = DownloadTask(
            url: URL(string: "https://example.com/file2.zip")!,
            category: "Test",
            partNumber: 2,
            totalParts: 3,
            datasetName: "TEST"
        )
        let task3 = DownloadTask(
            url: URL(string: "https://example.com/file3.zip")!,
            category: "Test",
            partNumber: 3,
            totalParts: 3,
            datasetName: "TEST"
        )

        await queue.enqueueAll([task1, task2, task3])

        // Move task3 to position 0
        await queue.reorder(taskID: task3.id, toIndex: 0)

        // Get next pending should now be task3
        let next = await queue.getNextPendingTask()
        XCTAssertEqual(next?.id, task3.id)
    }

    func test_prioritize_movesTaskToFront() async throws {
        let queue = DownloadQueueActor()
        let task1 = DownloadTask(
            url: URL(string: "https://example.com/file1.zip")!,
            category: "Test",
            partNumber: 1,
            totalParts: 3,
            datasetName: "TEST"
        )
        let task2 = DownloadTask(
            url: URL(string: "https://example.com/file2.zip")!,
            category: "Test",
            partNumber: 2,
            totalParts: 3,
            datasetName: "TEST"
        )
        let task3 = DownloadTask(
            url: URL(string: "https://example.com/file3.zip")!,
            category: "Test",
            partNumber: 3,
            totalParts: 3,
            datasetName: "TEST"
        )

        await queue.enqueueAll([task1, task2, task3])

        // Prioritize task3
        await queue.prioritize(task3.id)

        // Next pending should now be task3
        let next = await queue.getNextPendingTask()
        XCTAssertEqual(next?.id, task3.id)
    }

    // MARK: - Task State Tests

    func test_getTask_returnsCorrectTask() async throws {
        let queue = DownloadQueueActor()
        let task = DownloadTask(
            url: URL(string: "https://example.com/file.zip")!,
            category: "Test",
            partNumber: 1,
            totalParts: 1,
            datasetName: "TEST"
        )

        await queue.enqueue(task)

        let retrieved = await queue.getTask(task.id)
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.id, task.id)
    }

    func test_getTask_returnsNilForNonExistent() async throws {
        let queue = DownloadQueueActor()

        let retrieved = await queue.getTask(UUID())
        XCTAssertNil(retrieved)
    }

    func test_updateTask_modifiesTask() async throws {
        let queue = DownloadQueueActor()
        var task = DownloadTask(
            url: URL(string: "https://example.com/file.zip")!,
            category: "Test",
            partNumber: 1,
            totalParts: 1,
            datasetName: "TEST",
            totalBytes: 1_000_000_000
        )

        await queue.enqueue(task)

        await queue.updateTask(task.id) { task in
            task.updateProgress(bytesDownloaded: 500_000_000, totalBytes: 1_000_000_000)
        }

        let updated = await queue.getTask(task.id)
        XCTAssertEqual(updated?.bytesDownloaded, 500_000_000)
        XCTAssertEqual(updated?.progress, 0.5, accuracy: 0.01)
    }

    // MARK: - Filtering Tests

    func test_getTasksWithStatus_filtersCorrectly() async throws {
        let queue = DownloadQueueActor()
        let task1 = DownloadTask(
            url: URL(string: "https://example.com/file1.zip")!,
            category: "Test",
            partNumber: 1,
            totalParts: 3,
            datasetName: "TEST",
            status: .pending
        )
        let task2 = DownloadTask(
            url: URL(string: "https://example.com/file2.zip")!,
            category: "Test",
            partNumber: 2,
            totalParts: 3,
            datasetName: "TEST",
            status: .downloading
        )
        let task3 = DownloadTask(
            url: URL(string: "https://example.com/file3.zip")!,
            category: "Test",
            partNumber: 3,
            totalParts: 3,
            datasetName: "TEST",
            status: .completed
        )

        await queue.enqueueAll([task1, task2, task3])

        let pending = await queue.getTasksWithStatus(.pending)
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending.first?.id, task1.id)

        let downloading = await queue.getTasksWithStatus(.downloading)
        XCTAssertEqual(downloading.count, 1)
        XCTAssertEqual(downloading.first?.id, task2.id)

        let completed = await queue.getTasksWithStatus(.completed)
        XCTAssertEqual(completed.count, 1)
        XCTAssertEqual(completed.first?.id, task3.id)
    }

    func test_getActiveTasks_returnsDownloadingAndExtracting() async throws {
        let queue = DownloadQueueActor()
        let task1 = DownloadTask(
            url: URL(string: "https://example.com/file1.zip")!,
            category: "Test",
            partNumber: 1,
            totalParts: 3,
            datasetName: "TEST",
            status: .downloading
        )
        let task2 = DownloadTask(
            url: URL(string: "https://example.com/file2.zip")!,
            category: "Test",
            partNumber: 2,
            totalParts: 3,
            datasetName: "TEST",
            status: .extracting
        )
        let task3 = DownloadTask(
            url: URL(string: "https://example.com/file3.zip")!,
            category: "Test",
            partNumber: 3,
            totalParts: 3,
            datasetName: "TEST",
            status: .pending
        )

        await queue.enqueueAll([task1, task2, task3])

        let active = await queue.getActiveTasks()
        XCTAssertEqual(active.count, 2)
        XCTAssertTrue(active.contains { $0.id == task1.id })
        XCTAssertTrue(active.contains { $0.id == task2.id })
    }

    func test_getTasksForCategory_filtersCorrectly() async throws {
        let queue = DownloadQueueActor()
        let task1 = DownloadTask(
            url: URL(string: "https://example.com/file1.zip")!,
            category: "Animals",
            partNumber: 1,
            totalParts: 2,
            datasetName: "INCLUDE"
        )
        let task2 = DownloadTask(
            url: URL(string: "https://example.com/file2.zip")!,
            category: "Animals",
            partNumber: 2,
            totalParts: 2,
            datasetName: "INCLUDE"
        )
        let task3 = DownloadTask(
            url: URL(string: "https://example.com/file3.zip")!,
            category: "Seasons",
            partNumber: 1,
            totalParts: 1,
            datasetName: "INCLUDE"
        )

        await queue.enqueueAll([task1, task2, task3])

        let animals = await queue.getTasksForCategory("Animals")
        XCTAssertEqual(animals.count, 2)

        let seasons = await queue.getTasksForCategory("Seasons")
        XCTAssertEqual(seasons.count, 1)
    }

    // MARK: - Progress Update Tests

    func test_updateProgress_updatesCorrectTask() async throws {
        let queue = DownloadQueueActor()
        let task = DownloadTask(
            url: URL(string: "https://example.com/file.zip")!,
            category: "Test",
            partNumber: 1,
            totalParts: 1,
            datasetName: "TEST",
            totalBytes: 1_000_000_000
        )

        await queue.enqueue(task)

        await queue.updateProgress(
            id: task.id,
            bytesDownloaded: 250_000_000,
            totalBytes: 1_000_000_000
        )

        let updated = await queue.getTask(task.id)
        XCTAssertEqual(updated?.bytesDownloaded, 250_000_000)
        XCTAssertEqual(updated?.progress, 0.25, accuracy: 0.01)
    }

    func test_markDownloading_changesStatusAndSetsStartedAt() async throws {
        let queue = DownloadQueueActor()
        let task = DownloadTask(
            url: URL(string: "https://example.com/file.zip")!,
            category: "Test",
            partNumber: 1,
            totalParts: 1,
            datasetName: "TEST",
            status: .pending
        )

        await queue.enqueue(task)

        let beforeStart = await queue.getTask(task.id)
        XCTAssertEqual(beforeStart?.status, .pending)
        XCTAssertNil(beforeStart?.startedAt)

        await queue.markDownloading(task.id)

        let afterStart = await queue.getTask(task.id)
        XCTAssertEqual(afterStart?.status, .downloading)
        XCTAssertNotNil(afterStart?.startedAt)
    }

    func test_markCompleted_changesStatusAndSetsCompletedAt() async throws {
        let queue = DownloadQueueActor()
        let task = DownloadTask(
            url: URL(string: "https://example.com/file.zip")!,
            category: "Test",
            partNumber: 1,
            totalParts: 1,
            datasetName: "TEST",
            status: .extracting
        )

        await queue.enqueue(task)

        await queue.markCompleted(task.id)

        let completed = await queue.getTask(task.id)
        XCTAssertEqual(completed?.status, .completed)
        XCTAssertNotNil(completed?.completedAt)
        XCTAssertEqual(completed?.progress, 1.0)
    }

    func test_markFailed_changesStatusAndSetsError() async throws {
        let queue = DownloadQueueActor()
        let task = DownloadTask(
            url: URL(string: "https://example.com/file.zip")!,
            category: "Test",
            partNumber: 1,
            totalParts: 1,
            datasetName: "TEST",
            status: .downloading
        )

        await queue.enqueue(task)

        await queue.markFailed(task.id, error: "Network connection lost")

        let failed = await queue.getTask(task.id)
        XCTAssertEqual(failed?.status, .failed)
        XCTAssertEqual(failed?.errorMessage, "Network connection lost")
    }

    // MARK: - Concurrency Control Tests

    func test_getNextPendingTask_returnsNilWhen3Active() async throws {
        let queue = DownloadQueueActor(maxConcurrentDownloads: 3)

        // Add 3 downloading tasks
        for i in 1...3 {
            let task = DownloadTask(
                url: URL(string: "https://example.com/file\(i).zip")!,
                category: "Test",
                partNumber: i,
                totalParts: 5,
                datasetName: "TEST",
                status: .downloading
            )
            await queue.enqueue(task)
        }

        // Add a pending task
        let pendingTask = DownloadTask(
            url: URL(string: "https://example.com/file4.zip")!,
            category: "Test",
            partNumber: 4,
            totalParts: 5,
            datasetName: "TEST",
            status: .pending
        )
        await queue.enqueue(pendingTask)

        // Should return nil because 3 are already active
        let next = await queue.getNextPendingTask()
        XCTAssertNil(next)
    }

    func test_getNextPendingTask_returnsTaskWhenFewerThan3Active() async throws {
        let queue = DownloadQueueActor(maxConcurrentDownloads: 3)

        // Add 2 downloading tasks
        for i in 1...2 {
            let task = DownloadTask(
                url: URL(string: "https://example.com/file\(i).zip")!,
                category: "Test",
                partNumber: i,
                totalParts: 3,
                datasetName: "TEST",
                status: .downloading
            )
            await queue.enqueue(task)
        }

        // Add a pending task
        let pendingTask = DownloadTask(
            url: URL(string: "https://example.com/file3.zip")!,
            category: "Test",
            partNumber: 3,
            totalParts: 3,
            datasetName: "TEST",
            status: .pending
        )
        await queue.enqueue(pendingTask)

        // Should return the pending task
        let next = await queue.getNextPendingTask()
        XCTAssertNotNil(next)
        XCTAssertEqual(next?.id, pendingTask.id)
    }

    func test_canStartMoreDownloads_respectsLimit() async throws {
        let queue = DownloadQueueActor(maxConcurrentDownloads: 3)

        XCTAssertTrue(await queue.canStartMoreDownloads())

        // Add 3 active tasks
        for i in 1...3 {
            let task = DownloadTask(
                url: URL(string: "https://example.com/file\(i).zip")!,
                category: "Test",
                partNumber: i,
                totalParts: 3,
                datasetName: "TEST",
                status: .downloading
            )
            await queue.enqueue(task)
        }

        XCTAssertFalse(await queue.canStartMoreDownloads())
    }

    func test_globalPause_preventsGetNextPendingTask() async throws {
        let queue = DownloadQueueActor()
        let task = DownloadTask(
            url: URL(string: "https://example.com/file.zip")!,
            category: "Test",
            partNumber: 1,
            totalParts: 1,
            datasetName: "TEST",
            status: .pending
        )

        await queue.enqueue(task)

        // Should return task when not paused
        let beforePause = await queue.getNextPendingTask()
        XCTAssertNotNil(beforePause)

        // Pause queue
        await queue.pauseAll()

        // Should return nil when paused
        let afterPause = await queue.getNextPendingTask()
        XCTAssertNil(afterPause)
    }

    // MARK: - Queue Control Tests

    func test_pauseAll_pausesActiveDownloads() async throws {
        let queue = DownloadQueueActor()
        let task = DownloadTask(
            url: URL(string: "https://example.com/file.zip")!,
            category: "Test",
            partNumber: 1,
            totalParts: 1,
            datasetName: "TEST",
            status: .downloading
        )

        await queue.enqueue(task)
        await queue.pauseAll()

        let paused = await queue.getTask(task.id)
        XCTAssertEqual(paused?.status, .paused)
        XCTAssertTrue(await queue.getIsPaused())
    }

    func test_resumeAll_clearsGlobalPause() async throws {
        let queue = DownloadQueueActor()

        await queue.pauseAll()
        XCTAssertTrue(await queue.getIsPaused())

        await queue.resumeAll()
        XCTAssertFalse(await queue.getIsPaused())
    }

    func test_retryFailed_resetsFailedTasks() async throws {
        let queue = DownloadQueueActor()
        let task = DownloadTask(
            url: URL(string: "https://example.com/file.zip")!,
            category: "Test",
            partNumber: 1,
            totalParts: 1,
            datasetName: "TEST",
            status: .failed,
            errorMessage: "Network error"
        )

        await queue.enqueue(task)
        XCTAssertEqual(await queue.getFailedTasks().count, 1)

        await queue.retryFailed()

        let retried = await queue.getTask(task.id)
        XCTAssertEqual(retried?.status, .pending)
        XCTAssertNil(retried?.errorMessage)
        XCTAssertEqual(await queue.getFailedTasks().count, 0)
    }

    func test_retryTask_resetsSpecificFailedTask() async throws {
        let queue = DownloadQueueActor()
        let task = DownloadTask(
            url: URL(string: "https://example.com/file.zip")!,
            category: "Test",
            partNumber: 1,
            totalParts: 1,
            datasetName: "TEST",
            status: .failed
        )

        await queue.enqueue(task)

        await queue.retryTask(task.id)

        let retried = await queue.getTask(task.id)
        XCTAssertEqual(retried?.status, .pending)
    }

    // MARK: - Aggregation Tests

    func test_getOverallProgress_calculatesWeightedAverage() async throws {
        let queue = DownloadQueueActor()
        let task1 = DownloadTask(
            url: URL(string: "https://example.com/file1.zip")!,
            category: "Test",
            partNumber: 1,
            totalParts: 3,
            datasetName: "TEST",
            progress: 1.0
        )
        let task2 = DownloadTask(
            url: URL(string: "https://example.com/file2.zip")!,
            category: "Test",
            partNumber: 2,
            totalParts: 3,
            datasetName: "TEST",
            progress: 0.5
        )
        let task3 = DownloadTask(
            url: URL(string: "https://example.com/file3.zip")!,
            category: "Test",
            partNumber: 3,
            totalParts: 3,
            datasetName: "TEST",
            progress: 0.0
        )

        await queue.enqueueAll([task1, task2, task3])

        // (1.0 + 0.5 + 0.0) / 3 = 0.5
        let overall = await queue.getOverallProgress()
        XCTAssertEqual(overall, 0.5, accuracy: 0.01)
    }

    func test_getTotalBytes_sumsAllTasks() async throws {
        let queue = DownloadQueueActor()
        let task1 = DownloadTask(
            url: URL(string: "https://example.com/file1.zip")!,
            category: "Test",
            partNumber: 1,
            totalParts: 2,
            datasetName: "TEST",
            totalBytes: 1_000_000_000
        )
        let task2 = DownloadTask(
            url: URL(string: "https://example.com/file2.zip")!,
            category: "Test",
            partNumber: 2,
            totalParts: 2,
            datasetName: "TEST",
            totalBytes: 1_500_000_000
        )

        await queue.enqueueAll([task1, task2])

        let total = await queue.getTotalBytes()
        XCTAssertEqual(total, 2_500_000_000)
    }

    func test_getCategoryProgress_calculatesPerCategory() async throws {
        let queue = DownloadQueueActor()
        let task1 = DownloadTask(
            url: URL(string: "https://example.com/file1.zip")!,
            category: "Animals",
            partNumber: 1,
            totalParts: 2,
            datasetName: "INCLUDE",
            progress: 1.0
        )
        let task2 = DownloadTask(
            url: URL(string: "https://example.com/file2.zip")!,
            category: "Animals",
            partNumber: 2,
            totalParts: 2,
            datasetName: "INCLUDE",
            progress: 0.5
        )
        let task3 = DownloadTask(
            url: URL(string: "https://example.com/file3.zip")!,
            category: "Seasons",
            partNumber: 1,
            totalParts: 1,
            datasetName: "INCLUDE",
            progress: 0.0
        )

        await queue.enqueueAll([task1, task2, task3])

        // Animals: (1.0 + 0.5) / 2 = 0.75
        let animalsProgress = await queue.getCategoryProgress("Animals")
        XCTAssertEqual(animalsProgress, 0.75, accuracy: 0.01)

        // Seasons: 0.0 / 1 = 0.0
        let seasonsProgress = await queue.getCategoryProgress("Seasons")
        XCTAssertEqual(seasonsProgress, 0.0, accuracy: 0.01)
    }

    // MARK: - Persistence Tests

    func test_exportState_producesValidJSON() async throws {
        let queue = DownloadQueueActor()
        let task = DownloadTask(
            url: URL(string: "https://example.com/file.zip")!,
            category: "Test",
            partNumber: 1,
            totalParts: 1,
            datasetName: "TEST"
        )

        await queue.enqueue(task)

        let data = try await queue.exportState()
        XCTAssertFalse(data.isEmpty)

        // Verify it's valid JSON
        let decoded = try JSONDecoder().decode(DownloadQueueState.self, from: data)
        XCTAssertEqual(decoded.tasks.count, 1)
        XCTAssertEqual(decoded.tasks.first?.id, task.id)
    }

    func test_importState_restoresTasksCorrectly() async throws {
        let queue = DownloadQueueActor()
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

        await queue.enqueueAll([task1, task2])

        // Export
        let data = try await queue.exportState()

        // Clear queue
        await queue.clear()
        XCTAssertEqual(await queue.getTotalCount(), 0)

        // Import
        try await queue.importState(data)

        // Verify
        let allTasks = await queue.getAllTasks()
        XCTAssertEqual(allTasks.count, 2)
        XCTAssertTrue(allTasks.contains { $0.id == task1.id })
        XCTAssertTrue(allTasks.contains { $0.id == task2.id })
    }

    func test_persistenceRoundTrip_preservesAllData() async throws {
        let queue = DownloadQueueActor(maxConcurrentDownloads: 5)
        let task = DownloadTask(
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

        await queue.enqueue(task)
        await queue.pauseAll()

        // Export
        let data = try await queue.exportState()

        // Create new queue and import
        let newQueue = DownloadQueueActor()
        try await newQueue.importState(data)

        // Verify
        let restored = await newQueue.getTask(task.id)
        XCTAssertEqual(restored?.id, task.id)
        XCTAssertEqual(restored?.status, task.status)
        XCTAssertEqual(restored?.progress, task.progress, accuracy: 0.01)
        XCTAssertEqual(restored?.bytesDownloaded, task.bytesDownloaded)
        XCTAssertTrue(await newQueue.getIsPaused())
        XCTAssertEqual(await newQueue.getMaxConcurrentDownloads(), 5)
    }

    // MARK: - Edge Case Tests

    func test_operationOnNonExistentTask_doesNotCrash() async throws {
        let queue = DownloadQueueActor()
        let nonExistentID = UUID()

        // These should all handle gracefully
        await queue.remove(nonExistentID)
        await queue.updateProgress(id: nonExistentID, bytesDownloaded: 100, totalBytes: 1000)
        await queue.markDownloading(nonExistentID)
        await queue.markCompleted(nonExistentID)
        await queue.markFailed(nonExistentID, error: "test")

        // No crash = success
        XCTAssertEqual(await queue.getTotalCount(), 0)
    }

    func test_emptyQueue_returnsSensibleDefaults() async throws {
        let queue = DownloadQueueActor()

        XCTAssertEqual(await queue.getTotalCount(), 0)
        XCTAssertEqual(await queue.getActiveCount(), 0)
        XCTAssertEqual(await queue.getPendingCount(), 0)
        XCTAssertEqual(await queue.getCompletedCount(), 0)
        XCTAssertEqual(await queue.getOverallProgress(), 0.0)
        XCTAssertEqual(await queue.getTotalBytes(), 0)
        XCTAssertEqual(await queue.getDownloadedBytes(), 0)
        XCTAssertNil(await queue.getNextPendingTask())
        XCTAssertTrue(await queue.canStartMoreDownloads())
    }

    func test_progressWithZeroTotalBytes_doesNotCrash() async throws {
        let queue = DownloadQueueActor()
        let task = DownloadTask(
            url: URL(string: "https://example.com/file.zip")!,
            category: "Test",
            partNumber: 1,
            totalParts: 1,
            datasetName: "TEST",
            totalBytes: 0
        )

        await queue.enqueue(task)

        // Update progress with zero total bytes
        await queue.updateProgress(id: task.id, bytesDownloaded: 100, totalBytes: 0)

        // Should not crash
        let updated = await queue.getTask(task.id)
        XCTAssertEqual(updated?.bytesDownloaded, 100)
    }

    func test_getCategoryProgress_withNonExistentCategory_returnsZero() async throws {
        let queue = DownloadQueueActor()

        let progress = await queue.getCategoryProgress("NonExistent")
        XCTAssertEqual(progress, 0.0)
    }

    // MARK: - Count Tests

    func test_counts_areAccurate() async throws {
        let queue = DownloadQueueActor()
        let tasks = [
            DownloadTask(
                url: URL(string: "https://example.com/file1.zip")!,
                category: "Test",
                partNumber: 1,
                totalParts: 5,
                datasetName: "TEST",
                status: .pending
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
                status: .completed
            ),
            DownloadTask(
                url: URL(string: "https://example.com/file4.zip")!,
                category: "Test",
                partNumber: 4,
                totalParts: 5,
                datasetName: "TEST",
                status: .extracting
            ),
            DownloadTask(
                url: URL(string: "https://example.com/file5.zip")!,
                category: "Test",
                partNumber: 5,
                totalParts: 5,
                datasetName: "TEST",
                status: .failed
            )
        ]

        await queue.enqueueAll(tasks)

        XCTAssertEqual(await queue.getTotalCount(), 5)
        XCTAssertEqual(await queue.getPendingCount(), 1)
        XCTAssertEqual(await queue.getActiveCount(), 2) // downloading + extracting
        XCTAssertEqual(await queue.getCompletedCount(), 1)
    }
}
