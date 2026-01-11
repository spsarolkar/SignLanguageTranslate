import Foundation
import Observation

/// Observable wrapper for the download queue that bridges actor-based state to SwiftUI
///
/// The DownloadManager provides a SwiftUI-friendly interface to the download system:
/// - Observable properties for binding to views
/// - Methods for controlling downloads
/// - Integration with DownloadEngine for actual download processing
/// - State recovery after app restarts
///
/// ## State Recovery Flow
/// ```
/// App Launch:
/// 1. DownloadManager.init()
/// 2. recoverDownloads()
/// 3. Load persisted queue state
/// 4. Check URLSession for pending/completed tasks
/// 5. Reconcile states
/// 6. Resume any interrupted downloads
/// 7. Update UI
/// ```
@MainActor
@Observable
final class DownloadManager {

    // MARK: - Properties

    /// The download engine for processing downloads
    private let engine: DownloadEngine

    /// The download queue actor for state management
    private var queue: DownloadQueueActor { engine.queueActor }

    /// Progress tracker for real-time progress monitoring
    private let progressTracker: DownloadProgressTracker

    /// Download history for analytics and debugging
    private let history: DownloadHistory

    /// Whether recovery has been performed
    private(set) var hasRecovered: Bool = false

    private(set) var tasks: [DownloadTask] = []
    private(set) var taskGroups: [DownloadTaskGroup] = []
    private(set) var overallProgress: Double = 0.0
    private(set) var totalBytes: Int64 = 0
    private(set) var downloadedBytes: Int64 = 0
    private(set) var activeCount: Int = 0
    private(set) var completedCount: Int = 0
    private(set) var failedCount: Int = 0
    private(set) var pendingCount: Int = 0
    private(set) var totalCount: Int = 0
    private(set) var isPaused: Bool = false

    /// Current download rate from progress tracker
    var currentDownloadRate: Double { progressTracker.currentDownloadRate }

    /// Formatted download rate (e.g., "2.5 MB/s")
    var formattedDownloadRate: String { progressTracker.formattedDownloadRate }

    /// Estimated time remaining
    var estimatedTimeRemaining: TimeInterval? { progressTracker.estimatedTimeRemaining }

    /// Formatted time remaining (e.g., "2m 30s")
    var formattedTimeRemaining: String? { progressTracker.formattedTimeRemaining }

    /// Whether the engine is currently running
    var isEngineRunning: Bool { engine.isRunning }

    /// Whether network is available
    var isNetworkAvailable: Bool { engine.isNetworkAvailable }

    var isDownloading: Bool { engine.isRunning && !engine.isPaused && activeCount > 0 }
    var isComplete: Bool { totalCount > 0 && completedCount == totalCount }
    var hasFailed: Bool { failedCount > 0 }
    var progressPercentage: Int { Int((overallProgress * 100).rounded()) }

    var statusText: String {
        if !engine.isNetworkAvailable { return "No Network" }
        else if isPaused { return "Paused" }
        else if isComplete { return "Completed" }
        else if activeCount > 0 { return "Downloading \(activeCount) of \(totalCount)" }
        else if failedCount > 0 { return "\(failedCount) failed" }
        else if pendingCount > 0 { return "\(pendingCount) pending" }
        else { return "Ready" }
    }

    var bytesProgressText: String {
        let downloaded = FileManager.formattedSize(downloadedBytes)
        let total = FileManager.formattedSize(totalBytes)
        return "\(downloaded) / \(total)"
    }

    // MARK: - Initialization

    /// Create a download manager with specified concurrency
    /// - Parameter maxConcurrentDownloads: Maximum concurrent downloads (default 3)
    init(maxConcurrentDownloads: Int = 3) {
        self.engine = DownloadEngine(maxConcurrentDownloads: maxConcurrentDownloads)
        self.progressTracker = DownloadProgressTracker()
        self.history = DownloadHistory()
        setupDelegation()
    }

