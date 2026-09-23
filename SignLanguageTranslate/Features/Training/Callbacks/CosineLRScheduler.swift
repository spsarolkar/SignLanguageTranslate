import Foundation
import MLX

/// Cosine Annealing Learning Rate Scheduler with Warmup
///
/// Gradually decreases learning rate following a cosine curve.
/// Optionally starts with a linear warmup phase.
public final class CosineLRScheduler: TrainingCallback, @unchecked Sendable {
    
    // MARK: - Properties
    
    private let baseLR: Float
    private let totalEpochs: Int
    private let minLR: Float
    private let warmupEpochs: Int
    
    /// Closure to update the optimizer's learning rate
    private let updateLR: (Float) -> Void
    private let logger: ((String) -> Void)?
    
    // MARK: - Initialization
    
    public init(
        baseLR: Float,
        totalEpochs: Int,
        minLR: Float = 1e-6,
        warmupEpochs: Int = 0,
        updateLR: @escaping (Float) -> Void,
        logger: ((String) -> Void)? = nil
    ) {
        self.baseLR = baseLR
        self.totalEpochs = max(1, totalEpochs)
        self.minLR = minLR
        self.warmupEpochs = warmupEpochs
        self.updateLR = updateLR
        self.logger = logger
    }
    
    // MARK: - TrainingCallback
    
    public func onTrainBegin(run: TrainingRun) async {
        // Set initial LR for epoch 0
        let initialLR = calculateLR(epoch: 0)
        updateLR(initialLR)
        logger?("Cosine Scheduler: Initial LR set to \(initialLR)")
    }
    
    public func onEpochEnd(epoch: Int, metrics: EpochMetrics, run: TrainingRun) async -> CallbackAction {
        // Calculate LR for the NEXT epoch
        let nextEpoch = epoch + 1
        
        // Don't update if we are done
        guard nextEpoch < totalEpochs else { return .continue }
        
        let newLR = calculateLR(epoch: nextEpoch)
        updateLR(newLR)
        // logger?("Cosine Scheduler: LR updated to \(newLR)") // Too verbose?
        return .continue
    }
    
    public func onBatchEnd(batch: Int, metrics: BatchMetrics, run: TrainingRun) async {}
    public func onTrainEnd(run: TrainingRun) async {}
    
    // MARK: - Calculation
    
    private func calculateLR(epoch: Int) -> Float {
        // Phase 1: Warmup
        if epoch < warmupEpochs {
            // Linear increase from minLR (or 0) to baseLR
            // let startLR = minLR
            let progress = Float(epoch + 1) / Float(warmupEpochs)
            return minLR + (baseLR - minLR) * progress
        }
        
        // Phase 2: Cosine Decay
        // Progress from 0 to 1 over the remaining epochs
        let effectiveEpoch = epoch - warmupEpochs
        let effectiveTotal = totalEpochs - warmupEpochs
        
        if effectiveTotal <= 0 { return minLR }
        
        let progress = Float(effectiveEpoch) / Float(effectiveTotal)
        // Cosine goes from 1 to -1. We want 1 to 0 mapping?
        // standard formula: lr = min + 0.5 * (max - min) * (1 + cos(pi * progress))
        // progress 0 -> cos(0)=1 -> 1+1=2 -> min + (max-min) = max
        // progress 1 -> cos(pi)=-1 -> 1-1=0 -> min
        
        let cosineDecay = 0.5 * (1 + cos(Float.pi * progress))
        return minLR + (baseLR - minLR) * cosineDecay
    }
}
