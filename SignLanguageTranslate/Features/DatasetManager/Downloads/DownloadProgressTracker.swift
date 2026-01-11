import Foundation
import Observation

/// Observable class for tracking and aggregating download progress
///
/// This class provides real-time progress tracking with:
/// - Per-task progress monitoring
/// - Download rate calculation with smoothing
/// - Estimated time remaining (ETA) calculation
/// - Aggregated progress across all tasks
///
/// The tracker uses a rolling window approach for calculating download rates,
/// providing smooth estimates that aren't affected by momentary fluctuations.
///
/// Usage:
/// ```swift
/// let tracker = DownloadProgressTracker()
///
/// // Update progress as downloads occur
/// tracker.updateProgress(taskId: id, bytes: 1024, total: 10240)
///
/// // Access aggregated stats
/// print("Progress: \(tracker.progressPercentage)%")
/// print("Speed: \(tracker.formattedDownloadRate)")
/// print("ETA: \(tracker.formattedTimeRemaining ?? "Calculating...")")
/// ```
@MainActor
@Observable
final class DownloadProgressTracker {

    // MARK: - Types

    /// Progress data for a single task
    struct TaskProgress: Sendable {
        /// Bytes downloaded so far
        var bytesDownloaded: Int64

        /// Total bytes to download (0 if unknown)
        var totalBytes: Int64

        /// When progress was last updated
        var lastUpdate: Date

        /// Calculated download rate in bytes per second
        var downloadRate: Double

        /// Previous bytes for rate calculation
        var previousBytes: Int64

        /// Previous update time for rate calculation
        var previousUpdate: Date?

        /// Progress as fraction (0.0 to 1.0)
        var progress: Double {
            guard totalBytes > 0 else { return 0.0 }
            return min(1.0, Double(bytesDownloaded) / Double(totalBytes))
        }

        init(
            bytesDownloaded: Int64 = 0,
            totalBytes: Int64 = 0,
            lastUpdate: Date = Date(),
            downloadRate: Double = 0.0
        ) {
            self.bytesDownloaded = bytesDownloaded
            self.totalBytes = totalBytes
            self.lastUpdate = lastUpdate
            self.downloadRate = downloadRate
            self.previousBytes = 0
            self.previousUpdate = nil
        }
    }

    /// Sample for rolling rate calculation
    private struct RateSample {
        let bytes: Int64
        let timestamp: Date
    }

    // MARK: - Properties

    /// Per-task progress tracking
    private var taskProgress: [UUID: TaskProgress] = [:]

    /// Rolling samples for rate calculation
    private var rateSamples: [RateSample] = []

    /// Maximum number of samples to keep
    private let maxSamples = 10

    /// Minimum sample interval to avoid noise
    private let minSampleInterval: TimeInterval = 0.5

    /// Last sample timestamp
    private var lastSampleTime: Date?

    // MARK: - Observable Properties

    /// Overall progress across all tasks (0.0 to 1.0)
    private(set) var overallProgress: Double = 0.0

    /// Total bytes downloaded across all tasks
    private(set) var totalBytesDownloaded: Int64 = 0

    /// Total bytes expected across all tasks
    private(set) var totalBytesExpected: Int64 = 0

    /// Estimated time remaining in seconds
    private(set) var estimatedTimeRemaining: TimeInterval?

    /// Current download rate in bytes per second
    private(set) var currentDownloadRate: Double = 0.0

    /// Number of active downloads
    private(set) var activeTaskCount: Int = 0

    // MARK: - Computed Properties

    /// Overall progress as percentage (0-100)
    var progressPercentage: Int {
        Int((overallProgress * 100).rounded())
    }

    /// Formatted download rate (e.g., "2.5 MB/s")
    var formattedDownloadRate: String {
        formatBytesPerSecond(currentDownloadRate)
    }

