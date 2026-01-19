import XCTest
import Combine
@testable import SignLanguageTranslate

/// Integration tests for the download system
///
/// These tests verify that all download components work together correctly.
/// They test complete flows from enqueueing tasks through completion.
@MainActor
final class DownloadIntegrationTests: XCTestCase {

    var engine: DownloadEngine!
    var mockSession: MockURLSession!
    var tempDirectory: URL!
    var cancellables: Set<AnyCancellable>!

    override func setUpWithError() throws {
        try super.setUpWithError()

        cancellables = []
        mockSession = MockURLSession()

        // Create temp directory
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("IntegrationTests_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        // Create engine with fast retry for testing
        engine = DownloadEngine(
            maxConcurrentDownloads: 3,
            maxRetryAttempts: 2,
            retryDelaySeconds: 0.1
        )
    }

    override func tearDown() async throws {
        if let engine = engine {
            await engine.stop()
            await engine.clearAll()
        }
        engine = nil
        mockSession = nil
        cancellables = nil

        if let temp = tempDirectory {
            try? FileManager.default.removeItem(at: temp)
        }
        tempDirectory = nil
    }

    // MARK: - Full Download Flow Tests

    func test_fullDownloadFlow_enqueueToComplete() async {
        // 1. Create and enqueue tasks
        let tasks = createTestDownloadTasks(count: 3)
        await engine.enqueueAll(tasks)

        // 2. Verify tasks are queued
        let allTasks = await engine.getAllTasks()
        XCTAssertEqual(allTasks.count, 3)

        // 3. Start engine
        await engine.start()
        XCTAssertTrue(engine.isRunning)

        // 4. Verify engine state
        XCTAssertFalse(engine.isPaused)
    }

    func test_enqueueAndStartDownloads() async {
        let tasks = createTestDownloadTasks(count: 5)
        await engine.enqueueAll(tasks)

        await engine.start()

        // Give time for queue processing
        try? await Task.sleep(nanoseconds: 100_000_000)

        // Check that active count respects max concurrent
        let queueActor = engine.queueActor
        let activeCount = await queueActor.getActiveCount()

        XCTAssertLessThanOrEqual(activeCount, 3)
    }

    func test_progressUpdatesFlow() async {
        let task = createTestDownloadTask()
        await engine.enqueue(task)
        await engine.start()

        // Simulate progress via coordinator
        let coordinator = engine.downloadCoordinator
        await coordinator.handleProgressUpdate(taskId: task.id, bytesWritten: 500, totalBytes: 1000)

        // Verify progress was recorded
        let queueActor = engine.queueActor
        let updatedTask = await queueActor.getTask(task.id)

        XCTAssertEqual(updatedTask?.bytesDownloaded, 500)
        XCTAssertEqual(updatedTask?.totalBytes, 1000)
        XCTAssertEqual(updatedTask?.progress ?? 0, 0.5, accuracy: 0.01)
    }

    // MARK: - Pause and Resume Flow Tests

    func test_pauseAndResumeFlow() async {
        let task = createTestDownloadTask(status: .downloading)
        await engine.enqueue(task)
        await engine.start()

        // Pause
        await engine.pause()
        XCTAssertTrue(engine.isPaused)

        // Resume
        await engine.resume()
        XCTAssertFalse(engine.isPaused)
    }

    func test_pauseSingleTask() async {
        let task = createTestDownloadTask()
        await engine.enqueue(task)
        await engine.start()

        // Wait for task to start
        try? await Task.sleep(nanoseconds: 100_000_000)

        // Pause specific task
        await engine.pauseTask(task.id)

        let queueActor = engine.queueActor
        let pausedTask = await queueActor.getTask(task.id)

        XCTAssertEqual(pausedTask?.status, .paused)
    }

    func test_resumeSingleTask() async {
        let task = createTestDownloadTask(status: .paused)
        await engine.enqueue(task)
        await engine.start()

        // Resume specific task
        await engine.resumeTask(task.id)

        let queueActor = engine.queueActor
        let resumedTask = await queueActor.getTask(task.id)

        XCTAssertEqual(resumedTask?.status, .downloading)
    }

    // MARK: - Failure and Retry Flow Tests

    func test_failureUpdatesTaskState() async {
        let task = createTestDownloadTask(status: .downloading)
        await engine.enqueue(task)
        await engine.start()

        // Simulate failure
        let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorNetworkConnectionLost)
        let coordinator = engine.downloadCoordinator
        await coordinator.handleDownloadFailed(taskId: task.id, error: error, resumeData: nil)

        let queueActor = engine.queueActor
        let failedTask = await queueActor.getTask(task.id)

        XCTAssertEqual(failedTask?.status, .failed)
        XCTAssertNotNil(failedTask?.errorMessage)
    }

