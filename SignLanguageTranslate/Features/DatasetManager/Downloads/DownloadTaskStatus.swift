import Foundation
import SwiftUI

/// Represents all possible states of a download task
///
/// State transitions:
/// - pending → queued → downloading → extracting → completed
/// - downloading → paused → downloading (resume)
/// - Any state → failed
/// - failed/completed → pending (retry/reset)
enum DownloadTaskStatus: String, Codable, CaseIterable, Hashable {

    // MARK: - Cases

    /// Waiting to start (initial state)
    case pending

    /// In the download queue but not yet started (waiting for available slot)
    case queued

    /// Currently downloading from server
    case downloading

    /// Paused by user (can be resumed)
    case paused

    /// Download complete, now extracting zip file
    case extracting

    /// Fully complete (downloaded and extracted)
    case completed

    /// Failed with error
    case failed

    // MARK: - Display Properties

    /// Human-readable name for UI
    var displayName: String {
        switch self {
        case .pending:
            return "Pending"
        case .queued:
            return "Queued"
        case .downloading:
            return "Downloading"
        case .paused:
            return "Paused"
        case .extracting:
            return "Extracting"
        case .completed:
            return "Completed"
        case .failed:
            return "Failed"
        }
    }

    /// SF Symbol icon name
    var iconName: String {
        switch self {
        case .pending:
            return "clock"
        case .queued:
            return "line.3.horizontal"
        case .downloading:
            return "arrow.down.circle"
        case .paused:
            return "pause.circle"
        case .extracting:
            return "archivebox"
        case .completed:
            return "checkmark.circle"
        case .failed:
            return "exclamationmark.triangle"
        }
    }

    /// Color associated with this status
    var color: Color {
        switch self {
        case .pending:
            return .gray
        case .queued:
            return .orange
        case .downloading:
            return .blue
        case .paused:
            return .yellow
        case .extracting:
            return .purple
        case .completed:
            return .green
        case .failed:
            return .red
        }
    }

    // MARK: - State Properties

    /// Whether this status represents an active operation
    var isActive: Bool {
        switch self {
        case .downloading, .extracting, .queued:
            return true
        case .pending, .paused, .completed, .failed:
            return false
        }
    }

    /// Whether download can be started from this state
    var canStart: Bool {
        switch self {
        case .pending, .paused, .failed:
            return true
        case .queued, .downloading, .extracting, .completed:
            return false
        }
    }

    /// Whether download can be paused from this state
    var canPause: Bool {
        switch self {
        case .downloading, .queued:
            return true
        case .pending, .paused, .extracting, .completed, .failed:
            return false
        }
    }

    /// Whether this is a terminal state (no further automatic transitions)
    var isTerminal: Bool {
        switch self {
        case .completed, .failed:
            return true
        case .pending, .queued, .downloading, .paused, .extracting:
            return false
        }
    }

    /// Whether the download is in progress (downloading or extracting)
    var isInProgress: Bool {
        switch self {
        case .downloading, .extracting:
            return true
        case .pending, .queued, .paused, .completed, .failed:
            return false
        }
    }

    /// Whether the task can be retried
    var canRetry: Bool {
        switch self {
        case .failed:
            return true
        case .pending, .queued, .downloading, .paused, .extracting, .completed:
            return false
        }
    }

    /// Whether the task is waiting to start
    var isWaiting: Bool {
        switch self {
        case .pending, .queued:
            return true
        case .downloading, .paused, .extracting, .completed, .failed:
            return false
        }
    }
}

// MARK: - CustomStringConvertible

extension DownloadTaskStatus: CustomStringConvertible {
    var description: String {
        displayName
    }
}

// MARK: - Preview Helpers

extension DownloadTaskStatus {

    /// All non-terminal statuses
    static var activeStatuses: [DownloadTaskStatus] {
        allCases.filter { !$0.isTerminal }
    }

    /// All terminal statuses
    static var terminalStatuses: [DownloadTaskStatus] {
        allCases.filter { $0.isTerminal }
    }

    /// All statuses that represent progress
    static var progressStatuses: [DownloadTaskStatus] {
        [.downloading, .extracting]
    }
}
