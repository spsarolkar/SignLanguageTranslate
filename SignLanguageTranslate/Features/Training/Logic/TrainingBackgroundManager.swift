import Foundation
import BackgroundTasks
import MLX

/// Manages background execution of training tasks using BGProcessingTask.
/// This allows training to continue when the app is suspended/locked.
///
/// Note: iOS background processing is opportunistic - iOS decides when to run tasks
/// based on device conditions (charging, WiFi, etc.). For intensive ML training,
/// the best approach is to keep the app in foreground with screen lock disabled.
public final class TrainingBackgroundManager: @unchecked Sendable {

    // MARK: - Constants

    public static let taskId = "com.sunil.SignLanguageTranslate.training"

    // MARK: - Singleton

    public static let shared = TrainingBackgroundManager()

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
        // Only schedule if training was active
        Task { @MainActor in
            let manager = TrainingSessionManager.shared
            guard manager.state == .training || manager.state == .paused else {
                print("[BGTask] No active training to resume, skipping schedule")
                return
            }

            let request = BGProcessingTaskRequest(identifier: Self.taskId)
            request.requiresNetworkConnectivity = false // Local training
            request.requiresExternalPower = false // Allow without charging (user preference)

            // Schedule for soon - iOS will determine actual timing
            request.earliestBeginDate = Date(timeIntervalSinceNow: 60)

            do {
                try BGTaskScheduler.shared.submit(request)
                print("[BGTask] Scheduled processing task for training resume")
            } catch {
                print("[BGTask] Could not schedule task: \(error)")
            }
        }
    }

    // MARK: - Execution

    private func handle(task: BGProcessingTask) {
        print("[BGTask] 🚀 Background task started!")

        // Expiration Handler - save state before iOS kills us
        task.expirationHandler = {
            print("[BGTask] ⚠️ Task expiration warning! Saving state...")
            NotificationCenter.default.post(name: .trainingShouldSaveAndStop, object: nil)
        }

        // Resume training using the singleton manager
        Task { @MainActor in
            let manager = TrainingSessionManager.shared

            // Check if there's training to resume
            guard manager.state == .paused || manager.state == .training else {
                print("[BGTask] No training to resume (state: \(manager.state))")
                task.setTaskCompleted(success: true)
                return
            }

            // If paused, resume it
            if manager.state == .paused {
                print("[BGTask] Resuming paused training...")
                // The training loop checks isPaused, so we just need to unpause
                NotificationCenter.default.post(name: .trainingResumeInBackground, object: nil)
            }

            // Wait for training to complete or task to expire
            // Check periodically if training is still running
            var iterations = 0
            let maxIterations = 540 // ~9 minutes max (checking every second)

            while iterations < maxIterations {
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                iterations += 1

                // Check if training completed or stopped
                if manager.state == .completed || manager.state == .idle || manager.state == .failed {
                    print("[BGTask] Training finished (state: \(manager.state))")
                    break
                }
            }

            task.setTaskCompleted(success: true)
            print("[BGTask] Background task completed after \(iterations) seconds")

            // Reschedule if training is still in progress
            if manager.state == .training || manager.state == .paused {
                self.schedule()
            }
        }
    }
}

// MARK: - Notifications

extension Notification.Name {
    public static let trainingShouldSaveAndStop = Notification.Name("trainingShouldSaveAndStop")
    public static let trainingResumeInBackground = Notification.Name("trainingResumeInBackground")
}
