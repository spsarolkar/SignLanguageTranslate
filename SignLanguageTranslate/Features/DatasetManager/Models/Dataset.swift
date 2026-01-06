import Foundation
import SwiftData

/// Represents a sign language dataset containing video samples.
/// This is the top-level container that groups all videos from a particular source.
///
/// Example datasets:
/// - INCLUDE: Word-level signs organized by category (Animals, Greetings, etc.)
/// - ISL-CSLTR: Sentence-level continuous sign language
@Model
final class Dataset {

    // MARK: - Stored Properties

    /// Unique identifier
    var id: UUID

    /// Dataset name (e.g., "INCLUDE", "ISL-CSLTR")
    var name: String

    /// Type of dataset (stored as raw value for SwiftData)
    var typeRawValue: String

    /// Current download status (stored as raw value)
    var statusRawValue: String

    /// Total number of video samples in this dataset
    var totalSamples: Int

    /// Number of samples that have been downloaded
    var downloadedSamples: Int

    /// Total number of zip files/parts to download
    var totalParts: Int

    /// Number of parts that have been downloaded
    var downloadedParts: Int

    /// Total size in bytes (estimated or actual)
    var totalBytes: Int64

    /// Bytes downloaded so far
    var downloadedBytes: Int64

    /// Timestamp when dataset was added
    var createdAt: Date

    /// Timestamp when download started
    var downloadStartedAt: Date?

    /// Timestamp when download completed
    var downloadCompletedAt: Date?

    /// Last error message if status is .failed
    var lastError: String?

    /// User notes about this dataset
    var notes: String?

    // MARK: - Computed Properties

    /// Dataset type as enum
    var datasetType: DatasetType {
        get { DatasetType(rawValue: typeRawValue) ?? .include }
        set { typeRawValue = newValue.rawValue }
    }

    /// Download status as enum
    var downloadStatus: DownloadStatus {
        get { DownloadStatus(rawValue: statusRawValue) ?? .notStarted }
        set { statusRawValue = newValue.rawValue }
    }

    /// Download progress (0.0 to 1.0) based on bytes
    var downloadProgress: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(downloadedBytes) / Double(totalBytes)
    }

    /// Download progress based on parts (0.0 to 1.0)
    var partsProgress: Double {
        guard totalParts > 0 else { return 0 }
        return Double(downloadedParts) / Double(totalParts)
    }

    /// Sample count progress (0.0 to 1.0)
    var samplesProgress: Double {
        guard totalSamples > 0 else { return 0 }
        return Double(downloadedSamples) / Double(totalSamples)
    }

    /// Whether download is complete
    var isComplete: Bool {
        downloadStatus == .completed
    }

    /// Whether dataset is ready to use
    var isReady: Bool {
        downloadStatus == .completed && downloadedSamples > 0
    }

    /// Whether download can be started or resumed
    var canStartDownload: Bool {
        downloadStatus.canStart
    }

    /// Whether download can be paused
    var canPauseDownload: Bool {
        downloadStatus.canPause
    }

    /// Human-readable downloaded size
    var formattedDownloadedSize: String {
        FileManager.formattedSize(downloadedBytes)
    }

    /// Human-readable total size
    var formattedTotalSize: String {
        FileManager.formattedSize(totalBytes)
    }

    /// Progress text (e.g., "1.2 GB / 5.0 GB")
    var progressText: String {
        "\(formattedDownloadedSize) / \(formattedTotalSize)"
    }

    /// Parts progress text (e.g., "5 / 46 files")
    var partsProgressText: String {
        "\(downloadedParts) / \(totalParts) files"
    }

    /// Samples count text
    var samplesText: String {
        if totalSamples > 0 {
            return "\(downloadedSamples.formatted()) / \(totalSamples.formatted()) videos"
        } else {
            return "\(downloadedSamples.formatted()) videos"
        }
    }

    /// Directory where this dataset's files are stored
    var storageDirectory: URL {
        FileManager.default.datasetsDirectory.appendingPathComponent(name)
    }

    /// Check if storage directory exists
    var hasLocalStorage: Bool {
        FileManager.default.directoryExists(at: storageDirectory)
    }

    /// Calculate actual storage used on disk
    var actualStorageUsed: Int64 {
        FileManager.default.directorySize(at: storageDirectory)
    }

    /// Human-readable actual storage
    var formattedActualStorage: String {
        FileManager.formattedSize(actualStorageUsed)
    }

    // MARK: - Initialization

    /// Create a new dataset
    /// - Parameters:
    ///   - name: Dataset name
    ///   - type: Dataset type
    init(name: String, type: DatasetType) {
        self.id = UUID()
        self.name = name
        self.typeRawValue = type.rawValue
        self.statusRawValue = DownloadStatus.notStarted.rawValue
        self.totalSamples = 0
        self.downloadedSamples = 0
        self.totalParts = 0
        self.downloadedParts = 0
        self.totalBytes = 0
        self.downloadedBytes = 0
        self.createdAt = Date.now
        self.downloadStartedAt = nil
        self.downloadCompletedAt = nil
        self.lastError = nil
        self.notes = nil
    }

    /// Full initializer for testing/migration
    init(
        id: UUID = UUID(),
        name: String,
        type: DatasetType,
        status: DownloadStatus = .notStarted,
        totalSamples: Int = 0,
        downloadedSamples: Int = 0,
        totalParts: Int = 0,
        downloadedParts: Int = 0,
        totalBytes: Int64 = 0,
        downloadedBytes: Int64 = 0,
        createdAt: Date = .now,
        downloadStartedAt: Date? = nil,
        downloadCompletedAt: Date? = nil,
        lastError: String? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.name = name
        self.typeRawValue = type.rawValue
        self.statusRawValue = status.rawValue
        self.totalSamples = totalSamples
        self.downloadedSamples = downloadedSamples
        self.totalParts = totalParts
        self.downloadedParts = downloadedParts
        self.totalBytes = totalBytes
        self.downloadedBytes = downloadedBytes
        self.createdAt = createdAt
        self.downloadStartedAt = downloadStartedAt
        self.downloadCompletedAt = downloadCompletedAt
        self.lastError = lastError
        self.notes = notes
    }

    // MARK: - Methods

    /// Start or resume downloading
    func startDownload() {
        downloadStatus = .downloading
        if downloadStartedAt == nil {
            downloadStartedAt = Date.now
        }
        lastError = nil
    }

    /// Pause the download
    func pauseDownload() {
        downloadStatus = .paused
    }

    /// Mark download as completed
    func completeDownload() {
        downloadStatus = .completed
        downloadCompletedAt = Date.now
    }

    /// Mark download as failed
    func failDownload(error: String) {
        downloadStatus = .failed
        lastError = error
    }

    /// Update download progress
    func updateProgress(downloadedBytes: Int64, totalBytes: Int64) {
        self.downloadedBytes = downloadedBytes
        if totalBytes > 0 {
            self.totalBytes = totalBytes
        }
    }

    /// Update parts progress
    func updatePartsProgress(downloadedParts: Int, totalParts: Int) {
        self.downloadedParts = downloadedParts
        if totalParts > 0 {
            self.totalParts = totalParts
        }
    }

    /// Update samples count
    func updateSamplesCount(downloaded: Int, total: Int? = nil) {
        self.downloadedSamples = downloaded
        if let total = total {
            self.totalSamples = total
        }
    }

    /// Increment downloaded parts count
    func incrementDownloadedParts() {
        downloadedParts += 1
        if downloadedParts >= totalParts && totalParts > 0 {
            downloadStatus = .processing
        }
    }

    /// Reset download state (for retry)
    func resetDownload() {
        downloadStatus = .notStarted
        downloadedBytes = 0
        downloadedParts = 0
        downloadStartedAt = nil
        downloadCompletedAt = nil
        lastError = nil
    }
}

