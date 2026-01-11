import Foundation

/// Represents a single entry in the download history
///
/// Each entry captures information about a completed (or failed) download
/// for analytics, debugging, and user reference.
struct DownloadHistoryEntry: Codable, Identifiable, Sendable {

    /// Unique identifier for this entry
    let id: UUID

    /// The task ID from the download queue
    let taskId: UUID

    /// URL that was downloaded
    let url: URL

    /// Category of the download (e.g., "Animals", "Greetings")
    let category: String

    /// Dataset name (e.g., "INCLUDE")
    let datasetName: String

    /// When the download started
    let startedAt: Date

    /// When the download completed (nil if failed before completion)
    let completedAt: Date?

    /// Total bytes downloaded
    let bytesDownloaded: Int64

    /// Total bytes expected
    let totalBytes: Int64

    /// Whether the download was successful
    let success: Bool

    /// Error message if failed (nil if successful)
    let errorMessage: String?

    /// Duration in seconds (from start to completion)
    var duration: TimeInterval? {
        guard let completedAt = completedAt else { return nil }
        return completedAt.timeIntervalSince(startedAt)
    }

    /// Formatted duration (e.g., "2m 30s")
    var formattedDuration: String? {
        guard let duration = duration else { return nil }
        let totalSeconds = Int(duration)

        if totalSeconds < 60 {
            return "\(totalSeconds)s"
        } else if totalSeconds < 3600 {
            let minutes = totalSeconds / 60
            let seconds = totalSeconds % 60
            return "\(minutes)m \(seconds)s"
        } else {
            let hours = totalSeconds / 3600
            let minutes = (totalSeconds % 3600) / 60
            return "\(hours)h \(minutes)m"
        }
    }

    /// Average download speed in bytes per second
    var averageSpeed: Double? {
        guard let duration = duration, duration > 0 else { return nil }
        return Double(bytesDownloaded) / duration
    }

    /// Formatted average speed (e.g., "2.5 MB/s")
    var formattedAverageSpeed: String? {
        guard let speed = averageSpeed else { return nil }
        return formatBytesPerSecond(speed)
    }

    /// Create a history entry from a completed download task
    /// - Parameters:
    ///   - task: The download task
    ///   - success: Whether the download was successful
    ///   - errorMessage: Error message if failed
    init(
        from task: DownloadTask,
        success: Bool,
        errorMessage: String? = nil
    ) {
        self.id = UUID()
        self.taskId = task.id
        self.url = task.url
        self.category = task.category
        self.datasetName = task.datasetName
        self.startedAt = task.startedAt ?? task.createdAt
        self.completedAt = success ? (task.completedAt ?? Date()) : nil
        self.bytesDownloaded = task.bytesDownloaded
        self.totalBytes = task.totalBytes
        self.success = success
        self.errorMessage = errorMessage
    }

