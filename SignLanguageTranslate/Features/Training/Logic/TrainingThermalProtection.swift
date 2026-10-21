import Foundation
import Combine

/// Observes device-wide thermal state, independently of any visible dashboard.
/// The cooldown is app policy; it does not estimate temperatures in degrees.
@MainActor
final class TrainingThermalProtection {
    nonisolated static let cooldownDuration: Duration = .seconds(30)

    private let notificationCenter: NotificationCenter
    private let thermalState: () -> ProcessInfo.ThermalState
    private let cooldown: Duration
    private var observer: AnyCancellable?
    private var cooldownTask: Task<Void, Never>?
    private var cooldownID: UUID?
    private var onChange: ((Bool) -> Void)?
    private var generation = UUID()
    private(set) var isCooling = false

    // Avoid the affected runtime's synthesized isolated-deinit executor hop.
    // Observer/task closures hold only weak references to this controller.
    nonisolated deinit {}

    init(notificationCenter: NotificationCenter = .default,
         cooldown: Duration = TrainingThermalProtection.cooldownDuration,
         thermalState: @escaping () -> ProcessInfo.ThermalState = { ProcessInfo.processInfo.thermalState }) {
        self.notificationCenter = notificationCenter
        self.cooldown = cooldown
        self.thermalState = thermalState
    }

    func start(onChange: @escaping (Bool) -> Void) {
        guard observer == nil else { return }
        self.onChange = onChange
        let initial = thermalState() // Apple requires access before observing.
        let currentGeneration = generation
        observer = notificationCenter.publisher(for: ProcessInfo.thermalStateDidChangeNotification)
            .sink { @Sendable [weak self] _ in
                Task { @MainActor in
                    guard let self, self.generation == currentGeneration else { return }
                    self.refresh()
                }
            }
        update(initial)
        refresh() // Close the read/registration window.
    }

    func refresh() {
        guard observer != nil else { return }
        update(thermalState())
    }

    func stop() {
        generation = UUID()
        observer?.cancel()
        observer = nil
        cooldownTask?.cancel()
        cooldownTask = nil
        cooldownID = nil
        onChange = nil
        isCooling = false
    }

    private func update(_ level: ProcessInfo.ThermalState) {
        switch level {
        case .serious, .critical:
            cooldownTask?.cancel()
            cooldownTask = nil
            cooldownID = nil
            if !isCooling {
                isCooling = true
                onChange?(true)
            }
        case .nominal, .fair:
            guard isCooling, cooldownTask == nil else { return }
            let currentGeneration = generation
            let duration = cooldown
            let timerID = UUID()
            cooldownID = timerID
            cooldownTask = Task { [weak self] in
                do { try await Task.sleep(for: duration) } catch { return }
                guard let self, !Task.isCancelled, self.generation == currentGeneration,
                      self.cooldownID == timerID, self.observer != nil else { return }
                self.cooldownTask = nil
                self.cooldownID = nil
                switch self.thermalState() {
                case .nominal, .fair:
                    self.isCooling = false
                    self.onChange?(false)
                default:
                    self.update(self.thermalState())
                }
            }
        @unknown default:
            // Unknown states cannot establish a safe cooldown.
            cooldownTask?.cancel()
            cooldownTask = nil
            cooldownID = nil
        }
    }
}
