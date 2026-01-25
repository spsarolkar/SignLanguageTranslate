import Foundation

/// Keras-like ReduceLROnPlateau callback.
/// Reduces learning rate when a metric has stopped improving.
///
/// ## Usage
/// ```swift
/// let lrScheduler = LRSchedulerCallback(
///     monitor: "valLoss",
///     factor: 0.1,
///     patience: 5
/// ) { newLR in
///     optimizer.learningRate = newLR
/// }
/// callbackManager.register(lrScheduler)
/// ```
public final class LRSchedulerCallback: TrainingCallback, @unchecked Sendable {
    
    // MARK: - Configuration
    
    /// Factor by which the learning rate will be reduced. new_lr = lr * factor
    public let factor: Float
    
    /// Number of epochs with no improvement after which learning rate will be reduced.
    public let patience: Int
    
    /// Lower bound on the learning rate.
    public let minLR: Float
    
    /// Number of epochs to wait before resuming normal operation after lr has been reduced.
    public let cooldown: Int
    
    /// The metric to monitor.
    public let monitor: String
    
    /// Whether lower values are better.
    public let mode: EarlyStoppingCallback.Mode
    
    /// Closure to update the optimizer's learning rate.
    public let updateLR: (@Sendable (Float) -> Void)
    
    // MARK: - State
    
    private var bestValue: Float
    private var waitCount: Int = 0
    private var cooldownCount: Int = 0
    private var currentLR: Float?
    
    // MARK: - Initialization
    
    public init(
        monitor: String = "valLoss",
        factor: Float = 0.1,
        patience: Int = 10,
        minLR: Float = 1e-6,
        cooldown: Int = 0,
        mode: EarlyStoppingCallback.Mode = .min,
        updateLR: @escaping @Sendable (Float) -> Void
    ) {
        self.monitor = monitor
        self.factor = factor
        self.patience = patience
        self.minLR = minLR
        self.cooldown = cooldown
        self.mode = mode
        self.updateLR = updateLR
        self.bestValue = mode == .min ? Float.infinity : -Float.infinity
    }
    
    // MARK: - TrainingCallback
    
    public func onTrainBegin(run: TrainingRun) async {
        bestValue = mode == .min ? Float.infinity : -Float.infinity
        waitCount = 0
        cooldownCount = 0
        currentLR = run.config?.learningRate
        print("[LRScheduler] Monitoring \(monitor) with patience=\(patience), factor=\(factor)")
    }
    
    public func onEpochEnd(epoch: Int, metrics: EpochMetrics, run: TrainingRun) async -> CallbackAction {
        guard let currentValue = getMonitoredValue(from: metrics) else {
            return .continue
        }
        
        // Use last known LR if not set tracking yet
        if currentLR == nil {
             currentLR = run.config?.learningRate ?? 1e-4 // Default fallback if config missing
        }
        
        // If in cooldown, just wait
        if cooldownCount > 0 {
            cooldownCount -= 1
            return .continue
        }
        
        let improved = isImproved(current: currentValue, best: bestValue)
        
        if improved {
            bestValue = currentValue
            waitCount = 0
        } else {
            waitCount += 1
            if waitCount >= patience {
                if let lr = currentLR, lr > minLR {
                    let newLR = max(lr * factor, minLR)
                    if newLR != lr {
                        print("[LRScheduler] Epoch \(epoch): \(monitor) plateaued. Reducing LR from \(lr) to \(newLR)")
                        updateLR(newLR)
                        currentLR = newLR
                        cooldownCount = cooldown
                        waitCount = 0
                    }
                }
            }
        }
        
        return .continue
    }
    
    public func onBatchEnd(batch: Int, metrics: BatchMetrics, run: TrainingRun) async {
        // Optionally track LR per batch
        if batch == 0 {
             currentLR = metrics.learningRate
        }
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
        // Simple comparison without minDelta for LR reduction
        switch mode {
        case .min:
            return current < best
        case .max:
            return current > best
        }
    }
}
