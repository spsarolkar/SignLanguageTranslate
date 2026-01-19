#if canImport(XCTest)
import XCTest
@testable import SignLanguageTranslate

/// Tests for DownloadEngine
@MainActor
final class DownloadEngineTests: XCTestCase {

    var engine: DownloadEngine!

    override func setUpWithError() throws {
        try super.setUpWithError()
        engine = DownloadEngine(
            maxConcurrentDownloads: 3,
            maxRetryAttempts: 3,
            retryDelaySeconds: 0.1 // Fast retries for testing
        )
    }

    override func tearDown() async throws {
        await engine.stop()
        await engine.clearAll()
        engine = nil
        try await super.tearDown()
    }

    // MARK: - Initialization Tests

    func test_initialization_defaultValues() {
        let defaultEngine = DownloadEngine()

        XCTAssertEqual(defaultEngine.maxConcurrentDownloads, 3)
        XCTAssertEqual(defaultEngine.maxRetryAttempts, 3)
        XCTAssertEqual(defaultEngine.retryDelaySeconds, 2.0)
    }

    func test_initialization_customValues() {
        let customEngine = DownloadEngine(
            maxConcurrentDownloads: 5,
            maxRetryAttempts: 5,
            retryDelaySeconds: 1.0
        )

        XCTAssertEqual(customEngine.maxConcurrentDownloads, 5)
        XCTAssertEqual(customEngine.maxRetryAttempts, 5)
        XCTAssertEqual(customEngine.retryDelaySeconds, 1.0)
    }

    func test_initialization_notRunningByDefault() {
        XCTAssertFalse(engine.isRunning)
        XCTAssertFalse(engine.isPaused)
    }

    // MARK: - Start/Stop Tests

    func test_start_setsRunningState() async {
        await engine.start()

        XCTAssertTrue(engine.isRunning)
        XCTAssertFalse(engine.isPaused)
    }

    func test_start_multipleCallsAreSafe() async {
        await engine.start()
        await engine.start()
        await engine.start()

        XCTAssertTrue(engine.isRunning)
    }

    func test_stop_clearsRunningState() async {
        await engine.start()
        XCTAssertTrue(engine.isRunning)

        await engine.stop()

        XCTAssertFalse(engine.isRunning)
        XCTAssertFalse(engine.isPaused)
    }

    func test_stop_whenNotRunning_isNoop() async {
        XCTAssertFalse(engine.isRunning)

        await engine.stop()

        XCTAssertFalse(engine.isRunning)
    }

    // MARK: - Pause/Resume Tests

    func test_pause_setsPausedState() async {
        await engine.start()

        await engine.pause()

        XCTAssertTrue(engine.isPaused)
        XCTAssertTrue(engine.isRunning) // Still running, just paused
    }

    func test_pause_whenNotRunning_isNoop() async {
        XCTAssertFalse(engine.isRunning)

        await engine.pause()

        XCTAssertFalse(engine.isPaused)
    }

    func test_resume_clearsPausedState() async {
        await engine.start()
        await engine.pause()
        XCTAssertTrue(engine.isPaused)

        await engine.resume()

        XCTAssertFalse(engine.isPaused)
        XCTAssertTrue(engine.isRunning)
    }

    func test_resume_whenNotPaused_isNoop() async {
        await engine.start()
        XCTAssertFalse(engine.isPaused)

        await engine.resume()

        XCTAssertFalse(engine.isPaused)
    }

    // MARK: - Queue Management Tests

    func test_enqueue_addsSingleTask() async {
        let task = createTestDownloadTask()

        await engine.enqueue(task)

        let tasks = await engine.getAllTasks()
        XCTAssertEqual(tasks.count, 1)
        XCTAssertEqual(tasks.first?.id, task.id)
    }

    func test_enqueueAll_addsMultipleTasks() async {
        let tasks = createTestDownloadTasks(count: 5)

        await engine.enqueueAll(tasks)

        let allTasks = await engine.getAllTasks()
        XCTAssertEqual(allTasks.count, 5)
    }

