import Foundation

/// Manages filesystem operations for feature files
struct FeatureFileManager {
    
    // MARK: - Properties
    
    static let shared = FeatureFileManager()
    private let storageRoot: URL

    init(storageRoot: URL? = nil) {
        self.storageRoot = storageRoot ?? FileManager.default.datasetsDirectory
    }

    enum ArtifactError: LocalizedError {
        case emptyFeatures

        var errorDescription: String? {
            "This feature file contains no frames. Choose Extract all in Pipeline to re-extract incomplete results."
        }
    }
    
    private let fileManager = FileManager.default
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted // For readability/debugging
        return encoder
    }()
    
    private let decoder = JSONDecoder()
    
    // MARK: - Public Methods
    
    /// Save extracted features to disk
    /// - Parameters:
    ///   - features: The array of frame features to save
    ///   - videoPath: The relative path of the original video (e.g. "INCLUDE/Animals/Dog/video.mp4")
    ///   - modelName: The model used (e.g. "Vision")
    /// - Returns: The relative path to the saved feature file
    func saveFeatures(_ features: [FrameFeatures], forVideoPath videoPath: String, modelName: String) throws -> String {
        guard !features.isEmpty else { throw ArtifactError.emptyFeatures }
        // Construct feature path: Features/<Dataset>/.../<VideoName>_<Model>.json
        // Input videoPath: "INCLUDE/Animals/Dog/video.mp4"
        // Output path: "Features/INCLUDE/Animals/Dog/video_Vision_body.json" (relative)
        
        let videoURL = URL(fileURLWithPath: videoPath)
        
        // Create parallel directory structure under "Features"
        let relativeDir = (videoPath as NSString).deletingLastPathComponent
        let featuresDirName = "Features" // Top level folder
        
        let absoluteFeaturesDir = storageRoot
            .appendingPathComponent(featuresDirName)
            .appendingPathComponent(relativeDir) // Replicate internal structure
        
        try fileManager.createDirectory(at: absoluteFeaturesDir, withIntermediateDirectories: true)
        
        let filename = videoURL.deletingPathExtension().lastPathComponent
        let featureFilename = "\(filename)_\(modelName)_features.json"
        
        let absoluteFileURL = absoluteFeaturesDir.appendingPathComponent(featureFilename)
        
        let data = try encoder.encode(features)
        try data.write(to: absoluteFileURL, options: .atomic)
        
        // Return relative path from datasets directory
        // e.g. "Features/INCLUDE/Animals/Dog/video_Vision_features.json"
        let fullRelativePath = "\(featuresDirName)/\(relativeDir)/\(featureFilename)"
        // Clean up double slashes just in case
        return fullRelativePath.replacingOccurrences(of: "//", with: "/")
    }
    
    /// Load features from disk
    /// - Parameter relativePath: Relative path to the feature file
    /// - Returns: Array of FrameFeatures
    func loadFeatures(at relativePath: String) throws -> [FrameFeatures] {
        let absoluteURL = storageRoot.appendingPathComponent(relativePath)
        let data = try Data(contentsOf: absoluteURL)
        let frames = try decoder.decode([FrameFeatures].self, from: data)
        guard !frames.isEmpty else { throw ArtifactError.emptyFeatures }
        return frames
    }

    /// Existing metadata alone is insufficient: the saved JSON must be readable
    /// and agree with its positive frame count before a batch may skip the clip.
    func canReuseFeatures(at relativePath: String, frameCount: Int) -> Bool {
        guard frameCount > 0, let frames = try? loadFeatures(at: relativePath) else { return false }
        return frames.count == frameCount
    }
    
    /// Get the standard name context for a model
    /// - Parameter model: The model name
    /// - Returns: A sanitized short string for filenames
    static func sanitizeModelName(_ model: String) -> String {
        // Simple mapping or sanitization
        if model.contains("Vision") { return "Vision" }
        if model.contains("MediaPipe") { return "MediaPipe" }
        return "Custom"
    }
}
