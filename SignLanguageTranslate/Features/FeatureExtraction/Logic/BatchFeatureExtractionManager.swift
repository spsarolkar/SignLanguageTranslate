import Foundation
import SwiftData
import AVFoundation

/// Orchestrates bulk feature extraction across all videos in a dataset
public actor BatchFeatureExtractionManager {
    
    // MARK: - Types
    
    public enum ExtractionModel: String, CaseIterable, Sendable {
        case appleVision = "Apple Vision"
        case mediaPipe = "MediaPipe" // Future support
        
        var identifier: String {
            switch self {
            case .appleVision: return "vision"
            case .mediaPipe: return "mediapipe"
            }
        }
    }
    
    public struct ExtractionProgress: Sendable {
        public let totalVideos: Int
        public let processedVideos: Int
        public let currentVideo: String?
        public let errors: [String]
        public let status: Status
        
        public enum Status: Sendable {
            case idle
            case processing
            case completed
            case failed
        }
        
        public var percentage: Double {
            guard totalVideos > 0 else { return 0 }
            return Double(processedVideos) / Double(totalVideos)
        }
    }
    
    // MARK: - Properties
    
    private let extractionService = VideoFeatureExtractionService()
    private let fileManager = FeatureFileManager()
    
    private var currentProgress = ExtractionProgress(
        totalVideos: 0,
        processedVideos: 0,
        currentVideo: nil,
        errors: [],
        status: .idle
    )
    
    private var progressContinuation: AsyncStream<ExtractionProgress>.Continuation?
    
    // MARK: - Public API
    
    /// Stream of progress updates
    public var progress: AsyncStream<ExtractionProgress> {
        AsyncStream { continuation in
            self.progressContinuation = continuation
            continuation.yield(currentProgress)
        }
    }
    
    /// Extract features for all videos in a dataset
    public func extractFeatures(
        for datasetName: String,
        modelType: ExtractionModel,
        modelContext: ModelContext
    ) async throws {
        
        currentProgress = ExtractionProgress(
            totalVideos: 0,
            processedVideos: 0,
            currentVideo: nil,
            errors: [],
            status: .processing
        )
        
        // Fetch videos that need feature extraction
        let descriptor = FetchDescriptor<VideoSample>(
            predicate: #Predicate { $0.datasetName == datasetName }
        )
        
        let allVideos = try await MainActor.run {
            try modelContext.fetch(descriptor)
        }
        
        print("[BatchExtraction] Dataset '\(datasetName)' has \(allVideos.count) total videos")
        
        // Filter videos that don't have features for this model
        let videosNeedingExtraction = allVideos.filter { video in
            !video.featureSets.contains { $0.modelName.contains(modelType.identifier) }
        }
        
        currentProgress = ExtractionProgress(
            totalVideos: videosNeedingExtraction.count,
            processedVideos: 0,
            currentVideo: nil,
            errors: [],
            status: .processing
        )
        yieldProgress()
        
        print("[BatchExtraction] Found \(videosNeedingExtraction.count) videos needing extraction")
        
        // Process videos with concurrency limit
        var errors: [String] = []
        let maxConcurrent = 2
        
        for (index, video) in videosNeedingExtraction.enumerated() {
            // Update current video
            await updateProgress(
                processedVideos: index,
                currentVideo: video.displayTitle,
                errors: errors
            )
            
            do {
                try await extractFeaturesForVideo(
                    video,
                    modelType: modelType,
                    modelContext: modelContext
                )
            } catch {
                let errorMsg = "Failed to extract \(video.displayTitle): \(error.localizedDescription)"
                errors.append(errorMsg)
                print("[BatchExtraction] \(errorMsg)")
            }
        }
        
        // Final update
        await updateProgress(
            processedVideos: videosNeedingExtraction.count,
            currentVideo: nil,
            errors: errors,
            status: errors.isEmpty ? .completed : .failed
        )
        
        print("[BatchExtraction] Completed. \(videosNeedingExtraction.count) processed, \(errors.count) errors")
    }
    
    // MARK: - Private Methods
    
    private func extractFeaturesForVideo(
        _ video: VideoSample,
        modelType: ExtractionModel,
        modelContext: ModelContext
    ) async throws {
        
        let videoURL = video.absoluteURL
        
        // Verify video exists
        guard FileManager.default.fileExists(atPath: videoURL.path) else {
            throw BatchExtractionError.videoNotFound(videoURL)
        }
        
        // Extract features based on model type
        let frames: [FrameFeatures]
        switch modelType {
        case .appleVision:
            frames = try await extractionService.extractFeatures(from: videoURL)
        case .mediaPipe:
            throw BatchExtractionError.modelNotSupported(modelType.rawValue)
        }
        
        guard !frames.isEmpty else {
            throw BatchExtractionError.noFeaturesExtracted
        }
        
        // Save features to disk
        let featurePath = try await saveFeatures(
            frames,
            for: video,
            modelType: modelType
        )
        
        // Create FeatureSet record
        await MainActor.run {
            let featureSet = FeatureSet(
                modelName: "\(modelType.identifier)_\(modelType.rawValue)",
                extractedAt: .now,
                filePath: featurePath.relativePath,
                frameCount: frames.count
            )
            
            video.featureSets.append(featureSet)
            
            try? modelContext.save()
        }
    }
    
    private func saveFeatures(
        _ frames: [FrameFeatures],
        for video: VideoSample,
        modelType: ExtractionModel
    ) async throws -> URL {
        
        // Create relative path: Features/{Dataset}/{Category}/{video_id}_{model}.json
        let category = video.labels.first?.name ?? "Uncategorized"
        let videoID = video.fileNameWithoutExtension
        let fileName = "\(videoID)_\(modelType.identifier).json"
        
        let relativePath = "Features/\(video.datasetName)/\(category)/\(fileName)"
        
        // Convert frames to JSON
        let featuresData = FeatureFileData(
            modelName: modelType.identifier,
            version: 1,
            frameCount: frames.count,
            frames: frames
        )
        
        // Save using FeatureFileManager
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let jsonData = try encoder.encode(featuresData)
        
        let docsDir = await MainActor.run { FileManager.default.documentsDirectory }
        let fullPath = docsDir.appendingPathComponent(relativePath)
        
        // Create directory
        try FileManager.default.createDirectory(
            at: fullPath.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        
        try jsonData.write(to: fullPath)
        
        return fullPath
    }
    
    private func updateProgress(
        processedVideos: Int,
        currentVideo: String?,
        errors: [String],
        status: ExtractionProgress.Status = .processing
    ) async {
        currentProgress = ExtractionProgress(
            totalVideos: currentProgress.totalVideos,
            processedVideos: processedVideos,
            currentVideo: currentVideo,
            errors: errors,
            status: status
        )
        yieldProgress()
    }
    
    private func yieldProgress() {
        progressContinuation?.yield(currentProgress)
    }
}

// MARK: - Supporting Types

private struct FeatureFileData: Codable, Sendable {
    let modelName: String
    let version: Int
    let frameCount: Int
    let frames: [FrameFeatures]
}

// MARK: - Errors

enum BatchExtractionError: LocalizedError {
    case videoNotFound(URL)
    case modelNotSupported(String)
    case noFeaturesExtracted
    
    var errorDescription: String? {
        switch self {
        case .videoNotFound(let url):
            return "Video not found at \(url.path)"
        case .modelNotSupported(let model):
            return "Model \(model) is not yet supported"
        case .noFeaturesExtracted:
            return "No features could be extracted from the video"
        }
    }
}
