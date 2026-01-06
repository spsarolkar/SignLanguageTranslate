import Foundation

/// Serializable state of the download queue for persistence
///
/// This struct captures the complete state of the download queue at a point in time,
/// allowing it to be saved to disk and restored later (e.g., after app restart).
///
/// Use cases:
/// - Persist download queue between app launches
/// - Backup download state before major operations
/// - Export download state for debugging
///
/// Example usage:
/// ```swift
/// // Export
/// let state = await queue.exportState()
/// try? state.write(to: fileURL)
///
/// // Import
/// let data = try Data(contentsOf: fileURL)
/// let state = try JSONDecoder().decode(DownloadQueueState.self, from: data)
/// try await queue.importState(state)
/// ```
struct DownloadQueueState: Codable, Hashable, Equatable {

    // MARK: - Properties

    /// All download tasks in the queue
    let tasks: [DownloadTask]

    /// Order of task IDs in the queue (determines download priority)
    let queueOrder: [UUID]

    /// Whether the queue is globally paused
    let isPaused: Bool

    /// Maximum number of concurrent downloads allowed
    let maxConcurrentDownloads: Int

    /// When this state was exported
    let exportedAt: Date

    /// Version number for state format (for future migration support)
    let version: Int

    // MARK: - Initialization

    /// Create a download queue state
    /// - Parameters:
    ///   - tasks: All tasks in the queue
    ///   - queueOrder: Order of task IDs
    ///   - isPaused: Whether queue is paused
    ///   - maxConcurrentDownloads: Max concurrent download limit
    ///   - exportedAt: Export timestamp (defaults to now)
    ///   - version: State format version (defaults to 1)
    init(
        tasks: [DownloadTask],
        queueOrder: [UUID],
        isPaused: Bool,
        maxConcurrentDownloads: Int = 3,
        exportedAt: Date = Date(),
        version: Int = 1
    ) {
        self.tasks = tasks
        self.queueOrder = queueOrder
        self.isPaused = isPaused
        self.maxConcurrentDownloads = maxConcurrentDownloads
        self.exportedAt = exportedAt
        self.version = version
    }

    // MARK: - Computed Properties

    /// Total number of tasks
    var totalCount: Int {
        tasks.count
    }

    /// Number of completed tasks
    var completedCount: Int {
        tasks.filter { $0.status == .completed }.count
    }

    /// Number of active tasks (downloading or extracting)
    var activeCount: Int {
        tasks.filter { $0.isActive }.count
    }

    /// Number of failed tasks
    var failedCount: Int {
        tasks.filter { $0.status == .failed }.count
    }

    /// Number of pending tasks
    var pendingCount: Int {
        tasks.filter { $0.status == .pending }.count
    }

    /// Whether all tasks are completed
    var allCompleted: Bool {
        !tasks.isEmpty && tasks.allSatisfy { $0.status == .completed }
    }

    /// Overall progress (0.0 to 1.0)
    var overallProgress: Double {
        guard !tasks.isEmpty else { return 0.0 }

        let totalProgress = tasks.reduce(0.0) { $0 + $1.progress }
        return totalProgress / Double(tasks.count)
    }

    /// Total bytes across all tasks
    var totalBytes: Int64 {
        tasks.reduce(0) { $0 + $1.totalBytes }
    }

    /// Downloaded bytes across all tasks
    var downloadedBytes: Int64 {
        tasks.reduce(0) { $0 + $1.bytesDownloaded }
    }

    // MARK: - Validation

    /// Validate the state for consistency
    /// - Returns: Array of validation errors (empty if valid)
    func validate() -> [String] {
        var errors: [String] = []

        // Check that queueOrder contains valid task IDs
        let taskIDs = Set(tasks.map(\.id))
        let queueIDs = Set(queueOrder)

        if queueIDs != taskIDs {
            errors.append("Queue order IDs don't match task IDs")

            // Provide details
            let missingInQueue = taskIDs.subtracting(queueIDs)
            if !missingInQueue.isEmpty {
                errors.append("Tasks not in queue order: \(missingInQueue.count)")
            }

            let extraInQueue = queueIDs.subtracting(taskIDs)
            if !extraInQueue.isEmpty {
                errors.append("Queue contains non-existent task IDs: \(extraInQueue.count)")
            }
        }

        // Check for duplicate task IDs
        if tasks.count != Set(tasks.map(\.id)).count {
            errors.append("Duplicate task IDs found")
        }

        // Check for duplicate queue order IDs
        if queueOrder.count != Set(queueOrder).count {
            errors.append("Duplicate IDs in queue order")
        }

        // Check version
        if version < 1 {
            errors.append("Invalid version number: \(version)")
        }

        return errors
    }

