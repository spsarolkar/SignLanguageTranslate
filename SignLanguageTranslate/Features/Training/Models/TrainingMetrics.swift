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
    public let cosineSimilarity: Float?
    public let validationCosineSimilarity: Float?
    public let validationAccuracy: Float?
    public let validationTop5Accuracy: Float?
    public let validationSampleCount: Int?
    public let evaluationVersion: Int?
    public let timestamp: Date
    
    public init(
        epoch: Int,
        batchIndex: Int,
        trainingLoss: Float,
        validationLoss: Float? = nil,
        accuracy: Float? = nil,
        timestamp: Date = Date(),
        cosineSimilarity: Float? = nil,
        validationCosineSimilarity: Float? = nil,
        validationAccuracy: Float? = nil,
        validationTop5Accuracy: Float? = nil,
        validationSampleCount: Int? = nil,
        evaluationVersion: Int? = nil
    ) {
        self.epoch = epoch
        self.batchIndex = batchIndex
        self.trainingLoss = trainingLoss
        self.validationLoss = validationLoss
        self.accuracy = accuracy
        self.timestamp = timestamp
        self.cosineSimilarity = cosineSimilarity
        self.validationCosineSimilarity = validationCosineSimilarity
        self.validationAccuracy = validationAccuracy
        self.validationTop5Accuracy = validationTop5Accuracy
        self.validationSampleCount = validationSampleCount
        self.evaluationVersion = evaluationVersion
    }
}

/// Configuration parameters for the training session
public struct TrainingConfig: Codable, Sendable {
    public var batchSize: Int
    public var learningRate: Float
    public var epochs: Int
    public var validationInterval: Int // 0: epoch end only; positive: additional batch interval
    public var device: String // "gpu" or "cpu"
    public var useLegacyModel: Bool = false
    /// Missing in saved configs means the original Keras-style architecture.
    public var bilstmVersion: Int = 2
    public var augmentData: Bool = false
    public var validationSplitRatio: Double = 0.2 // Default 20%
    public var patience: Int = 5 // Default 5 epochs for early stopping
    public var patienceLR: Int = 5 // Default 5 epochs for LR reduction
    
    // Model Arch (Phase 8)
    // Model Arch (Phase 8)
    public var numLayers: Int = 4
    public var hiddenDim: Int = 256
    public var numHeads: Int? = 4
    public var dropout: Float = 0.1 // Default 0.1
    
    // Phase 9 Configs (User Request)
    public enum LossType: String, Codable, CaseIterable, Sendable {
        case cosine = "Cosine Similarity"
        case contrastive = "Contrastive (InfoNCE)"
        case crossEntropy = "Cross Entropy / Softmax"
    }
    public var lossFunction: LossType = .contrastive
    public var contrastiveTemperature: Float = 0.07
    public var enableTemporalAugmentation: Bool = true // Sliding Window

    // Phase 10: Advanced Training Configs
    public var gradientClipping: Float = 5.0        // Max gradient norm (1-2 is normal, >10 is concerning)
    public var labelSmoothing: Float = 0.1          // Label smoothing factor
    public var warmupEpochs: Int = 2                // Learning rate warmup
    public var weightDecay: Float = 0.01            // AdamW weight decay

    public enum SchedulerType: String, Codable, CaseIterable, Sendable {
        case reduceOnPlateau = "Reduce on Plateau"
        case cosineDecay = "Cosine Decay"
    }
    public var scheduler: SchedulerType = .reduceOnPlateau

    public init(
        batchSize: Int,
        learningRate: Float,
        epochs: Int,
        validationInterval: Int,
        device: String,
        useLegacyModel: Bool = false,
        augmentData: Bool = false,
        validationSplitRatio: Double = 0.2,
        patience: Int = 5,
        patienceLR: Int = 5,
        numLayers: Int = 4,
        hiddenDim: Int = 256,
        numHeads: Int? = 4,
        dropout: Float = 0.1,
        lossFunction: LossType = .contrastive,
        contrastiveTemperature: Float = 0.07,
        enableTemporalAugmentation: Bool = true,
        gradientClipping: Float = 1.0,
        labelSmoothing: Float = 0.1,
        warmupEpochs: Int = 2,
        weightDecay: Float = 0.01,
        scheduler: SchedulerType = .reduceOnPlateau,
        bilstmVersion: Int = 2
    ) {
        self.batchSize = batchSize
        self.learningRate = learningRate
        self.epochs = epochs
        self.validationInterval = validationInterval
        self.device = device
        self.useLegacyModel = useLegacyModel
        self.bilstmVersion = bilstmVersion
        self.augmentData = augmentData
        self.validationSplitRatio = validationSplitRatio
        self.patience = patience
        self.patienceLR = patienceLR
        self.numLayers = numLayers
        self.hiddenDim = hiddenDim
        self.numHeads = numHeads
        self.dropout = dropout
        self.lossFunction = lossFunction
        self.contrastiveTemperature = contrastiveTemperature
        self.enableTemporalAugmentation = enableTemporalAugmentation
        self.gradientClipping = gradientClipping
        self.labelSmoothing = labelSmoothing
        self.warmupEpochs = warmupEpochs
        self.weightDecay = weightDecay
        self.scheduler = scheduler
    }
    
