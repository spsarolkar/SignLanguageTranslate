import Foundation
import SwiftData

/// Represents a set of extracted features for a specific video
///
/// Stores metadata about the extraction process and points to the stored feature file.
/// A video can have multiple feature sets (e.g., one from Apple Vision, one from MediaPipe).
@Model
final class FeatureSet {
    // MARK: - stored Properties
    
    /// Unique identifier
    var id: UUID
    
    /// Name of the model used for extraction (e.g., "Vision.VNDetectHumanBodyPoseRequest", "MediaPipe.BlazePose")
    var modelName: String
    
    /// Timestamp when extraction was performed
    var extractedAt: Date
    
    /// Relative path to the JSON/Parquet file containing the actual keypoints
    /// Example: "Features/INCLUDE/Animals/Dog/video_001_vision_body.json"
    var filePath: String
    
    /// Number of frames successfully processed
    var frameCount: Int
    
    /// Format version of the feature file
    var formatVersion: Int
    
    // MARK: - Relationships
    
    /// The video sample these features belong to
    var videoSample: VideoSample?
    
    // MARK: - Computed Properties
    
    /// Absolute URL to the feature file
    var absoluteURL: URL {
        FileManager.default.datasetsDirectory.appendingPathComponent(filePath)
    }
    
    /// Whether the feature file exists on disk
    var fileExists: Bool {
        FileManager.default.fileExists(at: absoluteURL)
    }
    
    // MARK: - Initialization
    
    init(
        id: UUID = UUID(),
        modelName: String,
        extractedAt: Date = .now,
        filePath: String,
        frameCount: Int,
        formatVersion: Int = 1
    ) {
        self.id = id
        self.modelName = modelName
        self.extractedAt = extractedAt
        self.filePath = filePath
        self.frameCount = frameCount
        self.formatVersion = formatVersion
    }
}
