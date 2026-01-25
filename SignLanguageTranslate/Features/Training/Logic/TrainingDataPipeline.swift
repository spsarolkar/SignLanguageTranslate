import Foundation
import SwiftData
import MLX

/// A specialized loader that converts extracted FeatureSets into MLX tensors for training.
/// Handles normalization, padding, and batching.
actor TrainingDataPipeline {
    
    // MARK: - Constants
    
    /// Maximum number of frames to preserve per sample (temporal dim)
    static let maxFrames = 60
    
    /// Total features per frame: Body (18) + LeftHand (21) + RightHand (21) = 60 points * 3 dims (x,y,z) = 180
    static let featureDim = 180
    
    // MARK: - Types
    
    struct TrainingBatch {
        /// Shape: [Batch, Time, Features] type: float32
        let inputs: MLXArray
        
        /// Shape: [Batch, EmbeddingDim] type: float32
        let targets: MLXArray
        
        /// Original Video IDs in this batch (for debugging)
        let videoIds: [UUID]
    }
    
    /// Sendable representation of a sample for safe cross-actor passing
    struct SampleInfo: Sendable {
        let id: UUID
        let featurePath: URL
        let embedding: [Float]
        let split: String? // "train", "validation", or "test"
    }
    
    // MARK: - Properties
    
    private let context: ModelContext
    private let fileManager = FeatureFileManager() // Use local instance to avoid actor isolation issues
    
    // MARK: - Initialization
    
    init(modelContext: ModelContext) {
        self.context = modelContext
    }
    
    // MARK: - Public API
    
    /// Loads training data, processes it, and yields batches asynchronously.
    /// - Parameters:
    ///   - samples: The list of SampleInfo to train on
    ///   - batchSize: Number of samples per batch
    ///   - shuffle: Whether to shuffle the data before batching
    /// - Returns: An async stream of TrainingBatch
    func batchStream(samples: [SampleInfo], batchSize: Int, shuffle: Bool = true, augment: Bool = false) -> AsyncStream<TrainingBatch> {
        AsyncStream { continuation in
            Task {
                var processingSamples = samples
                if shuffle {
                    processingSamples.shuffle()
                }
                
                // Process in chunks (Manual stride)
                var startIndex = 0
                while startIndex < processingSamples.count {
                    let endIndex = min(startIndex + batchSize, processingSamples.count)
                    let batchSamples = processingSamples[startIndex..<endIndex]
                    startIndex = endIndex
                    
                    // Parallel Load & Process
                    // Use TaskGroup to load files and process CPU tasks concurrently
                    let batchData: [(inputs: [Float], targets: [Float], id: UUID)] = await withTaskGroup(of: (inputs: [Float], targets: [Float], id: UUID)?.self) { group in
                        for sample in batchSamples {
                            group.addTask {
                                // Load (Async I/O)
                                // Note: we call a non-actor helper or actor method. 
                                // Since 'self' is an actor, 'await loadFeatures' hops to actor.
                                // BUT loadFeatures does I/O.
                                // To truly parallelize I/O, 'fileManager' should be used directly if possible or 'loadFeatures' should be nonisolated.
                                // 'fileManager' is let, but 'FeatureFileManager' is a struct (in latest code probably?) or actor?
                                // If FeatureFileManager is a struct/class not bound to actor, we can use it directly?
                                // In Line 41: private let fileManager = FeatureFileManager()
                                // Using 'self.fileManager' allows access.
                                
                                // Let's try calling the helper. Even if it hops, if it awaits I/O, it suspends, allowing others to run.
                                guard let features = await self.loadFeatures(at: sample.featurePath), !features.isEmpty else {
                                    return nil
                                }
                                
                                // Process (CPU) - NONISOLATED call, runs on this Task's thread pool
                                let processedInput = self.processFeatures(features, augment: augment)
                                
                                return (processedInput, sample.embedding, sample.id)
                            }
                        }
                        
                        var results: [(inputs: [Float], targets: [Float], id: UUID)] = []
                        for await result in group {
                            if let val = result {
                                results.append(val)
                            }
                        }
                        return results
                    }
                    
                    if batchData.isEmpty { continue }
                    
                    // Separate into columns
                    let inputs = batchData.map { $0.inputs }
                    let targets = batchData.map { $0.targets }
                    let ids = batchData.map { $0.id }
                    
                    let batch = createBatch(inputs: inputs, targets: targets, ids: ids)
                    continuation.yield(batch)
                }
                
                continuation.finish()
            }
        }
    }
    
    // Deprecated for cross-actor usage, kept for internal or single-actor context
    func batchStream(videoSamples: [VideoSample], batchSize: Int, shuffle: Bool = true) -> AsyncStream<TrainingBatch> {
        // Convert to SampleInfo if possible? 
        // Cannot access properties of non-sendable class comfortably here if passed from another actor.
        // We will ignore this method for the training loop and use the struct-based one.
        AsyncStream { continuation in continuation.finish() }
    }
    
    // MARK: - Private Processing
    
    private func loadFeatures(for featureSet: FeatureSet) async -> [FrameFeatures]? {
        await loadFeatures(at: URL(fileURLWithPath: featureSet.filePath))
    }

    private func loadFeatures(at url: URL) async -> [FrameFeatures]? {
        do {
            // FIX: Load directly from absolute URL. 
            // FeatureFileManager.loadFeatures(at:) expects a relative path and prepends the directory, causing double pathing.
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            return try decoder.decode([FrameFeatures].self, from: data)
        } catch {
            print("[Pipeline] Failed to load features from \(url): \(error)")
            return nil
        }
    }
    
    /// Converts raw [FrameFeatures] into a flat array of floats with Temporally Resampling and Augmentation
    /// Format: [TotalFrames * FeatureDim] (Row-major compatible)
    /// Converts raw [FrameFeatures] into a flat array of floats with Temporally Resampling and Augmentation
    /// Format: [TotalFrames * FeatureDim] (Row-major compatible)
    nonisolated private func processFeatures(_ frames: [FrameFeatures], augment: Bool) -> [Float] {
        // 1. Temporal Normalization (Framerate Independence)
        // Instead of truncating/padding, we resample to exactly maxFrames.
        var processedFrames = TimeResampler.resample(frames, targetCount: Self.maxFrames)
        
        // 2. Augmentation (Geometric Robustness)
        if augment {
            // PoseAugmenter is thread-safe (static structs)
            processedFrames = PoseAugmenter.augment(frames: processedFrames)
        }
        
        // 3. Flatten (Serialize)
        var flatData = [Float]()
        flatData.reserveCapacity(Self.maxFrames * Self.featureDim)
        
        for frame in processedFrames {
            flatData.append(contentsOf: serializeFrame(frame))
        }
        
        // Note: Resampler guarantees count == maxFrames, so no padding needed usually.
        // But safeguard just in case:
        let currentCount = flatData.count
        let expectedCount = Self.maxFrames * Self.featureDim
        
        if currentCount < expectedCount {
             flatData.append(contentsOf: Array(repeating: 0.0, count: expectedCount - currentCount))
        }
        
        return flatData
    }
    
    /// Serializes a single frame into [Float] (180 values) with normalization (centering)
    nonisolated private func serializeFrame(_ frame: FrameFeatures) -> [Float] {
        var params = [Float]()
        params.reserveCapacity(Self.featureDim) // 180
        
        // 1. Find Center (Neck) to normalize position
        // This makes the model invariant to where the person is standing in the frame
        var offsetX: Float = 0
        var offsetY: Float = 0
        
        if let neck = frame.body.first(where: { $0.id == "neck" }) ?? frame.body.first(where: { $0.id == "nose" }) {
            offsetX = neck.x
            offsetY = neck.y
        }
        
        // Helper to append points, applying offset
        func appendPoints(_ points: [UnifiedKeypoint]?, expected: Int) {
            if let pts = points {
                for p in pts {
                    // Normalize: Center around 0.5 (relative to neck)
                    // If p.x is 0.6 and neck is 0.5 -> new x is 0.6 - 0.5 = 0.1.
                    // We might want to keep it in 0...1 range or just centered around 0.
                    // Let's center around 0.
                    let nx = p.x - offsetX
                    let ny = p.y - offsetY
                    
                    params.append(nx)
                    params.append(ny)
                    params.append(p.confidence)
                }
                // If detected points < expected (e.g. occlusion?), pad remaining
                let extractedCount = pts.count
                if extractedCount < expected {
                    let missing = expected - extractedCount
                    params.append(contentsOf: Array(repeating: 0.0, count: missing * 3))
                }
            } else {
                // Entire group missing
                params.append(contentsOf: Array(repeating: 0.0, count: expected * 3))
            }
        }
        
        // Body (18 points)
        appendPoints(frame.body, expected: 18)
        
        // Left Hand (21 points)
        appendPoints(frame.leftHand, expected: 21)
        
        // Right Hand (21 points)
        appendPoints(frame.rightHand, expected: 21)
        
        // Total should be exactly 180. If model has different counts, this needs adjustment.
        // Vision Pose has specific counts. We assume UnifiedKeypoint input is normalized.
        
        // Ensure strictly featureDim size (truncate or pad if logic logic was off)
        if params.count > Self.featureDim {
            return Array(params.prefix(Self.featureDim))
        } else if params.count < Self.featureDim {
            return params + Array(repeating: 0.0, count: Self.featureDim - params.count)
        }
        
        return params
    }
    
    private func createBatch(inputs: [[Float]], targets: [[Float]], ids: [UUID]) -> TrainingBatch {
        // Inputs: [Batch, Time * Features] -> Reshape [Batch, Time, Features]
        let flatInputs = inputs.flatMap { $0 }
        let batchSize = inputs.count
        
        // MLXArray init(array, shape) -- no labels
        let inputTensor = MLXArray(flatInputs, [batchSize, Self.maxFrames, Self.featureDim])
        
        // Targets: [Batch, EmbeddingDim]
        let flatTargets = targets.flatMap { $0 }
        let embeddingDim = targets.first?.count ?? 0
        let targetTensor = MLXArray(flatTargets, [batchSize, embeddingDim])
        
        return TrainingBatch(inputs: inputTensor, targets: targetTensor, videoIds: ids)
    }
}
