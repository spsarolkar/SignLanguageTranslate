import Foundation

nonisolated public enum TrainingWorkPhase: String, Sendable {
    case idle = "Idle"
    case preparing = "Preparing worker"
    case training = "Training"
    case validating = "Validating"
    case epochCallbacks = "Finishing epoch"
    case checkpointing = "Saving checkpoint"
    case paused = "Pause requested"
    case stopping = "Stopping after current operation"
    case completed = "Completed"
    case failed = "Failed"
}

/// Owns one live operation. Pausing preserves its stack, model, data iterator
/// and counters; resuming never calls the operation again.
@MainActor
final class TrainingWorkerLifecycle {
    private var worker: Task<Void, Never>?
    private(set) var isPaused = false
    private(set) var isStopping = false
    private(set) var isParked = false
    var hasWorker: Bool { worker != nil }

    nonisolated deinit {}

    @discardableResult
    func start(onCompletion: @escaping @MainActor () -> Void = {},
               operation: @escaping @MainActor () async -> Void) -> Bool {
        guard worker == nil else { return false }
        isPaused = false
        isStopping = false
        isParked = false
        worker = Task {
            await operation()
            worker = nil
            isPaused = false
            isStopping = false
            isParked = false
            onCompletion()
        }
        return true
    }

    @discardableResult
    func pause() -> Bool {
        guard hasWorker, !isStopping, !isPaused else { return false }
        isPaused = true
        return true
    }

    @discardableResult
    func resume() -> Bool {
        guard hasWorker, isPaused, !isStopping else { return false }
        isPaused = false
        return true
    }

    @discardableResult
    func stop() -> Bool {
        guard hasWorker, !isStopping else { return false }
        isStopping = true
        isPaused = false
        return true
    }

    /// Cooperative boundary before updating weights, validation batches and
    /// epoch callbacks. Stop wakes a paused worker without launching a new one.
    func waitUntilRunnable() async -> Bool {
        while hasWorker, isPaused, !isStopping, !Task.isCancelled {
            isParked = true
            do { try await Task.sleep(for: .milliseconds(50)) }
            catch { isParked = false; return false }
        }
        isParked = false
        return hasWorker && !isStopping && !Task.isCancelled
    }

    /// Used only to avoid reading live weights during a background save. A
    /// stalled GPU operation must not cause an unsafe concurrent checkpoint.
    func waitUntilPaused(timeout: Duration = .seconds(2)) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while hasWorker, isPaused, !isStopping, !isParked {
            guard clock.now < deadline, !Task.isCancelled else { return false }
            do { try await Task.sleep(for: .milliseconds(10)) }
            catch { return false }
        }
        return hasWorker && isPaused && isParked && !isStopping
    }
}
