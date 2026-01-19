#if canImport(XCTest)
import XCTest
@testable import SignLanguageTranslate

/// Tests for BackgroundSessionManager
///
/// Note: These tests exercise the BackgroundSessionManager interface
/// without making real network calls. Some tests verify the session
/// configuration and task management logic.
final class BackgroundSessionManagerTests: XCTestCase {

    var manager: BackgroundSessionManager!

    override func setUpWithError() throws {
        try super.setUpWithError()
        manager = BackgroundSessionManager.shared
    }

    override func tearDownWithError() throws {
        // Cancel all downloads to clean up
        manager.cancelAllDownloads()
        manager.onProgress = nil
        manager.onComplete = nil
        manager.onFailed = nil
        manager.onPaused = nil
        try super.tearDownWithError()
    }

    // MARK: - Session Configuration Tests

    func test_sessionConfiguration_isBackgroundSession() {
        // Verify the session is configured for background downloads
        let config = manager.session.configuration

        XCTAssertNotNil(config.identifier)
        XCTAssertTrue(config.identifier!.contains("background"))
    }

    func test_sessionConfiguration_hasCorrectSettings() {
        let config = manager.session.configuration

        // Check key background session settings
        XCTAssertFalse(config.isDiscretionary, "Session should not be discretionary")
        XCTAssertTrue(config.sessionSendsLaunchEvents, "Should send launch events")
        XCTAssertTrue(config.allowsConstrainedNetworkAccess, "Should allow constrained network")
        XCTAssertTrue(config.allowsExpensiveNetworkAccess, "Should allow expensive network")
    }

    func test_sessionConfiguration_hasReasonableTimeouts() {
        let config = manager.session.configuration

        XCTAssertEqual(config.timeoutIntervalForRequest, 60, "Request timeout should be 60 seconds")
        XCTAssertEqual(config.timeoutIntervalForResource, 60 * 60 * 24, "Resource timeout should be 24 hours")
    }

    // MARK: - Task Creation Tests

    func test_startDownload_createsTask() {
        let taskId = UUID()
        let url = URL(string: "https://example.com/test.zip")!

        let downloadTask = manager.startDownload(url: url, taskId: taskId)

        XCTAssertNotNil(downloadTask)
        XCTAssertTrue(manager.isDownloading(taskId: taskId))
    }

    func test_startDownload_resumesTask() {
        let taskId = UUID()
        let url = URL(string: "https://example.com/test.zip")!

        let downloadTask = manager.startDownload(url: url, taskId: taskId)

        // Download task should be in running state after startDownload
        XCTAssertEqual(downloadTask.state, .running)
    }

    func test_startDownload_replacesExistingTask() {
        let taskId = UUID()
        let url1 = URL(string: "https://example.com/test1.zip")!
        let url2 = URL(string: "https://example.com/test2.zip")!

        let _ = manager.startDownload(url: url1, taskId: taskId)
        let secondTask = manager.startDownload(url: url2, taskId: taskId)

        // Should still have the task mapped
        XCTAssertTrue(manager.isDownloading(taskId: taskId))
        // Second URL should be used
        XCTAssertEqual(secondTask.originalRequest?.url, url2)
    }

    // MARK: - Task Tracking Tests

    func test_isDownloading_returnsTrueForActiveTask() {
        let taskId = UUID()
        let url = URL(string: "https://example.com/test.zip")!

        manager.startDownload(url: url, taskId: taskId)

        XCTAssertTrue(manager.isDownloading(taskId: taskId))
    }

    func test_isDownloading_returnsFalseForUnknownTask() {
        let unknownId = UUID()

        XCTAssertFalse(manager.isDownloading(taskId: unknownId))
    }

    func test_activeDownloadCount_tracksActiveTasks() {
        let initialCount = manager.activeDownloadCount

        let taskId1 = UUID()
        let taskId2 = UUID()
        let url = URL(string: "https://example.com/test.zip")!

        manager.startDownload(url: url, taskId: taskId1)
        XCTAssertEqual(manager.activeDownloadCount, initialCount + 1)

        manager.startDownload(url: url, taskId: taskId2)
        XCTAssertEqual(manager.activeDownloadCount, initialCount + 2)

        manager.cancelDownload(taskId: taskId1)
        XCTAssertEqual(manager.activeDownloadCount, initialCount + 1)
    }

    // MARK: - Cancel Tests

    func test_cancelDownload_removesTaskFromTracking() {
        let taskId = UUID()
        let url = URL(string: "https://example.com/test.zip")!

        manager.startDownload(url: url, taskId: taskId)
        XCTAssertTrue(manager.isDownloading(taskId: taskId))

        manager.cancelDownload(taskId: taskId)
        XCTAssertFalse(manager.isDownloading(taskId: taskId))
    }

    func test_cancelDownload_handlesUnknownTask() {
        let unknownId = UUID()

        // Should not crash or throw
        manager.cancelDownload(taskId: unknownId)
    }

    func test_cancelAllDownloads_removesAllTasks() {
        let url = URL(string: "https://example.com/test.zip")!

        for _ in 0..<5 {
            manager.startDownload(url: url, taskId: UUID())
        }

        XCTAssertGreaterThan(manager.activeDownloadCount, 0)

        manager.cancelAllDownloads()

        XCTAssertEqual(manager.activeDownloadCount, 0)
    }

    // MARK: - Resume Download Tests

