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
    
    // Background execution
    @Published var shouldContinueInBackground: Bool = true
    private let audioPlayer = SilentAudioPlayer()
    
    // Pause state
    @Published var isPaused: Bool = false
    private var pausedDuration: TimeInterval = 0
    private var lastPauseTime: Date?
    
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
        
        // Begin Background Task & Audio
        beginBackgroundTask()
        audioPlayer.start() // Start silent audio to keep app alive
        UIApplication.shared.isIdleTimerDisabled = true
        
        // Reset state
        isExtracting = true
        failedVideos = []
        progress = Progress(completed: 0, total: videos.count, currentVideoName: "Starting...")
        isPaused = false
        pausedDuration = 0
        lastPauseTime = nil
        
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
                self.cleanup()
            }
        }
    }
    
    /// Cancel ongoing extraction
    func cancel() {
        extractionTask?.cancel()
        cleanup()
    }
    
    private func cleanup() {
        extractionTask = nil
        isExtracting = false
        progress = nil
        currentVideo = nil
        executionMetrics = nil
        isPaused = false
        pausedDuration = 0
        
        audioPlayer.stop()
        UIApplication.shared.isIdleTimerDisabled = false
        endBackgroundTask()
    }
    
    // Debugging
    @Published var backgroundDebugInfo: String?
    
    // ...
    
    /// Pause extraction (e.g. backgrounding)
    func pause() {
        guard !isPaused else { return }
        // Only pause if we are actually extracting
        guard isExtracting else { return }
        
        // If we are allowed to continue in background AND audio session is valid:
        if shouldContinueInBackground {
            if audioPlayer.isSetupSuccessful {
                print("[BatchExtraction] Backgrounding... Keeping alive via Silent Audio.")
                backgroundDebugInfo = "Background Active (Audio OK)"
                return
            } else {
                let error = audioPlayer.setupError ?? "Unknown Audio Error"
                print("[BatchExtraction] Audio Setup Failed: \(error)")
                backgroundDebugInfo = "Background Failed: \(error)"
            }
        } else {
             backgroundDebugInfo = "Background Mode Disabled"
        }
        
        // Fallback: If capability missing or user disabled, pause to save state/metrics
        isPaused = true
        lastPauseTime = Date()
        print("[BatchExtraction] Paused execution.")
    }
    
    /// Resume extraction
    func resume() {
        backgroundDebugInfo = nil
        guard isPaused else { return } // If we never paused (due to background mode), this returns immediately
        
        if let lastPause = lastPauseTime {
            pausedDuration += Date().timeIntervalSince(lastPause)
        }
        isPaused = false
        lastPauseTime = nil
        print("[BatchExtraction] Resumed execution.")
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
        let startTime = Date() // This is "Process Start Time"
        var processedCount = 0
        
        // Loop videos
        for (index, video) in videos.enumerated() {
            // Check cancellation
            guard !Task.isCancelled else {
                await MainActor.run { cleanup() }
                return
            }
            
            // Handle Paused State
            while isPaused {
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s check
            }
            // Check cancellation again after resume
            guard !Task.isCancelled else { return }
            
            // Fetch fresh video to ensure relationships are up to date
            // Using the existing video object might be stale if passed from a previous query scope
            let videoID = video.id
            var currentVideo = video // Fallback
            
            if let freshVideo: VideoSample = modelContext.registeredModel(for: video.persistentModelID) {
                currentVideo = freshVideo
            } else {
                // Try fetch if not registered (unlikely since we just passed it)
                let descriptor = FetchDescriptor<VideoSample>(predicate: #Predicate { $0.id == videoID })
                if let fetched = try? modelContext.fetch(descriptor).first {
                     currentVideo = fetched
                }
            }
            
            // Debug check
            // print("checking \(currentVideo.fileName): \(currentVideo.featureSets.count) sets. Identifiers: \(currentVideo.featureSets.map(\.modelName))")

            // Smart Skip with File Validation
            if let existingSet = currentVideo.featureSets.first(where: { $0.modelName == model.rawValue }) {
                if existingSet.fileExists {
                    print("[BatchExtraction] Skipping \(currentVideo.fileName) - Already has \(model.rawValue) (File Verified)")
                    await MainActor.run {
                        self.progress = Progress(
                            completed: index + 1,
                            total: videos.count,
                            currentVideoName: currentVideo.fileName
                        )
                    }
                    continue
                } else {
                    print("[BatchExtraction] File missing for \(currentVideo.fileName) (\(existingSet.filePath)). Removing stale record and re-extracting.")
                    // Remove stale record
                    modelContext.delete(existingSet)
                    try? modelContext.save()
                }
            }
            
            // Update current video
            await MainActor.run {
                self.currentVideo = currentVideo
                self.progress = Progress(
                    completed: index,
                    total: videos.count,
                    currentVideoName: currentVideo.fileName
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
                    
                    // Calculate elapsed time excluding pause
                    var activeDuration = Date().timeIntervalSince(startTime) - self.pausedDuration
                    if self.isPaused, let lastPause = self.lastPauseTime {
                         activeDuration -= Date().timeIntervalSince(lastPause)
                    }
                    
                    // Prevent negative time
                    activeDuration = max(activeDuration, 1.0)
                    
                    let avgTime = activeDuration / Double(processedCount)
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
            // Show completion state
            self.progress = Progress(
                completed: videos.count,
                total: videos.count,
                currentVideoName: "Extraction Complete ✅"
            )
            self.isExtracting = false
            self.currentVideo = nil
            
            // Stop audio immediately as we are done
            self.audioPlayer.stop()
            self.endBackgroundTask()
            
            // Clear progress after a delay
            Task {
                try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds visibility
                await MainActor.run {
                    self.cleanup()
                }
            }
        }
    }
}
