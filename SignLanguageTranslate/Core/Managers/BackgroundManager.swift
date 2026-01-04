//
//  BackgroundManager.swift
//  SignLanguageTranslate
//
//  Created by Sunil Sarolkar
//

import Foundation
#if os(iOS)
import UIKit
import BackgroundTasks
#endif

/// Singleton manager for background task scheduling and idle timer control.
/// Manages keep-awake functionality and background processing tasks.
final class BackgroundManager {
    
    // MARK: - Singleton
    
    static let shared = BackgroundManager()
    
    private init() {
        #if os(iOS)
        registerBackgroundTask()
        #endif
    }
    
    // MARK: - Properties
    
    #if os(iOS)
    /// Background task identifier for data processing
    private let backgroundTaskIdentifier = "in.sunilsarolkar.signlanguagetranslate.background.processing"
    #endif
    
    /// Current state of keep-awake mode
    private(set) var isKeepAwakeEnabled = false
    
    // MARK: - Keep Awake Control
    
    /// Enables keep-awake mode to prevent device from sleeping during processing
    @MainActor
    func enableKeepAwake() {
        guard !isKeepAwakeEnabled else { return }
        #if os(iOS)
        UIApplication.shared.isIdleTimerDisabled = true
        #endif
        isKeepAwakeEnabled = true
    }
    
    /// Disables keep-awake mode, allowing device to sleep normally
    @MainActor
    func disableKeepAwake() {
        guard isKeepAwakeEnabled else { return }
        #if os(iOS)
        UIApplication.shared.isIdleTimerDisabled = false
        #endif
        isKeepAwakeEnabled = false
    }
    
    /// Toggles keep-awake mode
    @MainActor
    func toggleKeepAwake() {
        if isKeepAwakeEnabled {
            disableKeepAwake()
        } else {
            enableKeepAwake()
        }
    }
    
    // MARK: - Background Task Registration
    
    #if os(iOS)
    /// Registers the background processing task
    /// Note: The task identifier must be added to Info.plist under UIBackgroundModes
    private func registerBackgroundTask() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: backgroundTaskIdentifier,
            using: nil
        ) { task in
            self.handleBackgroundTask(task: task as! BGProcessingTask)
        }
    }
    
    /// Schedules background processing
    /// - Parameter earliestBeginDate: Earliest time to begin processing (nil = ASAP)
    nonisolated func scheduleBackgroundProcessing(earliestBeginDate: Date? = nil) {
        let request = BGProcessingTaskRequest(identifier: backgroundTaskIdentifier)
        request.earliestBeginDate = earliestBeginDate
        request.requiresNetworkConnectivity = false
        request.requiresExternalPower = false
        
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            print("Could not schedule background processing: \(error)")
        }
    }
    
    /// Handles the background task execution
    /// - Parameter task: The background processing task
    nonisolated private func handleBackgroundTask(task: BGProcessingTask) {
        // Schedule the next background task
        scheduleBackgroundProcessing()
        
        // Create an expiration handler
        task.expirationHandler = {
            task.setTaskCompleted(success: false)
        }
        
        // Perform background work
        // This will be implemented when the pipeline is built
        // For now, just mark as completed
        Task {
            // Placeholder for background processing logic
            // await processDataInBackground()
            
            task.setTaskCompleted(success: true)
        }
    }
    #endif
}