    /// Create a download manager with an existing engine
    /// - Parameters:
    ///   - engine: Existing download engine
    ///   - progressTracker: Progress tracker (optional, creates new instance if nil)
    ///   - history: Download history (optional, creates new instance if nil)
    init(
        engine: DownloadEngine,
        progressTracker: DownloadProgressTracker? = nil,
        history: DownloadHistory? = nil
    ) {
        self.engine = engine
        self.progressTracker = progressTracker ?? DownloadProgressTracker()
        self.history = history ?? DownloadHistory()
        setupDelegation()
    }

    private func setupDelegation() {
        queue.setDelegate(self)
        engine.delegate = self
    }

    // MARK: - Recovery

    /// Recover download state after app relaunch
    ///
    /// This method should be called early in the app lifecycle to:
    /// 1. Restore persisted queue state
    /// 2. Reconcile with background URLSession tasks
    /// 3. Resume interrupted downloads
    ///
    /// - Returns: True if recovery was successful or no recovery was needed
    @discardableResult
    func recoverDownloads() async -> Bool {
        guard !hasRecovered else {
            print("[DownloadManager] Recovery already performed")
            return true
        }

        print("[DownloadManager] Starting download recovery...")

        // 1. Load persisted state
        let restored = await queue.restoreState()
        print("[DownloadManager] Restored state: \(restored)")

        // 2. Check for background session tasks
        let backgroundTasks = await getBackgroundSessionTasks()
        print("[DownloadManager] Found \(backgroundTasks.count) background tasks")

        // 3. Reconcile background tasks with our queue
        await reconcileBackgroundTasks(backgroundTasks)

        // 4. Restore task mappings for the session manager
        await restoreTaskMappings()

        // 5. Update UI
        await refresh()

        hasRecovered = true
        print("[DownloadManager] Recovery complete. Tasks: \(tasks.count)")

        return true
    }

    /// Get pending tasks from background URLSession
    private func getBackgroundSessionTasks() async -> [URLSessionDownloadTask] {
        await BackgroundSessionManager.shared.getPendingTasks()
    }

    /// Reconcile background session tasks with our queue
    ///
    /// This handles cases where:
    /// - Downloads completed while app was terminated
    /// - Downloads are still in progress from background session
    /// - Downloads failed while app was terminated
    private func reconcileBackgroundTasks(_ backgroundTasks: [URLSessionDownloadTask]) async {
        // Get current task IDs that are marked as downloading
        let downloadingTasks = await queue.getTasksWithStatus(.downloading)

        // Check each downloading task
        for task in downloadingTasks {
            // Check if there's a corresponding background task
            let hasBackgroundTask = backgroundTasks.contains { sessionTask in
                // Check if this session task matches our task
                // We need to restore the mapping based on URL
                sessionTask.originalRequest?.url == task.url
            }

            if !hasBackgroundTask {
                // No active background task - check if we have resume data
                let resumeDataManager = await queue.getResumeDataManager()
                if resumeDataManager.hasResumeData(for: task.id) {
                    // Can resume - mark as paused
                    await queue.markPaused(task.id)
                    print("[DownloadManager] Task \(task.id) paused (has resume data)")
                } else {
                    // No resume data - reset to pending for restart
                    await queue.updateTask(task.id) { $0.reset() }
                    print("[DownloadManager] Task \(task.id) reset to pending")
                }
            } else {
                print("[DownloadManager] Task \(task.id) still active in background")
            }
        }
    }

    /// Restore task ID mappings for background session manager
    ///
    /// This allows the session manager to route events to the correct tasks
    /// after app relaunch
    private func restoreTaskMappings() async {
        let backgroundTasks = await BackgroundSessionManager.shared.getPendingTasks()
        let allTasks = await queue.getAllTasks()

        var mappings: [(sessionTaskId: Int, ourTaskId: UUID)] = []

        for sessionTask in backgroundTasks {
            guard let url = sessionTask.originalRequest?.url else { continue }

            // Find matching task by URL
            if let matchingTask = allTasks.first(where: { $0.url == url }) {
                mappings.append((sessionTask.taskIdentifier, matchingTask.id))
            }
        }

        if !mappings.isEmpty {
            BackgroundSessionManager.shared.restoreTaskMappings(tasks: mappings)
            print("[DownloadManager] Restored \(mappings.count) task mappings")
        }
    }

