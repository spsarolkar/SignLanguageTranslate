//
//  DownloadEngine.swift
//  SignLanguageTranslate
//
//  Created on Phase 4.2 - Download Engine Implementation
//

import Foundation
import Observation
import Combine

/// Core download engine that processes the download queue
///
/// The DownloadEngine is responsible for:
/// - Processing the download queue respecting concurrency limits
/// - Managing download lifecycle (start, pause, resume, cancel)
/// - Handling network status changes
/// - Automatic retry for retryable errors
/// - Coordinating with BackgroundSessionManager for actual downloads
///
/// Architecture:
/// ```
/// ┌─────────────────┐     ┌────────────────────┐
/// │  DownloadEngine │────▶│ BackgroundSession  │
/// │   (Observable)  │     │     Manager        │
/// └────────┬────────┘     └────────────────────┘
///          │
///          ▼
/// ┌────────────────────┐
/// │  DownloadQueueActor│
/// │    (State Mgmt)    │
/// └────────────────────┘
/// ```
@MainActor
@Observable
final class DownloadEngine {

    // MARK: - Observable State

    /// Whether the engine is currently running
    private(set) var isRunning = false

    /// Whether the engine is paused
    private(set) var isPaused = false

    /// Whether network is available
    private(set) var isNetworkAvailable = true

    // MARK: - Configuration

    /// Maximum number of concurrent downloads
    let maxConcurrentDownloads: Int

    /// Maximum retry attempts for retryable errors
    let maxRetryAttempts: Int

    /// Delay between retry attempts (in seconds)
    let retryDelaySeconds: Double

    // MARK: - Dependencies

    /// The download queue actor for state management
    private let queue: DownloadQueueActor

    /// The download coordinator for orchestration
    private let coordinator: DownloadCoordinator

    /// File manager for download file operations
    private let fileManager: DownloadFileManager

    /// Reference to the background session manager
    private var sessionManager: BackgroundSessionManager {
        BackgroundSessionManager.shared
    }

    /// Network monitor for connectivity tracking
    private let networkMonitor: NetworkMonitor

    // MARK: - Internal State

    /// Retry counts per task
    private var retryCounts: [UUID: Int] = [:]

    /// Processing task
    private var processingTask: Task<Void, Never>?

    /// Network observation cancellable (nonisolated to allow access in deinit)
    private nonisolated(unsafe) var networkCancellable: AnyCancellable?

    /// Delegate for engine events
    weak var delegate: DownloadEngineDelegate?

    // MARK: - Callbacks for BackgroundSessionManager

    /// Called when download progress is updated
    var onProgress: ((UUID, Int64, Int64) -> Void)?

    /// Called when download completes
    var onComplete: ((UUID, URL) -> Void)?

    /// Called when download fails
    var onFailed: ((UUID, Error, Data?) -> Void)?

    // MARK: - Initialization

    /// Create a download engine
    /// - Parameters:
    ///   - maxConcurrentDownloads: Maximum concurrent downloads (default 3)
    ///   - maxRetryAttempts: Maximum retry attempts (default 3)
    ///   - retryDelaySeconds: Delay between retries (default 2.0)
    init(
        maxConcurrentDownloads: Int = 3,
        maxRetryAttempts: Int = 3,
        retryDelaySeconds: Double = 2.0
    ) {
        self.maxConcurrentDownloads = maxConcurrentDownloads
        self.maxRetryAttempts = maxRetryAttempts
        self.retryDelaySeconds = retryDelaySeconds

        self.queue = DownloadQueueActor(maxConcurrentDownloads: maxConcurrentDownloads)
        self.fileManager = DownloadFileManager()
        self.coordinator = DownloadCoordinator(queue: queue, fileManager: fileManager)
        self.networkMonitor = NetworkMonitor.shared

        setupCallbacks()
        setupNetworkMonitoring()
    }

