import Foundation
import SwiftData
import AVFoundation
import Combine
import UIKit // For UIApplication

/// Service for batch extraction of features from multiple videos
@MainActor
class BatchExtractionService: ObservableObject {
    @Published var isExtracting = false
    @Published var progress: Progress?
    @Published var currentVideo: VideoSample?
    @Published var failedVideos: [(video: VideoSample, error: String)] = []
    @Published var thermalState: ProcessInfo.ThermalState = .nominal
    @Published var executionMetrics: ExecutionMetrics?
    
    private var extractionTask: Task<Void, Never>?
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    
    struct ExecutionMetrics: Equatable {
        let startTime: Date
        let processedCount: Int
        let averageTimePerVideo: TimeInterval
        let estimatedTimeRemaining: TimeInterval
        
        var formattedAverageTime: String {
            String(format: "%.1fs", averageTimePerVideo)
        }
        
        var formattedETA: String {
            if processedCount == 0 { return "Calculating..." }
            
            let formatter = DateComponentsFormatter()
            formatter.allowedUnits = [.hour, .minute, .second]
            formatter.unitsStyle = .abbreviated
            return formatter.string(from: estimatedTimeRemaining) ?? "--"
        }
    }
    
    struct Progress: Equatable {
        let completed: Int
        let total: Int
        let currentVideoName: String
        
        var percentage: Double {
            guard total > 0 else { return 0 }
            return Double(completed) / Double(total)
        }
        
        var formattedProgress: String {
            "\(completed)/\(total)"
        }
    }
    
    enum ExtractionModel: String {
        case appleVision = "AppleVision"
        case mediaPipe = "MediaPipe"
    }
    
    /// Start batch extraction for all videos
    func extractAll(
        videos: [VideoSample],
        model: ExtractionModel,
        modelContext: ModelContext
    ) {
        // Cancel any existing extraction
        cancel()
        
        // Begin Background Task
        beginBackgroundTask()
        UIApplication.shared.isIdleTimerDisabled = true
        
        // Reset state
        isExtracting = true
        failedVideos = []
        progress = Progress(completed: 0, total: videos.count, currentVideoName: "Starting...")
        
        // Initialize metrics
        executionMetrics = ExecutionMetrics(
            startTime: Date(),
            processedCount: 0,
            averageTimePerVideo: 0,
            estimatedTimeRemaining: 0
        )
        
        extractionTask = Task {
            await performBatchExtraction(videos: videos, model: model, modelContext: modelContext)
            
            // Cleanup
            await MainActor.run {
                UIApplication.shared.isIdleTimerDisabled = false
                self.endBackgroundTask()
            }
        }
    }
    
    /// Cancel ongoing extraction
    func cancel() {
        extractionTask?.cancel()
        extractionTask = nil
        isExtracting = false
        progress = nil
        currentVideo = nil
        executionMetrics = nil
        
        UIApplication.shared.isIdleTimerDisabled = false
        endBackgroundTask()
    }
    
    // MARK: - Private Methods
    
    private func beginBackgroundTask() {
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "BatchExtraction") {
            // End task if time expires
            self.endBackgroundTask()
        }
    }
    
    private func endBackgroundTask() {
        if backgroundTaskID != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTaskID)
            backgroundTaskID = .invalid
        }
    }
    
    private func performBatchExtraction(
        videos: [VideoSample],
        model: ExtractionModel,
        modelContext: ModelContext
    ) async {
        let service = VideoFeatureExtractionService()
        let fileManager = FeatureFileManager()
        let startTime = Date()
        var processedCount = 0
        
        for (index, video) in videos.enumerated() {
            // Check cancellation
            guard !Task.isCancelled else {
                await MainActor.run {
                    self.isExtracting = false
                    self.progress = nil
                }
                return
            }
            
            // Skip if already extracted with this model
            if video.featureSets.contains(where: { $0.modelName == model.rawValue }) {
                await MainActor.run {
                    self.progress = Progress(
                        completed: index + 1,
                        total: videos.count,
                        currentVideoName: video.fileName
                    )
                }
                continue
            }
            
            // Update current video
            await MainActor.run {
                self.currentVideo = video
                self.progress = Progress(
                    completed: index,
                    total: videos.count,
                    currentVideoName: video.fileName
                )
            }
            
            // Extract features
            do {
                let videoURL = video.absoluteURL
                
                // Verify file exists
                guard FileManager.default.fileExists(atPath: videoURL.path) else {
                    throw NSError(domain: "BatchExtraction", code: 404, userInfo: [
                        NSLocalizedDescriptionKey: "Video file not found"
                    ])
                }
                
                // Extract
                let features = try await service.extractFeatures(from: videoURL)
                let outputPath = try fileManager.saveFeatures(
                    features,
                    forVideoPath: video.localPath,
                    modelName: model.rawValue
                )
                
                // Save to database
                await MainActor.run {
                    let featureSet = FeatureSet(
                        modelName: model.rawValue,
                        filePath: outputPath,
                        frameCount: features.count
                    )
                    featureSet.videoSample = video
                    modelContext.insert(featureSet)
                    
                    do {
                        try modelContext.save()
                    } catch {
                        print("[BatchExtraction] Failed to save FeatureSet: \(error)")
                    }
                    
                    // Update Metrics
                    processedCount += 1
                    let timeElapsed = Date().timeIntervalSince(startTime)
                    let avgTime = timeElapsed / Double(processedCount)
                    let remaining = Double(videos.count - (index + 1)) * avgTime
                    
                    self.executionMetrics = ExecutionMetrics(
                        startTime: startTime,
                        processedCount: processedCount,
                        averageTimePerVideo: avgTime,
                        estimatedTimeRemaining: remaining
                    )
                }
                
            } catch {
                // Track failure but continue
                await MainActor.run {
                    self.failedVideos.append((video: video, error: error.localizedDescription))
                }
                print("[BatchExtraction] Failed to extract \(video.fileName): \(error)")
            }
            
            // Adaptive Thermal Throttling
            let thermalState = ProcessInfo.processInfo.thermalState
            await MainActor.run { self.thermalState = thermalState }
            
            var sleepNanoseconds: UInt64 = 100_000_000 // 0.1s (default)
            
            switch thermalState {
            case .nominal:
                sleepNanoseconds = 100_000_000 // 0.1s
            case .fair:
                sleepNanoseconds = 1_000_000_000 // 1.0s (let it cool slightly)
            case .serious:
                sleepNanoseconds = 5_000_000_000 // 5.0s (significant cooldown)
                print("[BatchExtraction] Thermal state SERIOUS. Throttling execution.")
            case .critical:
                sleepNanoseconds = 30_000_000_000 // 30.0s (emergency cooldown)
                print("[BatchExtraction] Thermal state CRITICAL. Pausing for cooldown.")
            @unknown default:
                sleepNanoseconds = 500_000_000 // 0.5s conservative default
            }
            
            try? await Task.sleep(nanoseconds: sleepNanoseconds)
        }
        
        // Extraction complete
        await MainActor.run {
            self.isExtracting = false
            self.progress = Progress(
                completed: videos.count,
                total: videos.count,
                currentVideoName: "Complete"
            )
            self.currentVideo = nil
            self.executionMetrics = nil 
            
            // Clear progress after a delay
            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
                await MainActor.run {
                    self.progress = nil
                }
            }
        }
    }
}
