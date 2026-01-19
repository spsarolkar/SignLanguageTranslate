import Foundation

/// Represents a single download task with progress tracking
///
/// This is a value type (struct) that tracks the state of downloading a single file
/// from the dataset manifest. It will be managed by a Swift Actor for thread safety.
///
/// Lifecycle:
/// 1. Create from ManifestEntry (status: pending)
/// 2. Start download (status: downloading, progress updates)
/// 3. Complete download (status: extracting)
/// 4. Finish extraction (status: completed)
///
/// Or at any point:
/// - Pause (status: paused, saves resume data)
/// - Fail (status: failed, stores error message)
/// - Reset/Retry (back to pending)
struct DownloadTask: Identifiable, Codable, Hashable, Equatable, Sendable {

    // MARK: - Properties

    /// Unique identifier for this download task
    let id: UUID

    /// The URL to download from
    let url: URL

    /// Category name (e.g., "Animals", "Greetings")
    let category: String

    /// Part number within this category (1-indexed)
    let partNumber: Int

    /// Total number of parts in this category
    let totalParts: Int

    /// Dataset name (e.g., "INCLUDE", "ISL-CSLTR")
    let datasetName: String

    /// Current status of the download
    var status: DownloadTaskStatus

    /// Download progress (0.0 to 1.0)
    var progress: Double

    /// Number of bytes downloaded so far
    var bytesDownloaded: Int64

    /// Total bytes to download (0 if unknown)
    var totalBytes: Int64

    /// Error message if status is .failed
    var errorMessage: String?

    /// Path to saved resume data file (for pausing/resuming)
    var resumeDataPath: String?

    /// When this task was created
    let createdAt: Date

    /// When download actually started (nil if not started yet)
    var startedAt: Date?

    /// When download completed (nil if not completed yet)
    var completedAt: Date?

    // MARK: - Computed Properties

    /// Filename extracted from URL
    var filename: String {
        if url.lastPathComponent == "content" {
            return url.deletingLastPathComponent().lastPathComponent
        }
        return url.lastPathComponent
    }

    /// Display name for UI (e.g., "Animals Part 1 of 2" or "Seasons")
    var displayName: String {
        if totalParts == 1 {
            return category
        } else {
            return "\(category) (Part \(partNumber) of \(totalParts))"
        }
    }

    /// Short display name (e.g., "Animals 1/2" or "Seasons")
    var shortDisplayName: String {
        if totalParts == 1 {
            return category
        } else {
            return "\(category) \(partNumber)/\(totalParts)"
        }
    }

    /// Progress as percentage (0-100)
    var progressPercentage: Int {
        Int((progress * 100).rounded())
    }

    /// Progress text for UI (e.g., "12.5 MB / 45.0 MB" or "45%")
    var progressText: String {
        if totalBytes > 0 {
            let downloaded = FileManager.formattedSize(bytesDownloaded)
            let total = FileManager.formattedSize(totalBytes)
            return "\(downloaded) / \(total)"
        } else if bytesDownloaded > 0 {
            // Total unknown, just show downloaded
            return FileManager.formattedSize(bytesDownloaded)
        } else {
            // Nothing downloaded yet
            return "\(progressPercentage)%"
        }
    }

    /// Whether this task is currently active (downloading or extracting)
    var isActive: Bool {
        status.isActive
    }

    /// Whether this task can be started
    var canStart: Bool {
        status.canStart
    }

    /// Whether this task can be paused
    var canPause: Bool {
        status.canPause
    }

    /// Whether resume data is available
    var hasResumeData: Bool {
        resumeDataPath != nil
    }

    /// Estimated time remaining (if enough data available)
    /// Returns nil if cannot estimate
    var estimatedTimeRemaining: TimeInterval? {
        guard status == .downloading,
              bytesDownloaded > 0,
              totalBytes > 0,
              let startedAt = startedAt else {
            return nil
        }

        let elapsed = Date().timeIntervalSince(startedAt)
        guard elapsed > 0 else { return nil }

        let bytesPerSecond = Double(bytesDownloaded) / elapsed
        guard bytesPerSecond > 0 else { return nil }

        let bytesRemaining = totalBytes - bytesDownloaded
        return Double(bytesRemaining) / bytesPerSecond
    }

