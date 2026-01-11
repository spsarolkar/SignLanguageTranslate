//
//  DownloadEngineDelegate.swift
//  SignLanguageTranslate
//
//  Created on Phase 4.2 - Download Engine Implementation
//

import Foundation

/// Protocol for receiving download engine events
///
/// Conforming types receive callbacks for download progress updates, completions,
/// failures, and overall engine state changes. All delegate methods are called
/// on the MainActor since DownloadEngine is @MainActor isolated.
@MainActor
protocol DownloadEngineDelegate: AnyObject {
    /// Called when a download task's state or progress is updated
    /// - Parameters:
    ///   - engine: The download engine reporting the update
    ///   - task: The updated download task
    func downloadEngine(_ engine: DownloadEngine, didUpdateTask task: DownloadTask)

    /// Called when a download task completes successfully
    /// - Parameters:
    ///   - engine: The download engine reporting the completion
    ///   - task: The completed download task
    func downloadEngine(_ engine: DownloadEngine, didCompleteTask task: DownloadTask)

    /// Called when a download task fails
    /// - Parameters:
    ///   - engine: The download engine reporting the failure
    ///   - task: The failed download task
    ///   - error: The error that caused the failure
    func downloadEngine(_ engine: DownloadEngine, didFailTask task: DownloadTask, error: DownloadError)

    /// Called when all tasks in the queue have been processed
    /// - Parameter engine: The download engine that finished processing
    func downloadEngineDidFinishAllTasks(_ engine: DownloadEngine)

    /// Called when the engine's running state changes
    /// - Parameters:
    ///   - engine: The download engine
    ///   - isRunning: Whether the engine is now running
    func downloadEngine(_ engine: DownloadEngine, didChangeRunningState isRunning: Bool)

    /// Called when the engine's paused state changes
    /// - Parameters:
    ///   - engine: The download engine
    ///   - isPaused: Whether the engine is now paused
    func downloadEngine(_ engine: DownloadEngine, didChangePausedState isPaused: Bool)

    /// Called when the engine starts a new download
    /// - Parameters:
    ///   - engine: The download engine
    ///   - task: The task that started downloading
    func downloadEngine(_ engine: DownloadEngine, didStartTask task: DownloadTask)

    /// Called when network status changes affect the engine
    /// - Parameters:
    ///   - engine: The download engine
    ///   - isConnected: Whether network is available
    func downloadEngine(_ engine: DownloadEngine, networkStatusChanged isConnected: Bool)
}

// MARK: - Default Implementations

extension DownloadEngineDelegate {
    func downloadEngine(_ engine: DownloadEngine, didChangeRunningState isRunning: Bool) {
        // Default empty implementation
    }

    func downloadEngine(_ engine: DownloadEngine, didChangePausedState isPaused: Bool) {
        // Default empty implementation
    }

    func downloadEngine(_ engine: DownloadEngine, didStartTask task: DownloadTask) {
        // Default empty implementation
    }

    func downloadEngine(_ engine: DownloadEngine, networkStatusChanged isConnected: Bool) {
        // Default empty implementation
    }
}
