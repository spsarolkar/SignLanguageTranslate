import Foundation

/// Singleton manager for background URLSession downloads
///
/// This manager handles background download operations that continue even when
/// the app is suspended or terminated. It manages the URLSession lifecycle and
/// maintains mappings between download tasks and their identifiers.
///
/// Usage:
/// ```swift
/// let task = BackgroundSessionManager.shared.startDownload(url: url, taskId: id)
/// // ... later ...
/// BackgroundSessionManager.shared.cancelDownload(taskId: id)
/// ```
///
/// Background Session Lifecycle:
/// 1. App starts download → creates URLSessionDownloadTask
/// 2. App goes to background → system continues download
/// 3. Download completes → system wakes app
/// 4. AppDelegate receives `handleEventsForBackgroundURLSession`
/// 5. Delegate methods called → `urlSessionDidFinishEvents` called
/// 6. App calls stored `backgroundCompletionHandler`
final class BackgroundSessionManager: NSObject {

    // MARK: - Singleton

    /// Shared singleton instance
    static let shared = BackgroundSessionManager()

    // MARK: - Properties

    /// Unique identifier for the background session
    private let sessionIdentifier = "com.signlanguage.translate.background-downloads"

    /// The background URLSession configured for downloads
    private(set) lazy var session: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: sessionIdentifier)

        // Don't wait for optimal conditions (WiFi, charging)
        config.isDiscretionary = false

        // Wake app when events occur in background
        config.sessionSendsLaunchEvents = true

        // Allow downloads on cellular/constrained networks
        config.allowsConstrainedNetworkAccess = true

        // Allow downloads on expensive networks (cellular)
        config.allowsExpensiveNetworkAccess = true

        // Reasonable timeout for network operations
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 60 * 60 * 24 // 24 hours for large files

        // HTTP additional headers (useful for some servers)
        config.httpAdditionalHeaders = [
            "Accept": "*/*",
            "Accept-Encoding": "gzip, deflate"
        ]

        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    /// Completion handler provided by the system for background events
    /// Must be called after all background events are processed
    var backgroundCompletionHandler: (() -> Void)?

    /// Active download tasks mapped by task UUID
    /// Key: Our internal task UUID, Value: URLSessionDownloadTask
    private var activeDownloads: [UUID: URLSessionDownloadTask] = [:]

    /// Reverse mapping from URLSessionTask identifier to our task UUID
    /// Key: URLSessionTask.taskIdentifier, Value: Our internal task UUID
    private var taskIdMapping: [Int: UUID] = [:]

    /// Lock for thread-safe access to download mappings
    private let lock = NSLock()

    /// Coordinator for handling download events
    /// Set by DownloadCoordinator during initialization
    weak var coordinator: DownloadCoordinator?

    // MARK: - Initialization

    private override init() {
        super.init()
        // Force lazy initialization of session
        _ = session
    }

    // MARK: - Download Management

    /// Start a new download
    /// - Parameters:
    ///   - url: URL to download from
    ///   - taskId: Our internal task UUID for tracking
    /// - Returns: The URLSessionDownloadTask that was created
    @discardableResult
    func startDownload(url: URL, taskId: UUID) -> URLSessionDownloadTask {
        lock.lock()
        defer { lock.unlock() }

        // Cancel any existing download for this task
        if let existingTask = activeDownloads[taskId] {
            existingTask.cancel()
        }

        let downloadTask = session.downloadTask(with: url)

        activeDownloads[taskId] = downloadTask
        taskIdMapping[downloadTask.taskIdentifier] = taskId

        downloadTask.resume()

        return downloadTask
    }

    /// Pause a download and return resume data
    /// - Parameter taskId: Our internal task UUID
    /// - Returns: Resume data if available, nil otherwise
    func pauseDownload(taskId: UUID) async -> Data? {
        let downloadTask: URLSessionDownloadTask? = lock.withLock {
            activeDownloads[taskId]
        }

        guard let task = downloadTask else {
            return nil
        }

        return await withCheckedContinuation { continuation in
            task.cancel { resumeData in
                self.lock.lock()
                self.activeDownloads.removeValue(forKey: taskId)
                if let mapping = self.taskIdMapping.first(where: { $0.value == taskId }) {
                    self.taskIdMapping.removeValue(forKey: mapping.key)
                }
                self.lock.unlock()

                continuation.resume(returning: resumeData)
            }
        }
    }

    /// Resume a download with previously saved resume data
    /// - Parameters:
    ///   - resumeData: Data from a previous pause operation
    ///   - taskId: Our internal task UUID
    /// - Returns: The URLSessionDownloadTask that was created
    @discardableResult
    func resumeDownload(resumeData: Data, taskId: UUID) -> URLSessionDownloadTask {
        lock.lock()
        defer { lock.unlock() }

        // Cancel any existing download for this task
        if let existingTask = activeDownloads[taskId] {
            existingTask.cancel()
        }

        let downloadTask = session.downloadTask(withResumeData: resumeData)

        activeDownloads[taskId] = downloadTask
        taskIdMapping[downloadTask.taskIdentifier] = taskId

        downloadTask.resume()

        return downloadTask
    }

    /// Cancel a download
    /// - Parameter taskId: Our internal task UUID
    func cancelDownload(taskId: UUID) {
        lock.lock()
        defer { lock.unlock() }

        guard let downloadTask = activeDownloads[taskId] else {
            return
        }

        downloadTask.cancel()
        activeDownloads.removeValue(forKey: taskId)
        taskIdMapping.removeValue(forKey: downloadTask.taskIdentifier)
    }

    /// Cancel all active downloads
    func cancelAllDownloads() {
        lock.lock()
        let tasks = Array(activeDownloads.values)
        activeDownloads.removeAll()
        taskIdMapping.removeAll()
        lock.unlock()

        for task in tasks {
            task.cancel()
        }
    }

    // MARK: - Internal Helpers

    /// Get our internal task UUID from a URLSessionTask
    /// - Parameter sessionTask: The URLSessionTask
    /// - Returns: Our internal task UUID, if found
    func getTaskId(for sessionTask: URLSessionTask) -> UUID? {
        lock.lock()
        defer { lock.unlock() }
        return taskIdMapping[sessionTask.taskIdentifier]
    }

    /// Remove task from active downloads
    /// - Parameter taskId: Our internal task UUID
    func removeTask(_ taskId: UUID) {
        lock.lock()
        defer { lock.unlock() }

        if let downloadTask = activeDownloads[taskId] {
            taskIdMapping.removeValue(forKey: downloadTask.taskIdentifier)
        }
        activeDownloads.removeValue(forKey: taskId)
    }

    /// Get count of active downloads
    var activeDownloadCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return activeDownloads.count
    }

    /// Check if a task is currently downloading
    /// - Parameter taskId: Our internal task UUID
    /// - Returns: True if the task is in the active downloads
    func isDownloading(taskId: UUID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return activeDownloads[taskId] != nil
    }

    /// Restore task mappings after app relaunch
    /// Called when the app is relaunched due to background session events
    func restoreTaskMappings(tasks: [(sessionTaskId: Int, ourTaskId: UUID)]) {
        lock.lock()
        defer { lock.unlock() }

        for (sessionTaskId, ourTaskId) in tasks {
            taskIdMapping[sessionTaskId] = ourTaskId
        }
    }
}