    /// Formatted estimated time remaining (e.g., "2m 30s")
    var estimatedTimeRemainingText: String? {
        guard let timeRemaining = estimatedTimeRemaining else {
            return nil
        }

        let minutes = Int(timeRemaining) / 60
        let seconds = Int(timeRemaining) % 60

        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        } else {
            return "\(seconds)s"
        }
    }

    /// Current download speed (bytes/second)
    var downloadSpeed: Double {
        guard status == .downloading,
              let startedAt = startedAt,
              bytesDownloaded > 0 else { return 0 }
        
        let elapsed = Date().timeIntervalSince(startedAt)
        return elapsed > 0 ? Double(bytesDownloaded) / elapsed : 0
    }

    // MARK: - Initialization

    /// Create a download task from a manifest entry
    /// - Parameters:
    ///   - entry: The manifest entry to download
    ///   - datasetName: Name of the dataset
    init(from entry: ManifestEntry, datasetName: String) {
        self.id = UUID()
        self.url = entry.url
        self.category = entry.category
        self.partNumber = entry.partNumber
        self.totalParts = entry.totalParts
        self.datasetName = datasetName
        self.status = .pending
        self.progress = 0.0
        self.bytesDownloaded = 0
        self.totalBytes = entry.estimatedSize ?? 0
        self.errorMessage = nil
        self.resumeDataPath = nil
        self.createdAt = Date()
        self.startedAt = nil
        self.completedAt = nil
    }

    /// Create a download task with all properties (for testing/restoration)
    init(
        id: UUID = UUID(),
        url: URL,
        category: String,
        partNumber: Int,
        totalParts: Int,
        datasetName: String,
        status: DownloadTaskStatus = .pending,
        progress: Double = 0.0,
        bytesDownloaded: Int64 = 0,
        totalBytes: Int64 = 0,
        errorMessage: String? = nil,
        resumeDataPath: String? = nil,
        createdAt: Date = Date(),
        startedAt: Date? = nil,
        completedAt: Date? = nil
    ) {
        self.id = id
        self.url = url
        self.category = category
        self.partNumber = partNumber
        self.totalParts = totalParts
        self.datasetName = datasetName
        self.status = status
        self.progress = progress
        self.bytesDownloaded = bytesDownloaded
        self.totalBytes = totalBytes
        self.errorMessage = errorMessage
        self.resumeDataPath = resumeDataPath
        self.createdAt = createdAt
        self.startedAt = startedAt
        self.completedAt = completedAt
    }

    // MARK: - State Transition Methods

    /// Update download progress
    /// - Parameters:
    ///   - bytesDownloaded: Number of bytes downloaded
    ///   - totalBytes: Total bytes to download (if known)
    mutating func updateProgress(bytesDownloaded: Int64, totalBytes: Int64) {
        self.bytesDownloaded = bytesDownloaded

        // Update total bytes if provided and greater than current
        if totalBytes > 0 {
            self.totalBytes = max(self.totalBytes, totalBytes)
        }

        // Calculate progress
        if self.totalBytes > 0 {
            self.progress = Double(bytesDownloaded) / Double(self.totalBytes)
            self.progress = min(1.0, max(0.0, self.progress)) // Clamp to 0.0-1.0
        } else {
            // Total unknown, can't calculate accurate progress
            self.progress = 0.0
        }
    }

    /// Set the exact file size (overriding any estimate)
    /// - Parameter size: The actual file size in bytes
    mutating func setFileSize(_ size: Int64) {
        self.totalBytes = size
        self.bytesDownloaded = size
        self.progress = 1.0
    }

    /// Start the download
    mutating func start() {
        guard canStart else { return }

        self.status = .downloading
        if self.startedAt == nil {
            self.startedAt = Date()
        }
        self.errorMessage = nil
    }

    /// Queue the download (waiting for available slot)
    mutating func queue() {
        guard status == .pending else { return }
        self.status = .queued
    }

    /// Pause the download
    mutating func pause() {
        guard canPause else { return }
        self.status = .paused
    }

    /// Mark download as complete and start extraction
    mutating func startExtracting() {
        guard status == .downloading else { return }
        self.status = .extracting
        self.progress = 1.0
        self.bytesDownloaded = totalBytes
    }

    /// Complete the entire task (download + extraction)
    mutating func complete() {
        self.status = .completed
        self.progress = 1.0
        self.completedAt = Date()
        self.errorMessage = nil
        self.resumeDataPath = nil
    }

    /// Fail the download with an error
    /// - Parameter message: Error message describing the failure
    mutating func fail(with message: String) {
        self.status = .failed
        self.errorMessage = message
        self.resumeDataPath = nil
    }

    /// Reset the task to pending state (for retry)
    mutating func reset() {
        self.status = .pending
        self.progress = 0.0
        self.bytesDownloaded = 0
        self.errorMessage = nil
        self.resumeDataPath = nil
        self.startedAt = nil
        self.completedAt = nil
    }

    /// Save resume data path (for pausing)
    /// - Parameter path: Path to the resume data file
    mutating func saveResumeData(at path: String) {
        self.resumeDataPath = path
    }

    /// Clear resume data
    mutating func clearResumeData() {
        self.resumeDataPath = nil
    }
}