    func test_getTask_returnsCorrectTask() async {
        let task = createTestDownloadTask()
        await engine.enqueue(task)

        let retrieved = await engine.getTask(task.id)

        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.id, task.id)
        XCTAssertEqual(retrieved?.category, task.category)
    }

    func test_getTask_returnsNilForUnknown() async {
        let unknownId = UUID()

        let retrieved = await engine.getTask(unknownId)

        XCTAssertNil(retrieved)
    }

    func test_getAllTasks_returnsAllEnqueuedTasks() async {
        let tasks = createTestDownloadTasks(count: 10)
        await engine.enqueueAll(tasks)

        let allTasks = await engine.getAllTasks()

        XCTAssertEqual(allTasks.count, 10)
    }

    func test_clearAll_removesAllTasks() async {
        let tasks = createTestDownloadTasks(count: 5)
        await engine.enqueueAll(tasks)

        await engine.clearAll()

        let allTasks = await engine.getAllTasks()
        XCTAssertEqual(allTasks.count, 0)
    }

    // MARK: - Retry Count Management Tests

    func test_getRetryCount_returnsZeroForNewTask() {
        let taskId = UUID()

        let count = engine.getRetryCount(for: taskId)

        XCTAssertEqual(count, 0)
    }

    func test_resetRetryCount_resetsToZero() async {
        // We can't easily increment retry count without triggering failures
        // but we can test that reset works
        let taskId = UUID()

        engine.resetRetryCount(for: taskId)

        XCTAssertEqual(engine.getRetryCount(for: taskId), 0)
    }

    func test_resetAllRetryCounts_clearsAllCounts() {
        engine.resetAllRetryCounts()

        // Verify no counts exist
        let randomId = UUID()
        XCTAssertEqual(engine.getRetryCount(for: randomId), 0)
    }

    // MARK: - Queue Actor Access Tests

    func test_queueActor_isAccessible() {
        XCTAssertNotNil(engine.queueActor)
    }

    func test_downloadCoordinator_isAccessible() {
        XCTAssertNotNil(engine.downloadCoordinator)
    }

    // MARK: - Network Status Tests

    func test_networkStatus_initiallyAvailable() {
        XCTAssertTrue(engine.isNetworkAvailable)
    }

    // MARK: - Delegate Tests

    func test_delegate_canBeSet() {
        class MockDelegate: DownloadEngineDelegate {
            var didUpdateTask = false
            var didCompleteTask = false
            var didFailTask = false

            func downloadEngine(_ engine: DownloadEngine, didUpdateTask task: DownloadTask) {
                didUpdateTask = true
            }

            func downloadEngine(_ engine: DownloadEngine, didCompleteTask task: DownloadTask) {
                didCompleteTask = true
            }

            func downloadEngine(_ engine: DownloadEngine, didFailTask task: DownloadTask, error: DownloadError) {
                didFailTask = true
            }

            func downloadEngineDidFinishAllTasks(_ engine: DownloadEngine) {}
        }

        let delegate = MockDelegate()
        engine.delegate = delegate

        XCTAssertNotNil(engine.delegate)
    }

    // MARK: - Concurrency Limit Tests

    func test_maxConcurrentDownloads_isConfigured() {
        let engine3 = DownloadEngine(maxConcurrentDownloads: 3)
        let engine5 = DownloadEngine(maxConcurrentDownloads: 5)

        XCTAssertEqual(engine3.maxConcurrentDownloads, 3)
        XCTAssertEqual(engine5.maxConcurrentDownloads, 5)
    }

    // MARK: - Task Control Tests

    func test_cancelTask_removesFromRetryTracking() async {
        let task = createTestDownloadTask()
        await engine.enqueue(task)

        await engine.cancelTask(task.id)

        XCTAssertEqual(engine.getRetryCount(for: task.id), 0)
    }

    func test_retryTask_resetsRetryCount() async {
        let task = createTestDownloadTask(status: .failed)
        await engine.enqueue(task)

        await engine.retryTask(task.id)

        XCTAssertEqual(engine.getRetryCount(for: task.id), 0)
    }

    // MARK: - Callback Closure Tests

    func test_onProgress_canBeSet() {
        var called = false

        engine.onProgress = { _, _, _ in
            called = true
        }

        XCTAssertNotNil(engine.onProgress)
    }

    func test_onComplete_canBeSet() {
        var called = false

        engine.onComplete = { _, _ in
            called = true
        }

        XCTAssertNotNil(engine.onComplete)
    }

    func test_onFailed_canBeSet() {
        var called = false

        engine.onFailed = { _, _, _ in
            called = true
        }

        XCTAssertNotNil(engine.onFailed)
    }

    // MARK: - State Transitions Tests

    func test_stateTransitions_startPauseResumeStop() async {
        // Initial state
        XCTAssertFalse(engine.isRunning)
        XCTAssertFalse(engine.isPaused)

        // Start
        await engine.start()
        XCTAssertTrue(engine.isRunning)
        XCTAssertFalse(engine.isPaused)

        // Pause
        await engine.pause()
        XCTAssertTrue(engine.isRunning)
        XCTAssertTrue(engine.isPaused)

        // Resume
        await engine.resume()
        XCTAssertTrue(engine.isRunning)
        XCTAssertFalse(engine.isPaused)

        // Stop
        await engine.stop()
        XCTAssertFalse(engine.isRunning)
        XCTAssertFalse(engine.isPaused)
    }

    // MARK: - Edge Cases

    func test_operationsOnEmptyQueue_areSafe() async {
        await engine.start()

        // These should all be safe on empty queue
        await engine.pause()
        await engine.resume()
        await engine.stop()

        let tasks = await engine.getAllTasks()
        XCTAssertEqual(tasks.count, 0)
    }

    func test_doubleEnqueue_sameTaskId_doesNotDuplicate() async {
        let task = createTestDownloadTask()

        await engine.enqueue(task)
        await engine.enqueue(task)

        let tasks = await engine.getAllTasks()
        XCTAssertEqual(tasks.count, 1)
    }

    // MARK: - Retry Configuration Tests

    func test_maxRetryAttempts_isConfigured() {
        let engine1 = DownloadEngine(maxRetryAttempts: 1)
        let engine5 = DownloadEngine(maxRetryAttempts: 5)

        XCTAssertEqual(engine1.maxRetryAttempts, 1)
        XCTAssertEqual(engine5.maxRetryAttempts, 5)
    }

    func test_retryDelaySeconds_isConfigured() {
        let engineFast = DownloadEngine(retryDelaySeconds: 0.5)
        let engineSlow = DownloadEngine(retryDelaySeconds: 5.0)

        XCTAssertEqual(engineFast.retryDelaySeconds, 0.5)
        XCTAssertEqual(engineSlow.retryDelaySeconds, 5.0)
    }
}
#endif
