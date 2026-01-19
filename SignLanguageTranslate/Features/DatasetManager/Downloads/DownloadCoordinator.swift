import Foundation

/// Coordinates between BackgroundSessionManager and DownloadQueueActor
///
/// This actor bridges the background download system with our queue management:
/// - Processes the download queue to start pending downloads
/// - Handles download completion, progress, and failure events
/// - Manages file operations through DownloadFileManager
/// - Enforces concurrent download limits
///
/// Architecture:
/// ```
/// ┌────────────────────┐      ┌─────────────────────┐
/// │ BackgroundSession  │ ───▶ │  DownloadCoordinator │
/// │     Manager        │      │       (actor)        │
/// └────────────────────┘      └──────────┬──────────┘
///                                        │
///                    ┌───────────────────┼───────────────────┐
///                    ▼                   ▼                   ▼
///           ┌────────────────┐  ┌────────────────┐  ┌────────────────┐
///           │ DownloadQueue  │  │ DownloadFile   │  │ DownloadManager│
///           │    Actor       │  │   Manager      │  │    (UI)        │
///           └────────────────┘  └────────────────┘  └────────────────┘
/// ```
actor DownloadCoordinator {

    // MARK: - Properties

    /// The download queue actor for state management
    private let queue: DownloadQueueActor

    /// File manager for download file operations
    private let fileManager: DownloadFileManager

    /// Reference to the background session manager
    private var sessionManager: BackgroundSessionManager {
        BackgroundSessionManager.shared
    }

    /// Whether the coordinator is currently processing the queue
    private var isProcessing = false

    /// Timer for periodic queue processing (when app is in foreground)
    private var processingTask: Task<Void, Never>?

    // MARK: - Initialization

    /// Create a download coordinator
    /// - Parameters:
    ///   - queue: The download queue actor
    ///   - fileManager: The file manager (defaults to new instance)
    init(queue: DownloadQueueActor, fileManager: DownloadFileManager = DownloadFileManager()) {
        self.queue = queue
        self.fileManager = fileManager
    }

    /// Start the coordinator and connect to the session manager
    func start() {
        // Connect to session manager (must be done on main thread due to weak reference)
        Task { @MainActor in
            BackgroundSessionManager.shared.coordinator = self
        }
        // NOTE: Queue processing is handled by DownloadEngine, not here
        // to avoid duplicate processing and race conditions
    }

    /// Stop the coordinator
    func stop() {
        processingTask?.cancel()
        processingTask = nil
    }

    // MARK: - Queue Processing

    // NOTE: startProcessing() removed - DownloadEngine handles queue processing
    // The coordinator only handles individual task operations and callbacks

    /// Process the queue to start pending downloads
    ///
    /// This method:
    /// 1. Checks if we can start more downloads
    /// 2. Gets the next pending task
    /// 3. Validates storage space
    /// 4. Starts the download
    func processQueue() async {
        guard !isProcessing else { return }

        isProcessing = true
        defer { isProcessing = false }

        // Keep starting downloads while we can
        while await queue.canStartMoreDownloads() {
            guard let task = await queue.getNextPendingTask() else {
                // No more pending tasks
                break
            }

            // Check storage space
            if task.totalBytes > 0 {
                let available = fileManager.availableStorageSpace()
                if !fileManager.hasStorageSpace(for: task.totalBytes) {
                    await queue.markFailed(
                        task.id,
                        error: "Insufficient storage: \(FileManager.formattedSize(task.totalBytes)) required, \(FileManager.formattedSize(available)) available"
                    )
                    continue
                }
            }

            // Check for existing resume data
            if let resumeDataPath = task.resumeDataPath,
               let resumeData = try? fileManager.loadResumeData(for: task.id) {
                // Resume from saved data
                await queue.markDownloading(task.id)
                sessionManager.resumeDownload(resumeData: resumeData, taskId: task.id)
                // Delete resume data file since it's now in use
                fileManager.deleteResumeData(for: task.id)
                await queue.setResumeDataPath(task.id, path: nil)
            } else {
                // Start fresh download
                await queue.markDownloading(task.id)
                sessionManager.startDownload(url: task.url, taskId: task.id)
            }
        }
    }

    // MARK: - Download Event Handlers

    /// Handle download completion
    /// - Parameters:
    ///   - taskId: Our internal task ID
    ///   - tempFileURL: Temporary file location from URLSession
    func handleDownloadComplete(taskId: UUID, tempFileURL: URL) async {
        guard let task = await queue.getTask(taskId) else {
            // Task was removed, clean up temp file
            FileManager.default.safeDelete(at: tempFileURL)
            return
        }

        do {
            // Move file to permanent location
            let permanentURL = try fileManager.moveCompletedDownload(from: tempFileURL, for: task)

            // Clean up any resume data
            fileManager.deleteResumeData(for: taskId)

            // Mark as extracting (next phase will handle actual extraction)
            await queue.markExtracting(taskId)

            // For now, immediately mark as completed
            // TODO: Phase 4.x will add actual ZIP extraction here
            await queue.markCompleted(taskId)

            // NOTE: Queue processing is handled by DownloadEngine's loop, not here

        } catch {
            // File move failed
            await queue.markFailed(taskId, error: "Failed to save download: \(error.localizedDescription)")
            // NOTE: Queue processing is handled by DownloadEngine's loop, not here
        }
    }

    /// Handle download progress update
    /// - Parameters:
    ///   - taskId: Our internal task ID
    ///   - bytesWritten: Total bytes written so far
    ///   - totalBytes: Expected total bytes (-1 if unknown)
    func handleProgressUpdate(taskId: UUID, bytesWritten: Int64, totalBytes: Int64) async {
        // URLSession reports -1 for unknown total
        let actualTotal = totalBytes > 0 ? totalBytes : 0

        await queue.updateProgress(
            id: taskId,
            bytesDownloaded: bytesWritten,
            totalBytes: actualTotal
        )
    }

    /// Handle download failure
    /// - Parameters:
    ///   - taskId: Our internal task ID
    ///   - error: The error that occurred
    ///   - resumeData: Resume data if available
    func handleDownloadFailed(taskId: UUID, error: Error, resumeData: Data?) async {
        // Save resume data if available
        if let resumeData = resumeData {
            do {
                let url = try fileManager.saveResumeData(resumeData, for: taskId)
                await queue.setResumeDataPath(taskId, path: url.path)
            } catch {
                // Failed to save resume data, continue with failure
            }
        }

        // Mark task as failed
        let errorMessage = humanReadableError(error)
        await queue.markFailed(taskId, error: errorMessage)

        // NOTE: Queue processing is handled by DownloadEngine's loop, not here
    }

    /// Handle download pause (with resume data)
    /// - Parameters:
    ///   - taskId: Our internal task ID
    ///   - resumeData: Resume data if available
    func handleDownloadPaused(taskId: UUID, resumeData: Data?) async {
        // Save resume data if available
        if let resumeData = resumeData {
            do {
                let url = try fileManager.saveResumeData(resumeData, for: taskId)
                await queue.setResumeDataPath(taskId, path: url.path)
            } catch {
                // Failed to save resume data
            }
        }

        await queue.markPaused(taskId)
    }

    // MARK: - User Actions

    /// Start downloading a specific task
    /// - Parameter taskId: Task ID to start
    func startTask(_ taskId: UUID) async {
        guard let task = await queue.getTask(taskId) else { return }
        guard task.canStart else { return }

        // Check storage space
        if task.totalBytes > 0 && !fileManager.hasStorageSpace(for: task.totalBytes) {
            let available = fileManager.availableStorageSpace()
            await queue.markFailed(
                taskId,
                error: "Insufficient storage: \(FileManager.formattedSize(task.totalBytes)) required, \(FileManager.formattedSize(available)) available"
            )
            return
        }

        // Check for resume data
        if let resumeDataPath = task.resumeDataPath,
           let resumeData = try? fileManager.loadResumeData(for: taskId) {
            await queue.markDownloading(taskId)
            sessionManager.resumeDownload(resumeData: resumeData, taskId: taskId)
            fileManager.deleteResumeData(for: taskId)
            await queue.setResumeDataPath(taskId, path: nil)
        } else {
            await queue.markDownloading(taskId)
            sessionManager.startDownload(url: task.url, taskId: taskId)
        }
    }

    /// Pause a downloading task
    /// - Parameter taskId: Task ID to pause
    func pauseTask(_ taskId: UUID) async {
        guard let task = await queue.getTask(taskId) else { return }
        guard task.canPause else { return }

        // Request pause from session manager
        if let resumeData = await sessionManager.pauseDownload(taskId: taskId) {
            do {
                let url = try fileManager.saveResumeData(resumeData, for: taskId)
                await queue.setResumeDataPath(taskId, path: url.path)
            } catch {
                // Failed to save resume data, but still mark as paused
            }
        }

        await queue.markPaused(taskId)
    }

    /// Resume a paused task
    /// - Parameter taskId: Task ID to resume
    func resumeTask(_ taskId: UUID) async {
        await startTask(taskId)
    }

    /// Cancel and remove a task
    /// - Parameter taskId: Task ID to cancel
    func cancelTask(_ taskId: UUID) async {
        // Cancel download if active
        sessionManager.cancelDownload(taskId: taskId)

        // Clean up files
        fileManager.deleteResumeData(for: taskId)
        if let task = await queue.getTask(taskId) {
            fileManager.deleteCompletedDownload(for: task)
        }

        // Remove from queue
        await queue.remove(taskId)
    }

    /// Abort a download without removing it from the queue
    /// - Parameter taskId: Task ID to abort
    func abortDownload(_ taskId: UUID) async {
        // Cancel download if active
        sessionManager.cancelDownload(taskId: taskId)
        
        // Clean up resume data as we are aborting
        fileManager.deleteResumeData(for: taskId)
        
        // Note: We don't remove from queue as this is used when we are about to mark it completed manually
    }

    /// Retry a failed task
    /// - Parameter taskId: Task ID to retry
    func retryTask(_ taskId: UUID) async {
        guard let task = await queue.getTask(taskId) else { return }
        guard task.status == .failed else { return }

        // Clean up any stale resume data
        fileManager.deleteResumeData(for: taskId)

        // Reset task to pending - engine's loop will restart it
        await queue.retryTask(taskId)
        // NOTE: Queue processing is handled by DownloadEngine's loop, not here
    }

    /// Pause all active downloads
    func pauseAll() async {
        let activeTasks = await queue.getActiveTasks()

        for task in activeTasks where task.status == .downloading {
            await pauseTask(task.id)
        }

        await queue.pauseAll()
    }

    /// Resume all paused downloads
    func resumeAll() async {
        await queue.resumeAll()
        // NOTE: Queue processing is handled by DownloadEngine's loop, not here
    }

    /// Cancel all downloads
    func cancelAll() async {
        sessionManager.cancelAllDownloads()

        // Clean up all files
        let tasks = await queue.getAllTasks()
        for task in tasks {
            fileManager.deleteResumeData(for: task.id)
            fileManager.deleteCompletedDownload(for: task)
        }

        await queue.clear()
    }

    // MARK: - Restoration

    /// Restore state after app relaunch
    /// Call this after restoring queue state from persistence
    func restoreAfterRelaunch() async {
        // Clean up orphaned files
        let tasks = await queue.getAllTasks()
        let validIds = Set(tasks.map { $0.id })
        fileManager.cleanupOrphanedFiles(validTaskIds: validIds)

        // NOTE: Queue processing is handled by DownloadEngine's loop, not here
    }

    // MARK: - Helpers

    /// Convert error to human-readable message
    private func humanReadableError(_ error: Error) -> String {
        let nsError = error as NSError

        // Handle common network errors
        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorNotConnectedToInternet:
                return "No internet connection"
            case NSURLErrorNetworkConnectionLost:
                return "Network connection lost"
            case NSURLErrorTimedOut:
                return "Request timed out"
            case NSURLErrorCannotFindHost:
                return "Server not found"
            case NSURLErrorCannotConnectToHost:
                return "Cannot connect to server"
            case NSURLErrorSecureConnectionFailed:
                return "Secure connection failed"
            case NSURLErrorServerCertificateUntrusted:
                return "Server certificate untrusted"
            case NSURLErrorInternationalRoamingOff:
                return "International roaming is off"
            case NSURLErrorDataNotAllowed:
                return "Cellular data not allowed"
            case NSURLErrorFileDoesNotExist:
                return "File not found on server"
            default:
                break
            }
        }

        // Fall back to localized description
        return error.localizedDescription
    }

    // MARK: - Storage Info

    /// Get available storage space
    func availableStorage() -> Int64 {
        fileManager.availableStorageSpace()
    }

    /// Check if there's enough storage for remaining downloads
    func hasStorageForRemainingDownloads() async -> Bool {
        let pendingTasks = await queue.getPendingTasks()
        let totalRequired = pendingTasks.reduce(Int64(0)) { $0 + $1.totalBytes }
        return fileManager.hasStorageSpace(for: totalRequired)
    }
}
