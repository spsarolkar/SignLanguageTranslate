import Foundation
import SwiftData

/// Represents a single video sample in the sign language dataset.
/// Each video demonstrates a sign and is associated with labels (category, word, or sentence).
///
/// Example:
/// A video at "INCLUDE/Animals/12. Dog/video_001.mp4" would have:
/// - localPath: "INCLUDE/Animals/Dog/video_001.mp4" (sanitized)
/// - datasetName: "INCLUDE"
/// - labels: [Category: "Animals", Word: "Dog"]
@Model
final class VideoSample {

    // MARK: - Stored Properties

    /// Unique identifier for this video sample
    var id: UUID

    /// Relative path from the datasets directory to the video file
    /// Example: "INCLUDE/Animals/Dog/video_001.mp4"
    var localPath: String

    /// Name of the parent dataset (e.g., "INCLUDE", "ISL-CSLTR")
    var datasetName: String

    /// Original filename as found in the dataset
    var originalFilename: String

    /// File size in bytes (0 if unknown)
    var fileSize: Int64

    /// Duration of the video in seconds (0 if unknown)
    var duration: Double

    /// Timestamp when this sample was imported
    var createdAt: Date

    /// Timestamp when this sample was last accessed/played
    var lastAccessedAt: Date?

    /// Whether this sample has been marked as favorite
    var isFavorite: Bool

    /// Optional notes added by user
    var notes: String?

    // MARK: - Relationships

    /// Labels associated with this video (category, word, sentence)
    /// A video typically has 2 labels: one category and one word
    @Relationship(inverse: \Label.videoSamples)
    var labels: [Label]

    /// Extracted feature sets (e.g., body pose, hand landmarks)
    @Relationship(deleteRule: .cascade, inverse: \FeatureSet.videoSample)
    var featureSets: [FeatureSet] = []

    // MARK: - Computed Properties

    /// Absolute URL to the video file
    var absoluteURL: URL {
        FileManager.default.datasetsDirectory.appendingPathComponent(localPath)
    }

    /// Just the filename (e.g., "video_001.mp4")
    var fileName: String {
        (localPath as NSString).lastPathComponent
    }

    /// Filename without extension (e.g., "video_001")
    var fileNameWithoutExtension: String {
        ((localPath as NSString).lastPathComponent as NSString).deletingPathExtension
    }

    /// File extension (e.g., "mp4")
    var fileExtension: String {
        (localPath as NSString).pathExtension.lowercased()
    }

    /// Whether the video file exists on disk
    var fileExists: Bool {
        FileManager.default.fileExists(at: absoluteURL)
    }

    /// Human-readable file size (e.g., "12.5 MB")
    var formattedFileSize: String {
        FileManager.formattedSize(fileSize)
    }

    /// Human-readable duration (e.g., "0:45" or "1:23")
    var formattedDuration: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// Get the category label if present
    var categoryLabel: Label? {
        labels.first { $0.type == .category }
    }

    /// Get the word label if present
    var wordLabel: Label? {
        labels.first { $0.type == .word }
    }

    /// Get the sentence label if present
    var sentenceLabel: Label? {
        labels.first { $0.type == .sentence }
    }

    /// Category name (convenience accessor)
    var categoryName: String? {
        categoryLabel?.name
    }

    /// Word name (convenience accessor)
    var wordName: String? {
        wordLabel?.name
    }

    /// Sentence text (convenience accessor)
    var sentenceText: String? {
        sentenceLabel?.name
    }

    /// Display title for UI (prefers word, then sentence, then filename)
    var displayTitle: String {
        wordName ?? sentenceText ?? fileNameWithoutExtension
    }

    /// Subtitle for UI (category name or dataset name)
    var displaySubtitle: String {
        categoryName ?? datasetName
    }

    // MARK: - Initialization

