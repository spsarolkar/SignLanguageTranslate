import Foundation
import SwiftData
import Combine
import SwiftUI

/// A temporary utility script to migrate incorrectly formatted BatchExtractor .json files
/// into the standardized FeatureFileManager format without needing to rerun CPU extraction.
/// Used to rescue the 6-hour extraction runs that users performed prior to the schema fix.
@MainActor
class LegacyFeatureFixer: ObservableObject {
    
    @Published var isFixing = false
    @Published var progress: Double = 0
    @Published var totalFixed: Int = 0
    @Published var totalFailed: Int = 0
    @Published var errorMessage: String?
    
    // Legacy schema that the BatchExtractor mistakenly used
    private struct LegacyFeatureFileData: Codable {
        let modelName: String
        let version: Int
        let frameCount: Int
        let frames: [FrameFeatures]
    }
    
    func fixLegacyFeatures(for dataset: Dataset, in context: ModelContext) {
        Task {
            isFixing = true
            progress = 0
            totalFixed = 0
            totalFailed = 0
            errorMessage = nil
            
            do {
                // Fetch all videos for this dataset
                let datasetName = dataset.name
                let descriptor = FetchDescriptor<VideoSample>(
                    predicate: #Predicate { $0.datasetName == datasetName }
                )
                
                let videos = try await MainActor.run {
                    try context.fetch(descriptor)
                }
                
                let fileManager = FeatureFileManager.shared
                let systemFileManager = FileManager.default
                let documentDir = systemFileManager.documentsDirectory
                
                let totalVideos = videos.count
                
                for (index, video) in videos.enumerated() {
                    progress = Double(index) / Double(totalVideos)
                    
                    // Look for AppleVision feature sets attached to this video (which may point to legacy paths)
                    guard let featureSet = video.featureSets.first(where: { $0.modelName == "AppleVision" || $0.modelName == "vision_AppleVision" }) else {
                        continue // No features to fix
                    }
                    
                    let possibleCorruptedPath = documentDir.appendingPathComponent(featureSet.filePath)
                    
                    guard systemFileManager.fileExists(atPath: possibleCorruptedPath.path) else {
                        continue // File doesn't exist, might be a dangling reference or already fixed
                    }
                    
                    do {
                        // Attempt to read the file.
                        let data = try Data(contentsOf: possibleCorruptedPath)
                        
                        // Try decoding as the NEW schema (pure array). If it succeeds, it's already fixed.
                        if let _ = try? JSONDecoder().decode([FrameFeatures].self, from: data) {
                            continue // Already in correct format
                        }
                        
                        // If it fails, it's likely the old schema. Try decoding with Legacy schema.
                        let legacyData = try JSONDecoder().decode(LegacyFeatureFileData.self, from: data)
                        let rawFrames = legacyData.frames
                        
                        // Resave using the proper standardized FeatureFileManager utility!
                        let correctRelativePath = try fileManager.saveFeatures(
                            rawFrames,
                            forVideoPath: video.localPath,
                            modelName: "AppleVision"
                        )
                        
                        // Delete the old wrapper/schema file if it was saved securely somewhere else
                        // (Assuming fileManager.saveFeatures overwrites or creates a new one)
                        if featureSet.filePath != correctRelativePath {
                             try? systemFileManager.removeItem(at: possibleCorruptedPath)
                        }
                        
                        // Update the SwiftData Model Database entry to reflect the clean standardized state
                        await MainActor.run {
                            // Purge duplicate shadow records if they exist
                            let existingSets = video.featureSets.filter { $0.modelName == "AppleVision" || $0.modelName == "vision_AppleVision" }
                            for oldSet in existingSets {
                                context.delete(oldSet)
                                video.featureSets.removeAll(where: { $0.id == oldSet.id })
                            }

                            // Create the fresh fixed reference
                            let newSet = FeatureSet(
                                modelName: "AppleVision",
                                filePath: correctRelativePath,
                                frameCount: rawFrames.count
                            )
                            newSet.videoSample = video
                            context.insert(newSet)
                            video.featureSets.append(newSet)
                            
                            try? context.save()
                        }
                        
                        await MainActor.run {
                            totalFixed += 1
                        }
                        
                    } catch {
                        print("Failed to rescue features for \(video.displayTitle): \(error)")
                        await MainActor.run {
                            totalFailed += 1
                        }
                    }
                }
                
                await MainActor.run {
                    progress = 1.0
                    isFixing = false
                }
                
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isFixing = false
                }
            }
        }
    }
}