// MARK: - URLSessionDelegate

extension BackgroundSessionManager: URLSessionDelegate {

    /// Called when all events for a background session have been delivered
    /// This is the signal that we should call the system's completion handler
    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        DispatchQueue.main.async { [weak self] in
            self?.backgroundCompletionHandler?()
            self?.backgroundCompletionHandler = nil
        }
    }

    /// Called when the session becomes invalid
    func urlSession(_ session: URLSession, didBecomeInvalidWithError error: Error?) {
        if let error = error {
            print("[BackgroundSessionManager] Session became invalid with error: \(error.localizedDescription)")
        }
    }
}

// MARK: - URLSessionDownloadDelegate

extension BackgroundSessionManager: URLSessionDownloadDelegate {

    /// Called when a download task completes successfully
    /// The file at `location` is temporary and must be moved immediately
    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let taskId = getTaskId(for: downloadTask) else {
            print("[BackgroundSessionManager] Received completion for unknown task")
            return
        }

        // Notify coordinator on main actor
        Task { @MainActor in
            await coordinator?.handleDownloadComplete(taskId: taskId, tempFileURL: location)
        }
    }

    /// Called periodically during download with progress updates
    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard let taskId = getTaskId(for: downloadTask) else {
            return
        }

        // Notify coordinator on main actor
        Task { @MainActor in
            await coordinator?.handleProgressUpdate(
                taskId: taskId,
                bytesWritten: totalBytesWritten,
                totalBytes: totalBytesExpectedToWrite
            )
        }
    }

    /// Called when download resumes (e.g., after pause)
    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didResumeAtOffset fileOffset: Int64,
        expectedTotalBytes: Int64
    ) {
        guard let taskId = getTaskId(for: downloadTask) else {
            return
        }

        print("[BackgroundSessionManager] Task \(taskId) resumed at offset \(fileOffset)")

        // Update progress with resumed offset
        Task { @MainActor in
            await coordinator?.handleProgressUpdate(
                taskId: taskId,
                bytesWritten: fileOffset,
                totalBytes: expectedTotalBytes
            )
        }
    }
}

// MARK: - URLSessionTaskDelegate

extension BackgroundSessionManager: URLSessionTaskDelegate {

    /// Called when a task completes (success or failure)
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let taskId = getTaskId(for: task) else {
            return
        }

        // Remove from active downloads
        removeTask(taskId)

        guard let error = error else {
            // Success case is handled by didFinishDownloadingTo
            return
        }

        // Handle error
        let nsError = error as NSError

        // Check for resume data in case of cancellation or network error
        let resumeData = nsError.userInfo[NSURLSessionDownloadTaskResumeData] as? Data

        // Check if this was a user-initiated cancellation
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
            // User cancelled - don't report as failure if we have resume data
            if resumeData != nil {
                Task { @MainActor in
                    await coordinator?.handleDownloadPaused(taskId: taskId, resumeData: resumeData)
                }
                return
            }
        }

        // Report failure to coordinator
        Task { @MainActor in
            await coordinator?.handleDownloadFailed(
                taskId: taskId,
                error: error,
                resumeData: resumeData
            )
        }
    }
}