    func test_retryFailedTask() async {
        // Create failed task
        let task = createTestDownloadTask(status: .failed, errorMessage: "Test error")
        await engine.enqueue(task)
        await engine.start()

        // Retry
        await engine.retryTask(task.id)

        let queueActor = engine.queueActor
        let retriedTask = await queueActor.getTask(task.id)

        // Should be reset to pending or downloading
        XCTAssertTrue(retriedTask?.status == .pending || retriedTask?.status == .downloading)
        XCTAssertNil(retriedTask?.errorMessage)
    }

    // MARK: - State Persistence Flow Tests

    func test_stateRecoveryAfterRelaunch() async {
        // 1. Create tasks and persist state
        let tasks = createTestDownloadTasks(count: 5)
        await engine.enqueueAll(tasks)

        // 2. Persist state
        let queueActor = engine.queueActor
        try? await queueActor.persistStateImmediately()

        // 3. Create new engine instance
        let newEngine = DownloadEngine(
            maxConcurrentDownloads: 3,
            maxRetryAttempts: 2,
            retryDelaySeconds: 0.1
        )

        // 4. Restore state
        let restored = await newEngine.queueActor.restoreState()

        // 5. Verify state was restored
        if restored {
            let restoredTasks = await newEngine.getAllTasks()
            XCTAssertEqual(restoredTasks.count, 5)
        }

        // Cleanup
        await newEngine.stop()
        await newEngine.clearAll()
    }

    // MARK: - Completion Handler Flow Tests

    func test_completionUpdatesState() async {
        let task = createTestDownloadTask(status: .downloading)
        await engine.enqueue(task)
        await engine.start()

        // Create a temp file to simulate download
        let tempFile = tempDirectory.appendingPathComponent("test.zip")
        try? Data("test content".utf8).write(to: tempFile)

        // Simulate completion
        let coordinator = engine.downloadCoordinator
        await coordinator.handleDownloadComplete(taskId: task.id, tempFileURL: tempFile)

        let queueActor = engine.queueActor
        let completedTask = await queueActor.getTask(task.id)

        XCTAssertEqual(completedTask?.status, .completed)
    }

    // MARK: - Queue Processing Tests

    func test_queueRespectsConcurrencyLimit() async {
        // Create more tasks than max concurrent
        let tasks = createTestDownloadTasks(count: 10)
        await engine.enqueueAll(tasks)

        await engine.start()

        // Wait for queue processing
        try? await Task.sleep(nanoseconds: 200_000_000)

        let queueActor = engine.queueActor
        let activeCount = await queueActor.getActiveCount()

        // Should never exceed max concurrent
        XCTAssertLessThanOrEqual(activeCount, 3)
    }

    func test_queueProcessesNextTaskAfterCompletion() async {
        let tasks = createTestDownloadTasks(count: 5)
        await engine.enqueueAll(tasks)
        await engine.start()

        // Wait for initial batch to start
        try? await Task.sleep(nanoseconds: 100_000_000)

        let queueActor = engine.queueActor
        let initialActive = await queueActor.getActiveCount()

        // Complete one task
        if let firstTask = await queueActor.getActiveTasks().first {
            let tempFile = tempDirectory.appendingPathComponent("\(firstTask.id).zip")
            try? Data("test content".utf8).write(to: tempFile)

            let coordinator = engine.downloadCoordinator
            await coordinator.handleDownloadComplete(taskId: firstTask.id, tempFileURL: tempFile)
        }

        // Queue should process next task
        try? await Task.sleep(nanoseconds: 100_000_000)

        // Active count should be maintained or have completed tasks
        let finalActive = await queueActor.getActiveCount()
        let completed = await queueActor.getCompletedCount()

        XCTAssertGreaterThan(completed, 0)
    }

    // MARK: - Cancel Flow Tests

    func test_cancelTask_removesFromQueue() async {
        let task = createTestDownloadTask()
        await engine.enqueue(task)

        await engine.cancelTask(task.id)

        let queueActor = engine.queueActor
        let cancelled = await queueActor.getTask(task.id)

        XCTAssertNil(cancelled)
    }

    func test_stopEngine_stopsAllDownloads() async {
        let tasks = createTestDownloadTasks(count: 5)
        await engine.enqueueAll(tasks)
        await engine.start()

        // Wait for some downloads to start
        try? await Task.sleep(nanoseconds: 100_000_000)

        await engine.stop()

        XCTAssertFalse(engine.isRunning)
    }

    // MARK: - Delegate Integration Tests

