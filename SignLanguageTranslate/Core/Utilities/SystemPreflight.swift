import Foundation
import Network
import Observation

/// Live device conditions that affect a large download: free storage,
/// network, Low Data Mode and Low Power Mode. Read from the system, never
/// hardcoded. Call `monitor()` from a view's `.task`; it runs until cancelled.
@MainActor
@Observable
final class SystemPreflight {

    enum Connection: Equatable {
        case checking, offline, wifi, wiredEthernet, cellular, other
    }

    /// Free space for important data on the app's volume, or nil if unknown.
    private(set) var freeBytes: Int64?
    private(set) var connection: Connection = .checking
    /// The current path is constrained (Low Data Mode).
    private(set) var isLowDataMode = false
    private(set) var isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled

    func refreshStorage() {
        let values = try? URL.documentsDirectory.resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey]
        )
        freeBytes = values?.volumeAvailableCapacityForImportantUsage
    }

    /// Streams network and power-state changes into the properties.
    func monitor() async {
        refreshStorage()
        await withTaskGroup(of: Void.self) { group in
            group.addTask { @MainActor [weak self] in
                for await path in NWPathMonitor() {
                    self?.apply(path)
                }
            }
            group.addTask { @MainActor [weak self] in
                let changes = NotificationCenter.default.notifications(
                    named: .NSProcessInfoPowerStateDidChange
                )
                for await _ in changes {
                    self?.isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
                }
            }
        }
    }

    private func apply(_ path: NWPath) {
        isLowDataMode = path.isConstrained
        guard path.status == .satisfied else {
            connection = .offline
            return
        }
        if path.usesInterfaceType(.wifi) {
            connection = .wifi
        } else if path.usesInterfaceType(.wiredEthernet) {
            connection = .wiredEthernet
        } else if path.usesInterfaceType(.cellular) {
            connection = .cellular
        } else {
            connection = .other
        }
    }
}
