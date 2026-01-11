//
//  DownloadError.swift
//  SignLanguageTranslate
//
//  Created on Phase 4.2 - Download Engine Implementation
//

import Foundation

/// Comprehensive error types for download operations
enum DownloadError: LocalizedError, Equatable, Sendable {
    /// Insufficient storage space for download
    case insufficientStorage(required: Int64, available: Int64)

    /// No network connection available
    case networkUnavailable

    /// Invalid or malformed download URL
    case invalidURL(String)

    /// Failed to move downloaded file to final destination
    case fileMoveFailed(reason: String)

    /// Resume data is corrupted or incompatible
    case resumeDataCorrupted

    /// Server returned an error status code
    case serverError(statusCode: Int)

    /// Request timed out
    case timeout

    /// Download was cancelled by user
    case cancelled

    /// Task not found in queue
    case taskNotFound(UUID)

    /// Maximum retry attempts exceeded
    case maxRetriesExceeded(attempts: Int)

    /// Download is already in progress
    case alreadyDownloading

    /// Network connection lost during download
    case connectionLost

    /// SSL/TLS certificate error
    case certificateError

    /// Server not found
    case serverNotFound

    /// Unknown error with underlying cause
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .insufficientStorage(let required, let available):
            let requiredStr = ByteCountFormatter.string(fromByteCount: required, countStyle: .file)
            let availableStr = ByteCountFormatter.string(fromByteCount: available, countStyle: .file)
            return "Insufficient storage space. Required: \(requiredStr), Available: \(availableStr)"

        case .networkUnavailable:
            return "No network connection available"

        case .invalidURL(let url):
            return "Invalid download URL: \(url)"

        case .fileMoveFailed(let reason):
            return "Failed to save downloaded file: \(reason)"

        case .resumeDataCorrupted:
            return "Resume data is corrupted and cannot be used"

        case .serverError(let statusCode):
            return "Server error (HTTP \(statusCode))"

        case .timeout:
            return "Download request timed out"

        case .cancelled:
            return "Download was cancelled"

        case .taskNotFound(let id):
            return "Download task not found: \(id)"

        case .maxRetriesExceeded(let attempts):
            return "Download failed after \(attempts) attempts"

        case .alreadyDownloading:
            return "Download is already in progress"

        case .connectionLost:
            return "Network connection was lost"

        case .certificateError:
            return "SSL certificate verification failed"

        case .serverNotFound:
            return "Server not found"

        case .unknown(let message):
            return message
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .insufficientStorage:
            return "Free up space by deleting unused apps or files, then try again."

        case .networkUnavailable:
            return "Check your internet connection and try again."

        case .invalidURL:
            return "The download URL is invalid. Please report this issue."

        case .fileMoveFailed:
            return "Try restarting the app and downloading again."

        case .resumeDataCorrupted:
            return "The download will restart from the beginning."

        case .serverError(let statusCode):
            if statusCode >= 500 {
                return "The server is experiencing issues. Please try again later."
            } else if statusCode == 404 {
                return "The file is no longer available. Please check for updates."
            } else {
                return "Please try again later or contact support."
            }

        case .timeout:
            return "Check your network connection and try again."

        case .cancelled:
            return "You can restart the download at any time."

        case .taskNotFound:
            return "The download may have been removed. Try adding it again."

        case .maxRetriesExceeded:
            return "Check your network connection and try again later."

        case .alreadyDownloading:
            return "Wait for the current download to complete."

        case .connectionLost:
            return "Check your internet connection. The download will resume automatically when connected."

        case .certificateError:
            return "Ensure your device's date and time are correct, then try again."

        case .serverNotFound:
            return "Check your internet connection or try again later."

