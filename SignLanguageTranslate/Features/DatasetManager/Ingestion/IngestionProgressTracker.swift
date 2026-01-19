import Foundation

/// Tracks video ingestion progress for UI updates
@Observable
final class IngestionProgressTracker {
    
    // MARK: - Status
    
    enum Status: Equatable {
        case idle
        case scanning
        case ingesting
        case completed
        case failed(String)
        
        var isActive: Bool {
            switch self {
            case .scanning, .ingesting:
                return true
            default:
                return false
            }
        }
        
        var displayText: String {
            switch self {
            case .idle:
                return "Ready"
            case .scanning:
                return "Scanning files..."
            case .ingesting:
                return "Importing videos..."
            case .completed:
                return "Complete"
            case .failed(let error):
                return "Failed: \(error)"
            }
        }
    }
    
    // MARK: - Progress Properties
    
    private(set) var status: Status = .idle
    private(set) var currentCategory: String?
    private(set) var filesProcessed: Int = 0
    private(set) var totalFiles: Int = 0
    private(set) var samplesCreated: Int = 0
    private(set) var labelsCreated: Int = 0
    private(set) var errors: [String] = []
    
    // Current file
    private(set) var currentFile: String?
    
    // Timing
    private(set) var startTime: Date?
    private(set) var endTime: Date?
    
    // MARK: - Computed Properties
    
    var isActive: Bool {
        status.isActive
    }
    
    var progress: Double {
        guard totalFiles > 0 else { return 0 }
        return Double(filesProcessed) / Double(totalFiles)
    }
    
    var progressPercentage: Int {
        Int((progress * 100).rounded())
    }
    
    var duration: TimeInterval? {
        guard let start = startTime else { return nil }
        let end = endTime ?? Date()
        return end.timeIntervalSince(start)
    }
    
    var estimatedTimeRemaining: TimeInterval? {
        guard isActive,
              let duration = duration,
              filesProcessed > 0,
              filesProcessed < totalFiles else {
            return nil
        }
        
        let timePerFile = duration / Double(filesProcessed)
        let remainingFiles = totalFiles - filesProcessed
        return timePerFile * Double(remainingFiles)
    }
    
    var formattedDuration: String {
        guard let duration = duration else { return "0s" }
        return formatTimeInterval(duration)
    }
    
    var formattedTimeRemaining: String {
        guard let remaining = estimatedTimeRemaining else { return "--" }
        return formatTimeInterval(remaining)
    }
    
    var hasErrors: Bool {
        !errors.isEmpty
    }
    
    // MARK: - Progress Updates
    
    func startScanning() {
        self.status = .scanning
        self.startTime = Date()
        self.endTime = nil
        self.filesProcessed = 0
        self.totalFiles = 0
        self.samplesCreated = 0
        self.labelsCreated = 0
        self.errors = []
    }
    
    func scanningComplete(totalFiles: Int) {
        self.totalFiles = totalFiles
    }
    
    func startIngesting() {
        self.status = .ingesting
    }
    
    func updateCategory(_ category: String) {
        self.currentCategory = category
    }
    
    func updateFile(_ filename: String) {
        self.currentFile = filename
    }
    
    func fileProcessed(sampleCreated: Bool = true) {
        self.filesProcessed += 1
        if sampleCreated {
            self.samplesCreated += 1
        }
        self.currentFile = nil
    }
    
    func labelCreated() {
        self.labelsCreated += 1
    }
    
    func addError(_ error: String) {
        self.errors.append(error)
    }
    
    func complete() {
        self.status = .completed
        self.endTime = Date()
        self.currentCategory = nil
        self.currentFile = nil
    }
    
    func fail(_ error: String) {
        self.status = .failed(error)
        self.endTime = Date()
        self.addError(error)
    }
    
    func reset() {
        self.status = .idle
        self.currentCategory = nil
        self.filesProcessed = 0
        self.totalFiles = 0
        self.samplesCreated = 0
        self.labelsCreated = 0
        self.errors = []
        self.currentFile = nil
        self.startTime = nil
        self.endTime = nil
    }
    
    // MARK: - Statistics
    
    /// Get summary of ingestion results
    var summary: IngestionSummary {
        IngestionSummary(
            filesProcessed: filesProcessed,
            samplesCreated: samplesCreated,
            labelsCreated: labelsCreated,
            errorCount: errors.count,
            duration: duration ?? 0
        )
    }
    
    // MARK: - Private Helpers
    
    private func formatTimeInterval(_ interval: TimeInterval) -> String {
        let seconds = Int(interval)
        
        if seconds < 60 {
            return "\(seconds)s"
        } else if seconds < 3600 {
            let minutes = seconds / 60
            let secs = seconds % 60
            return "\(minutes)m \(secs)s"
        } else {
            let hours = seconds / 3600
            let minutes = (seconds % 3600) / 60
            return "\(hours)h \(minutes)m"
        }
    }
}

// MARK: - Supporting Types

/// Summary of ingestion results
struct IngestionSummary {
    let filesProcessed: Int
    let samplesCreated: Int
    let labelsCreated: Int
    let errorCount: Int
    let duration: TimeInterval
    
    var successRate: Double {
        guard filesProcessed > 0 else { return 0 }
        return Double(samplesCreated) / Double(filesProcessed)
    }
    
    var formattedDuration: String {
        let seconds = Int(duration)
        if seconds < 60 {
            return "\(seconds)s"
        } else if seconds < 3600 {
            let minutes = seconds / 60
            return "\(minutes)m"
        } else {
            let hours = seconds / 3600
            let minutes = (seconds % 3600) / 60
            return "\(hours)h \(minutes)m"
        }
    }
}
