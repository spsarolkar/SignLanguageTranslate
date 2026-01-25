import Foundation

/// Represents the current status of the training session
public enum TrainingState: String, CaseIterable, Identifiable, Sendable {
    case idle
    case preparing
    case training
    case paused
    case completing
    case completed
    case failed
    
    public var id: String { rawValue }
}

/// Metrics for a single batch or aggregated epoch
public struct TrainingMetrics: Identifiable, Sendable, Codable {
    public var id = UUID()
    public let epoch: Int
    public let batchIndex: Int
    public let trainingLoss: Float
    public let validationLoss: Float?
    public let accuracy: Float?
    public let timestamp: Date
    
    public init(
        epoch: Int,
        batchIndex: Int,
        trainingLoss: Float,
        validationLoss: Float? = nil,
        accuracy: Float? = nil,
        timestamp: Date = Date()
    ) {
        self.epoch = epoch
        self.batchIndex = batchIndex
        self.trainingLoss = trainingLoss
        self.validationLoss = validationLoss
        self.accuracy = accuracy
        self.timestamp = timestamp
    }
}

/// Configuration parameters for the training session
public struct TrainingConfig: Codable, Sendable {
    public var batchSize: Int
    public var learningRate: Float
    public var epochs: Int
    public var validationInterval: Int // Batches between validation checks
    public var device: String // "gpu" or "cpu"
    public var useLegacyModel: Bool = false
    public var augmentData: Bool = false
    public var validationSplitRatio: Double = 0.2 // Default 20%
    
    public static let `default` = TrainingConfig(
        batchSize: 32,
        learningRate: 1e-4,
        epochs: 10,
        validationInterval: 10,
        device: "gpu",
        useLegacyModel: false,
        augmentData: false,
        validationSplitRatio: 0.2
    )
}