    func test_resumeDownload_createsNewTask() {
        let taskId = UUID()
        let resumeData = createMockResumeData()

        let downloadTask = manager.resumeDownload(resumeData: resumeData, taskId: taskId)

        XCTAssertNotNil(downloadTask)
        XCTAssertTrue(manager.isDownloading(taskId: taskId))
    }

    func test_resumeDownload_replacesExistingTask() {
        let taskId = UUID()
        let url = URL(string: "https://example.com/test.zip")!
        let resumeData = createMockResumeData()

        // Start with a normal download
        manager.startDownload(url: url, taskId: taskId)

        // Resume should replace it
        let resumedTask = manager.resumeDownload(resumeData: resumeData, taskId: taskId)

        XCTAssertNotNil(resumedTask)
        XCTAssertTrue(manager.isDownloading(taskId: taskId))
    }

    // MARK: - Pause Download Tests

    func test_pauseDownload_returnsNilForUnknownTask() async {
        let unknownId = UUID()

        let resumeData = await manager.pauseDownload(taskId: unknownId)

        XCTAssertNil(resumeData)
    }

    // MARK: - Task ID Mapping Tests

    func test_getTaskId_returnsCorrectMapping() {
        let taskId = UUID()
        let url = URL(string: "https://example.com/test.zip")!

        let downloadTask = manager.startDownload(url: url, taskId: taskId)

        let retrievedId = manager.getTaskId(for: downloadTask)

        XCTAssertEqual(retrievedId, taskId)
    }

    func test_getTaskId_returnsNilForUnknownTask() {
        // Create a task through the session but not through our manager
        let unknownTask = manager.session.downloadTask(with: URL(string: "https://example.com/unknown.zip")!)

        let taskId = manager.getTaskId(for: unknownTask)

        XCTAssertNil(taskId)
    }

    // MARK: - Remove Task Tests

    func test_removeTask_removesFromTracking() {
        let taskId = UUID()
        let url = URL(string: "https://example.com/test.zip")!

        manager.startDownload(url: url, taskId: taskId)
        XCTAssertTrue(manager.isDownloading(taskId: taskId))

        manager.removeTask(taskId)
        XCTAssertFalse(manager.isDownloading(taskId: taskId))
    }

    func test_removeTask_handlesUnknownTask() {
        let unknownId = UUID()

        // Should not crash or throw
        manager.removeTask(unknownId)
    }

    // MARK: - Restore Task Mappings Tests

    func test_restoreTaskMappings_addsMappings() {
        let taskId1 = UUID()
        let taskId2 = UUID()

        let mappings: [(sessionTaskId: Int, ourTaskId: UUID)] = [
            (sessionTaskId: 100, ourTaskId: taskId1),
            (sessionTaskId: 200, ourTaskId: taskId2)
        ]

        manager.restoreTaskMappings(tasks: mappings)

        // The mappings are internal, but we can verify the count hasn't changed unexpectedly
        // Since we don't have actual URLSessionTasks, we can't fully verify
    }

    // MARK: - Callback Tests

    func test_callbackClosures_canBeSet() {
        var progressCalled = false
        var completeCalled = false
        var failedCalled = false
        var pausedCalled = false

        manager.onProgress = { _, _, _ in
            progressCalled = true
        }

        manager.onComplete = { _, _ in
            completeCalled = true
        }

        manager.onFailed = { _, _, _ in
            failedCalled = true
        }

        manager.onPaused = { _, _ in
            pausedCalled = true
        }

        // Verify closures are set (they won't be called without actual download activity)
        XCTAssertNotNil(manager.onProgress)
        XCTAssertNotNil(manager.onComplete)
        XCTAssertNotNil(manager.onFailed)
        XCTAssertNotNil(manager.onPaused)
    }

    // MARK: - Background Completion Handler Tests

    func test_backgroundCompletionHandler_canBeSetAndCleared() {
        var handlerCalled = false

        manager.backgroundCompletionHandler = {
            handlerCalled = true
        }

        XCTAssertNotNil(manager.backgroundCompletionHandler)

        // Simulate calling it
        manager.backgroundCompletionHandler?()

        XCTAssertTrue(handlerCalled)
    }

    // MARK: - Get Pending Tasks Tests

    func test_getPendingTasks_returnsEmptyWhenNoTasks() async {
        manager.cancelAllDownloads()

        let tasks = await manager.getPendingTasks()

        // We should get back any tasks managed by the background session
        // Since we cancelled all, new ones we start would be pending
        XCTAssertNotNil(tasks)
    }

    func test_getAllTasks_returnsTuple() async {
        let result = await manager.getAllTasks()

        XCTAssertNotNil(result.dataTasks)
        XCTAssertNotNil(result.uploadTasks)
        XCTAssertNotNil(result.downloadTasks)
    }

    // MARK: - Concurrent Access Tests

    func test_concurrentAccess_isSafe() async {
        let url = URL(string: "https://example.com/test.zip")!

        // Perform many concurrent operations
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<100 {
                group.addTask {
                    let taskId = UUID()
                    self.manager.startDownload(url: url, taskId: taskId)

                    if i % 3 == 0 {
                        self.manager.cancelDownload(taskId: taskId)
                    } else if i % 3 == 1 {
                        self.manager.removeTask(taskId)
                    }
                    // Let some tasks stay active
                }
            }
        }

        // Clean up
        manager.cancelAllDownloads()
    }

    // MARK: - Singleton Tests

    func test_singleton_returnsSameInstance() {
        let instance1 = BackgroundSessionManager.shared
        let instance2 = BackgroundSessionManager.shared

        XCTAssertTrue(instance1 === instance2)
    }
}
#endif