        case .unknown:
            return "Please try again. If the problem persists, restart the app."
        }
    }

    /// Whether the error is potentially recoverable through retry
    var isRetryable: Bool {
        switch self {
        case .insufficientStorage:
            return false // User needs to free space first

        case .networkUnavailable:
            return true // Network may become available

        case .invalidURL:
            return false // URL won't change

        case .fileMoveFailed:
            return true // Might work on retry

        case .resumeDataCorrupted:
            return true // Can restart fresh

        case .serverError(let statusCode):
            // Retry for server errors (5xx), not client errors (4xx)
            return statusCode >= 500

        case .timeout:
            return true // Network conditions may improve

        case .cancelled:
            return false // User action, not auto-retry

        case .taskNotFound:
            return false // Task doesn't exist

        case .maxRetriesExceeded:
            return false // Already exhausted retries

        case .alreadyDownloading:
            return false // Not an error condition for retry

        case .connectionLost:
            return true // Connection may be restored

        case .certificateError:
            return false // Requires user action

        case .serverNotFound:
            return true // DNS/network may resolve

        case .unknown:
            return true // Unknown errors worth retrying
        }
    }

    /// Whether the error should trigger automatic pause
    var shouldAutoPause: Bool {
        switch self {
        case .networkUnavailable, .connectionLost:
            return true
        default:
            return false
        }
    }

    /// Create a DownloadError from an NSError (typically from URLSession)
    static func from(_ error: Error) -> DownloadError {
        let nsError = error as NSError

        // Handle URL errors
        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorNotConnectedToInternet:
                return .networkUnavailable

            case NSURLErrorNetworkConnectionLost:
                return .connectionLost

            case NSURLErrorTimedOut:
                return .timeout

            case NSURLErrorCancelled:
                return .cancelled

            case NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed:
                return .serverNotFound

            case NSURLErrorSecureConnectionFailed,
                 NSURLErrorServerCertificateHasBadDate,
                 NSURLErrorServerCertificateUntrusted,
                 NSURLErrorServerCertificateHasUnknownRoot,
                 NSURLErrorServerCertificateNotYetValid,
                 NSURLErrorClientCertificateRejected,
                 NSURLErrorClientCertificateRequired:
                return .certificateError

            case NSURLErrorCannotDecodeContentData,
                 NSURLErrorCannotDecodeRawData:
                return .resumeDataCorrupted

            default:
                return .unknown(error.localizedDescription)
            }
        }

        // Handle file system errors
        if nsError.domain == NSCocoaErrorDomain {
            switch nsError.code {
            case NSFileWriteOutOfSpaceError:
                return .insufficientStorage(required: 0, available: 0)

            case NSFileWriteNoPermissionError,
                 NSFileWriteVolumeReadOnlyError:
                return .fileMoveFailed(reason: error.localizedDescription)

            default:
                return .unknown(error.localizedDescription)
            }
        }

        return .unknown(error.localizedDescription)
    }

    // MARK: - Equatable

    static func == (lhs: DownloadError, rhs: DownloadError) -> Bool {
        switch (lhs, rhs) {
        case (.insufficientStorage(let r1, let a1), .insufficientStorage(let r2, let a2)):
            return r1 == r2 && a1 == a2
        case (.networkUnavailable, .networkUnavailable):
            return true
        case (.invalidURL(let u1), .invalidURL(let u2)):
            return u1 == u2
        case (.fileMoveFailed(let r1), .fileMoveFailed(let r2)):
            return r1 == r2
        case (.resumeDataCorrupted, .resumeDataCorrupted):
            return true
        case (.serverError(let c1), .serverError(let c2)):
            return c1 == c2
        case (.timeout, .timeout):
            return true
        case (.cancelled, .cancelled):
            return true
        case (.taskNotFound(let id1), .taskNotFound(let id2)):
            return id1 == id2
        case (.maxRetriesExceeded(let a1), .maxRetriesExceeded(let a2)):
            return a1 == a2
        case (.alreadyDownloading, .alreadyDownloading):
            return true
        case (.connectionLost, .connectionLost):
            return true
        case (.certificateError, .certificateError):
            return true
        case (.serverNotFound, .serverNotFound):
            return true
        case (.unknown(let m1), .unknown(let m2)):
            return m1 == m2
        default:
            return false
        }
    }
}
