#if canImport(XCTest)
import Foundation
@testable import SignLanguageTranslate

// MARK: - Mock URLSession Download Task

/// A mock download task for testing without network
final class MockDownloadTask: URLSessionDownloadTask, @unchecked Sendable {
    private let lock = NSLock()

    /// The URL being downloaded
    let downloadURL: URL

    /// Identifier for this task
    private let _taskIdentifier: Int

    override var taskIdentifier: Int {
        _taskIdentifier
    }

    /// Mock state for the task
    private var _mockState: URLSessionTask.State = .suspended

    override var state: URLSessionTask.State {
        lock.lock()
        defer { lock.unlock() }
        return _mockState
    }

    /// Resume data to return when cancelled
    var resumeDataToReturn: Data?

    /// Called when resume() is invoked
    var onResume: (() -> Void)?

    /// Called when suspend() is invoked
    var onSuspend: (() -> Void)?

    /// Called when cancel() is invoked
    var onCancel: (() -> Void)?

    /// Progress of this task (0.0 - 1.0)
    var downloadProgress: Double = 0.0

    /// Total bytes to download
    var totalBytesToDownload: Int64 = 100_000_000

    /// Bytes downloaded so far
    var bytesDownloaded: Int64 {
        Int64(Double(totalBytesToDownload) * downloadProgress)
    }

    init(url: URL, taskIdentifier: Int) {
        self.downloadURL = url
        self._taskIdentifier = taskIdentifier
        super.init()
    }

    override func resume() {
        lock.lock()
        _mockState = .running
        lock.unlock()
        onResume?()
    }

    override func suspend() {
        lock.lock()
        _mockState = .suspended
        lock.unlock()
        onSuspend?()
    }

    override func cancel() {
        lock.lock()
        _mockState = .canceling
        lock.unlock()
        onCancel?()
    }

    override func cancel(byProducingResumeData completionHandler: @escaping @Sendable (Data?) -> Void) {
        lock.lock()
        _mockState = .canceling
        let resumeData = resumeDataToReturn
        lock.unlock()
        completionHandler(resumeData)
        onCancel?()
    }

    /// Simulate task completion
    func simulateComplete() {
        lock.lock()
        _mockState = .completed
        downloadProgress = 1.0
        lock.unlock()
    }

    /// Simulate task failure
    func simulateFailure() {
        lock.lock()
        _mockState = .completed // URLSession marks failed tasks as completed
        lock.unlock()
    }
}

// MARK: - Mock URLSession

/// A mock URLSession for testing downloads without network
final class MockURLSession: @unchecked Sendable {
    private let lock = NSLock()

    /// Download tasks that have been created
    private var _downloadTasks: [Int: MockDownloadTask] = [:]

    /// Counter for generating unique task identifiers
    private var taskIdentifierCounter: Int = 1

    /// Called when a new download task is created
    var onTaskCreated: ((MockDownloadTask) -> Void)?

    /// Delegate for receiving callbacks
    weak var downloadDelegate: URLSessionDownloadDelegate?

    /// Task delegate for completion callbacks
    weak var taskDelegate: URLSessionTaskDelegate?

    /// All created download tasks
    var downloadTasks: [MockDownloadTask] {
        lock.lock()
        defer { lock.unlock() }
        return Array(_downloadTasks.values)
    }

    /// Get task by identifier
    func task(withIdentifier id: Int) -> MockDownloadTask? {
        lock.lock()
        defer { lock.unlock() }
        return _downloadTasks[id]
    }

    /// Create a download task for a URL
    /// - Parameter url: The URL to download
    /// - Returns: A mock download task
    func downloadTask(with url: URL) -> MockDownloadTask {
        lock.lock()
        let taskId = taskIdentifierCounter
        taskIdentifierCounter += 1
        let task = MockDownloadTask(url: url, taskIdentifier: taskId)
        _downloadTasks[taskId] = task
        lock.unlock()

        onTaskCreated?(task)
        return task
    }

    /// Create a download task with resume data
    /// - Parameter resumeData: Previously saved resume data
    /// - Returns: A mock download task
    func downloadTask(withResumeData resumeData: Data) -> MockDownloadTask {
        // In a real session, this would extract the URL from resume data
        // For testing, we create a task with a placeholder URL
        let url = URL(string: "https://example.com/resumed")!

        lock.lock()
        let taskId = taskIdentifierCounter
        taskIdentifierCounter += 1
        let task = MockDownloadTask(url: url, taskIdentifier: taskId)
        _downloadTasks[taskId] = task
        lock.unlock()

        onTaskCreated?(task)
        return task
    }

