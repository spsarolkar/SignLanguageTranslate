import Foundation

// MARK: - Training Callback Protocol

/// Protocol for Keras-like training callbacks.
/// Implement this to hook into the training loop at key points.
public protocol TrainingCallback: Sendable {
    
    /// Called once at the start of training.
    /// - Parameter run: The training run being started.
    func onTrainBegin(run: TrainingRun) async
    
    /// Called at the end of each epoch.
    /// - Parameters:
    ///   - epoch: The epoch that just completed (0-indexed).
    ///   - metrics: Metrics for this epoch.
    ///   - run: The current training run.
    /// - Returns: Action to take (continue or stop training).
    func onEpochEnd(epoch: Int, metrics: EpochMetrics, run: TrainingRun) async -> CallbackAction
    
    /// Called at the end of each batch (optional, default no-op).
    /// - Parameters:
    ///   - batch: The batch that just completed.
    ///   - metrics: Metrics for this batch.
    ///   - run: The current training run.
    func onBatchEnd(batch: Int, metrics: BatchMetrics, run: TrainingRun) async
    
    /// Called once at the end of training (normal completion or early stop).
    /// - Parameter run: The training run that completed.
    func onTrainEnd(run: TrainingRun) async
}

// MARK: - Default Implementations

public extension TrainingCallback {
    func onTrainBegin(run: TrainingRun) async {
        // Default: no-op
    }
    
    func onBatchEnd(batch: Int, metrics: BatchMetrics, run: TrainingRun) async {
        // Default: no-op (batch callbacks are optional and expensive if syncing)
    }
    
    func onTrainEnd(run: TrainingRun) async {
        // Default: no-op
    }
}

// MARK: - Callback Action

/// Action returned by callbacks to control training flow.
public enum CallbackAction: Sendable {
    /// Continue training normally.
    case `continue`
    
    /// Stop training early with the given reason.
    case stopTraining(reason: String)
}

// MARK: - Epoch Metrics

/// Metrics collected for a single epoch.
public struct EpochMetrics: Codable, Sendable {
    public let epoch: Int
    public let trainLoss: Float
    public let valLoss: Float?
    public let trainAccuracy: Float?
    public let valAccuracy: Float?
    public let epochDuration: TimeInterval
    public let timestamp: Date
    public let savedCheckpoint: Bool
    public let batches: [BatchMetrics]
    
    public init(
        epoch: Int,
        trainLoss: Float,
        valLoss: Float? = nil,
        trainAccuracy: Float? = nil,
        valAccuracy: Float? = nil,
        epochDuration: TimeInterval,
        timestamp: Date = Date(),
        savedCheckpoint: Bool = false,
        batches: [BatchMetrics] = []
    ) {
        self.epoch = epoch
        self.trainLoss = trainLoss
        self.valLoss = valLoss
        self.trainAccuracy = trainAccuracy
        self.valAccuracy = valAccuracy
        self.epochDuration = epochDuration
        self.timestamp = timestamp
        self.savedCheckpoint = savedCheckpoint
        self.batches = batches
    }
}

// MARK: - Batch Metrics

/// Metrics collected for a single batch.
public struct BatchMetrics: Codable, Sendable {
    public let batchIndex: Int
    public let globalStep: Int
    public let loss: Float
    public let learningRate: Float
    public let batchDuration: TimeInterval
    public let timestamp: Date
    
    public init(
        batchIndex: Int,
        globalStep: Int,
        loss: Float,
        learningRate: Float,
        batchDuration: TimeInterval,
        timestamp: Date = Date()
    ) {
        self.batchIndex = batchIndex
        self.globalStep = globalStep
        self.loss = loss
        self.learningRate = learningRate
        self.batchDuration = batchDuration
        self.timestamp = timestamp
    }
}

// MARK: - Callback Manager

/// Manages a collection of callbacks and dispatches events to them.
public actor CallbackManager {
    private var callbacks: [any TrainingCallback] = []
    
    public init() {}
    
    public func register(_ callback: any TrainingCallback) {
        callbacks.append(callback)
    }
    
    public func clear() {
        callbacks.removeAll()
    }
    
    public func notifyTrainBegin(run: TrainingRun) async {
        for callback in callbacks {
            await callback.onTrainBegin(run: run)
        }
    }
    
    public func notifyEpochEnd(epoch: Int, metrics: EpochMetrics, run: TrainingRun) async -> CallbackAction {
        for callback in callbacks {
            let action = await callback.onEpochEnd(epoch: epoch, metrics: metrics, run: run)
            if case .stopTraining = action {
                return action
            }
        }
        return .continue
    }
    
    public func notifyBatchEnd(batch: Int, metrics: BatchMetrics, run: TrainingRun) async {
        for callback in callbacks {
            await callback.onBatchEnd(batch: batch, metrics: metrics, run: run)
        }
    }
    
    public func notifyTrainEnd(run: TrainingRun) async {
        for callback in callbacks {
            await callback.onTrainEnd(run: run)
        }
    }
}
