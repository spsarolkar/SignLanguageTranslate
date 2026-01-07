import Foundation

/// Errors that can occur in DownloadManager operations
enum DownloadManagerError: Error {
    case manifestLoadFailed(reason: String)
    case taskNotFound(id: UUID)
    case stateSaveFailed(underlying: Error)
    case stateRestoreFailed(underlying: Error)
    case alreadyDownloading
    case queueEmpty
}

// MARK: - LocalizedError Conformance

extension DownloadManagerError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .manifestLoadFailed(let reason):
            return "Failed to load download manifest: \(reason)"
        case .taskNotFound(let id):
            return "Download task not found: \(id.uuidString)"
        case .stateSaveFailed(let error):
            return "Failed to save download state: \(error.localizedDescription)"
        case .stateRestoreFailed(let error):
            return "Failed to restore download state: \(error.localizedDescription)"
        case .alreadyDownloading:
            return "Downloads are already in progress"
        case .queueEmpty:
            return "No downloads in queue"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .manifestLoadFailed:
            return "Check your network connection and try again."
        case .taskNotFound:
            return "The download may have been removed. Please refresh the list."
        case .stateSaveFailed, .stateRestoreFailed:
            return "Check available storage space and app permissions."
        case .alreadyDownloading:
            return "Wait for current downloads to complete or pause them first."
        case .queueEmpty:
            return "Add downloads to the queue before starting."
        }
    }
}
