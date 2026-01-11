import Foundation

/// Protocol for receiving download queue events
///
/// Implement this protocol to receive notifications about download state changes.
/// Useful for updating UI in response to download progress, completions, and failures.
///
/// All methods are optional with default empty implementations.
///
/// Example usage:
/// ```swift
/// class DownloadViewModel: DownloadQueueDelegate {
///     func queueDidUpdateTask(_ task: DownloadTask) {
///         // Update UI with new progress
///     }
///
///     func queueDidCompleteTask(_ task: DownloadTask) {
///         // Show completion notification
///     }
/// }
/// ```
@MainActor
protocol DownloadQueueDelegate: AnyObject {

    /// Called when a task's state changes (progress, status, etc.)
    /// - Parameter task: The updated task
    func queueDidUpdateTask(_ task: DownloadTask)

    /// Called when a task successfully completes
    /// - Parameter task: The completed task
    func queueDidCompleteTask(_ task: DownloadTask)

    /// Called when a task fails
    /// - Parameters:
    ///   - task: The failed task
    ///   - error: Error message describing the failure
    func queueDidFailTask(_ task: DownloadTask, error: String)

    /// Called when the number of active downloads changes
    /// - Parameter count: New number of active downloads
    func queueDidChangeActiveCount(_ count: Int)

    /// Called when all tasks in the queue are completed
    func queueDidComplete()

    /// Called when a task is added to the queue
    /// - Parameter task: The newly added task
    func queueDidEnqueueTask(_ task: DownloadTask)

    /// Called when a task is removed from the queue
    /// - Parameter taskID: ID of the removed task
    func queueDidRemoveTask(_ taskID: UUID)

    /// Called when the queue is cleared
    func queueDidClear()

    /// Called when global pause state changes
    /// - Parameter isPaused: New pause state
    func queueDidChangePauseState(_ isPaused: Bool)
}

// MARK: - Default Implementations

extension DownloadQueueDelegate {

    func queueDidUpdateTask(_ task: DownloadTask) {
        // Default: no-op
    }

    func queueDidCompleteTask(_ task: DownloadTask) {
        // Default: no-op
    }

    func queueDidFailTask(_ task: DownloadTask, error: String) {
        // Default: no-op
    }

    func queueDidChangeActiveCount(_ count: Int) {
        // Default: no-op
    }

    func queueDidComplete() {
        // Default: no-op
    }

    func queueDidEnqueueTask(_ task: DownloadTask) {
        // Default: no-op
    }

    func queueDidRemoveTask(_ taskID: UUID) {
        // Default: no-op
    }

    func queueDidClear() {
        // Default: no-op
    }

    func queueDidChangePauseState(_ isPaused: Bool) {
        // Default: no-op
    }
}