    // MARK: - State Synchronization

    func refresh() async {
        tasks = await queue.getAllTasks()
        updateDerivedState()
    }

    private func updateDerivedState() {
        tasks.sort { ($0.category, $0.partNumber) < ($1.category, $1.partNumber) }

        let grouped = Dictionary(grouping: tasks) { $0.category }
        taskGroups = grouped.map { category, categoryTasks in
            DownloadTaskGroup(category: category, tasks: categoryTasks)
        }.sorted { $0.category < $1.category }

        activeCount = tasks.filter { $0.isActive }.count
        completedCount = tasks.filter { $0.status == .completed }.count
        failedCount = tasks.filter { $0.status == .failed }.count
        pendingCount = tasks.filter { $0.status == .pending }.count
        totalCount = tasks.count

        totalBytes = tasks.reduce(0) { $0 + $1.totalBytes }
        downloadedBytes = tasks.reduce(0) { $0 + $1.bytesDownloaded }

        if totalCount > 0 {
            overallProgress = tasks.reduce(0.0) { $0 + $1.progress } / Double(totalCount)
        } else {
            overallProgress = 0.0
        }
    }

    // MARK: - Queue Operations

    func enqueue(_ task: DownloadTask) async {
        await queue.enqueue(task)
        await refresh()
    }

    func enqueueAll(_ newTasks: [DownloadTask]) async {
        await queue.enqueueAll(newTasks)
        await refresh()
    }

    func remove(_ id: UUID) async {
        await queue.remove(id)
        await refresh()
    }

    func clear() async {
        await queue.clear()
        await refresh()
    }

    // MARK: - Engine Control

    /// Start the download engine
    func startDownloads() async {
        await engine.start()
        isPaused = false
        await refresh()
    }

    /// Pause all active downloads
    func pauseAllDownloads() async {
        await engine.pause()
        isPaused = true
        await refresh()
    }

    /// Resume paused downloads
    func resumeAllDownloads() async {
        await engine.resume()
        isPaused = false
        await refresh()
    }

    /// Stop the download engine
    func stopDownloads() async {
        await engine.stop()
        await refresh()
    }

    // MARK: - Task Control

    func pauseAll() {
        Task {
            await pauseAllDownloads()
        }
    }

    func resumeAll() {
        Task {
            await resumeAllDownloads()
        }
    }

    func retryFailed() {
        Task {
            let failedTasks = await queue.getFailedTasks()
            for task in failedTasks {
                await engine.retryTask(task.id)
            }
            await refresh()
        }
    }

    func retryTask(_ id: UUID) {
        Task {
            await engine.retryTask(id)
            await refresh()
        }
    }

    func pauseTask(_ id: UUID) {
        Task {
            await engine.pauseTask(id)
            await refresh()
        }
    }

    func resumeTask(_ id: UUID) {
        Task {
            await engine.resumeTask(id)
            await refresh()
        }
    }

    func cancelTask(_ id: UUID) {
        Task {
            await engine.cancelTask(id)
            await refresh()
        }
    }

    func prioritizeTask(_ id: UUID) {
        Task {
            await queue.prioritize(id)
            await refresh()
        }
    }

    // MARK: - Task Access

    func getTask(_ id: UUID) -> DownloadTask? {
        tasks.first { $0.id == id }
    }

    func getTasksForCategory(_ category: String) -> [DownloadTask] {
        tasks.filter { $0.category == category }
    }

    func getTaskGroup(for category: String) -> DownloadTaskGroup? {
        taskGroups.first { $0.category == category }
    }

    /// Access to the underlying queue actor
    var queueActor: DownloadQueueActor { queue }

    /// Access to the download engine
    var downloadEngine: DownloadEngine { engine }

    /// Get retry count for a specific task
    func getRetryCount(for taskId: UUID) -> Int {
        engine.getRetryCount(for: taskId)
    }

    // MARK: - Progress Tracker Access

    /// Access to the progress tracker
    var downloadProgressTracker: DownloadProgressTracker { progressTracker }

