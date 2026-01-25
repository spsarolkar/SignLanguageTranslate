import Foundation

// MARK: - Training Run Record (Cloud Schema)

/// Complete record of a training run for cloud persistence.
/// Designed for sharing and global analytics.
public struct TrainingRunRecord: Codable, Sendable {
    
    // MARK: - Identification
    
    public let runId: String
    public let startedAt: Date
    public var endedAt: Date?
    
    // MARK: - Device Info (for Apple Silicon showcase)
    
    public let deviceName: String        // "iPad Pro 12.9-inch (6th generation)"
    public let deviceChip: String        // "Apple M2"
    public let iosVersion: String        // "17.4"
    public let appVersion: String        // "1.0.0 (42)"
    
    // MARK: - Configuration
    
    public let config: TrainingConfigRecord
    
    // MARK: - Metrics
    
    public var epochs: [EpochRecord]
    
    // MARK: - Status
    
    public var status: RunStatus
    public var bestEpoch: Int?
    public var bestValLoss: Float?
    public var totalTrainingTime: TimeInterval
    public var stopReason: String?
    
    // MARK: - Computed
    
    public var isComplete: Bool {
        status == .completed || status == .earlyStopped
    }
    
    public var lastEpoch: Int {
        epochs.last?.epoch ?? 0
    }
    
    // MARK: - Initialization
    
    public init(
        runId: String = UUID().uuidString,
        startedAt: Date = Date(),
        deviceName: String,
        deviceChip: String,
        iosVersion: String,
        appVersion: String,
        config: TrainingConfigRecord
    ) {
        self.runId = runId
        self.startedAt = startedAt
        self.deviceName = deviceName
        self.deviceChip = deviceChip
        self.iosVersion = iosVersion
        self.appVersion = appVersion
        self.config = config
        self.epochs = []
        self.status = .running
        self.totalTrainingTime = 0
    }
}

// MARK: - Training Config Record

/// Configuration snapshot for a training run.
public struct TrainingConfigRecord: Codable, Sendable {
    public let modelArchitecture: String     // "Transformer" or "LegacyLSTM"
    public let modelSize: String?            // "Small", "Medium", "Large"
    public let hiddenDim: Int
    public let numLayers: Int
    public let numHeads: Int?                // Transformer only
    public let batchSize: Int
    public let learningRate: Float
    public let maxEpochs: Int
    public let datasetName: String
    public let trainSamples: Int
    public let valSamples: Int
    public let augmentData: Bool
    public let earlyStopping: EarlyStoppingConfig?
    
    public init(
        modelArchitecture: String,
        modelSize: String? = nil,
        hiddenDim: Int,
        numLayers: Int,
        numHeads: Int? = nil,
        batchSize: Int,
        learningRate: Float,
        maxEpochs: Int,
        datasetName: String,
        trainSamples: Int,
        valSamples: Int,
        augmentData: Bool,
        earlyStopping: EarlyStoppingConfig? = nil
    ) {
        self.modelArchitecture = modelArchitecture
        self.modelSize = modelSize
        self.hiddenDim = hiddenDim
        self.numLayers = numLayers
        self.numHeads = numHeads
        self.batchSize = batchSize
        self.learningRate = learningRate
        self.maxEpochs = maxEpochs
        self.datasetName = datasetName
        self.trainSamples = trainSamples
        self.valSamples = valSamples
        self.augmentData = augmentData
        self.earlyStopping = earlyStopping
    }
}

// MARK: - Early Stopping Config

public struct EarlyStoppingConfig: Codable, Sendable {
    public let patience: Int
    public let minDelta: Float
    public let monitor: String
    
    public init(patience: Int, minDelta: Float, monitor: String = "valLoss") {
        self.patience = patience
        self.minDelta = minDelta
        self.monitor = monitor
    }
}

// MARK: - Epoch Record

/// Record of a single epoch for cloud storage.
public struct EpochRecord: Codable, Sendable {
    public let epoch: Int
    public let trainLoss: Float
    public let valLoss: Float?
    public let trainAccuracy: Float?
    public let valAccuracy: Float?
    public let epochDuration: TimeInterval
    public let timestamp: Date
    public let savedCheckpoint: Bool
    public let batchCount: Int
    public let avgBatchDuration: TimeInterval
    
    public init(
        epoch: Int,
        trainLoss: Float,
        valLoss: Float? = nil,
        trainAccuracy: Float? = nil,
        valAccuracy: Float? = nil,
        epochDuration: TimeInterval,
        timestamp: Date = Date(),
        savedCheckpoint: Bool = false,
        batchCount: Int = 0,
        avgBatchDuration: TimeInterval = 0
    ) {
        self.epoch = epoch
        self.trainLoss = trainLoss
        self.valLoss = valLoss
        self.trainAccuracy = trainAccuracy
        self.valAccuracy = valAccuracy
        self.epochDuration = epochDuration
        self.timestamp = timestamp
        self.savedCheckpoint = savedCheckpoint
        self.batchCount = batchCount
        self.avgBatchDuration = avgBatchDuration
    }
    
    /// Convert from EpochMetrics
    public init(from metrics: EpochMetrics) {
        self.epoch = metrics.epoch
        self.trainLoss = metrics.trainLoss
        self.valLoss = metrics.valLoss
        self.trainAccuracy = metrics.trainAccuracy
        self.valAccuracy = metrics.valAccuracy
        self.epochDuration = metrics.epochDuration
        self.timestamp = metrics.timestamp
        self.savedCheckpoint = metrics.savedCheckpoint
        self.batchCount = metrics.batches.count
        self.avgBatchDuration = metrics.batches.isEmpty ? 0 :
            metrics.batches.map(\.batchDuration).reduce(0, +) / Double(metrics.batches.count)
    }
}

// MARK: - Run Status

/// Status of a training run.
public enum RunStatus: String, Codable, Sendable {
    case running
    case paused
    case backgrounded
    case completed
    case failed
    case earlyStopped
}

// MARK: - Device Info Helper

/// Utility to get current device information.
public struct DeviceInfo {
    
    public static var deviceName: String {
        #if os(iOS)
        return UIDevice.current.name
        #else
        return Host.current().localizedName ?? "Mac"
        #endif
    }
    
    public static var deviceModel: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let identifier = withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(validatingUTF8: $0) ?? "Unknown"
            }
        }
        return chipName(for: identifier)
    }
    
    public static var iosVersion: String {
        #if os(iOS)
        return UIDevice.current.systemVersion
        #else
        return ProcessInfo.processInfo.operatingSystemVersionString
        #endif
    }
    
    public static var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
    
    private static func chipName(for identifier: String) -> String {
        // Map device identifiers to chip names
        let chipMap: [String: String] = [
            "iPad14,3": "Apple M2",
            "iPad14,4": "Apple M2",
            "iPad14,5": "Apple M2",
            "iPad14,6": "Apple M2",
            "iPad13,4": "Apple M1",
            "iPad13,5": "Apple M1",
            "iPad13,6": "Apple M1",
            "iPad13,7": "Apple M1",
            // Add more as needed
        ]
        return chipMap[identifier] ?? "Apple Silicon"
    }
}

#if os(iOS)
import UIKit
#endif
