import Foundation
import SwiftData

/// Utility to populate the database with mock training data for testing
actor MockTrainingDataGenerator {
    
    /// Generate mock samples for testing training
    @MainActor
    static func generateMockSamples(modelContext: ModelContext, count: Int = 10) throws {
        print("[MockData] Generating \(count) mock training samples...")
        
        // Check if we already have samples
        let descriptor = FetchDescriptor<VideoSample>()
        let existing = try modelContext.fetch(descriptor)
        if !existing.isEmpty {
            print("[MockData] Found \(existing.count) existing samples, skipping generation")
            return
        }
        
        // Create mock labels
        let mockWords = ["Hello", "Thank You", "Please", "Yes", "No", "Help", "Water", "Food", "Dog", "Cat"]
        var createdLabels: [Label] = []
        
        for word in mockWords {
            let label = Label(name: word, type: .word)
            label.generateEmbedding() // Generate NLEmbedding
            modelContext.insert(label)
            createdLabels.append(label)
            print("[MockData] Created label: \(word)")
        }
        
        // Create mock video samples with features
        for i in 0..<count {
            let label = createdLabels[i % createdLabels.count]
            
            let sample = VideoSample(
                id: UUID(),
                localPath: "mock/video_\(i).mp4",
                datasetName: "MockDataset",
                originalFilename: "mock_video_\(i).mp4",
                fileSize: 1024000,
                duration: 2.0
            )
            sample.labels = [label]
            
            // Create mock feature set
            let mockFeaturePath = "Features/Mock/video_\(i)_features.json"
            let featureSet = FeatureSet(
                modelName: "vision_mock",
                extractedAt: .now,
                filePath: mockFeaturePath,
                frameCount: 60
            )
            
            // Generate and save mock feature file
            try generateMockFeatureFile(at: mockFeaturePath, frameCount: 60)
            
            sample.featureSets = [featureSet]
            
            modelContext.insert(sample)
        }
        
        try modelContext.save()
        print("[MockData] Successfully created \(count) mock samples")
    }
    
    /// Generate a mock feature JSON file
    private static func generateMockFeatureFile(at path: String, frameCount: Int) throws {
        let fileManager = FileManager.default
        let documentsDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let fullPath = documentsDir.appendingPathComponent(path)
        
        // Create directory if needed
        try fileManager.createDirectory(at: fullPath.deletingLastPathComponent(), withIntermediateDirectories: true)
        
        // Generate mock frames
        var frames: [[String: Any]] = []
        for i in 0..<frameCount {
            let frame: [String: Any] = [
                "frameIndex": i,
                "timestamp": Double(i) / 30.0,
                "body": generateMockKeypoints(count: 18),
                "leftHand": generateMockKeypoints(count: 21),
                "rightHand": generateMockKeypoints(count: 21)
            ]
            frames.append(frame)
        }
        
        let data: [String: Any] = [
            "modelName": "vision_mock",
            "version": 1,
            "frameCount": frameCount,
            "frames": frames
        ]
        
        let jsonData = try JSONSerialization.data(withJSONObject: data, options: .prettyPrinted)
        try jsonData.write(to: fullPath)
    }
    
    private static func generateMockKeypoints(count: Int) -> [[String: Any]] {
        var keypoints: [[String: Any]] = []
        for i in 0..<count {
            // Random positions normalized to 0-1
            let x = Float.random(in: 0.2...0.8)
            let y = Float.random(in: 0.2...0.8)
            let confidence = Float.random(in: 0.7...0.99)
            
            keypoints.append([
                "id": "point_\(i)",
                "x": x,
                "y": y,
                "confidence": confidence
            ])
        }
        return keypoints
    }
    
    /// Clear all mock data
    @MainActor
    static func clearMockData(modelContext: ModelContext) throws {
        let descriptor = FetchDescriptor<VideoSample>()
        let samples = try modelContext.fetch(descriptor)
        
        for sample in samples where sample.datasetName == "MockDataset" {
            modelContext.delete(sample)
        }
        
        try modelContext.save()
        print("[MockData] Cleared mock samples")
    }
}
