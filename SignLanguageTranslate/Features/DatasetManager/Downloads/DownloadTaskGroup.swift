import Foundation

/// Groups download tasks by category for organized UI display
///
/// This struct aggregates multiple tasks belonging to the same category
/// (e.g., all parts of "Animals") and provides computed statistics for
/// displaying overall category progress.
///
/// Use cases:
/// - Display progress for multi-part downloads
/// - Show category-level status in UI
/// - Aggregate byte counts and completion status
struct DownloadTaskGroup: Identifiable, Hashable, Equatable, Sendable {

    // MARK: - Properties

    /// Category name (serves as identifier)
    let category: String

    /// All tasks in this category
    let tasks: [DownloadTask]

    /// Unique identifier (based on category)
    var id: String { category }

    // MARK: - Initialization

    /// Create a task group for a category
    /// - Parameters:
    ///   - category: Category name
    ///   - tasks: Tasks in this category
    init(category: String, tasks: [DownloadTask]) {
        self.category = category
        self.tasks = tasks
    }

    // MARK: - Computed Properties - Counts

    /// Total number of tasks (parts) in this group
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

    /// Number of paused tasks
    var pausedCount: Int {
        tasks.filter { $0.status == .paused }.count
    }

    // MARK: - Computed Properties - Status

    /// Whether all tasks in this group are completed
    var allCompleted: Bool {
        !tasks.isEmpty && tasks.allSatisfy { $0.status == .completed }
    }

    /// Whether any task is currently active
    var anyActive: Bool {
        tasks.contains { $0.isActive }
    }

    /// Whether any task has failed
    var anyFailed: Bool {
        tasks.contains { $0.status == .failed }
    }

    /// Whether all tasks are pending (none started)
    var allPending: Bool {
        !tasks.isEmpty && tasks.allSatisfy { $0.status == .pending }
    }

    /// Overall status for the group (prioritized)
    var overallStatus: DownloadTaskStatus {
        if allCompleted {
            return .completed
        } else if anyActive {
            // Return the most advanced active status
            if tasks.contains(where: { $0.status == .extracting }) {
                return .extracting
            } else if tasks.contains(where: { $0.status == .downloading }) {
                return .downloading
            } else {
                return .queued
            }
        } else if anyFailed {
            return .failed
        } else if tasks.contains(where: { $0.status == .paused }) {
            return .paused
        } else if tasks.contains(where: { $0.status == .queued }) {
            return .queued
        } else {
            return .pending
        }
    }

    // MARK: - Computed Properties - Progress

    /// Average progress across all tasks (0.0 to 1.0)
    var totalProgress: Double {
        guard !tasks.isEmpty else { return 0.0 }

        let sum = tasks.reduce(0.0) { $0 + $1.progress }
        return sum / Double(tasks.count)
    }

    /// Progress as percentage (0-100)
    var progressPercentage: Int {
        Int((totalProgress * 100).rounded())
    }

    /// Total bytes across all tasks
    var totalBytes: Int64 {
        tasks.reduce(0) { $0 + $1.totalBytes }
    }

    /// Downloaded bytes across all tasks
    var downloadedBytes: Int64 {
        tasks.reduce(0) { $0 + $1.bytesDownloaded }
    }

    /// Progress text for UI (e.g., "12.5 GB / 45.0 GB")
    var progressText: String {
        if totalBytes > 0 {
            let downloaded = FileManager.formattedSize(downloadedBytes)
            let total = FileManager.formattedSize(totalBytes)
            return "\(downloaded) / \(total)"
        } else {
            return "\(progressPercentage)%"
        }
    }

    /// Short status summary (e.g., "2/3 completed", "Downloading", "Failed")
    var statusSummary: String {
        if allCompleted {
            return "Completed"
        } else if allPending {
            return "Pending"
        } else if completedCount > 0 {
            return "\(completedCount)/\(totalCount) completed"
        } else {
            return overallStatus.displayName
        }
    }

    // MARK: - Task Access

    /// Get task by part number
    /// - Parameter partNumber: Part number (1-indexed)
    /// - Returns: Task if found
    func task(forPart partNumber: Int) -> DownloadTask? {
        tasks.first { $0.partNumber == partNumber }
    }

    /// All active tasks in this group
    var activeTasks: [DownloadTask] {
        tasks.filter { $0.isActive }
    }

    /// All failed tasks in this group
    var failedTasks: [DownloadTask] {
        tasks.filter { $0.status == .failed }
    }

    /// All completed tasks in this group
    var completedTasks: [DownloadTask] {
        tasks.filter { $0.status == .completed }
    }

    /// Tasks sorted by part number
    var sortedTasks: [DownloadTask] {
        tasks.sorted { $0.partNumber < $1.partNumber }
    }
}

// MARK: - Collection Grouping

