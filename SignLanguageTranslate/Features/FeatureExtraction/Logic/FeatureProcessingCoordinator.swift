import Foundation
import SwiftData

/// Coordinator for managing the feature extraction workflow and persistence
actor FeatureProcessingCoordinator {
    
    // MARK: - Properties
    
    private let extractionService = VideoFeatureExtractionService()
    private let fileManager = FeatureFileManager.shared
    private let modelContext: ModelContext
    
    // MARK: - Initialization
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    // MARK: - Public Methods
    
    /// Process a video sample to extract and save features
    /// - Parameters:
    ///   - video: The video sample to process
    ///   - onProgress: Progress callback
    /// - Returns: The created FeatureSet object
    func processVideo(
        _ video: VideoSample,
        onProgress: ((Double) -> Void)? = nil
    ) async throws -> FeatureSet {
        // 1. Verify file exists
        let videoURL = video.absoluteURL
        guard FileManager.default.fileExists(atPath: videoURL.path) else {
            throw AppError.fileNotFound(video.localPath)
        }
        
        // 2. Extract Features
        let features = try await extractionService.extractFeatures(from: videoURL, onProgress: onProgress)
        
        // 3. Save JSON to disk
        // Use a standardized model name for now
        let modelName = "Vision-BodyHand-v1"
        let shortModelName = FeatureFileManager.sanitizeModelName(modelName)
        
        let savedPath = try fileManager.saveFeatures(
            features,
            forVideoPath: video.localPath,
            modelName: shortModelName
        )
        
        // 4. Create SwiftData Record
        // We need to do this on the ModelContext's actor
        // Since we are inside an actor, we need to return the data to create it,
        // OR use a detached task with the context if it's MainActor bound (it usually is).
        
        let frameCount = features.count
        let videoID = video.id
        
        // We'll perform the DB write on the MainActor to ensure thread safety with the view context
        let featureSet = await MainActor.run {
            let featureSet = FeatureSet(
                modelName: modelName,
                filePath: savedPath,
                frameCount: frameCount
            )
            
            // Re-fetch video to attach (strictly needed if passing across actor boundaries?)
            // If 'video' is a Model from MainContext, we can just use it if we are on MainActor.
            
            video.featureSets.append(featureSet)
            // Note: SwiftData automatically saves or waits for explicit save
            return featureSet
        }
        
        return featureSet
    }
}

/// Simple error type for the coordinator
enum AppError: LocalizedError {
    case fileNotFound(String)
    
    var errorDescription: String? {
        switch self {
        case .fileNotFound(let path): return "File not found at: \(path)"
        }
    }
}