    /// Simulate progress update for a task
    /// - Parameters:
    ///   - progress: Progress value 0.0 - 1.0
    ///   - taskIdentifier: The task identifier
    func simulateProgress(_ progress: Double, forTaskWithIdentifier taskIdentifier: Int) {
        guard let task = task(withIdentifier: taskIdentifier) else { return }

        task.downloadProgress = progress
        let bytesWritten = task.bytesDownloaded
        let totalBytes = task.totalBytesToDownload

        // Call the optional delegate method for progress updates
        downloadDelegate?.urlSession?(
            URLSession.shared,
            downloadTask: task,
            didWriteData: Int64(Double(totalBytes) * 0.1), // Incremental bytes
            totalBytesWritten: bytesWritten,
            totalBytesExpectedToWrite: totalBytes
        )
    }

    /// Simulate download completion for a task
    /// - Parameters:
    ///   - taskIdentifier: The task identifier
    ///   - fileURL: URL of the downloaded file
    func simulateComplete(forTaskWithIdentifier taskIdentifier: Int, fileURL: URL) {
        guard let task = task(withIdentifier: taskIdentifier) else { return }

        task.simulateComplete()

        downloadDelegate?.urlSession(
            URLSession.shared,
            downloadTask: task,
            didFinishDownloadingTo: fileURL
        )

        // Also call completion delegate
        taskDelegate?.urlSession?(
            URLSession.shared,
            task: task,
            didCompleteWithError: nil
        )
    }

    /// Simulate download failure for a task
    /// - Parameters:
    ///   - taskIdentifier: The task identifier
    ///   - error: The error that occurred
    ///   - resumeData: Optional resume data
    func simulateFailure(forTaskWithIdentifier taskIdentifier: Int, error: Error, resumeData: Data? = nil) {
        guard let task = task(withIdentifier: taskIdentifier) else { return }

        task.simulateFailure()
        task.resumeDataToReturn = resumeData

        var userInfo: [String: Any] = [:]
        if let resumeData = resumeData {
            userInfo[NSURLSessionDownloadTaskResumeData] = resumeData
        }

        let nsError = NSError(
            domain: NSURLErrorDomain,
            code: (error as NSError).code,
            userInfo: userInfo
        )

        taskDelegate?.urlSession?(
            URLSession.shared,
            task: task,
            didCompleteWithError: nsError
        )
    }

    /// Simulate cancellation with resume data
    /// - Parameters:
    ///   - taskIdentifier: The task identifier
    ///   - resumeData: Resume data to return
    func simulatePause(forTaskWithIdentifier taskIdentifier: Int, resumeData: Data?) {
        guard let task = task(withIdentifier: taskIdentifier) else { return }

        task.resumeDataToReturn = resumeData

        var userInfo: [String: Any] = [:]
        if let resumeData = resumeData {
            userInfo[NSURLSessionDownloadTaskResumeData] = resumeData
        }

        let error = NSError(
            domain: NSURLErrorDomain,
            code: NSURLErrorCancelled,
            userInfo: userInfo
        )

        taskDelegate?.urlSession?(
            URLSession.shared,
            task: task,
            didCompleteWithError: error
        )
    }

    /// Reset the mock session (clear all tasks)
    func reset() {
        lock.lock()
        _downloadTasks.removeAll()
        taskIdentifierCounter = 1
        lock.unlock()
    }

    /// Get count of download tasks
    var downloadTaskCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _downloadTasks.count
    }

    /// Get count of running tasks
    var runningTaskCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _downloadTasks.values.filter { $0.state == .running }.count
    }
}

// MARK: - Mock URLSession Configuration

extension MockURLSession {
    /// Create a configuration that mimics background session config
    static func mockBackgroundConfiguration(identifier: String) -> URLSessionConfiguration {
        let config = URLSessionConfiguration.background(withIdentifier: identifier)
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        config.allowsConstrainedNetworkAccess = true
        config.allowsExpensiveNetworkAccess = true
        return config
    }
}
#endif
