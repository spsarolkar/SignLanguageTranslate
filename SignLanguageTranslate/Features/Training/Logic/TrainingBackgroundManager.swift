import Foundation
import BackgroundTasks
import MLX

/// Manages background execution of training tasks using BGProcessingTask.
/// This allows training to continue sporadically when the app is suspended/locked.
public final class TrainingBackgroundManager: @unchecked Sendable {
    
    // MARK: - Constants
    
    public static let taskId = "com.sunil.SignLanguageTranslate.training"
    
    // MARK: - Singleton
    
    public static let shared = TrainingBackgroundManager()
    
    // MARK: - Dependencies
    
    // We cannot hold a strong reference to TrainingSessionManager directly to avoid leaks
    // or accessing UI-bound state from background. 
    // Instead, we will create a fresh session or reuse a dedicated "Headless" session.
    // For simplicity, we'll access the shared instance or create a new one.
    
    private var isRegistered = false
    
    private init() {}
    
    // MARK: - Registration
    
    /// Register the background task. Call this in Application.init or didFinishLaunching.
    public func register() {
        guard !isRegistered else { return }
        
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.taskId, using: nil) { [weak self] task in
            guard let task = task as? BGProcessingTask else { return }
            self?.handle(task: task)
        }
        
        isRegistered = true
        print("[BGTask] Registered task: \(Self.taskId)")
    }
    
    // MARK: - Scheduling
    
    /// Schedule the next background training task.
    /// Call this when the app goes to background.
    public func schedule() {
        let request = BGProcessingTaskRequest(identifier: Self.taskId)
        request.requiresNetworkConnectivity = false // Local training
        request.requiresExternalPower = true // Training is heavy, prefer charging
        
        // Schedule for 1 minute from now (test) or 15 mins (prod)
        // iOS decides when to run it anyway
        request.earliestBeginDate = Date(timeIntervalSinceNow: 1 * 60)
        
        do {
            try BGTaskScheduler.shared.submit(request)
            print("[BGTask] Scheduled processing task for \(Self.taskId)")
        } catch {
            print("[BGTask] Could not schedule task: \(error)")
        }
    }
    
    // MARK: - Execution
    
    private func handle(task: BGProcessingTask) {
        print("[BGTask] 🚀 Background task started!")
        
        // 1. Expiration Handler
        task.expirationHandler = {
            print("[BGTask] ⚠️ Task expiration warning! Saving state...")
            // We need a way to signal the active session to stop and save
            NotificationCenter.default.post(name: .trainingShouldSaveAndStop, object: nil)
        }
        
        // 2. Start Work
        // Since we are in the background, we need to create a new Task
        Task {
            do {
                // If the app was suspended, TrainingSessionManager might still be alive.
                // If terminated, we need to recreate.
                
                // For now, let's assume we can access the session manager or create one.
                // Since TrainingSessionManager is typically an EnvironmentObject, we might need a dedicated way to access it.
                // We'll use a Notification to ask the app to resume training if alive.
                // Or better: Use TrainingSessionManager.shared (doesn't exist yet, we'll refactor).
                
                // NOTE: This part requires TrainingSessionManager to be accessible.
                // We'll assume a pattern where we can invoke resume logic.
                
                // Try to find active session manager or create one
                // Post notification for now, listening in App or Manager
                NotificationCenter.default.post(name: .trainingResumeInBackground, object: nil)
                
                // We wait for some signal or time?
                // Actually, we need to know when it finishes.
                
                // HACK: Wait for 10 minutes strictly or until stopped
                // Real implementation needs feedback loop
                try await Task.sleep(nanoseconds: 9 * 60 * 1_000_000_000)
                
                task.setTaskCompleted(success: true)
                print("[BGTask] Task completed successfully")
                
                // Reschedule?
                self.schedule()
                
            } catch {
                print("[BGTask] Task failed or cancelled: \(error)")
                task.setTaskCompleted(success: false)
            }
        }
    }
}

// MARK: - Notifications

extension Notification.Name {
    public static let trainingShouldSaveAndStop = Notification.Name("trainingShouldSaveAndStop")
    public static let trainingResumeInBackground = Notification.Name("trainingResumeInBackground")
}