// MARK: - Preview Helpers

extension Dataset {

    /// Sample INCLUDE dataset (not started)
    static var previewIncludeNotStarted: Dataset {
        Dataset(
            name: "INCLUDE",
            type: .include,
            status: .notStarted,
            totalSamples: 15000,
            totalParts: 46,
            totalBytes: 50_000_000_000 // 50 GB
        )
    }

    /// Sample INCLUDE dataset (downloading)
    static var previewIncludeDownloading: Dataset {
        Dataset(
            name: "INCLUDE",
            type: .include,
            status: .downloading,
            totalSamples: 15000,
            downloadedSamples: 3200,
            totalParts: 46,
            downloadedParts: 12,
            totalBytes: 50_000_000_000,
            downloadedBytes: 12_500_000_000,
            downloadStartedAt: Date.now.addingTimeInterval(-3600)
        )
    }

    /// Sample INCLUDE dataset (completed)
    static var previewIncludeCompleted: Dataset {
        Dataset(
            name: "INCLUDE",
            type: .include,
            status: .completed,
            totalSamples: 15000,
            downloadedSamples: 15000,
            totalParts: 46,
            downloadedParts: 46,
            totalBytes: 50_000_000_000,
            downloadedBytes: 50_000_000_000,
            downloadStartedAt: Date.now.addingTimeInterval(-7200),
            downloadCompletedAt: Date.now.addingTimeInterval(-3600)
        )
    }

    /// Sample ISL-CSLTR dataset
    static var previewISLCSLTR: Dataset {
        Dataset(
            name: "ISL-CSLTR",
            type: .islcsltr,
            status: .notStarted,
            totalSamples: 5000,
            totalParts: 1,
            totalBytes: 10_000_000_000
        )
    }

    /// Sample paused dataset
    static var previewPaused: Dataset {
        Dataset(
            name: "INCLUDE",
            type: .include,
            status: .paused,
            totalSamples: 15000,
            downloadedSamples: 5000,
            totalParts: 46,
            downloadedParts: 15,
            totalBytes: 50_000_000_000,
            downloadedBytes: 16_000_000_000
        )
    }

    /// Sample failed dataset
    static var previewFailed: Dataset {
        Dataset(
            name: "INCLUDE",
            type: .include,
            status: .failed,
            totalSamples: 15000,
            downloadedSamples: 2000,
            totalParts: 46,
            downloadedParts: 8,
            totalBytes: 50_000_000_000,
            downloadedBytes: 8_000_000_000,
            lastError: "Network connection lost"
        )
    }

    /// All preview datasets
    static var previewList: [Dataset] {
        [
            previewIncludeCompleted,
            previewISLCSLTR,
            previewIncludeDownloading
        ]
    }

    /// Single preview dataset
    static var preview: Dataset {
        previewIncludeDownloading
    }
}
