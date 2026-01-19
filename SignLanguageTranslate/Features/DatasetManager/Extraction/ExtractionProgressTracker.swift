import Foundation
import SwiftUI

/// Observable class for tracking extraction progress across the UI
///
/// This class bridges the actor-based extraction system with SwiftUI views,
/// providing observable properties that update the UI in real-time.
///
/// ## Usage
/// ```swift
/// @Environment(ExtractionProgressTracker.self) var tracker
///
/// var body: some View {
///     if tracker.isExtracting {
///         ProgressView(value: tracker.overallProgress)
///         Text("Extracting \(tracker.currentCategory ?? "")...")
///     }
/// }
/// ```
@Observable
@MainActor
final class ExtractionProgressTracker {

    // MARK: - Extraction State

    /// Whether extraction is currently in progress
    private(set) var isExtracting = false

    /// Current extraction status
    private(set) var status: ExtractionStatus = .pending

    /// Error message if extraction failed
    private(set) var errorMessage: String?

    // MARK: - Progress Properties

    /// Overall extraction progress (0.0 to 1.0)
    private(set) var overallProgress: Double = 0

    /// Progress as percentage (0-100)
    var progressPercentage: Int {
        Int((overallProgress * 100).rounded())
    }

    /// Current category being extracted
    private(set) var currentCategory: String?

    /// Number of categories completed
    private(set) var categoriesCompleted = 0

    /// Total number of categories
    private(set) var totalCategories = 0

    /// Progress within the current category (0.0 to 1.0)
    private(set) var currentCategoryProgress: Double = 0

    // MARK: - File Progress

    /// Current file being extracted
    private(set) var currentFile: String?

    /// Number of files extracted in current category
    private(set) var filesExtracted = 0

    /// Total files in current category
    private(set) var totalFiles = 0

    // MARK: - Dataset Info

    /// Name of the dataset being extracted
    private(set) var datasetName: String?

    // MARK: - Timing

    /// When extraction started
    private(set) var startTime: Date?

    /// Elapsed time since extraction started
    var elapsedTime: TimeInterval {
        guard let startTime else { return 0 }
        return Date().timeIntervalSince(startTime)
    }

    /// Formatted elapsed time (e.g., "2m 30s")
    var formattedElapsedTime: String {
        formatTimeInterval(elapsedTime)
    }

    /// Estimated time remaining based on current progress
    var estimatedTimeRemaining: TimeInterval? {
        guard isExtracting,
              overallProgress > 0,
              overallProgress < 1,
              elapsedTime > 0 else {
            return nil
        }

        let rate = overallProgress / elapsedTime
        let remaining = (1.0 - overallProgress) / rate
        return remaining
    }

    /// Formatted estimated time remaining
    var formattedTimeRemaining: String? {
        guard let remaining = estimatedTimeRemaining else { return nil }
        return formatTimeInterval(remaining)
    }

    // MARK: - Computed Properties

    /// Status text for UI display
    var statusText: String {
        switch status {
        case .pending:
            return "Waiting to extract..."
        case .extracting:
            if let category = currentCategory {
                return "Extracting \(category)..."
            }
            return "Extracting..."
        case .completed:
            return "Extraction complete"
        case .failed:
            return errorMessage ?? "Extraction failed"
        case .cancelled:
            return "Extraction cancelled"
        }
    }

    /// Detailed progress text
    var detailedProgressText: String {
        if totalCategories > 0 {
            return "\(categoriesCompleted)/\(totalCategories) categories"
        }
        return ""
    }

    /// File progress text
    var fileProgressText: String {
        if totalFiles > 0 {
            return "\(filesExtracted)/\(totalFiles) files"
        }
        return ""
    }

    /// Whether extraction completed successfully
    var isComplete: Bool {
        status == .completed
    }

    /// Whether extraction failed
    var hasFailed: Bool {
        status == .failed
    }

    // MARK: - Initialization

    init() {}

    // MARK: - Update Methods

    /// Update progress from a DatasetExtractionProgress
    func update(from progress: DatasetExtractionProgress) {
        self.datasetName = progress.datasetName.isEmpty ? datasetName : progress.datasetName
        self.currentCategory = progress.currentCategory
        self.categoriesCompleted = progress.categoriesCompleted
        self.totalCategories = progress.totalCategories
        self.currentCategoryProgress = progress.currentCategoryProgress
        self.overallProgress = progress.overallProgress
        self.status = progress.status
        self.currentFile = progress.currentFile
        self.filesExtracted = progress.filesExtracted ?? 0
        self.totalFiles = progress.totalFiles ?? 0

        if progress.status == .extracting && !isExtracting {
            isExtracting = true
            if startTime == nil {
                startTime = Date()
            }
        } else if progress.status == .completed || progress.status == .failed || progress.status == .cancelled {
            isExtracting = false
        }
    }

    /// Start tracking extraction for a dataset
    func startExtraction(datasetName: String, totalCategories: Int) {
        self.datasetName = datasetName
        self.totalCategories = totalCategories
        self.categoriesCompleted = 0
        self.overallProgress = 0
        self.currentCategoryProgress = 0
        self.currentCategory = nil
        self.currentFile = nil
        self.filesExtracted = 0
        self.totalFiles = 0
        self.status = .extracting
        self.isExtracting = true
        self.startTime = Date()
        self.errorMessage = nil
    }

    /// Mark extraction as complete
    func completeExtraction() {
        self.status = .completed
        self.isExtracting = false
        self.overallProgress = 1.0
        self.currentCategory = nil
        self.currentFile = nil
    }

    /// Mark extraction as failed
    func failExtraction(with error: String) {
        self.status = .failed
        self.isExtracting = false
        self.errorMessage = error
    }

    /// Mark extraction as cancelled
    func cancelExtraction() {
        self.status = .cancelled
        self.isExtracting = false
    }

    /// Reset all progress state
    func reset() {
        self.isExtracting = false
        self.status = .pending
        self.overallProgress = 0
        self.currentCategory = nil
        self.categoriesCompleted = 0
        self.totalCategories = 0
        self.currentCategoryProgress = 0
        self.currentFile = nil
        self.filesExtracted = 0
        self.totalFiles = 0
        self.datasetName = nil
        self.startTime = nil
        self.errorMessage = nil
    }

    // MARK: - Private Methods

    private func formatTimeInterval(_ interval: TimeInterval) -> String {
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        let seconds = Int(interval) % 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        } else {
            return "\(seconds)s"
        }
    }
}

// MARK: - Progress Handler Extension

extension ExtractionProgressTracker {

    /// Create a progress handler closure for use with ExtractionCoordinator
    ///
    /// This method returns a closure that can be passed to extraction methods
    /// to automatically update this tracker.
    ///
    /// ## Usage
    /// ```swift
    /// let tracker = ExtractionProgressTracker()
    /// let result = try await coordinator.extractDataset(
    ///     datasetName: "INCLUDE",
    ///     downloadedFiles: files,
    ///     progressHandler: tracker.progressHandler
    /// )
    /// ```
    var progressHandler: @Sendable (DatasetExtractionProgress) -> Void {
        { [weak self] progress in
            Task { @MainActor in
                self?.update(from: progress)
            }
        }
    }
}
