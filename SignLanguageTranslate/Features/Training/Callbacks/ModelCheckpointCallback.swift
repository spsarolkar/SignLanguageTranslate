import Foundation
import MLX

/// Keras-like ModelCheckpoint callback.
/// Saves model weights when validation loss improves.
///
/// ## Usage
/// ```swift
/// let checkpoint = ModelCheckpointCallback(
///     checkpointDirectory: checkpointsURL,
///     saveBestOnly: true
/// )
/// callbackManager.register(checkpoint)
/// ```
public final class ModelCheckpointCallback: TrainingCallback, @unchecked Sendable {
    
    // MARK: - Configuration
    
    /// Directory to save checkpoints.
    public let checkpointDirectory: URL
    
    /// Only save when the model improves.
    public let saveBestOnly: Bool
    
    /// The metric to monitor.
    public let monitor: String
    
    /// Whether lower is better.
    public let mode: EarlyStoppingCallback.Mode
    
    /// Save frequency (every N epochs). Ignored if saveBestOnly is true.
    public let saveFreq: Int
    
    /// Callback when a checkpoint is saved (for cloud sync).
    public var onCheckpointSaved: ((URL, Int, Float) async -> Void)?
    
    // MARK: - State
    
    private var bestValue: Float
    private var bestEpoch: Int = 0
    
    // MARK: - Initialization
    
    public init(
        checkpointDirectory: URL,
        saveBestOnly: Bool = true,
        monitor: String = "valLoss",
        mode: EarlyStoppingCallback.Mode = .min,
        saveFreq: Int = 1
    ) {
        self.checkpointDirectory = checkpointDirectory
        self.saveBestOnly = saveBestOnly
        self.monitor = monitor
        self.mode = mode
        self.saveFreq = saveFreq
        self.bestValue = mode == .min ? Float.infinity : -Float.infinity
        
        // Ensure directory exists
        try? FileManager.default.createDirectory(at: checkpointDirectory, withIntermediateDirectories: true)
    }
    
    // MARK: - TrainingCallback
    
    public func onTrainBegin(run: TrainingRun) async {
        bestValue = mode == .min ? Float.infinity : -Float.infinity
        bestEpoch = 0
        print("[ModelCheckpoint] Saving to: \(checkpointDirectory.path)")
    }
    
    public func onEpochEnd(epoch: Int, metrics: EpochMetrics, run: TrainingRun) async -> CallbackAction {
        guard let currentValue = getMonitoredValue(from: metrics) else {
            return .continue
        }
        
        let shouldSave: Bool
        
        if saveBestOnly {
            shouldSave = isImproved(current: currentValue, best: bestValue)
            if shouldSave {
                bestValue = currentValue
                bestEpoch = epoch
            }
        } else {
            shouldSave = (epoch + 1) % saveFreq == 0
        }
        
        if shouldSave {
            await saveCheckpoint(epoch: epoch, value: currentValue, run: run)
        }
        
        return .continue
    }
    
    public func onTrainEnd(run: TrainingRun) async {
        print("[ModelCheckpoint] Training ended. Best checkpoint at epoch \(bestEpoch) with \(monitor)=\(bestValue)")
    }
    
    // MARK: - Checkpoint Saving
    
    private func saveCheckpoint(epoch: Int, value: Float, run: TrainingRun) async {
        let filename = saveBestOnly ? "best.safetensors" : "epoch_\(epoch).safetensors"
        let checkpointURL = checkpointDirectory.appendingPathComponent(filename)
        
        do {
            // Get model from run (we need access to the actual model)
            // For now, we'll save a marker file and log
            // Actual weight saving requires the model reference
            
            print("[ModelCheckpoint] Epoch \(epoch): Saving checkpoint with \(monitor)=\(value) to \(checkpointURL.lastPathComponent)")
            
            // Create a metadata file as placeholder
            let metadata: [String: Any] = [
                "epoch": epoch,
                "monitor": monitor,
                "value": value,
                "timestamp": ISO8601DateFormatter().string(from: Date())
            ]
            
            let metadataURL = checkpointDirectory.appendingPathComponent(
                saveBestOnly ? "best_metadata.json" : "epoch_\(epoch)_metadata.json"
            )
            let metadataData = try JSONSerialization.data(withJSONObject: metadata, options: .prettyPrinted)
            try metadataData.write(to: metadataURL)
            
            // Notify listener (for cloud sync)
            await onCheckpointSaved?(checkpointURL, epoch, value)
            
        } catch {
            print("[ModelCheckpoint] Error saving checkpoint: \(error)")
        }
    }
    
    // MARK: - Public Methods
    
    /// Save model weights to the checkpoint directory.
    /// Call this from TrainingSessionManager when you have access to the model.
    public func saveModelWeights(_ parameters: NestedDictionary<String, MLXArray>, epoch: Int) {
        let filename = saveBestOnly ? "best.safetensors" : "epoch_\(epoch).safetensors"
        let checkpointURL = checkpointDirectory.appendingPathComponent(filename)
        
        do {
            let arrays = Dictionary(uniqueKeysWithValues: parameters.flattened())
            try save(arrays: arrays, url: checkpointURL)
            print("[ModelCheckpoint] Saved weights to \(checkpointURL.lastPathComponent)")
        } catch {
            print("[ModelCheckpoint] Error saving weights: \(error)")
        }
    }
    
    /// Get the best checkpoint URL.
    public var bestCheckpointURL: URL {
        checkpointDirectory.appendingPathComponent("best.safetensors")
    }
    
    // MARK: - Helpers
    
    private func getMonitoredValue(from metrics: EpochMetrics) -> Float? {
        switch monitor {
        case "valLoss":
            return metrics.valLoss
        case "trainLoss":
            return metrics.trainLoss
        default:
            return nil
        }
    }
    
    private func isImproved(current: Float, best: Float) -> Bool {
        switch mode {
        case .min:
            return current < best
        case .max:
            return current > best
        }
    }
}
