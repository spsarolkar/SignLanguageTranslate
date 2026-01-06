import Foundation
import SwiftUI

/// Represents the download/availability status of a dataset
enum DownloadStatus: String, Codable, CaseIterable, Identifiable {

    /// Dataset has not been downloaded yet
    case notStarted

    /// Download is currently in progress
    case downloading

    /// Download was paused by user
    case paused

    /// Download completed successfully
    case completed

    /// Download failed (check error for details)
    case failed

    /// Dataset is being extracted/processed
    case processing

    var id: String { rawValue }

    /// Human-readable status text
    var displayName: String {
        switch self {
        case .notStarted: return "Not Downloaded"
        case .downloading: return "Downloading"
        case .paused: return "Paused"
        case .completed: return "Ready"
        case .failed: return "Failed"
        case .processing: return "Processing"
        }
    }

    /// Short status for compact UI
    var shortDisplayName: String {
        switch self {
        case .notStarted: return "Not Started"
        case .downloading: return "Downloading"
        case .paused: return "Paused"
        case .completed: return "Ready"
        case .failed: return "Failed"
        case .processing: return "Processing"
        }
    }

    /// SF Symbol icon for this status
    var iconName: String {
        switch self {
        case .notStarted: return "arrow.down.circle"
        case .downloading: return "arrow.down.circle.fill"
        case .paused: return "pause.circle.fill"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.circle.fill"
        case .processing: return "gearshape.circle.fill"
        }
    }

    /// Color associated with this status
    var color: Color {
        switch self {
        case .notStarted: return .gray
        case .downloading: return .blue
        case .paused: return .orange
        case .completed: return .green
        case .failed: return .red
        case .processing: return .purple
        }
    }

    /// Whether the dataset is in an active state (downloading or processing)
    var isActive: Bool {
        switch self {
        case .downloading, .processing:
            return true
        default:
            return false
        }
    }

    /// Whether the dataset can be started/resumed
    var canStart: Bool {
        switch self {
        case .notStarted, .paused, .failed:
            return true
        default:
            return false
        }
    }

    /// Whether the dataset can be paused
    var canPause: Bool {
        self == .downloading
    }

    /// Whether the dataset is available for use
    var isAvailable: Bool {
        self == .completed
    }
}
