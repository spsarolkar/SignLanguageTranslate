import Foundation

// MARK: - Task Extensions

extension Task where Success == Never, Failure == Never {
    /// Sleep for a specified duration in seconds
    static func sleep(seconds: TimeInterval) async throws {
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }
}

// MARK: - Debouncer Actor

/// Thread-safe debouncer that ensures a function is only called once within a time window
actor Debouncer {
    private var task: Task<Void, Never>?
    private let duration: TimeInterval

    init(duration: TimeInterval = 0.3) {
        self.duration = duration
    }

    /// Debounce a function call - cancels any pending call and schedules a new one
    func debounce(_ action: @escaping @Sendable () async -> Void) {
        // Cancel any existing pending task
        task?.cancel()

        // Schedule new task
        task = Task {
            do {
                try await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
                await action()
            } catch {
                // Task was cancelled, do nothing
            }
        }
    }

    /// Cancel any pending debounced action
    func cancel() {
        task?.cancel()
        task = nil
    }
}

// MARK: - Throttler Actor

/// Thread-safe throttler that ensures a function is called at most once per time window
actor Throttler {
    private var lastExecutionTime: Date?
    private let interval: TimeInterval

    init(interval: TimeInterval = 1.0) {
        self.interval = interval
    }

    /// Throttle a function call - only executes if enough time has passed since last execution
    func throttle(_ action: @escaping @Sendable () async -> Void) async {
        let now = Date()

        if let lastTime = lastExecutionTime {
            let elapsed = now.timeIntervalSince(lastTime)
            if elapsed < interval {
                // Too soon, skip this call
                return
            }
        }

        lastExecutionTime = now
        await action()
    }

    /// Reset the throttler, allowing immediate next execution
    func reset() {
        lastExecutionTime = nil
    }
}

// MARK: - Periodic Timer Actor

/// Thread-safe periodic timer for running async tasks at regular intervals
actor PeriodicTimer {
    private var task: Task<Void, Never>?
    private let interval: TimeInterval
    private let action: @Sendable () async -> Void

    init(interval: TimeInterval, action: @escaping @Sendable () async -> Void) {
        self.interval = interval
        self.action = action
    }

    /// Start the periodic timer
    func start() {
        guard task == nil else { return }

        task = Task {
            while !Task.isCancelled {
                await action()

                do {
                    try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                } catch {
                    // Task was cancelled
                    break
                }
            }
        }
    }

    /// Stop the periodic timer
    func stop() {
        task?.cancel()
        task = nil
    }

    /// Check if timer is currently running
    var isRunning: Bool {
        task != nil
    }
}