    /// Get a snapshot of current progress
    func progressSnapshot() -> DownloadProgressTracker.Snapshot {
        progressTracker.snapshot()
    }

    // MARK: - History Access

    /// Access to the download history actor
    var downloadHistory: DownloadHistory { history }

    /// Get download history
    /// - Parameter limit: Maximum entries to return (0 for all)
    func getHistory(limit: Int = 50) async -> [DownloadHistoryEntry] {
        await history.getHistory(limit: limit)
    }

    /// Get download statistics
    func getHistoryStatistics() async -> DownloadHistory.Statistics {
        await history.getStatistics()
    }

    /// Clear download history
    func clearHistory() async {
        await history.clearHistory()
    }

    // MARK: - Persistence

    /// Force save current state to disk
    func persistState() async {
        try? await queue.persistStateImmediately()
    }

    /// Clear persisted state
    func clearPersistedState() async {
        try? await queue.clearPersistedState()
        progressTracker.reset()
    }
}

// MARK: - DownloadEngineDelegate

extension DownloadManager: DownloadEngineDelegate {

    func downloadEngine(_ engine: DownloadEngine, didUpdateTask task: DownloadTask) {
        if let index = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks[index] = task
            updateDerivedState()
        }

        // Update progress tracker
        if task.status == .downloading {
            progressTracker.updateProgress(
                taskId: task.id,
                bytes: task.bytesDownloaded,
                total: task.totalBytes
            )
        }
    }

    func downloadEngine(_ engine: DownloadEngine, didCompleteTask task: DownloadTask) {
        // Update progress tracker
        progressTracker.taskCompleted(task.id)

        // Record in history
        Task {
            await history.recordSuccess(task)
            await refresh()
        }
    }

    func downloadEngine(_ engine: DownloadEngine, didFailTask task: DownloadTask, error: DownloadError) {
        // Update progress tracker
        progressTracker.taskFailed(task.id)

        // Record in history
        Task {
            await history.recordFailure(task, error: error.errorDescription ?? "Unknown error")
            await refresh()
        }
    }

    func downloadEngineDidFinishAllTasks(_ engine: DownloadEngine) {
        // Reset progress tracker when all tasks complete
        progressTracker.reset()

        Task {
            await refresh()
        }
    }

    func downloadEngine(_ engine: DownloadEngine, didChangeRunningState isRunning: Bool) {
        if !isRunning {
            // Engine stopped, reset progress tracker
            progressTracker.reset()
        }

        Task {
            await refresh()
        }
    }

    func downloadEngine(_ engine: DownloadEngine, didChangePausedState isPaused: Bool) {
        self.isPaused = isPaused
    }

    func downloadEngine(_ engine: DownloadEngine, didStartTask task: DownloadTask) {
        if let index = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks[index] = task
            updateDerivedState()
        }

        // Initialize progress tracking for this task
        progressTracker.updateProgress(
            taskId: task.id,
            bytes: task.bytesDownloaded,
            total: task.totalBytes
        )
    }

    func downloadEngine(_ engine: DownloadEngine, networkStatusChanged isConnected: Bool) {
        Task {
            await refresh()
        }
    }
}

// MARK: - DownloadQueueDelegate

extension DownloadManager: DownloadQueueDelegate {

    func queueDidEnqueueTask(_ task: DownloadTask) {
        Task { await refresh() }
    }

    func queueDidRemoveTask(_ id: UUID) {
        Task { await refresh() }
    }

    func queueDidUpdateTask(_ task: DownloadTask) {
        if let index = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks[index] = task
            updateDerivedState()
        }
    }

    func queueDidCompleteTask(_ task: DownloadTask) {
        Task { await refresh() }
    }

    func queueDidFailTask(_ task: DownloadTask, error: String) {
        Task { await refresh() }
    }

    func queueDidChangeActiveCount(_ count: Int) {
        activeCount = count
    }

    func queueDidChangePauseState(_ paused: Bool) {
        isPaused = paused
    }

    func queueDidClear() {
        tasks = []
        taskGroups = []
        updateDerivedState()
    }

    func queueDidComplete() {
        Task { await refresh() }
    }
}