    /// Whether this state is valid
    var isValid: Bool {
        validate().isEmpty
    }

    // MARK: - Serialization Helpers

    /// Encode this state to JSON data
    /// - Throws: Encoding error
    /// - Returns: JSON data
    func toData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    /// Decode state from JSON data
    /// - Parameter data: JSON data
    /// - Throws: Decoding error
    /// - Returns: Decoded state
    static func fromData(_ data: Data) throws -> DownloadQueueState {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(DownloadQueueState.self, from: data)
    }

    /// Save state to a file URL
    /// - Parameter url: File URL to save to
    /// - Throws: File or encoding error
    func save(to url: URL) throws {
        let data = try toData()
        try data.write(to: url, options: .atomic)
    }

    /// Load state from a file URL
    /// - Parameter url: File URL to load from
    /// - Throws: File or decoding error
    /// - Returns: Loaded state
    static func load(from url: URL) throws -> DownloadQueueState {
        let data = try Data(contentsOf: url)
        return try fromData(data)
    }
}

// MARK: - Preview Helpers

extension DownloadQueueState {

    /// Sample empty state
    static var previewEmpty: DownloadQueueState {
        DownloadQueueState(
            tasks: [],
            queueOrder: [],
            isPaused: false,
            maxConcurrentDownloads: 3
        )
    }

    /// Sample state with active downloads
    static var previewActive: DownloadQueueState {
        let tasks = [
            DownloadTask(
                url: URL(string: "https://example.com/file1.zip")!,
                category: "Animals",
                partNumber: 1,
                totalParts: 2,
                datasetName: "INCLUDE",
                status: .downloading,
                progress: 0.45,
                bytesDownloaded: 540_000_000,
                totalBytes: 1_200_000_000
            ),
            DownloadTask(
                url: URL(string: "https://example.com/file2.zip")!,
                category: "Animals",
                partNumber: 2,
                totalParts: 2,
                datasetName: "INCLUDE",
                status: .pending,
                totalBytes: 1_100_000_000
            ),
            DownloadTask(
                url: URL(string: "https://example.com/file3.zip")!,
                category: "Seasons",
                partNumber: 1,
                totalParts: 1,
                datasetName: "INCLUDE",
                status: .completed,
                progress: 1.0,
                bytesDownloaded: 700_000_000,
                totalBytes: 700_000_000
            )
        ]

        return DownloadQueueState(
            tasks: tasks,
            queueOrder: tasks.map(\.id),
            isPaused: false,
            maxConcurrentDownloads: 3
        )
    }

    /// Sample state with paused queue
    static var previewPaused: DownloadQueueState {
        let tasks = [
            DownloadTask(
                url: URL(string: "https://example.com/file1.zip")!,
                category: "Animals",
                partNumber: 1,
                totalParts: 2,
                datasetName: "INCLUDE",
                status: .paused,
                progress: 0.67,
                bytesDownloaded: 804_000_000,
                totalBytes: 1_200_000_000
            )
        ]

        return DownloadQueueState(
            tasks: tasks,
            queueOrder: tasks.map(\.id),
            isPaused: true,
            maxConcurrentDownloads: 3
        )
    }

    /// Sample completed state
    static var previewCompleted: DownloadQueueState {
        let tasks = [
            DownloadTask(
                url: URL(string: "https://example.com/file1.zip")!,
                category: "Seasons",
                partNumber: 1,
                totalParts: 1,
                datasetName: "INCLUDE",
                status: .completed,
                progress: 1.0,
                bytesDownloaded: 700_000_000,
                totalBytes: 700_000_000
            ),
            DownloadTask(
                url: URL(string: "https://example.com/file2.zip")!,
                category: "Greetings",
                partNumber: 1,
                totalParts: 2,
                datasetName: "INCLUDE",
                status: .completed,
                progress: 1.0,
                bytesDownloaded: 1_100_000_000,
                totalBytes: 1_100_000_000
            )
        ]

        return DownloadQueueState(
            tasks: tasks,
            queueOrder: tasks.map(\.id),
            isPaused: false,
            maxConcurrentDownloads: 3
        )
    }
}