    /// Formatted time remaining (e.g., "2m 30s" or "1h 15m")
    var formattedTimeRemaining: String? {
        guard let seconds = estimatedTimeRemaining, seconds > 0, seconds.isFinite else {
            return nil
        }

        let totalSeconds = Int(seconds)

        if totalSeconds < 60 {
            return "\(totalSeconds)s"
        } else if totalSeconds < 3600 {
            let minutes = totalSeconds / 60
            let secs = totalSeconds % 60
            return "\(minutes)m \(secs)s"
        } else {
            let hours = totalSeconds / 3600
            let minutes = (totalSeconds % 3600) / 60
            return "\(hours)h \(minutes)m"
        }
    }

    /// Formatted bytes progress (e.g., "125.5 MB / 1.2 GB")
    var formattedBytesProgress: String {
        let downloaded = FileManager.formattedSize(totalBytesDownloaded)
        let total = FileManager.formattedSize(totalBytesExpected)
        return "\(downloaded) / \(total)"
    }

    /// Whether any downloads are in progress
    var isActive: Bool {
        activeTaskCount > 0
    }

    // MARK: - Public Methods

    /// Update progress for a specific task
    /// - Parameters:
    ///   - taskId: The task identifier
    ///   - bytes: Bytes downloaded so far
    ///   - total: Total bytes (0 if unknown)
    func updateProgress(taskId: UUID, bytes: Int64, total: Int64) {
        let now = Date()

        var progress = taskProgress[taskId] ?? TaskProgress()

        // Calculate instantaneous rate
        if let prevUpdate = progress.previousUpdate {
            let elapsed = now.timeIntervalSince(prevUpdate)
            if elapsed > 0 {
                let bytesDelta = bytes - progress.previousBytes
                let instantRate = Double(bytesDelta) / elapsed

                // Smooth the rate using exponential moving average
                let smoothingFactor = 0.3
                progress.downloadRate = progress.downloadRate * (1 - smoothingFactor) + instantRate * smoothingFactor
            }
        }

        progress.previousBytes = progress.bytesDownloaded
        progress.previousUpdate = progress.lastUpdate

        progress.bytesDownloaded = bytes
        progress.totalBytes = total
        progress.lastUpdate = now

        taskProgress[taskId] = progress

        // Add rate sample for overall rate calculation
        addRateSample(bytes: bytes, timestamp: now)

        // Recalculate aggregates
        recalculateAggregates()
    }

    /// Mark a task as completed
    /// - Parameter taskId: The task identifier
    func taskCompleted(_ taskId: UUID) {
        guard var progress = taskProgress[taskId] else { return }

        // Set to 100% complete
        progress.bytesDownloaded = progress.totalBytes
        progress.downloadRate = 0

        taskProgress[taskId] = progress

        recalculateAggregates()
    }

    /// Mark a task as failed
    /// - Parameter taskId: The task identifier
    func taskFailed(_ taskId: UUID) {
        taskProgress.removeValue(forKey: taskId)
        recalculateAggregates()
    }

    /// Remove a task from tracking
    /// - Parameter taskId: The task identifier
    func removeTask(_ taskId: UUID) {
        taskProgress.removeValue(forKey: taskId)
        recalculateAggregates()
    }

    /// Reset all tracking data
    func reset() {
        taskProgress.removeAll()
        rateSamples.removeAll()
        lastSampleTime = nil

        overallProgress = 0.0
        totalBytesDownloaded = 0
        totalBytesExpected = 0
        estimatedTimeRemaining = nil
        currentDownloadRate = 0.0
        activeTaskCount = 0
    }

    /// Get progress for a specific task
    /// - Parameter taskId: The task identifier
    /// - Returns: Task progress if tracked
    func getProgress(for taskId: UUID) -> TaskProgress? {
        taskProgress[taskId]
    }

    /// Get all tracked task IDs
    /// - Returns: Set of tracked task IDs
    func getTrackedTaskIds() -> Set<UUID> {
        Set(taskProgress.keys)
    }

    // MARK: - Private Methods