    /// Create a download engine with existing queue
    /// - Parameters:
    ///   - queue: Existing download queue actor
    ///   - maxConcurrentDownloads: Maximum concurrent downloads (default 3)
    ///   - maxRetryAttempts: Maximum retry attempts (default 3)
    ///   - retryDelaySeconds: Delay between retries (default 2.0)
    init(
        queue: DownloadQueueActor,
        maxConcurrentDownloads: Int = 3,
        maxRetryAttempts: Int = 3,
        retryDelaySeconds: Double = 2.0
    ) {
        self.maxConcurrentDownloads = maxConcurrentDownloads
        self.maxRetryAttempts = maxRetryAttempts
        self.retryDelaySeconds = retryDelaySeconds

        self.queue = queue
        self.fileManager = DownloadFileManager()
        self.coordinator = DownloadCoordinator(queue: queue, fileManager: fileManager)
        self.networkMonitor = NetworkMonitor.shared

        setupCallbacks()
        setupNetworkMonitoring()
    }

    deinit {
        networkCancellable?.cancel()
    }

    // MARK: - Setup

    private func setupCallbacks() {
        // Set up callbacks that forward to coordinator
        onProgress = { [weak self] taskId, bytes, total in
            guard let self = self else { return }
            Task { @MainActor in
                await self.handleDownloadProgress(taskId: taskId, bytes: bytes, total: total)
            }
        }

        onComplete = { [weak self] taskId, fileURL in
            guard let self = self else { return }
            Task { @MainActor in
                await self.handleDownloadComplete(taskId: taskId, fileURL: fileURL)
            }
        }

        onFailed = { [weak self] taskId, error, resumeData in
            guard let self = self else { return }
            Task { @MainActor in
                await self.handleDownloadFailed(taskId: taskId, error: error, resumeData: resumeData)
            }
        }
    }

