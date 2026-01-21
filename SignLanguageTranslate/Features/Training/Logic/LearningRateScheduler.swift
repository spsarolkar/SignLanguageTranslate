import Foundation
import MLX
import MLXNN
import MLXOptimizers

/// Learning rate scheduling strategies for training
///
/// Provides various scheduling algorithms to adjust learning rate during training:
/// - Warmup: Gradual increase from 0 to base LR
/// - Cosine Annealing: Smooth decay following cosine curve
/// - Step Decay: Reduce LR at specific epochs
/// - Linear Decay: Linear decrease over training
///
/// ## Usage
/// ```swift
/// let scheduler = LearningRateScheduler(
///     baseLR: 1e-4,
///     strategy: .cosineAnnealing(warmupSteps: 500, totalSteps: 10000)
/// )
///
/// for step in 0..<10000 {
///     let lr = scheduler.getLearningRate(step: step)
///     optimizer.learningRate = lr
///     // ... training step
/// }
/// ```
public struct LearningRateScheduler: Sendable {

    // MARK: - Types

    public enum Strategy: Sendable {
        /// Constant learning rate (no scheduling)
        case constant

        /// Linear warmup then constant
        case warmupConstant(warmupSteps: Int)

        /// Linear warmup then linear decay to minLR
        case warmupLinearDecay(warmupSteps: Int, totalSteps: Int, minLR: Float)

        /// Cosine annealing with optional warmup
        case cosineAnnealing(warmupSteps: Int, totalSteps: Int, minLR: Float)

        /// Step decay: multiply LR by factor at specific steps
        case stepDecay(stepSize: Int, gamma: Float)

        /// Exponential decay
        case exponentialDecay(decayRate: Float, decaySteps: Int)

        /// One-cycle policy (warmup -> peak -> decay)
        case oneCycle(totalSteps: Int, maxLR: Float, divFactor: Float, finalDivFactor: Float)

        /// Reduce on plateau (requires external loss tracking)
        case reduceLROnPlateau(factor: Float, patience: Int, minLR: Float)
    }

    // MARK: - Properties

    public let baseLR: Float
    public let strategy: Strategy

    // For reduce on plateau
    private var bestLoss: Float = Float.infinity
    private var patienceCounter: Int = 0
    private var currentLR: Float

    // MARK: - Initialization

    public init(baseLR: Float, strategy: Strategy = .constant) {
        self.baseLR = baseLR
        self.strategy = strategy
        self.currentLR = baseLR
    }

    // MARK: - Get Learning Rate

    /// Get the learning rate for the current step
    public mutating func getLearningRate(step: Int, epoch: Int = 0) -> Float {
        switch strategy {
        case .constant:
            return baseLR

        case .warmupConstant(let warmupSteps):
            if step < warmupSteps {
                return baseLR * Float(step + 1) / Float(warmupSteps)
            }
            return baseLR

        case .warmupLinearDecay(let warmupSteps, let totalSteps, let minLR):
            if step < warmupSteps {
                // Linear warmup
                return baseLR * Float(step + 1) / Float(warmupSteps)
            } else {
                // Linear decay
                let decaySteps = totalSteps - warmupSteps
                let decayProgress = Float(step - warmupSteps) / Float(decaySteps)
                return max(minLR, baseLR * (1.0 - decayProgress) + minLR * decayProgress)
            }

        case .cosineAnnealing(let warmupSteps, let totalSteps, let minLR):
            if step < warmupSteps {
                // Linear warmup
                return baseLR * Float(step + 1) / Float(warmupSteps)
            } else {
                // Cosine annealing
                let decaySteps = totalSteps - warmupSteps
                let progress = Float(step - warmupSteps) / Float(decaySteps)
                let cosineDecay = 0.5 * (1.0 + cos(Float.pi * progress))
                return minLR + (baseLR - minLR) * cosineDecay
            }

        case .stepDecay(let stepSize, let gamma):
            let numDecays = step / stepSize
            return baseLR * pow(gamma, Float(numDecays))

        case .exponentialDecay(let decayRate, let decaySteps):
            let numDecays = Float(step) / Float(decaySteps)
            return baseLR * pow(decayRate, numDecays)

        case .oneCycle(let totalSteps, let maxLR, let divFactor, let finalDivFactor):
            let initialLR = maxLR / divFactor
            let finalLR = initialLR / finalDivFactor

            // 30% warmup, 70% decay
            let warmupEnd = Int(Float(totalSteps) * 0.3)

            if step < warmupEnd {
                // Linear warmup from initial to max
                let progress = Float(step) / Float(warmupEnd)
                return initialLR + (maxLR - initialLR) * progress
            } else {
                // Cosine decay from max to final
                let decayProgress = Float(step - warmupEnd) / Float(totalSteps - warmupEnd)
                let cosineDecay = 0.5 * (1.0 + cos(Float.pi * decayProgress))
                return finalLR + (maxLR - finalLR) * cosineDecay
            }

        case .reduceLROnPlateau(_, _, _):
            // Use updateOnPlateau() for this strategy
            return currentLR
        }
    }