    // Custom decoder to handle backward compatibility with missing fields
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        batchSize = try container.decodeIfPresent(Int.self, forKey: .batchSize) ?? 8
        learningRate = try container.decodeIfPresent(Float.self, forKey: .learningRate) ?? 1e-4
        epochs = try container.decodeIfPresent(Int.self, forKey: .epochs) ?? 50
        validationInterval = try container.decodeIfPresent(Int.self, forKey: .validationInterval) ?? 0
        device = try container.decodeIfPresent(String.self, forKey: .device) ?? "gpu"
        useLegacyModel = try container.decodeIfPresent(Bool.self, forKey: .useLegacyModel) ?? false
        bilstmVersion = try container.decodeIfPresent(Int.self, forKey: .bilstmVersion) ?? 1
        augmentData = try container.decodeIfPresent(Bool.self, forKey: .augmentData) ?? false
        validationSplitRatio = try container.decodeIfPresent(Double.self, forKey: .validationSplitRatio) ?? 0.2
        patience = try container.decodeIfPresent(Int.self, forKey: .patience) ?? 10
        patienceLR = try container.decodeIfPresent(Int.self, forKey: .patienceLR) ?? 5
        
        numLayers = try container.decodeIfPresent(Int.self, forKey: .numLayers) ?? 4
        hiddenDim = try container.decodeIfPresent(Int.self, forKey: .hiddenDim) ?? 256
        numHeads = try container.decodeIfPresent(Int.self, forKey: .numHeads) ?? 4
        dropout = try container.decodeIfPresent(Float.self, forKey: .dropout) ?? 0.1
        
        lossFunction = try container.decodeIfPresent(LossType.self, forKey: .lossFunction) ?? .contrastive
        contrastiveTemperature = try container.decodeIfPresent(Float.self, forKey: .contrastiveTemperature) ?? 0.07
        enableTemporalAugmentation = try container.decodeIfPresent(Bool.self, forKey: .enableTemporalAugmentation) ?? false
        
        gradientClipping = try container.decodeIfPresent(Float.self, forKey: .gradientClipping) ?? 5.0
        labelSmoothing = try container.decodeIfPresent(Float.self, forKey: .labelSmoothing) ?? 0.1
        warmupEpochs = try container.decodeIfPresent(Int.self, forKey: .warmupEpochs) ?? 2
        weightDecay = try container.decodeIfPresent(Float.self, forKey: .weightDecay) ?? 0.01
        
        scheduler = try container.decodeIfPresent(SchedulerType.self, forKey: .scheduler) ?? .reduceOnPlateau
    }

    public static let `default` = TrainingConfig(
        batchSize: 8,
        learningRate: 3e-4,              // Increased from 1e-4 for faster convergence
        epochs: 50,                       // More epochs for better convergence
        validationInterval: 0,
        device: "gpu",
        useLegacyModel: false,
        augmentData: true,                // Enable augmentation by default
        validationSplitRatio: 0.15,       // Slightly less validation for more training data
        patience: 10,
        patienceLR: 5,
        numLayers: 6,                     // Match model config default
        hiddenDim: 384,                   // Match model config default (384/6=64 per head)
        numHeads: 6,                      // Match model config default
        dropout: 0.15,                    // Slightly higher for regularization
        lossFunction: .contrastive,
        contrastiveTemperature: 0.1,      // Slightly higher temp for softer probabilities
        enableTemporalAugmentation: true,
        gradientClipping: 5.0,
        labelSmoothing: 0.1,
        warmupEpochs: 3,
        weightDecay: 0.01
    )

    /// Validates and auto-corrects numHeads if not divisible by hiddenDim
    public func validated() -> TrainingConfig {
        var copy = self
        let heads = numHeads ?? 4
        if hiddenDim % heads != 0 {
            // Find a valid number of heads
            let preferred = [4, 6, 8, 2, 1]
            for h in preferred {
                if hiddenDim % h == 0 {
                    copy.numHeads = h
                    break
                }
            }
        }
        return copy
    }
}