    private func setupNetworkMonitoring() {
        networkMonitor.start()

        networkCancellable = networkMonitor.isConnectedPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isConnected in
                guard let self = self else { return }
                Task { @MainActor in
                    await self.handleNetworkStatusChange(isConnected: isConnected)
                }
            }
    }

    // MARK: - Control Methods

    /// Start the download engine
    func start() async {
        guard !isRunning else { return }

        isRunning = true
        isPaused = false

        // Start the coordinator
        await coordinator.start()

        // Start queue processing
        startProcessing()

        delegate?.downloadEngine(self, didChangeRunningState: true)

        print("[DownloadEngine] Started")
    }

    /// Pause all active downloads
    func pause() async {
        guard isRunning && !isPaused else { return }

        isPaused = true

        // Pause all active downloads
        await coordinator.pauseAll()

        delegate?.downloadEngine(self, didChangePausedState: true)

        print("[DownloadEngine] Paused")
    }

    /// Resume paused downloads
    func resume() async {
        guard isRunning && isPaused else { return }

        isPaused = false

        // Resume queue processing
        await coordinator.resumeAll()

        // Trigger queue processing
        await processQueue()

        delegate?.downloadEngine(self, didChangePausedState: false)

        print("[DownloadEngine] Resumed")
    }

    /// Stop the download engine
    func stop() async {
        guard isRunning else { return }

        isRunning = false
        isPaused = false

        // Stop processing
        processingTask?.cancel()
        processingTask = nil

        // Stop coordinator
        await coordinator.stop()

        delegate?.downloadEngine(self, didChangeRunningState: false)

        print("[DownloadEngine] Stopped")
    }

    // MARK: - Queue Processing

    /// Start periodic queue processing
    private func startProcessing() {
        processingTask?.cancel()
        processingTask = Task {
            while !Task.isCancelled && isRunning {
                if !isPaused && isNetworkAvailable {
                    await processQueue()
                }
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            }
        }
    }

    /// Process the queue to start pending downloads
    private func processQueue() async {
        guard isRunning && !isPaused && isNetworkAvailable else { return }

        // Keep starting downloads while we can
        while await startNextDownload() {
            // Continue starting downloads
        }

        // Check if all tasks are complete
        let tasks = await queue.getAllTasks()
        let allComplete = tasks.allSatisfy { $0.status == .completed }
        let anyPending = tasks.contains { $0.status == .pending || $0.status == .downloading }

        if !tasks.isEmpty && allComplete && !anyPending {
            delegate?.downloadEngineDidFinishAllTasks(self)
        }
    }

    /// Start the next available download
    /// - Returns: True if a download was started, false otherwise
    private func startNextDownload() async -> Bool {
        guard await queue.canStartMoreDownloads() else { return false }
        guard let task = await queue.getNextPendingTask() else { return false }

        // Validate network
        guard isNetworkAvailable else {
            print("[DownloadEngine] No network available, waiting...")
            return false
        }

        // Validate storage space
        if task.totalBytes > 0 {
            let available = fileManager.availableStorageSpace()
            if !fileManager.hasStorageSpace(for: task.totalBytes) {
                let error = DownloadError.insufficientStorage(required: task.totalBytes, available: available)
                await queue.markFailed(task.id, error: error.errorDescription ?? "Insufficient storage")
                delegate?.downloadEngine(self, didFailTask: task, error: error)
                return true // Continue processing other tasks
            }
        }

        // Start the download
        await coordinator.startTask(task.id)

        // Notify delegate
        if let updatedTask = await queue.getTask(task.id) {
            delegate?.downloadEngine(self, didStartTask: updatedTask)
        }

        return true
    }

    // MARK: - Event Handlers

    /// Handle download progress update
    func handleDownloadProgress(taskId: UUID, bytes: Int64, total: Int64) async {
        await coordinator.handleProgressUpdate(taskId: taskId, bytesWritten: bytes, totalBytes: total)

        if let task = await queue.getTask(taskId) {
            delegate?.downloadEngine(self, didUpdateTask: task)
        }
    }

    /// Handle download completion
    func handleDownloadComplete(taskId: UUID, fileURL: URL) async {
        // Reset retry count on success
        retryCounts.removeValue(forKey: taskId)

        await coordinator.handleDownloadComplete(taskId: taskId, tempFileURL: fileURL)

        if let task = await queue.getTask(taskId) {
            delegate?.downloadEngine(self, didCompleteTask: task)
        }

        // Process queue for next download
        await processQueue()
    }

    /// Handle download failure
    func handleDownloadFailed(taskId: UUID, error: Error, resumeData: Data?) async {
        let downloadError = DownloadError.from(error)

        // Check if we should retry
        if downloadError.isRetryable {
            let currentRetries = retryCounts[taskId] ?? 0

            if currentRetries < maxRetryAttempts {
                retryCounts[taskId] = currentRetries + 1
                print("[DownloadEngine] Retrying task \(taskId) (attempt \(currentRetries + 1)/\(maxRetryAttempts))")

                // Save resume data if available
                if let resumeData = resumeData {
                    do {
                        _ = try fileManager.saveResumeData(resumeData, for: taskId)
                    } catch {
                        print("[DownloadEngine] Failed to save resume data: \(error)")
                    }
                }

                // Delay before retry
                try? await Task.sleep(nanoseconds: UInt64(retryDelaySeconds * 1_000_000_000))

                // Retry the task
                await coordinator.retryTask(taskId)
                await processQueue()
                return
            } else {
                // Max retries exceeded
                let maxRetryError = DownloadError.maxRetriesExceeded(attempts: maxRetryAttempts)
                await coordinator.handleDownloadFailed(taskId: taskId, error: maxRetryError, resumeData: resumeData)

                if let task = await queue.getTask(taskId) {
                    delegate?.downloadEngine(self, didFailTask: task, error: maxRetryError)
                }
            }
        } else {
            // Not retryable, mark as failed
            await coordinator.handleDownloadFailed(taskId: taskId, error: error, resumeData: resumeData)

            if let task = await queue.getTask(taskId) {
                delegate?.downloadEngine(self, didFailTask: task, error: downloadError)
            }
        }

        // Clean up retry count
        retryCounts.removeValue(forKey: taskId)

        // Process queue for next download
        await processQueue()
    }

    /// Handle network status change
    private func handleNetworkStatusChange(isConnected: Bool) async {
        let wasConnected = isNetworkAvailable
        isNetworkAvailable = isConnected

        delegate?.downloadEngine(self, networkStatusChanged: isConnected)

        if !isConnected && wasConnected {
            // Network lost - pause active downloads
            print("[DownloadEngine] Network lost, pausing downloads...")

            // Save resume data for active downloads
            let activeTasks = await queue.getActiveTasks()
            for task in activeTasks where task.status == .downloading {
                if let resumeData = await sessionManager.pauseDownload(taskId: task.id) {
                    do {
                        _ = try fileManager.saveResumeData(resumeData, for: task.id)
                    } catch {
                        print("[DownloadEngine] Failed to save resume data for \(task.id): \(error)")
                    }
                }
                await queue.markPaused(task.id)
            }
        } else if isConnected && !wasConnected && isRunning && !isPaused {
            // Network restored - resume processing
            print("[DownloadEngine] Network restored, resuming downloads...")
            await processQueue()
        }
    }

    // MARK: - Single Task Control

    /// Pause a specific task
    /// - Parameter id: Task ID to pause
    func pauseTask(_ id: UUID) async {
        await coordinator.pauseTask(id)

        if let task = await queue.getTask(id) {
            delegate?.downloadEngine(self, didUpdateTask: task)
        }
    }

    /// Resume a specific task
    /// - Parameter id: Task ID to resume
    func resumeTask(_ id: UUID) async {
        await coordinator.resumeTask(id)

        if let task = await queue.getTask(id) {
            delegate?.downloadEngine(self, didUpdateTask: task)
        }

        await processQueue()
    }

    /// Cancel a specific task
    /// - Parameter id: Task ID to cancel
    func cancelTask(_ id: UUID) async {
        await coordinator.cancelTask(id)
        retryCounts.removeValue(forKey: id)

        await processQueue()
    }

    /// Retry a specific failed task
    /// - Parameter id: Task ID to retry
    func retryTask(_ id: UUID) async {
        retryCounts.removeValue(forKey: id)
        await coordinator.retryTask(id)

        if let task = await queue.getTask(id) {
            delegate?.downloadEngine(self, didUpdateTask: task)
        }

        await processQueue()
    }

    // MARK: - Queue Access

    /// Get the download queue actor
    var queueActor: DownloadQueueActor { queue }

    /// Get the download coordinator
    var downloadCoordinator: DownloadCoordinator { coordinator }

    /// Get all tasks
    func getAllTasks() async -> [DownloadTask] {
        await queue.getAllTasks()
    }

    /// Get a specific task
    func getTask(_ id: UUID) async -> DownloadTask? {
        await queue.getTask(id)
    }

    /// Enqueue a single task
    func enqueue(_ task: DownloadTask) async {
        await queue.enqueue(task)
    }

    /// Enqueue multiple tasks
    func enqueueAll(_ tasks: [DownloadTask]) async {
        await queue.enqueueAll(tasks)
    }

    /// Clear all tasks
    func clearAll() async {
        await coordinator.cancelAll()
        retryCounts.removeAll()
    }

    // MARK: - Retry Management

    /// Get retry count for a task
    func getRetryCount(for taskId: UUID) -> Int {
        retryCounts[taskId] ?? 0
    }

    /// Reset retry count for a task
    func resetRetryCount(for taskId: UUID) {
        retryCounts.removeValue(forKey: taskId)
    }

    /// Reset all retry counts
    func resetAllRetryCounts() {
        retryCounts.removeAll()
    }
}