    /// Update learning rate based on validation loss (for plateau strategy)
    public mutating func updateOnPlateau(validationLoss: Float) -> Float {
        guard case .reduceLROnPlateau(let factor, let patience, let minLR) = strategy else {
            return currentLR
        }

        if validationLoss < bestLoss {
            bestLoss = validationLoss
            patienceCounter = 0
        } else {
            patienceCounter += 1

            if patienceCounter >= patience {
                currentLR = max(minLR, currentLR * factor)
                patienceCounter = 0
                print("[LRScheduler] Reduced LR to \(currentLR) (plateau detected)")
            }
        }

        return currentLR
    }

    // MARK: - Convenience Factories

    /// Create a scheduler with warmup and cosine decay (recommended for transformers)
    public static func transformerSchedule(
        baseLR: Float = 1e-4,
        warmupSteps: Int = 500,
        totalSteps: Int = 10000
    ) -> LearningRateScheduler {
        LearningRateScheduler(
            baseLR: baseLR,
            strategy: .cosineAnnealing(
                warmupSteps: warmupSteps,
                totalSteps: totalSteps,
                minLR: baseLR * 0.01
            )
        )
    }

    /// Create a 1-cycle scheduler (good for faster convergence)
    public static func oneCycleSchedule(
        maxLR: Float = 1e-3,
        totalSteps: Int = 10000
    ) -> LearningRateScheduler {
        LearningRateScheduler(
            baseLR: maxLR,
            strategy: .oneCycle(
                totalSteps: totalSteps,
                maxLR: maxLR,
                divFactor: 25.0,  // Initial LR = maxLR / 25
                finalDivFactor: 10000.0  // Final LR = initial / 10000
            )
        )
    }

    /// Create a simple step decay scheduler
    public static func stepDecaySchedule(
        baseLR: Float = 1e-4,
        stepSize: Int = 1000,
        gamma: Float = 0.9
    ) -> LearningRateScheduler {
        LearningRateScheduler(
            baseLR: baseLR,
            strategy: .stepDecay(stepSize: stepSize, gamma: gamma)
        )
    }
}

// MARK: - Learning Rate History

/// Tracks learning rate values over training for visualization
public struct LearningRateHistory: Sendable {
    public var entries: [(step: Int, lr: Float)] = []

    public mutating func record(step: Int, lr: Float) {
        entries.append((step, lr))
    }

    public var asArrays: (steps: [Int], lrs: [Float]) {
        (entries.map { $0.step }, entries.map { $0.lr })
    }
}

// MARK: - Integration with Adam Optimizer

extension Adam {
    /// Create an Adam optimizer with a learning rate scheduler
    public convenience init(scheduler: LearningRateScheduler) {
        self.init(learningRate: scheduler.baseLR)
    }

    /// Update learning rate from scheduler
    public func setLearningRate(_ lr: Float) {
        // Note: MLX Adam uses learningRate property
        // This is a helper to make the API cleaner
        self.learningRate = lr
    }
}

// MARK: - Warmup Wrapper

/// Wrapper that adds warmup to any optimizer
public struct WarmupOptimizer {
    private let optimizer: Adam
    private var scheduler: LearningRateScheduler
    private var step: Int = 0

    public init(optimizer: Adam, warmupSteps: Int, baseLR: Float) {
        self.optimizer = optimizer
        self.scheduler = LearningRateScheduler(
            baseLR: baseLR,
            strategy: .warmupConstant(warmupSteps: warmupSteps)
        )
    }

    public mutating func step(model: Module, gradients: ModuleParameters) {
        let lr = scheduler.getLearningRate(step: step)
        optimizer.learningRate = lr
        optimizer.update(model: model, gradients: gradients)
        step += 1
    }
}
