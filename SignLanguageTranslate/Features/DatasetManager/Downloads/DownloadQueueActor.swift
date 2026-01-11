import Foundation

/// Thread-safe actor for managing download queue state
///
/// This actor provides thread-safe management of download tasks with:
/// - Concurrency limiting (max 3 simultaneous downloads by default)
/// - Queue ordering and prioritization
/// - Progress aggregation
/// - State persistence
///
/// This actor manages STATE only - it does NOT perform actual networking.
/// The download engine calls methods on this actor to update state.
///
/// Example usage:
/// ```swift
/// let queue = DownloadQueueActor(maxConcurrentDownloads: 3)
///
/// // Add tasks
/// await queue.enqueue(task)
///
/// // Start next download
/// if let next = await queue.getNextPendingTask() {
///     await queue.markDownloading(next.id)
///     // ... start actual download ...
/// }
///
/// // Update progress
/// await queue.updateProgress(id: taskID, bytesDownloaded: 1000, totalBytes: 5000)
///
/// // Complete
/// await queue.markCompleted(taskID)
/// ```
actor DownloadQueueActor {

    // MARK: - Properties

    /// All tasks indexed by ID for O(1) lookup
    private var tasks: [UUID: DownloadTask] = [:]

    /// Ordered list of task IDs (determines download order)
    private var queue: [UUID] = []

    /// Maximum number of concurrent downloads allowed
    private var maxConcurrentDownloads: Int

    /// Whether the queue is globally paused
    private var isPaused: Bool = false

    /// Optional delegate for queue events (stored as nonisolated unsafe for cross-actor access)
    private nonisolated(unsafe) weak var _delegate: (any DownloadQueueDelegate)?

    /// Persistence actor for saving/loading state
    private let persistence: DownloadStatePersistence

    /// Resume data manager for managing resume data files
    private let resumeDataManager: ResumeDataManager

    /// Whether state has been modified since last save
    private var isDirty: Bool = false

    // MARK: - Initialization

    /// Create a download queue actor
    /// - Parameters:
    ///   - maxConcurrentDownloads: Maximum concurrent downloads (default 3)
    ///   - persistence: State persistence actor (default creates new instance)
    ///   - resumeDataManager: Resume data manager (default creates new instance)
    init(
        maxConcurrentDownloads: Int = 3,
        persistence: DownloadStatePersistence = DownloadStatePersistence(),
        resumeDataManager: ResumeDataManager = ResumeDataManager()
    ) {
        self.maxConcurrentDownloads = maxConcurrentDownloads
        self.persistence = persistence
        self.resumeDataManager = resumeDataManager
    }

    // MARK: - Delegate Management

    /// Set the delegate for queue events
    /// - Parameter delegate: Delegate to receive events
    nonisolated func setDelegate(_ delegate: (any DownloadQueueDelegate)?) {
        _delegate = delegate
    }

    private func notifyDelegate(_ block: @escaping @MainActor @Sendable (any DownloadQueueDelegate) -> Void) {
        guard let delegate = _delegate else { return }
        Task { @MainActor in
            block(delegate)
        }
    }

    // MARK: - Queue Management

    /// Add a single task to the queue
    /// - Parameter task: Task to add
    func enqueue(_ task: DownloadTask) {
        guard tasks[task.id] == nil else {
            // Task already exists, don't add duplicate
            return
        }

        tasks[task.id] = task
        queue.append(task.id)

        notifyDelegate { delegate in
            delegate.queueDidEnqueueTask(task)
        }

        markDirty()
    }

    /// Add multiple tasks to the queue
    /// - Parameter newTasks: Tasks to add
    func enqueueAll(_ newTasks: [DownloadTask]) {
        var added = false

        for task in newTasks {
            guard tasks[task.id] == nil else { continue }

            tasks[task.id] = task
            queue.append(task.id)
            added = true

            notifyDelegate { delegate in
                delegate.queueDidEnqueueTask(task)
            }
        }

        if added {
            markDirty()
        }
    }

    /// Remove a task from the queue
    /// - Parameter id: Task ID to remove
    func remove(_ id: UUID) {
        guard tasks[id] != nil else { return }

        // Clean up resume data for this task
        resumeDataManager.delete(for: id)

        tasks.removeValue(forKey: id)
        queue.removeAll { $0 == id }

        notifyDelegate { delegate in
            delegate.queueDidRemoveTask(id)
        }

        markDirty()
    }

    /// Remove all tasks from the queue
    func clear() {
        // Clean up all resume data
        let taskIds = Array(tasks.keys)
        resumeDataManager.delete(for: taskIds)

        tasks.removeAll()
        queue.removeAll()

        notifyDelegate { delegate in
            delegate.queueDidClear()
        }

        markDirty()
    }

    /// Reorder a task to a specific index in the queue
    /// - Parameters:
    ///   - taskID: Task ID to move
    ///   - toIndex: Destination index
    func reorder(taskID: UUID, toIndex: Int) {
        guard tasks[taskID] != nil else { return }
        guard let currentIndex = queue.firstIndex(of: taskID) else { return }

        // Clamp to valid range
        let newIndex = min(max(0, toIndex), queue.count - 1)
        guard currentIndex != newIndex else { return }

        queue.remove(at: currentIndex)
        queue.insert(taskID, at: newIndex)
    }

    /// Move a task to the front of the pending queue
    /// - Parameter id: Task ID to prioritize
    func prioritize(_ id: UUID) {
        guard let task = tasks[id] else { return }
        guard task.status == .pending || task.status == .queued else { return }
        guard let currentIndex = queue.firstIndex(of: id) else { return }

        // Find first pending/queued task
        let firstPendingIndex = queue.firstIndex { taskID in
            if let t = tasks[taskID] {
                return t.status == .pending || t.status == .queued
            }
            return false
        } ?? 0

        guard currentIndex != firstPendingIndex else { return }

        queue.remove(at: currentIndex)
        queue.insert(id, at: firstPendingIndex)
    }

    // MARK: - Task State

    /// Get a task by ID
    /// - Parameter id: Task ID
    /// - Returns: Task if found
    func getTask(_ id: UUID) -> DownloadTask? {
        tasks[id]
    }

    /// Get all tasks
    /// - Returns: Array of all tasks
    func getAllTasks() -> [DownloadTask] {
        Array(tasks.values)
    }

    /// Update a task using a transform closure
    /// - Parameters:
    ///   - id: Task ID
    ///   - transform: Closure to modify the task
    func updateTask(_ id: UUID, transform: @Sendable (inout DownloadTask) -> Void) {
        guard var task = tasks[id] else { return }

        let previousActiveCount = getActiveCount()

        transform(&task)
        tasks[id] = task

        let newActiveCount = getActiveCount()

        notifyDelegate { delegate in
            delegate.queueDidUpdateTask(task)

            if previousActiveCount != newActiveCount {
                delegate.queueDidChangeActiveCount(newActiveCount)
            }
        }
    }

    // MARK: - Filtering

    /// Get tasks with a specific status
    /// - Parameter status: Status to filter by
    /// - Returns: Tasks with that status
    func getTasksWithStatus(_ status: DownloadTaskStatus) -> [DownloadTask] {
        tasks.values.filter { $0.status == status }
    }

    /// Get all pending tasks
    func getPendingTasks() -> [DownloadTask] {
        getTasksWithStatus(.pending)
    }

    /// Get all active tasks (downloading or extracting)
    func getActiveTasks() -> [DownloadTask] {
        tasks.values.filter { $0.isActive }
    }

    /// Get all completed tasks
    func getCompletedTasks() -> [DownloadTask] {
        getTasksWithStatus(.completed)
    }

    /// Get all failed tasks
    func getFailedTasks() -> [DownloadTask] {
        getTasksWithStatus(.failed)
    }

    /// Get all tasks for a specific category
    /// - Parameter category: Category name
    /// - Returns: Tasks in that category
    func getTasksForCategory(_ category: String) -> [DownloadTask] {
        tasks.values.filter { $0.category == category }
    }

    // MARK: - Progress Updates

    /// Update download progress for a task
    /// - Parameters:
    ///   - id: Task ID
    ///   - bytesDownloaded: Bytes downloaded so far
    ///   - totalBytes: Total bytes (if known)
    func updateProgress(id: UUID, bytesDownloaded: Int64, totalBytes: Int64) {
        updateTask(id) { task in
            task.updateProgress(bytesDownloaded: bytesDownloaded, totalBytes: totalBytes)
        }
    }

    /// Mark a task as downloading
    /// - Parameter id: Task ID
    func markDownloading(_ id: UUID) {
        updateTask(id) { task in
            task.start()
        }
    }

    /// Mark a task as paused
    /// - Parameter id: Task ID
    func markPaused(_ id: UUID) {
        updateTask(id) { task in
            task.pause()
        }
    }

    /// Mark a task as extracting
    /// - Parameter id: Task ID
    func markExtracting(_ id: UUID) {
        updateTask(id) { task in
            task.startExtracting()
        }
    }

    /// Mark a task as completed
    /// - Parameter id: Task ID
    func markCompleted(_ id: UUID) {
        guard let task = tasks[id] else { return }

        updateTask(id) { downloadTask in
            downloadTask.complete()
        }

        // Check if all tasks are complete (must be done before notifying)
        let allTasksCompleted = tasks.values.allSatisfy { $0.status == .completed }

        notifyDelegate { delegate in
            delegate.queueDidCompleteTask(task)

            // Notify if all tasks are complete
            if allTasksCompleted {
                delegate.queueDidComplete()
            }
        }
    }

    /// Mark a task as failed
    /// - Parameters:
    ///   - id: Task ID
    ///   - error: Error message
    func markFailed(_ id: UUID, error errorMessage: String) {
        guard var task = tasks[id] else { return }

        // Update the task directly instead of using updateTask closure
        let previousActiveCount = getActiveCount()
        task.fail(with: errorMessage)
        tasks[id] = task

        let newActiveCount = getActiveCount()
        let updatedTask = task
        let message = errorMessage

        notifyDelegate { delegate in
            delegate.queueDidUpdateTask(updatedTask)

            if previousActiveCount != newActiveCount {
                delegate.queueDidChangeActiveCount(newActiveCount)
            }

            delegate.queueDidFailTask(updatedTask, error: message)
        }
    }

    /// Set resume data path for a task
    /// - Parameters:
    ///   - id: Task ID
    ///   - path: Path to resume data file (nil to clear)
    func setResumeDataPath(_ id: UUID, path resumeDataPath: String?) {
        updateTask(id) { downloadTask in
            if let filePath = resumeDataPath {
                downloadTask.saveResumeData(at: filePath)
            } else {
                downloadTask.clearResumeData()
            }
        }
    }

    // MARK: - Queue Control

    /// Pause all active downloads
    func pauseAll() {
        isPaused = true

        let activeTasks = getActiveTasks()
        for task in activeTasks where task.canPause {
            updateTask(task.id) { $0.pause() }
        }

        notifyDelegate { delegate in
            delegate.queueDidChangePauseState(true)
        }
    }

    /// Resume all paused downloads
    func resumeAll() {
        isPaused = false

        notifyDelegate { delegate in
            delegate.queueDidChangePauseState(false)
        }
    }

    /// Reset all failed tasks to pending
    func retryFailed() {
        let failedTasks = getFailedTasks()
        for task in failedTasks {
            updateTask(task.id) { $0.reset() }
        }
    }

    /// Reset a specific failed task to pending
    /// - Parameter id: Task ID
    func retryTask(_ id: UUID) {
        guard let task = tasks[id], task.status == .failed else { return }

        updateTask(id) { $0.reset() }
    }

    // MARK: - Queue Queries

    /// Get the next pending task to start
    ///
    /// Returns nil if:
    /// - Queue is globally paused
    /// - Already at max concurrent downloads
    /// - No pending tasks available
    ///
    /// - Returns: Next task to start, or nil
    func getNextPendingTask() -> DownloadTask? {
        guard !isPaused else { return nil }
        guard canStartMoreDownloads() else { return nil }

        // Find first pending task in queue order
        for taskID in queue {
            guard let task = tasks[taskID] else { continue }
            if task.status == .pending {
                return task
            }
        }

        return nil
    }

    /// Check if more downloads can be started
    /// - Returns: True if active count < max concurrent
    func canStartMoreDownloads() -> Bool {
        getActiveCount() < maxConcurrentDownloads
    }

    /// Get number of active tasks
    func getActiveCount() -> Int {
        tasks.values.filter { $0.isActive }.count
    }

    /// Get number of pending tasks
    func getPendingCount() -> Int {
        tasks.values.filter { $0.status == .pending }.count
    }

    /// Get number of completed tasks
    func getCompletedCount() -> Int {
        tasks.values.filter { $0.status == .completed }.count
    }

    /// Get total number of tasks
    func getTotalCount() -> Int {
        tasks.count
    }

    /// Get global pause state
    func getIsPaused() -> Bool {
        isPaused
    }

    // MARK: - Aggregated Progress

    /// Get overall progress across all tasks
    /// - Returns: Progress from 0.0 to 1.0
    func getOverallProgress() -> Double {
        guard !tasks.isEmpty else { return 0.0 }

        let totalProgress = tasks.values.reduce(0.0) { $0 + $1.progress }
        return totalProgress / Double(tasks.count)
    }

    /// Get total bytes across all tasks
    func getTotalBytes() -> Int64 {
        tasks.values.reduce(0) { $0 + $1.totalBytes }
    }

    /// Get downloaded bytes across all tasks
    func getDownloadedBytes() -> Int64 {
        tasks.values.reduce(0) { $0 + $1.bytesDownloaded }
    }

    /// Get progress for a specific category
    /// - Parameter category: Category name
    /// - Returns: Progress from 0.0 to 1.0
    func getCategoryProgress(_ category: String) -> Double {
        let categoryTasks = getTasksForCategory(category)
        guard !categoryTasks.isEmpty else { return 0.0 }

        let totalProgress = categoryTasks.reduce(0.0) { $0 + $1.progress }
        return totalProgress / Double(categoryTasks.count)
    }

    // MARK: - Persistence

    /// Export current queue state as data
    /// - Returns: JSON data representing current state
    func exportState() throws -> Data {
        let state = DownloadQueueState(
            tasks: Array(tasks.values),
            queueOrder: queue,
            isPaused: isPaused,
            maxConcurrentDownloads: maxConcurrentDownloads
        )

        return try state.toData()
    }

    /// Import queue state from data
    /// - Parameter data: JSON data to import
    /// - Throws: Decoding or validation error
    func importState(_ data: Data) throws {
        let state = try DownloadQueueState.fromData(data)

        // Validate before importing
        let errors = state.validate()
        guard errors.isEmpty else {
            throw DownloadQueueError.invalidState(errors: errors)
        }

        // Clear current state
        tasks.removeAll()
        queue.removeAll()

        // Import new state
        for task in state.tasks {
            tasks[task.id] = task
        }
        queue = state.queueOrder
        isPaused = state.isPaused
        maxConcurrentDownloads = state.maxConcurrentDownloads
    }

    /// Import queue state directly
    /// - Parameter state: State to import
    /// - Throws: Validation error
    func importState(_ state: DownloadQueueState) throws {
        // Validate before importing
        let errors = state.validate()
        guard errors.isEmpty else {
            throw DownloadQueueError.invalidState(errors: errors)
        }

        // Clear current state
        tasks.removeAll()
        queue.removeAll()

        // Import new state
        for task in state.tasks {
            tasks[task.id] = task
        }
        queue = state.queueOrder
        isPaused = state.isPaused
        maxConcurrentDownloads = state.maxConcurrentDownloads
    }

    // MARK: - Configuration

    /// Update max concurrent downloads
    /// - Parameter max: New maximum (must be > 0)
    func setMaxConcurrentDownloads(_ max: Int) {
        guard max > 0 else { return }
        maxConcurrentDownloads = max
    }

    /// Get max concurrent downloads
    func getMaxConcurrentDownloads() -> Int {
        maxConcurrentDownloads
    }

    // MARK: - Persistence Integration

    /// Persist current state to disk
    ///
    /// This method is called automatically on significant state changes.
    /// It uses debounced saving to avoid excessive disk I/O.
    func persistState() async {
        let state = DownloadQueueState(
            tasks: Array(tasks.values),
            queueOrder: queue,
            isPaused: isPaused,
            maxConcurrentDownloads: maxConcurrentDownloads
        )

        await persistence.scheduleSave(state: state)
        isDirty = false
    }

    /// Force immediate state save
    func persistStateImmediately() async throws {
        let state = DownloadQueueState(
            tasks: Array(tasks.values),
            queueOrder: queue,
            isPaused: isPaused,
            maxConcurrentDownloads: maxConcurrentDownloads
        )

        try await persistence.save(state: state)
        isDirty = false
    }

    /// Restore state from disk
    ///
    /// Called on app launch to recover download state.
    /// This method also reconciles resume data with task state.
    ///
    /// - Returns: True if state was restored, false if no saved state
    @discardableResult
    func restoreState() async -> Bool {
        // Load and validate persisted state
        guard let state = await persistence.loadValidated() else {
            return false
        }

        // Import the state
        do {
            try await importStateInternal(state)
        } catch {
            print("[DownloadQueueActor] Failed to restore state: \(error.localizedDescription)")
            return false
        }

        // Reconcile resume data with task state
        await reconcileResumeData()

        // Clean up orphaned files
        let validTaskIds = Set(tasks.keys)
        resumeDataManager.cleanupOrphaned(validTaskIds: validTaskIds)

        return true
    }

    /// Import state without validation (internal use)
    private func importStateInternal(_ state: DownloadQueueState) async throws {
        // Clear current state
        tasks.removeAll()
        queue.removeAll()

        // Import new state
        for task in state.tasks {
            tasks[task.id] = task
        }
        queue = state.queueOrder
        isPaused = state.isPaused
        maxConcurrentDownloads = state.maxConcurrentDownloads

        isDirty = false
    }

    /// Reconcile resume data files with task state
    ///
    /// Ensures tasks marked as paused have valid resume data,
    /// and tasks without resume data are marked appropriately.
    private func reconcileResumeData() async {
        for (taskId, var task) in tasks {
            if task.status == .paused || task.status == .downloading {
                // Check if resume data exists
                if resumeDataManager.hasResumeData(for: taskId) {
                    // Verify resume data path is set
                    if task.resumeDataPath == nil {
                        task.resumeDataPath = resumeDataManager.filePath(for: taskId)
                        tasks[taskId] = task
                    }
                } else {
                    // No resume data - if downloading, reset to pending
                    // If paused without resume data, reset to pending
                    if task.status == .downloading || (task.status == .paused && task.resumeDataPath != nil) {
                        task.status = .pending
                        task.resumeDataPath = nil
                        tasks[taskId] = task
                    }
                }
            }
        }
    }

    /// Check if state has unsaved changes
    func hasUnsavedChanges() -> Bool {
        isDirty
    }

    /// Clear persisted state from disk
    func clearPersistedState() async throws {
        try await persistence.clear()
    }

    /// Get the resume data manager
    func getResumeDataManager() -> ResumeDataManager {
        resumeDataManager
    }

    /// Mark state as dirty (needs saving)
    private func markDirty() {
        isDirty = true

        // Schedule debounced save
        Task {
            await persistState()
        }
    }

    /// Save resume data for a task
    /// - Parameters:
    ///   - data: Resume data from URLSession
    ///   - taskId: Task identifier
    /// - Throws: File system error
    func saveResumeData(_ data: Data, for taskId: UUID) throws {
        let url = try resumeDataManager.save(data, for: taskId)

        // Update task with resume data path
        updateTask(taskId) { task in
            task.resumeDataPath = url.path
        }
    }

    /// Load resume data for a task
    /// - Parameter taskId: Task identifier
    /// - Returns: Resume data if available
    func loadResumeData(for taskId: UUID) throws -> Data? {
        try resumeDataManager.load(for: taskId)
    }

    /// Delete resume data for a task
    /// - Parameter taskId: Task identifier
    func deleteResumeData(for taskId: UUID) {
        resumeDataManager.delete(for: taskId)

        // Clear resume data path from task
        updateTask(taskId) { task in
            task.resumeDataPath = nil
        }
    }

    /// Check if resume data exists for a task
    /// - Parameter taskId: Task identifier
    /// - Returns: True if resume data exists
    func hasResumeData(for taskId: UUID) -> Bool {
        resumeDataManager.hasResumeData(for: taskId)
    }

    /// Get all task IDs that have resume data available
    func getTasksWithResumeData() -> Set<UUID> {
        Set(resumeDataManager.allTaskIds())
    }
}

// MARK: - Errors

/// Errors that can occur in download queue operations
enum DownloadQueueError: LocalizedError, Sendable {
    case invalidState(errors: [String])
    case taskNotFound(id: UUID)
    case invalidOperation(message: String)

    var errorDescription: String? {
        switch self {
        case .invalidState(let errors):
            return "Invalid queue state: \(errors.joined(separator: ", "))"
        case .taskNotFound(let id):
            return "Task not found: \(id)"
        case .invalidOperation(let message):
            return "Invalid operation: \(message)"
        }
    }
}