    /// Create a new video sample
    /// - Parameters:
    ///   - localPath: Relative path from datasets directory
    ///   - datasetName: Name of the parent dataset
    ///   - originalFilename: Original filename from the dataset
    ///   - fileSize: Size in bytes (default 0)
    ///   - duration: Duration in seconds (default 0)
    init(
        localPath: String,
        datasetName: String,
        originalFilename: String? = nil,
        fileSize: Int64 = 0,
        duration: Double = 0
    ) {
        self.id = UUID()
        self.localPath = localPath
        self.datasetName = datasetName
        self.originalFilename = originalFilename ?? (localPath as NSString).lastPathComponent
        self.fileSize = fileSize
        self.duration = duration
        self.createdAt = Date.now
        self.lastAccessedAt = nil
        self.isFavorite = false
        self.notes = nil
        self.labels = []
    }

    /// Full initializer with all properties (for testing/migration)
    init(
        id: UUID = UUID(),
        localPath: String,
        datasetName: String,
        originalFilename: String,
        fileSize: Int64 = 0,
        duration: Double = 0,
        createdAt: Date = .now,
        lastAccessedAt: Date? = nil,
        isFavorite: Bool = false,
        notes: String? = nil,
        labels: [Label] = []
    ) {
        self.id = id
        self.localPath = localPath
        self.datasetName = datasetName
        self.originalFilename = originalFilename
        self.fileSize = fileSize
        self.duration = duration
        self.createdAt = createdAt
        self.lastAccessedAt = lastAccessedAt
        self.isFavorite = isFavorite
        self.notes = notes
        self.labels = labels
    }

    // MARK: - Methods

    /// Mark this video as accessed (updates lastAccessedAt)
    func markAsAccessed() {
        lastAccessedAt = Date.now
    }

    /// Toggle favorite status
    func toggleFavorite() {
        isFavorite.toggle()
    }

    /// Add a label to this video sample
    func addLabel(_ label: Label) {
        if !labels.contains(where: { $0.id == label.id }) {
            labels.append(label)
        }
    }

    /// Remove a label from this video sample
    func removeLabel(_ label: Label) {
        labels.removeAll { $0.id == label.id }
    }

    /// Check if this video has a specific label
    func hasLabel(_ label: Label) -> Bool {
        labels.contains { $0.id == label.id }
    }

    /// Check if this video has a label with the given name and type
    func hasLabel(named name: String, type: LabelType) -> Bool {
        labels.contains { $0.name == name && $0.type == type }
    }
}

// MARK: - Preview Helpers

extension VideoSample {

    /// Create a sample video for previews with labels
    static var preview: VideoSample {
        let sample = VideoSample(
            localPath: "INCLUDE/Animals/Dog/sample_video_001.mp4",
            datasetName: "INCLUDE",
            originalFilename: "sample_video_001.mp4",
            fileSize: 15_000_000, // 15 MB
            duration: 45.5
        )
        return sample
    }

    /// Create a sample video with labels attached
    static func previewWithLabels() -> VideoSample {
        let sample = VideoSample(
            localPath: "INCLUDE/Animals/Dog/sample_video_001.mp4",
            datasetName: "INCLUDE",
            originalFilename: "sample_video_001.mp4",
            fileSize: 15_000_000,
            duration: 45.5
        )
        sample.labels = [
            Label(name: "Animals", type: .category),
            Label(name: "Dog", type: .word)
        ]
        return sample
    }

    /// Create multiple sample videos for list previews
    static var previewList: [VideoSample] {
        let words = ["Dog", "Cat", "Bird", "Fish", "Horse"]
        return words.enumerated().map { index, word in
            let sample = VideoSample(
                localPath: "INCLUDE/Animals/\(word)/video_\(index + 1).mp4",
                datasetName: "INCLUDE",
                originalFilename: "video_\(index + 1).mp4",
                fileSize: Int64.random(in: 5_000_000...25_000_000),
                duration: Double.random(in: 10...120)
            )
            sample.labels = [
                Label(name: "Animals", type: .category),
                Label(name: word, type: .word)
            ]
            return sample
        }
    }

    /// Create a sample sentence-level video (for ISL-CSLTR dataset)
    static var previewSentence: VideoSample {
        let sample = VideoSample(
            localPath: "ISL-CSLTR/sentences/video_s001.mp4",
            datasetName: "ISL-CSLTR",
            originalFilename: "video_s001.mp4",
            fileSize: 25_000_000,
            duration: 120.0
        )
        sample.labels = [
            Label(name: "How are you today?", type: .sentence)
        ]
        return sample
    }
}
