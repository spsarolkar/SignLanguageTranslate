import Foundation
import Observation

/// Observable wrapper for the download queue that bridges actor-based state to SwiftUI
@MainActor
@Observable
final class DownloadManager {

    // MARK: - Properties

    private let queue: DownloadQueueActor
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

    var isDownloading: Bool { activeCount > 0 }
    var isComplete: Bool { totalCount > 0 && completedCount == totalCount }
    var hasFailed: Bool { failedCount > 0 }
    var progressPercentage: Int { Int((overallProgress * 100).rounded()) }

    var statusText: String {
        if isPaused { return "Paused" }
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
        self.queue = DownloadQueueActor(maxConcurrentDownloads: maxConcurrentDownloads)
        setupDelegation()
    }

    init(queue: DownloadQueueActor) {
        self.queue = queue
        setupDelegation()
    }

    private func setupDelegation() {
        queue.setDelegate(self)
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

    // MARK: - Task Control

    func pauseAll() {
        Task {
            await queue.pauseAll()
            isPaused = await queue.getIsPaused()
            await refresh()
        }
    }

    func resumeAll() {
        Task {
            await queue.resumeAll()
            isPaused = await queue.getIsPaused()
            await refresh()
        }
    }

    func retryFailed() {
        Task {
            await queue.retryFailed()
            await refresh()
        }
    }

    func retryTask(_ id: UUID) {
        Task {
            await queue.retryTask(id)
            await refresh()
        }
    }

    func pauseTask(_ id: UUID) {
        Task {
            await queue.markPaused(id)
            await refresh()
        }
    }

    func resumeTask(_ id: UUID) {
        Task {
            await queue.markDownloading(id)
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

    var queueActor: DownloadQueueActor { queue }
}

// MARK: - DownloadQueueDelegate

extension DownloadManager: DownloadQueueDelegate {

    nonisolated func queueDidEnqueueTask(_ task: DownloadTask) {
        Task { @MainActor in await refresh() }
    }

    nonisolated func queueDidRemoveTask(_ id: UUID) {
        Task { @MainActor in await refresh() }
    }

    nonisolated func queueDidUpdateTask(_ task: DownloadTask) {
        Task { @MainActor in
            if let index = tasks.firstIndex(where: { $0.id == task.id }) {
                tasks[index] = task
                updateDerivedState()
            }
        }
    }

    nonisolated func queueDidCompleteTask(_ task: DownloadTask) {
        Task { @MainActor in await refresh() }
    }

    nonisolated func queueDidFailTask(_ task: DownloadTask, error: String) {
        Task { @MainActor in await refresh() }
    }

    nonisolated func queueDidChangeActiveCount(_ count: Int) {
        Task { @MainActor in activeCount = count }
    }

    nonisolated func queueDidChangePauseState(_ paused: Bool) {
        Task { @MainActor in isPaused = paused }
    }

    nonisolated func queueDidClear() {
        Task { @MainActor in
            tasks = []
            taskGroups = []
            updateDerivedState()
        }
    }

    nonisolated func queueDidComplete() {
        Task { @MainActor in await refresh() }
    }
}

