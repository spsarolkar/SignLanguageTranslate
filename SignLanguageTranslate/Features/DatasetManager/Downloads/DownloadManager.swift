import Foundation
import Observation

/// Observable wrapper for the download queue that bridges actor-based state to SwiftUI
///
/// The DownloadManager provides a SwiftUI-friendly interface to the download system:
/// - Observable properties for binding to views
/// - Methods for controlling downloads
/// - Integration with DownloadEngine for actual download processing
@MainActor
@Observable
final class DownloadManager {

    // MARK: - Properties

    /// The download engine for processing downloads
    private let engine: DownloadEngine

    /// The download queue actor for state management
    private var queue: DownloadQueueActor { engine.queueActor }

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

    init(maxConcurrentDownloads: Int = 3) {
        self.engine = DownloadEngine(maxConcurrentDownloads: maxConcurrentDownloads)
        setupDelegation()
    }

    init(engine: DownloadEngine) {
        self.engine = engine
        setupDelegation()
    }

    private func setupDelegation() {
        queue.setDelegate(self)
        engine.delegate = self
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
}

// MARK: - DownloadEngineDelegate

extension DownloadManager: DownloadEngineDelegate {

    func downloadEngine(_ engine: DownloadEngine, didUpdateTask task: DownloadTask) {
        if let index = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks[index] = task
            updateDerivedState()
        }
    }

    func downloadEngine(_ engine: DownloadEngine, didCompleteTask task: DownloadTask) {
        Task {
            await refresh()
        }
    }

    func downloadEngine(_ engine: DownloadEngine, didFailTask task: DownloadTask, error: DownloadError) {
        Task {
            await refresh()
        }
    }

    func downloadEngineDidFinishAllTasks(_ engine: DownloadEngine) {
        Task {
            await refresh()
        }
    }

    func downloadEngine(_ engine: DownloadEngine, didChangeRunningState isRunning: Bool) {
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

