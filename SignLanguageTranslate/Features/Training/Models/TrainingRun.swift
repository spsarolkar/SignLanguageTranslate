import Foundation
import SwiftData

/// Represents a persisted training session run
@Model
public final class TrainingRun {
    /// Unique ID of the run
    @Attribute(.unique) public var id: UUID
    
    /// When the training started
    public var timestamp: Date
    
    /// User-friendly name or auto-generated tag (e.g., "Run #4")
    public var name: String
    
    /// Serialized TrainingConfig
    public var configData: Data
    
    /// Serialized [TrainingMetrics] - Stored as Data to avoid overhead of thousands of child objects
    /// We can lazily decode this when viewing charts.
    public var metricsData: Data
    
    /// Final status of the run (completed, stopped, failed)
    public var status: String
    
    /// Total duration in seconds
    public var duration: TimeInterval
    
    /// Helper to access typed Config
    public var config: TrainingConfig? {
        get {
            try? JSONDecoder().decode(TrainingConfig.self, from: configData)
        }
        set {
            if let newValue = newValue {
                configData = (try? JSONEncoder().encode(newValue)) ?? Data()
            }
        }
    }
    
    /// Helper to access typed Metrics
    public var metrics: [TrainingMetrics] {
        get {
            (try? JSONDecoder().decode([TrainingMetrics].self, from: metricsData)) ?? []
        }
        set {
            metricsData = (try? JSONEncoder().encode(newValue)) ?? Data()
        }
    }
    
    public init(
        name: String = "Training Run",
        config: TrainingConfig,
        timestamp: Date = Date(),
        status: String = "Started"
    ) {
        self.id = UUID()
        self.name = name
        self.timestamp = timestamp
        self.status = status
        self.duration = 0
        
        // Encode initial data
        self.configData = (try? JSONEncoder().encode(config)) ?? Data()
        self.metricsData = (try? JSONEncoder().encode([TrainingMetrics]())) ?? Data()
    }
}
