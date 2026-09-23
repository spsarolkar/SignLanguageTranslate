import SwiftUI

/// Displays system resource usage during training
struct SystemStatsView: View {
    @ObservedObject var monitor: SystemMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                SwiftUI.Label("System Monitor", systemImage: "cpu")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)

                Spacer()

                if monitor.isThrottling {
                    SwiftUI.Label("THROTTLING", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2.bold())
                        .foregroundStyle(.red)
                }
            }

            if let stats = monitor.currentStats {
                HStack(spacing: 16) {
                    // CPU Usage
                    statItem(
                        icon: "cpu",
                        title: "CPU",
                        value: stats.formattedCPU,
                        color: cpuColor(stats.cpuUsage)
                    )

                    Divider()
                        .frame(height: 30)

                    // Memory
                    statItem(
                        icon: "memorychip",
                        title: "Memory",
                        value: stats.formattedMemoryPercent,
                        color: memoryColor(stats.memoryUsagePercent)
                    )

                    Divider()
                        .frame(height: 30)

                    // Thermal
                    statItem(
                        icon: stats.thermalState.icon,
                        title: "Thermal",
                        value: stats.thermalState.rawValue,
                        color: thermalColor(stats.thermalState)
                    )
                }

                // Warning message if throttling
                if stats.thermalState.isThrottling {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("Device is thermal throttling. Training may be slower.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 4)
                }
            } else {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Initializing monitor...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .background(Color(UIColor.tertiarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Components

    private func statItem(icon: String, title: String, value: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(color)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                Text(value)
                    .font(.caption.bold())
                    .foregroundStyle(color)
            }
        }
    }

    // MARK: - Colors

    private func cpuColor(_ usage: Double) -> Color {
        if usage > 90 { return .red }
        if usage > 70 { return .orange }
        if usage > 50 { return .yellow }
        return .green
    }

    private func memoryColor(_ usage: Double) -> Color {
        if usage > 85 { return .red }
        if usage > 70 { return .orange }
        return .green
    }

    private func thermalColor(_ state: SystemMonitor.ThermalLevel) -> Color {
        switch state {
        case .nominal: return .green
        case .fair: return .yellow
        case .serious: return .orange
        case .critical: return .red
        }
    }
}

// MARK: - Compact Version

struct SystemStatsCompactView: View {
    @ObservedObject var monitor: SystemMonitor

    var body: some View {
        HStack(spacing: 12) {
            if let stats = monitor.currentStats {
                // CPU
                HStack(spacing: 4) {
                    Image(systemName: "cpu")
                        .font(.caption2)
                    Text(stats.formattedCPU)
                        .font(.caption2.monospacedDigit())
                }
                .foregroundStyle(cpuColor(stats.cpuUsage))

                // Memory
                HStack(spacing: 4) {
                    Image(systemName: "memorychip")
                        .font(.caption2)
                    Text(stats.formattedMemoryPercent)
                        .font(.caption2.monospacedDigit())
                }
                .foregroundStyle(memoryColor(stats.memoryUsagePercent))

                // Thermal
                HStack(spacing: 4) {
                    Image(systemName: stats.thermalState.icon)
                        .font(.caption2)
                    if stats.thermalState.isThrottling {
                        Text("THROTTLE")
                            .font(.caption2.bold())
                    }
                }
                .foregroundStyle(thermalColor(stats.thermalState))
            } else {
                Text("...")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func cpuColor(_ usage: Double) -> Color {
        if usage > 90 { return .red }
        if usage > 70 { return .orange }
        return .secondary
    }

    private func memoryColor(_ usage: Double) -> Color {
        if usage > 85 { return .red }
        if usage > 70 { return .orange }
        return .secondary
    }

    private func thermalColor(_ state: SystemMonitor.ThermalLevel) -> Color {
        switch state {
        case .nominal: return .green
        case .fair: return .yellow
        case .serious: return .orange
        case .critical: return .red
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        SystemStatsView(monitor: SystemMonitor.shared)
            .padding()

        SystemStatsCompactView(monitor: SystemMonitor.shared)
            .padding()
    }
    .background(Color(UIColor.systemGroupedBackground))
    .onAppear {
        SystemMonitor.shared.start()
    }
}