// MARK: - Preview Helpers

extension DownloadTask {

    /// Sample pending task
    static var previewPending: DownloadTask {
        DownloadTask(
            url: URL(string: "https://zenodo.org/api/records/4010759/files/Seasons.zip")!,
            category: "Seasons",
            partNumber: 1,
            totalParts: 1,
            datasetName: "INCLUDE",
            status: .pending,
            totalBytes: 700_000_000
        )
    }

    /// Sample downloading task
    static var previewDownloading: DownloadTask {
        DownloadTask(
            url: URL(string: "https://zenodo.org/api/records/4010759/files/Animals_1of2.zip")!,
            category: "Animals",
            partNumber: 1,
            totalParts: 2,
            datasetName: "INCLUDE",
            status: .downloading,
            progress: 0.45,
            bytesDownloaded: 540_000_000,
            totalBytes: 1_200_000_000,
            startedAt: Date().addingTimeInterval(-60) // Started 60 seconds ago
        )
    }

    /// Sample extracting task
    static var previewExtracting: DownloadTask {
        DownloadTask(
            url: URL(string: "https://zenodo.org/api/records/4010759/files/Animals_2of2.zip")!,
            category: "Animals",
            partNumber: 2,
            totalParts: 2,
            datasetName: "INCLUDE",
            status: .extracting,
            progress: 1.0,
            bytesDownloaded: 1_100_000_000,
            totalBytes: 1_100_000_000,
            startedAt: Date().addingTimeInterval(-120),
            completedAt: Date()
        )
    }

    /// Sample completed task
    static var previewCompleted: DownloadTask {
        DownloadTask(
            url: URL(string: "https://zenodo.org/api/records/4010759/files/Greetings.zip")!,
            category: "Greetings",
            partNumber: 1,
            totalParts: 2,
            datasetName: "INCLUDE",
            status: .completed,
            progress: 1.0,
            bytesDownloaded: 1_100_000_000,
            totalBytes: 1_100_000_000,
            startedAt: Date().addingTimeInterval(-300),
            completedAt: Date().addingTimeInterval(-10)
        )
    }

    /// Sample failed task
    static var previewFailed: DownloadTask {
        DownloadTask(
            url: URL(string: "https://zenodo.org/api/records/4010759/files/Jobs.zip")!,
            category: "Jobs",
            partNumber: 1,
            totalParts: 2,
            datasetName: "INCLUDE",
            status: .failed,
            progress: 0.23,
            bytesDownloaded: 460_000_000,
            totalBytes: 2_000_000_000,
            errorMessage: "Network connection lost",
            startedAt: Date().addingTimeInterval(-180)
        )
    }

    /// Sample paused task
    static var previewPaused: DownloadTask {
        DownloadTask(
            url: URL(string: "https://zenodo.org/api/records/4010759/files/Colors.zip")!,
            category: "Colors",
            partNumber: 1,
            totalParts: 2,
            datasetName: "INCLUDE",
            status: .paused,
            progress: 0.67,
            bytesDownloaded: 1_340_000_000,
            totalBytes: 2_000_000_000,
            resumeDataPath: "/tmp/resume_data.bin",
            startedAt: Date().addingTimeInterval(-240)
        )
    }

    /// Sample list of tasks
    static var previewList: [DownloadTask] {
        [
            previewPending,
            previewDownloading,
            previewExtracting,
            previewCompleted,
            previewFailed,
            previewPaused
        ]
    }
}
