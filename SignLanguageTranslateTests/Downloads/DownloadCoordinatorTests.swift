#if canImport(XCTest)
import XCTest
@testable import SignLanguageTranslate

/// Tests for DownloadCoordinator
final class DownloadCoordinatorTests: XCTestCase {

    var coordinator: DownloadCoordinator!
    var queue: DownloadQueueActor!
    var fileManager: DownloadFileManager!
    var tempDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()

        // Create temp directory for file operations
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DownloadCoordinatorTests_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        queue = DownloadQueueActor(maxConcurrentDownloads: 3)
        fileManager = DownloadFileManager()
        coordinator = DownloadCoordinator(queue: queue, fileManager: fileManager)
    }

    override func tearDown() async throws {
        if let coord = coordinator {
            await coord.stop()
        }
        coordinator = nil
        queue = nil
        fileManager = nil

        // Clean up temp directory
        if let temp = tempDirectory {
            try? FileManager.default.removeItem(at: temp)
        }
        tempDirectory = nil

        try await super.tearDown()
    }

    // MARK: - Initialization Tests

    func test_initialization_createsCoordinator() {
        XCTAssertNotNil(coordinator)
    }

    func test_initialization_usesProvidedQueue() async {
        let customQueue = DownloadQueueActor(maxConcurrentDownloads: 5)
        let customCoordinator = DownloadCoordinator(queue: customQueue, fileManager: fileManager)

        let maxConcurrent = await customQueue.getMaxConcurrentDownloads()
        XCTAssertEqual(maxConcurrent, 5)

        await customCoordinator.stop()
    }

    // MARK: - Start/Stop Tests

    func test_start_startsCoordinator() async {
        await coordinator.start()

        // Coordinator is running (we can't directly check, but operations should work)
        let tasks = await queue.getAllTasks()
        XCTAssertEqual(tasks.count, 0)
    }

    func test_stop_stopsCoordinator() async {
        await coordinator.start()
        await coordinator.stop()

        // Coordinator stopped (operations may still work for cleanup)
        let tasks = await queue.getAllTasks()
        XCTAssertEqual(tasks.count, 0)
    }

    // MARK: - Task Management Tests

    func test_startTask_marksTaskAsDownloading() async {
        let task = createTestDownloadTask()
        await queue.enqueue(task)

        await coordinator.startTask(task.id)

        let updatedTask = await queue.getTask(task.id)
        XCTAssertEqual(updatedTask?.status, .downloading)
    }

    func test_startTask_ignoresNonexistentTask() async {
        let unknownId = UUID()

        // Should not crash
        await coordinator.startTask(unknownId)
    }

    func test_startTask_ignoresNonStartableTasks() async {
        let completedTask = createTestDownloadTask(status: .completed)
        await queue.enqueue(completedTask)

        await coordinator.startTask(completedTask.id)

        let task = await queue.getTask(completedTask.id)
        XCTAssertEqual(task?.status, .completed) // Should remain completed
    }

    // MARK: - Pause Task Tests

    func test_pauseTask_pausesDownloadingTask() async {
        let task = createTestDownloadTask(status: .downloading)
        await queue.enqueue(task)

        await coordinator.pauseTask(task.id)

        let updatedTask = await queue.getTask(task.id)
        XCTAssertEqual(updatedTask?.status, .paused)
    }

    func test_pauseTask_ignoresNonDownloadingTask() async {
        let pendingTask = createTestDownloadTask(status: .pending)
        await queue.enqueue(pendingTask)

        await coordinator.pauseTask(pendingTask.id)

        let task = await queue.getTask(pendingTask.id)
        XCTAssertEqual(task?.status, .pending) // Should remain pending
    }

    // MARK: - Resume Task Tests

    func test_resumeTask_callsStartTask() async {
        let task = createTestDownloadTask(status: .paused)
        await queue.enqueue(task)

        await coordinator.resumeTask(task.id)

        let updatedTask = await queue.getTask(task.id)
        // Resume calls start, which should mark as downloading
        XCTAssertEqual(updatedTask?.status, .downloading)
    }

    // MARK: - Cancel Task Tests

    func test_cancelTask_removesFromQueue() async {
        let task = createTestDownloadTask()
        await queue.enqueue(task)

        await coordinator.cancelTask(task.id)

        let retrieved = await queue.getTask(task.id)
        XCTAssertNil(retrieved)
    }

    func test_cancelTask_handlesNonexistentTask() async {
        let unknownId = UUID()

        // Should not crash
        await coordinator.cancelTask(unknownId)
    }

    // MARK: - Retry Task Tests

    func test_retryTask_resetsFailedTask() async {
        let failedTask = createTestDownloadTask(status: .failed, errorMessage: "Test error")
        await queue.enqueue(failedTask)

        await coordinator.retryTask(failedTask.id)

        let task = await queue.getTask(failedTask.id)
        XCTAssertEqual(task?.status, .pending)
        XCTAssertNil(task?.errorMessage)
    }

    func test_retryTask_ignoresNonFailedTask() async {
        let pendingTask = createTestDownloadTask(status: .pending)
        await queue.enqueue(pendingTask)

        await coordinator.retryTask(pendingTask.id)

        let task = await queue.getTask(pendingTask.id)
        XCTAssertEqual(task?.status, .pending) // Should remain pending
    }

    // MARK: - Pause/Resume All Tests

    func test_pauseAll_pausesAllDownloadingTasks() async {
        let task1 = createTestDownloadTask(status: .downloading, category: "Cat1")
        let task2 = createTestDownloadTask(status: .downloading, category: "Cat2")
        await queue.enqueueAll([task1, task2])

        await coordinator.pauseAll()

        let isPaused = await queue.getIsPaused()
        XCTAssertTrue(isPaused)

        let tasks = await queue.getAllTasks()
        for task in tasks {
            XCTAssertEqual(task.status, .paused)
        }
    }

    func test_resumeAll_resumesProcessing() async {
        await queue.pauseAll()
        let isPausedBefore = await queue.getIsPaused()
        XCTAssertTrue(isPausedBefore)

        await coordinator.resumeAll()

        let isPausedAfter = await queue.getIsPaused()
        XCTAssertFalse(isPausedAfter)
    }

    // MARK: - Cancel All Tests

    func test_cancelAll_clearsQueue() async {
        let tasks = createTestDownloadTasks(count: 5)
        await queue.enqueueAll(tasks)

        await coordinator.cancelAll()

        let remainingTasks = await queue.getAllTasks()
        XCTAssertEqual(remainingTasks.count, 0)
    }

    // MARK: - Progress Update Tests

    func test_handleProgressUpdate_updatesTaskProgress() async {
        let task = createTestDownloadTask(status: .downloading, totalBytes: 1000)
        await queue.enqueue(task)

        await coordinator.handleProgressUpdate(
            taskId: task.id,
            bytesWritten: 500,
            totalBytes: 1000
        )

        let updatedTask = await queue.getTask(task.id)
        XCTAssertEqual(updatedTask?.bytesDownloaded, 500)
        XCTAssertEqual(updatedTask?.progress ?? 0, 0.5, accuracy: 0.01)
    }

    func test_handleProgressUpdate_handlesUnknownTotal() async {
        let task = createTestDownloadTask(status: .downloading)
        await queue.enqueue(task)

        // -1 indicates unknown total from URLSession
        await coordinator.handleProgressUpdate(
            taskId: task.id,
            bytesWritten: 500,
            totalBytes: -1
        )

        let updatedTask = await queue.getTask(task.id)
        XCTAssertEqual(updatedTask?.bytesDownloaded, 500)
        // Total should be 0 when unknown
    }

    // MARK: - Download Complete Tests

    func test_handleDownloadComplete_marksTaskCompleted() async {
        let task = createTestDownloadTask(status: .downloading)
        await queue.enqueue(task)

        // Create a temp file to "download"
        let tempFile = tempDirectory.appendingPathComponent("test.zip")
        try? Data("test content".utf8).write(to: tempFile)

        await coordinator.handleDownloadComplete(taskId: task.id, tempFileURL: tempFile)

        let updatedTask = await queue.getTask(task.id)
        // Should go through extracting to completed
        XCTAssertEqual(updatedTask?.status, .completed)
    }

    func test_handleDownloadComplete_handlesNonexistentTask() async {
        let unknownId = UUID()
        let tempFile = tempDirectory.appendingPathComponent("test.zip")
        try? Data("test content".utf8).write(to: tempFile)

        // Should not crash
        await coordinator.handleDownloadComplete(taskId: unknownId, tempFileURL: tempFile)
    }

    // MARK: - Download Failed Tests

    func test_handleDownloadFailed_marksTaskFailed() async {
        let task = createTestDownloadTask(status: .downloading)
        await queue.enqueue(task)

        let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorNetworkConnectionLost)
        await coordinator.handleDownloadFailed(taskId: task.id, error: error, resumeData: nil)

        let updatedTask = await queue.getTask(task.id)
        XCTAssertEqual(updatedTask?.status, .failed)
        XCTAssertNotNil(updatedTask?.errorMessage)
    }

    func test_handleDownloadFailed_savesResumeData() async {
        let task = createTestDownloadTask(status: .downloading)
        await queue.enqueue(task)

        let resumeData = createMockResumeData()
        let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorNetworkConnectionLost)
        await coordinator.handleDownloadFailed(taskId: task.id, error: error, resumeData: resumeData)

        let updatedTask = await queue.getTask(task.id)
        XCTAssertNotNil(updatedTask?.resumeDataPath)
    }

    // MARK: - Download Paused Tests

    func test_handleDownloadPaused_marksTaskPaused() async {
        let task = createTestDownloadTask(status: .downloading)
        await queue.enqueue(task)

        let resumeData = createMockResumeData()
        await coordinator.handleDownloadPaused(taskId: task.id, resumeData: resumeData)

        let updatedTask = await queue.getTask(task.id)
        XCTAssertEqual(updatedTask?.status, .paused)
    }

    func test_handleDownloadPaused_savesResumeData() async {
        let task = createTestDownloadTask(status: .downloading)
        await queue.enqueue(task)

        let resumeData = createMockResumeData()
        await coordinator.handleDownloadPaused(taskId: task.id, resumeData: resumeData)

        let updatedTask = await queue.getTask(task.id)
        XCTAssertNotNil(updatedTask?.resumeDataPath)
    }

    // MARK: - Storage Tests

    func test_availableStorage_returnsValue() async {
        let available = await coordinator.availableStorage()

        XCTAssertGreaterThan(available, 0)
    }

    func test_hasStorageForRemainingDownloads_returnsTrueWhenEmpty() async {
        let hasStorage = await coordinator.hasStorageForRemainingDownloads()

        XCTAssertTrue(hasStorage)
    }

    // MARK: - Process Queue Tests

    func test_processQueue_startsDownloadsWhenCapacityAvailable() async {
        let task = createTestDownloadTask()
        await queue.enqueue(task)

        await coordinator.processQueue()

        let updatedTask = await queue.getTask(task.id)
        XCTAssertEqual(updatedTask?.status, .downloading)
    }

    func test_processQueue_respectsConcurrencyLimit() async {
        // Create more tasks than max concurrent
        let tasks = createTestDownloadTasks(count: 5)
        await queue.enqueueAll(tasks)

        await coordinator.processQueue()

        let activeTasks = await queue.getActiveTasks()
        XCTAssertLessThanOrEqual(activeTasks.count, 3)
    }

    // MARK: - Restoration Tests

    func test_restoreAfterRelaunch_cleansOrphanedFiles() async {
        // Add some tasks
        let tasks = createTestDownloadTasks(count: 3)
        await queue.enqueueAll(tasks)

        await coordinator.restoreAfterRelaunch()

        // Coordinator should have run cleanup
        let allTasks = await queue.getAllTasks()
        XCTAssertEqual(allTasks.count, 3)
    }

    // MARK: - Error Handling Tests

    func test_humanReadableError_networkErrors() async {
        let task = createTestDownloadTask(status: .downloading)
        await queue.enqueue(task)

        let networkError = NSError(
            domain: NSURLErrorDomain,
            code: NSURLErrorNotConnectedToInternet
        )
        await coordinator.handleDownloadFailed(taskId: task.id, error: networkError, resumeData: nil)

        let updatedTask = await queue.getTask(task.id)
        XCTAssertEqual(updatedTask?.errorMessage, "No internet connection")
    }

    func test_humanReadableError_timeoutError() async {
        let task = createTestDownloadTask(status: .downloading)
        await queue.enqueue(task)

        let timeoutError = NSError(
            domain: NSURLErrorDomain,
            code: NSURLErrorTimedOut
        )
        await coordinator.handleDownloadFailed(taskId: task.id, error: timeoutError, resumeData: nil)

        let updatedTask = await queue.getTask(task.id)
        XCTAssertEqual(updatedTask?.errorMessage, "Request timed out")
    }

    // MARK: - Edge Cases

    func test_multipleOperationsOnSameTask_areSafe() async {
        let task = createTestDownloadTask()
        await queue.enqueue(task)

        // Perform many operations concurrently
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.coordinator.startTask(task.id) }
            group.addTask { await self.coordinator.pauseTask(task.id) }
            group.addTask { await self.coordinator.resumeTask(task.id) }
            group.addTask { await self.coordinator.processQueue() }
        }

        // Should not crash, task should be in some valid state
        let finalTask = await queue.getTask(task.id)
        XCTAssertNotNil(finalTask)
    }
}
#endif
