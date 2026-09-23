import Foundation
import Combine

/// Monitors system resources during training to detect throttling
public class SystemMonitor: ObservableObject {

    // MARK: - Types

    public struct SystemStats: Sendable {
        public let cpuUsage: Double          // 0-100%
        public let memoryUsed: UInt64        // Bytes
        public let memoryTotal: UInt64       // Bytes
        public let thermalState: ThermalLevel
        public let timestamp: Date

        public var memoryUsagePercent: Double {
            guard memoryTotal > 0 else { return 0 }
            return Double(memoryUsed) / Double(memoryTotal) * 100
        }

        public var memoryUsedMB: Double {
            Double(memoryUsed) / 1_048_576
        }

        public var memoryTotalMB: Double {
            Double(memoryTotal) / 1_048_576
        }
    }

    public enum ThermalLevel: String, Sendable {
        case nominal = "Normal"
        case fair = "Warm"
        case serious = "Hot"
        case critical = "Critical"

        public var icon: String {
            switch self {
            case .nominal: return "thermometer.low"
            case .fair: return "thermometer.medium"
            case .serious: return "thermometer.high"
            case .critical: return "flame.fill"
            }
        }

        public var color: String {
            switch self {
            case .nominal: return "green"
            case .fair: return "yellow"
            case .serious: return "orange"
            case .critical: return "red"
            }
        }

        public var isThrottling: Bool {
            self == .serious || self == .critical
        }
    }

    // MARK: - Published State

    @Published public private(set) var currentStats: SystemStats?
    @Published public private(set) var isThrottling: Bool = false
    @Published public private(set) var statsHistory: [SystemStats] = []

    // MARK: - Properties

    private var timer: Timer?
    private var thermalObserver: NSObjectProtocol?
    private let maxHistoryCount = 60  // Keep last 60 samples (1 minute at 1Hz)

    // CPU tracking
    private var previousCPUInfo: host_cpu_load_info?

    // MARK: - Singleton

    public static let shared = SystemMonitor()

    private init() {
        setupThermalObserver()
    }

    deinit {
        stop()
        if let observer = thermalObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Public API

    /// Start monitoring at specified interval
    public func start(interval: TimeInterval = 1.0) {
        stop()

        // Take initial reading
        updateStats()

        // Schedule regular updates
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.updateStats()
        }
    }

    /// Stop monitoring
    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Clear history
    public func clearHistory() {
        statsHistory.removeAll()
    }

    // MARK: - Private

    private func setupThermalObserver() {
        thermalObserver = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateStats()
        }
    }

    private func updateStats() {
        let cpuUsage = getCPUUsage()
        let (memUsed, memTotal) = getMemoryUsage()
        let thermal = getThermalState()

        let stats = SystemStats(
            cpuUsage: cpuUsage,
            memoryUsed: memUsed,
            memoryTotal: memTotal,
            thermalState: thermal,
            timestamp: Date()
        )

        DispatchQueue.main.async {
            self.currentStats = stats
            self.isThrottling = thermal.isThrottling

            self.statsHistory.append(stats)
            if self.statsHistory.count > self.maxHistoryCount {
                self.statsHistory.removeFirst()
            }
        }
    }

    // MARK: - System Info

    private func getCPUUsage() -> Double {
        var cpuInfo: host_cpu_load_info?
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride)

        let result = withUnsafeMutablePointer(to: &cpuInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }

        guard result == KERN_SUCCESS, let info = cpuInfo else {
            return 0
        }

        let user = Double(info.cpu_ticks.0)
        let system = Double(info.cpu_ticks.1)
        let idle = Double(info.cpu_ticks.2)
        let nice = Double(info.cpu_ticks.3)

        let total = user + system + idle + nice

        // Calculate delta from previous reading
        if let prev = previousCPUInfo {
            let prevUser = Double(prev.cpu_ticks.0)
            let prevSystem = Double(prev.cpu_ticks.1)
            let prevIdle = Double(prev.cpu_ticks.2)
            let prevNice = Double(prev.cpu_ticks.3)
            let prevTotal = prevUser + prevSystem + prevIdle + prevNice

            let deltaTotal = total - prevTotal
            let deltaIdle = idle - Double(prev.cpu_ticks.2)

            previousCPUInfo = info

            if deltaTotal > 0 {
                return (1.0 - deltaIdle / deltaTotal) * 100.0
            }
        }

        previousCPUInfo = info

        // First reading - return instantaneous
        if total > 0 {
            return ((user + system + nice) / total) * 100.0
        }

        return 0
    }

    private func getMemoryUsage() -> (used: UInt64, total: UInt64) {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<integer_t>.size)

        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }

        let used: UInt64 = result == KERN_SUCCESS ? UInt64(info.resident_size) : 0
        let total = UInt64(ProcessInfo.processInfo.physicalMemory)

        return (used, total)
    }

    private func getThermalState() -> ThermalLevel {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal:
            return .nominal
        case .fair:
            return .fair
        case .serious:
            return .serious
        case .critical:
            return .critical
        @unknown default:
            return .nominal
        }
    }
}

// MARK: - Formatted Output

extension SystemMonitor.SystemStats {

    public var formattedCPU: String {
        String(format: "%.1f%%", cpuUsage)
    }

    public var formattedMemory: String {
        String(format: "%.0f / %.0f MB", memoryUsedMB, memoryTotalMB)
    }

    public var formattedMemoryPercent: String {
        String(format: "%.1f%%", memoryUsagePercent)
    }
}