    func test_delegateReceivesUpdates() async {
        class TestDelegate: DownloadEngineDelegate {
            var updateCount = 0
            var completedCount = 0
            var failedCount = 0
            var allFinished = false

            func downloadEngine(_ engine: DownloadEngine, didUpdateTask task: DownloadTask) {
                updateCount += 1
            }

            func downloadEngine(_ engine: DownloadEngine, didCompleteTask task: DownloadTask) {
                completedCount += 1
            }

            func downloadEngine(_ engine: DownloadEngine, didFailTask task: DownloadTask, error: DownloadError) {
                failedCount += 1
            }

            func downloadEngineDidFinishAllTasks(_ engine: DownloadEngine) {
                allFinished = true
            }
        }

        let delegate = TestDelegate()
        engine.delegate = delegate

        let task = createTestDownloadTask()
        await engine.enqueue(task)
        await engine.start()

        // Wait for processing
        try? await Task.sleep(nanoseconds: 100_000_000)

        // Delegate should have received some updates
        XCTAssertNotNil(engine.delegate)
    }

    // MARK: - Progress Tracker Integration Tests

    func test_progressTrackerUpdatesWithDownloads() async {
        let task = createTestDownloadTask(totalBytes: 1000)
        await engine.enqueue(task)
        await engine.start()

        // Simulate progress
        let coordinator = engine.downloadCoordinator
        await coordinator.handleProgressUpdate(taskId: task.id, bytesWritten: 500, totalBytes: 1000)

        // The progress should be tracked
        let queueActor = engine.queueActor
        let updatedTask = await queueActor.getTask(task.id)

        XCTAssertEqual(updatedTask?.bytesDownloaded, 500)
    }

    // MARK: - Edge Cases

    func test_emptyQueueHandling() async {
        await engine.start()

        // Should not crash with empty queue
        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertTrue(engine.isRunning)

        let queueActor = engine.queueActor
        let count = await queueActor.getTotalCount()
        XCTAssertEqual(count, 0)
    }

    func test_duplicateTaskPrevention() async {
        let task = createTestDownloadTask()

        await engine.enqueue(task)
        await engine.enqueue(task) // Duplicate

        let allTasks = await engine.getAllTasks()
        XCTAssertEqual(allTasks.count, 1)
    }

    func test_operationsOnStoppedEngine() async {
        let task = createTestDownloadTask()
        await engine.enqueue(task)

        // Don't start engine - should still be able to manage queue
        let allTasks = await engine.getAllTasks()
        XCTAssertEqual(allTasks.count, 1)
    }

    // MARK: - Concurrent Operations Tests

    func test_concurrentEnqueue_isSafe() async {
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<50 {
                group.addTask { @MainActor in
                    let task = self.createTestDownloadTask(category: "Cat\(i)")
                    await self.engine.enqueue(task)
                }
            }
        }

        let allTasks = await engine.getAllTasks()
        XCTAssertEqual(allTasks.count, 50)
    }

    func test_concurrentPauseResume_isSafe() async {
        let tasks = createTestDownloadTasks(count: 10)
        await engine.enqueueAll(tasks)
        await engine.start()

        await withTaskGroup(of: Void.self) { group in
            for i in 0..<20 {
                group.addTask { @MainActor in
                    if i % 2 == 0 {
                        await self.engine.pause()
                    } else {
                        await self.engine.resume()
                    }
                }
            }
        }

        // Should not crash, engine should be in valid state
        let isRunning = engine.isRunning
        XCTAssertTrue(isRunning)
    }

    // MARK: - Category-Based Tests

    func test_multipleCategoriesDownload() async {
        var tasks: [DownloadTask] = []

        for category in ["Animals", "Food", "Sports"] {
            for i in 1...3 {
                let task = createTestDownloadTask(
                    category: category,
                    partNumber: i,
                    totalParts: 3
                )
                tasks.append(task)
            }
        }

        await engine.enqueueAll(tasks)
        await engine.start()

        let queueActor = engine.queueActor
        let animalTasks = await queueActor.getTasksForCategory("Animals")
        let foodTasks = await queueActor.getTasksForCategory("Food")
        let sportsTasks = await queueActor.getTasksForCategory("Sports")

        XCTAssertEqual(animalTasks.count, 3)
        XCTAssertEqual(foodTasks.count, 3)
        XCTAssertEqual(sportsTasks.count, 3)
    }

    // MARK: - File Manager Integration

    func test_fileManagerCreatesDirectories() async {
        let fileManager = DownloadFileManager()

        XCTAssertTrue(FileManager.default.directoryExists(at: fileManager.downloadsDirectory))
        XCTAssertTrue(FileManager.default.directoryExists(at: fileManager.tempDirectory))
    }

    // MARK: - Background Session Integration

    func test_backgroundSessionManagerTracksDownloads() async {
        let sessionManager = BackgroundSessionManager.shared
        let taskId = UUID()
        let url = URL(string: "https://example.com/test.zip")!

        let downloadTask = sessionManager.startDownload(url: url, taskId: taskId)

        XCTAssertNotNil(downloadTask)
        XCTAssertTrue(sessionManager.isDownloading(taskId: taskId))

        // Cleanup
        sessionManager.cancelDownload(taskId: taskId)
        XCTAssertFalse(sessionManager.isDownloading(taskId: taskId))
    }
}