extension Array where Element == DownloadTask {

    /// Group tasks by category
    /// - Returns: Array of DownloadTaskGroup
    func groupedByCategory() -> [DownloadTaskGroup] {
        let grouped = Dictionary(grouping: self) { $0.category }
        return grouped.map { category, tasks in
            DownloadTaskGroup(category: category, tasks: tasks)
        }
        .sorted { $0.category < $1.category }
    }

    /// Group tasks by category with custom sorting
    /// - Parameter sortOrder: Sort comparator for groups
    /// - Returns: Array of DownloadTaskGroup
    func groupedByCategory(
        sortedBy sortOrder: (DownloadTaskGroup, DownloadTaskGroup) -> Bool
    ) -> [DownloadTaskGroup] {
        let grouped = Dictionary(grouping: self) { $0.category }
        return grouped.map { category, tasks in
            DownloadTaskGroup(category: category, tasks: tasks)
        }
        .sorted(by: sortOrder)
    }
}

// MARK: - Preview Helpers

extension DownloadTaskGroup {

    /// Sample group with all tasks completed
    static var previewCompleted: DownloadTaskGroup {
        DownloadTaskGroup(
            category: "Seasons",
            tasks: [
                DownloadTask(
                    url: URL(string: "https://zenodo.org/api/records/4010759/files/Seasons.zip")!,
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
        )
    }

    /// Sample group with downloads in progress
    static var previewInProgress: DownloadTaskGroup {
        DownloadTaskGroup(
            category: "Animals",
            tasks: [
                DownloadTask(
                    url: URL(string: "https://zenodo.org/api/records/4010759/files/Animals_1of2.zip")!,
                    category: "Animals",
                    partNumber: 1,
                    totalParts: 2,
                    datasetName: "INCLUDE",
                    status: .completed,
                    progress: 1.0,
                    bytesDownloaded: 1_200_000_000,
                    totalBytes: 1_200_000_000
                ),
                DownloadTask(
                    url: URL(string: "https://zenodo.org/api/records/4010759/files/Animals_2of2.zip")!,
                    category: "Animals",
                    partNumber: 2,
                    totalParts: 2,
                    datasetName: "INCLUDE",
                    status: .downloading,
                    progress: 0.45,
                    bytesDownloaded: 495_000_000,
                    totalBytes: 1_100_000_000
                )
            ]
        )
    }

    /// Sample group with failed tasks
    static var previewFailed: DownloadTaskGroup {
        DownloadTaskGroup(
            category: "Adjectives",
            tasks: [
                DownloadTask(
                    url: URL(string: "https://zenodo.org/api/records/4010759/files/Adjectives_1of8.zip")!,
                    category: "Adjectives",
                    partNumber: 1,
                    totalParts: 8,
                    datasetName: "INCLUDE",
                    status: .completed,
                    progress: 1.0,
                    bytesDownloaded: 1_000_000_000,
                    totalBytes: 1_000_000_000
                ),
                DownloadTask(
                    url: URL(string: "https://zenodo.org/api/records/4010759/files/Adjectives_2of8.zip")!,
                    category: "Adjectives",
                    partNumber: 2,
                    totalParts: 8,
                    datasetName: "INCLUDE",
                    status: .failed,
                    progress: 0.23,
                    bytesDownloaded: 230_000_000,
                    totalBytes: 1_000_000_000,
                    errorMessage: "Network connection lost"
                ),
                DownloadTask(
                    url: URL(string: "https://zenodo.org/api/records/4010759/files/Adjectives_3of8.zip")!,
                    category: "Adjectives",
                    partNumber: 3,
                    totalParts: 8,
                    datasetName: "INCLUDE",
                    status: .pending,
                    totalBytes: 1_000_000_000
                )
            ]
        )
    }

    /// Sample group with all pending tasks
    static var previewPending: DownloadTaskGroup {
        DownloadTaskGroup(
            category: "Greetings",
            tasks: [
                DownloadTask(
                    url: URL(string: "https://zenodo.org/api/records/4010759/files/Greetings_1of2.zip")!,
                    category: "Greetings",
                    partNumber: 1,
                    totalParts: 2,
                    datasetName: "INCLUDE",
                    status: .pending,
                    totalBytes: 1_100_000_000
                ),
                DownloadTask(
                    url: URL(string: "https://zenodo.org/api/records/4010759/files/Greetings_2of2.zip")!,
                    category: "Greetings",
                    partNumber: 2,
                    totalParts: 2,
                    datasetName: "INCLUDE",
                    status: .pending,
                    totalBytes: 1_100_000_000
                )
            ]
        )
    }

    /// Sample list of groups
    static var previewList: [DownloadTaskGroup] {
        [
            previewCompleted,
            previewInProgress,
            previewFailed,
            previewPending
        ]
    }
}
