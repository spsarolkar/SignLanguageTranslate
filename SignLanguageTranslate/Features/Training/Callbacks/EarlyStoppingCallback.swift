import Foundation

/// Keras-like EarlyStopping callback.
/// Stops training when a monitored metric has stopped improving.
///
/// ## Usage
/// ```swift
/// let earlyStopping = EarlyStoppingCallback(
///     patience: 10,
///     minDelta: 0.0001,
///     restoreBestWeights: true
/// )
/// callbackManager.register(earlyStopping)
/// ```
public final class EarlyStoppingCallback: TrainingCallback, @unchecked Sendable {
    
    // MARK: - Configuration
    
    /// Number of epochs with no improvement after which training will be stopped.
    public let patience: Int
    
    /// Minimum change in the monitored quantity to qualify as an improvement.
    public let minDelta: Float
    
    /// Whether to restore model weights from the epoch with the best value.
    public let restoreBestWeights: Bool
    
    /// The metric to monitor (currently only "valLoss" supported).
    public let monitor: String
    
    /// Whether lower values are better (true for loss, false for accuracy).
    public let mode: Mode
    
    public enum Mode: String, Sendable {
        case min  // Lower is better (loss)
        case max  // Higher is better (accuracy)
    }
    
    // MARK: - State
    
    private var bestValue: Float
    private var bestEpoch: Int = 0
    private var waitCount: Int = 0
    private var bestWeightsPath: URL?
    
    // MARK: - Initialization
    
    public init(
        patience: Int = 10,
        minDelta: Float = 0.0001,
        restoreBestWeights: Bool = true,
        monitor: String = "valLoss",
        mode: Mode = .min
    ) {
        self.patience = patience
        self.minDelta = minDelta
        self.restoreBestWeights = restoreBestWeights
        self.monitor = monitor
        self.mode = mode
        self.bestValue = mode == .min ? Float.infinity : -Float.infinity
    }
    
    // MARK: - TrainingCallback
    
    public func onTrainBegin(run: TrainingRun) async {
        // Reset state for new training run
        bestValue = mode == .min ? Float.infinity : -Float.infinity
        bestEpoch = 0
        waitCount = 0
        bestWeightsPath = nil
        
        print("[EarlyStopping] Initialized with patience=\(patience), minDelta=\(minDelta)")
    }
    
    public func onEpochEnd(epoch: Int, metrics: EpochMetrics, run: TrainingRun) async -> CallbackAction {
        // Get monitored value
        guard let currentValue = getMonitoredValue(from: metrics) else {
            print("[EarlyStopping] Warning: Monitor '\(monitor)' not found in metrics, skipping check")
            return .continue
        }
        
        // Check if improved
        let improved = isImproved(current: currentValue, best: bestValue)
        
        if improved {
            print("[EarlyStopping] Epoch \(epoch): \(monitor) improved from \(bestValue) to \(currentValue)")
            bestValue = currentValue
            bestEpoch = epoch
            waitCount = 0
            
            // Save best weights path (actual saving done by ModelCheckpointCallback)
            // This is just for reference
        } else {
            waitCount += 1
            print("[EarlyStopping] Epoch \(epoch): \(monitor) did not improve from \(bestValue). Patience: \(waitCount)/\(patience)")
            
            if waitCount >= patience {
                let reason = "Early stopping triggered at epoch \(epoch). Best epoch: \(bestEpoch) with \(monitor)=\(bestValue)"
                print("[EarlyStopping] \(reason)")
                return .stopTraining(reason: reason)
            }
        }
        
        return .continue
    }
    
    public func onTrainEnd(run: TrainingRun) async {
        print("[EarlyStopping] Training ended. Best \(monitor)=\(bestValue) at epoch \(bestEpoch)")
        
        // TODO: If restoreBestWeights is true, load weights from bestWeightsPath
        // This requires coordination with ModelCheckpointCallback
    }
    
    // MARK: - Helpers
    
    private func getMonitoredValue(from metrics: EpochMetrics) -> Float? {
        switch monitor {
        case "valLoss":
            return metrics.valLoss
        case "trainLoss":
            return metrics.trainLoss
        case "valAccuracy":
            return metrics.valAccuracy
        case "trainAccuracy":
            return metrics.trainAccuracy
        default:
            return nil
        }
    }
    
    private func isImproved(current: Float, best: Float) -> Bool {
        switch mode {
        case .min:
            return current < (best - minDelta)
        case .max:
            return current > (best + minDelta)
        }
    }
}