    /// Create a history entry with all fields
    init(
        id: UUID = UUID(),
        taskId: UUID,
        url: URL,
        category: String,
        datasetName: String,
        startedAt: Date,
        completedAt: Date?,
        bytesDownloaded: Int64,
        totalBytes: Int64,
        success: Bool,
        errorMessage: String?
    ) {
        self.id = id
        self.taskId = taskId
        self.url = url
        self.category = category
        self.datasetName = datasetName
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.bytesDownloaded = bytesDownloaded
        self.totalBytes = totalBytes
        self.success = success
        self.errorMessage = errorMessage
    }

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

/// Actor for managing download history
///
/// Tracks completed and failed downloads for analytics and debugging.
/// History is persisted to disk and limited to prevent unbounded growth.
///
/// Usage:
/// ```swift
/// let history = DownloadHistory()
///
/// // Record completion
/// await history.record(DownloadHistoryEntry(from: task, success: true))
///
/// // Get recent history
/// let recent = await history.getHistory(limit: 50)
///
/// // Export for debugging
/// let json = await history.exportToJSON()
/// ```
actor DownloadHistory {

    // MARK: - Properties

    /// History entries (most recent first)
    private var entries: [DownloadHistoryEntry] = []

    /// Maximum number of entries to keep
    private let maxEntries: Int

    /// File URL for persistent storage
    private let fileURL: URL

    /// JSON encoder
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    /// JSON decoder
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    /// Whether history has been loaded from disk
    private var isLoaded = false

    // MARK: - Initialization

    /// Create a download history actor
    /// - Parameters:
    ///   - maxEntries: Maximum entries to keep (default 1000)
    ///   - fileName: Name of the history file (default "download_history.json")
    init(maxEntries: Int = 1000, fileName: String = "download_history.json") {
        self.maxEntries = maxEntries
        self.fileURL = FileManager.default.documentsDirectory
            .appendingPathComponent(fileName)
    }

    // MARK: - Public Methods

    /// Record a history entry
    /// - Parameter entry: The entry to record
    func record(_ entry: DownloadHistoryEntry) async {
        // Ensure history is loaded
        await loadIfNeeded()

        // Add entry at the beginning (most recent first)
        entries.insert(entry, at: 0)

        // Trim if over limit
        if entries.count > maxEntries {
            entries = Array(entries.prefix(maxEntries))
        }

        // Save to disk
        await save()
    }

    /// Record a successful download
    /// - Parameter task: The completed download task
    func recordSuccess(_ task: DownloadTask) async {
        let entry = DownloadHistoryEntry(from: task, success: true)
        await record(entry)
    }

    /// Record a failed download
    /// - Parameters:
    ///   - task: The failed download task
    ///   - error: Error message
    func recordFailure(_ task: DownloadTask, error: String) async {
        let entry = DownloadHistoryEntry(from: task, success: false, errorMessage: error)
        await record(entry)
    }

    /// Get history entries
    /// - Parameter limit: Maximum entries to return (0 for all)
    /// - Returns: Array of history entries (most recent first)
    func getHistory(limit: Int = 0) async -> [DownloadHistoryEntry] {
        await loadIfNeeded()

        if limit > 0 {
            return Array(entries.prefix(limit))
        }
        return entries
    }

    /// Get history for a specific category
    /// - Parameters:
    ///   - category: Category to filter by
    ///   - limit: Maximum entries to return
    /// - Returns: Filtered history entries
    func getHistory(for category: String, limit: Int = 0) async -> [DownloadHistoryEntry] {
        await loadIfNeeded()

        let filtered = entries.filter { $0.category == category }

        if limit > 0 {
            return Array(filtered.prefix(limit))
        }
        return filtered
    }

    /// Get history for a specific dataset
    /// - Parameters:
    ///   - datasetName: Dataset name to filter by
    ///   - limit: Maximum entries to return
    /// - Returns: Filtered history entries
    func getHistory(forDataset datasetName: String, limit: Int = 0) async -> [DownloadHistoryEntry] {
        await loadIfNeeded()

        let filtered = entries.filter { $0.datasetName == datasetName }

        if limit > 0 {
            return Array(filtered.prefix(limit))
        }
        return filtered
    }

    /// Get only successful entries
    func getSuccessfulHistory(limit: Int = 0) async -> [DownloadHistoryEntry] {
        await loadIfNeeded()

        let filtered = entries.filter { $0.success }

        if limit > 0 {
            return Array(filtered.prefix(limit))
        }
        return filtered
    }

    /// Get only failed entries
    func getFailedHistory(limit: Int = 0) async -> [DownloadHistoryEntry] {
        await loadIfNeeded()

        let filtered = entries.filter { !$0.success }

        if limit > 0 {
            return Array(filtered.prefix(limit))
        }
        return filtered
    }

    /// Clear all history
    func clearHistory() async {
        entries.removeAll()
        await save()
    }

    /// Clear history older than a specified date
    /// - Parameter date: Cutoff date
    /// - Returns: Number of entries removed
    @discardableResult
    func clearHistory(before date: Date) async -> Int {
        await loadIfNeeded()

        let originalCount = entries.count
        entries.removeAll { $0.startedAt < date }

        if entries.count != originalCount {
            await save()
        }

        return originalCount - entries.count
    }

    /// Export history to JSON data
    /// - Returns: JSON data
    func exportToJSON() async -> Data {
        await loadIfNeeded()

        do {
            return try encoder.encode(entries)
        } catch {
            return Data()
        }
    }

    /// Get entry count
    func count() async -> Int {
        await loadIfNeeded()
        return entries.count
    }

    // MARK: - Statistics

    /// Statistics about download history
    struct Statistics: Sendable {
        let totalDownloads: Int
        let successfulDownloads: Int
        let failedDownloads: Int
        let successRate: Double
        let totalBytesDownloaded: Int64
        let averageDownloadSize: Int64
        let averageDownloadSpeed: Double?
        let averageDownloadDuration: TimeInterval?

        var formattedTotalBytes: String {
            FileManager.formattedSize(totalBytesDownloaded)
        }

        var formattedSuccessRate: String {
            String(format: "%.1f%%", successRate * 100)
        }
    }

    /// Get statistics about download history
    func getStatistics() async -> Statistics {
        await loadIfNeeded()

        let successful = entries.filter { $0.success }
        let failed = entries.filter { !$0.success }

        let totalBytes = entries.reduce(0) { $0 + $1.bytesDownloaded }
        let avgSize = entries.isEmpty ? 0 : totalBytes / Int64(entries.count)

        // Calculate average speed from successful downloads only
        let speeds = successful.compactMap { $0.averageSpeed }
        let avgSpeed: Double? = speeds.isEmpty ? nil : speeds.reduce(0, +) / Double(speeds.count)

        // Calculate average duration from successful downloads only
        let durations = successful.compactMap { $0.duration }
        let avgDuration: TimeInterval? = durations.isEmpty ? nil : durations.reduce(0, +) / Double(durations.count)

        return Statistics(
            totalDownloads: entries.count,
            successfulDownloads: successful.count,
            failedDownloads: failed.count,
            successRate: entries.isEmpty ? 0 : Double(successful.count) / Double(entries.count),
            totalBytesDownloaded: totalBytes,
            averageDownloadSize: avgSize,
            averageDownloadSpeed: avgSpeed,
            averageDownloadDuration: avgDuration
        )
    }

    // MARK: - Persistence

    /// Load history from disk if not already loaded
    private func loadIfNeeded() async {
        guard !isLoaded else { return }

        isLoaded = true

        guard FileManager.default.fileExists(at: fileURL) else {
            return
        }

        do {
            let data = try Data(contentsOf: fileURL)
            entries = try decoder.decode([DownloadHistoryEntry].self, from: data)
        } catch {
            print("[DownloadHistory] Failed to load history: \(error.localizedDescription)")
            entries = []
        }
    }

    /// Save history to disk
    private func save() async {
        do {
            let data = try encoder.encode(entries)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("[DownloadHistory] Failed to save history: \(error.localizedDescription)")
        }
    }
}

// MARK: - Preview Helpers

extension DownloadHistoryEntry {

    /// Sample successful entry
    static var previewSuccess: DownloadHistoryEntry {
        DownloadHistoryEntry(
            taskId: UUID(),
            url: URL(string: "https://example.com/Animals.zip")!,
            category: "Animals",
            datasetName: "INCLUDE",
            startedAt: Date().addingTimeInterval(-180),
            completedAt: Date().addingTimeInterval(-10),
            bytesDownloaded: 1_200_000_000,
            totalBytes: 1_200_000_000,
            success: true,
            errorMessage: nil
        )
    }

    /// Sample failed entry
    static var previewFailed: DownloadHistoryEntry {
        DownloadHistoryEntry(
            taskId: UUID(),
            url: URL(string: "https://example.com/Seasons.zip")!,
            category: "Seasons",
            datasetName: "INCLUDE",
            startedAt: Date().addingTimeInterval(-120),
            completedAt: nil,
            bytesDownloaded: 540_000_000,
            totalBytes: 700_000_000,
            success: false,
            errorMessage: "Network connection lost"
        )
    }

    /// Sample list of entries
    static var previewList: [DownloadHistoryEntry] {
        [previewSuccess, previewFailed]
    }
}