    /// Add a sample for rolling rate calculation
    private func addRateSample(bytes: Int64, timestamp: Date) {
        // Throttle samples to avoid noise
        if let lastTime = lastSampleTime {
            guard timestamp.timeIntervalSince(lastTime) >= minSampleInterval else {
                return
            }
        }

        // Calculate total bytes at this moment
        let totalCurrentBytes = taskProgress.values.reduce(0) { $0 + $1.bytesDownloaded }

        rateSamples.append(RateSample(bytes: totalCurrentBytes, timestamp: timestamp))
        lastSampleTime = timestamp

        // Trim old samples
        if rateSamples.count > maxSamples {
            rateSamples.removeFirst(rateSamples.count - maxSamples)
        }
    }

    /// Recalculate all aggregate values
    private func recalculateAggregates() {
        // Calculate totals
        totalBytesDownloaded = taskProgress.values.reduce(0) { $0 + $1.bytesDownloaded }
        totalBytesExpected = taskProgress.values.reduce(0) { $0 + $1.totalBytes }

        // Calculate overall progress
        if totalBytesExpected > 0 {
            overallProgress = min(1.0, Double(totalBytesDownloaded) / Double(totalBytesExpected))
        } else {
            overallProgress = 0.0
        }

        // Count active tasks (those still downloading)
        activeTaskCount = taskProgress.values.filter { progress in
            progress.bytesDownloaded < progress.totalBytes || progress.totalBytes == 0
        }.count

        // Calculate overall download rate
        currentDownloadRate = calculateOverallDownloadRate()

        // Calculate ETA
        estimatedTimeRemaining = calculateETA()
    }

    /// Calculate overall download rate using rolling samples
    private func calculateOverallDownloadRate() -> Double {
        guard rateSamples.count >= 2 else {
            // Fall back to sum of per-task rates
            return taskProgress.values.reduce(0.0) { $0 + $1.downloadRate }
        }

        // Use first and last samples for rate calculation
        guard let first = rateSamples.first,
              let last = rateSamples.last else {
            return 0.0
        }

        let elapsed = last.timestamp.timeIntervalSince(first.timestamp)
        guard elapsed > 0 else { return 0.0 }

        let bytesDelta = last.bytes - first.bytes
        return Double(bytesDelta) / elapsed
    }

    /// Calculate estimated time remaining
    private func calculateETA() -> TimeInterval? {
        guard currentDownloadRate > 0 else {
            return nil
        }

        let bytesRemaining = totalBytesExpected - totalBytesDownloaded
        guard bytesRemaining > 0 else {
            return nil
        }

        let eta = Double(bytesRemaining) / currentDownloadRate

        // Sanity check: cap at 24 hours
        guard eta < 86400 else {
            return nil
        }

        return eta
    }

    /// Format bytes per second to human-readable string
    private func formatBytesPerSecond(_ bytesPerSecond: Double) -> String {
        let bytes = Int64(bytesPerSecond)

        if bytes < 1024 {
            return "\(bytes) B/s"
        } else if bytes < 1024 * 1024 {
            return String(format: "%.1f KB/s", bytesPerSecond / 1024)
        } else if bytes < 1024 * 1024 * 1024 {
            return String(format: "%.1f MB/s", bytesPerSecond / (1024 * 1024))
        } else {
            return String(format: "%.1f GB/s", bytesPerSecond / (1024 * 1024 * 1024))
        }
    }
}

// MARK: - Snapshot Support

extension DownloadProgressTracker {

    /// A snapshot of the current progress state
    struct Snapshot: Sendable {
        let overallProgress: Double
        let totalBytesDownloaded: Int64
        let totalBytesExpected: Int64
        let estimatedTimeRemaining: TimeInterval?
        let currentDownloadRate: Double
        let activeTaskCount: Int
        let timestamp: Date

        var progressPercentage: Int {
            Int((overallProgress * 100).rounded())
        }
    }

    /// Capture current state as a snapshot
    /// - Returns: Immutable snapshot of current progress
    func snapshot() -> Snapshot {
        Snapshot(
            overallProgress: overallProgress,
            totalBytesDownloaded: totalBytesDownloaded,
            totalBytesExpected: totalBytesExpected,
            estimatedTimeRemaining: estimatedTimeRemaining,
            currentDownloadRate: currentDownloadRate,
            activeTaskCount: activeTaskCount,
            timestamp: Date()
        )
    }
}
