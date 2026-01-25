import SwiftUI

/// Progress overlay shown during batch extraction
struct ExtractionProgressOverlay: View {
    let progress: BatchExtractionService.Progress
    let metrics: BatchExtractionService.ExecutionMetrics?
    let thermalState: ProcessInfo.ThermalState
    let debugInfo: String?
    let onCancel: () -> Void
    
    // Thermal State Helpers
    private var thermalColor: Color {
        switch thermalState {
        case .nominal: return .green
        case .fair: return .yellow
        case .serious: return .orange
        case .critical: return .red
        @unknown default: return .gray
        }
    }
    
    private var thermalText: String {
        switch thermalState {
        case .nominal: return "Normal"
        case .fair: return "Warm"
        case .serious: return "Hot (Throttling)"
        case .critical: return "Critical (Paused)"
        @unknown default: return "Unknown"
        }
    }
    
    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Image(systemName: "cpu.fill")
                    .font(.title2)
                    .foregroundStyle(.blue)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Extracting Features")
                        .font(.headline)
                    Text("Device kept awake")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Button(action: onCancel) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            
            // Progress bar
            VStack(spacing: 8) {
                ProgressView(value: progress.percentage) {
                    HStack {
                        Text(progress.formattedProgress)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Spacer()
                        Text("\(Int(progress.percentage * 100))%")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .tint(thermalState == .critical ? .red : .blue)
                
                // Current video
                HStack {
                    Image(systemName: "film")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Text(progress.currentVideoName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    
                    Spacer()
                }
            }
            
            Divider()
            
            // Metrics Grid
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                // Avg Time
                MetricItem(
                    label: "Avg Time",
                    value: metrics?.formattedAverageTime ?? "--",
                    icon: "clock.arrow.circlepath"
                )
                
                // ETA
                MetricItem(
                    label: "Est. Remaining",
                    value: metrics?.formattedETA ?? "--",
                    icon: "hourglass"
                )
                
                // Thermal State
                MetricItem(
                    label: "Temperature",
                    value: thermalText,
                    icon: "thermometer.medium",
                    valueColor: thermalColor
                )
                
                // Background Status
                MetricItem(
                    label: "Mode",
                    value: debugInfo ?? "Active",
                    icon: debugInfo == nil ? "lock.open.laptopcomputer" : "exclamationmark.triangle",
                    valueColor: debugInfo == nil ? .primary : .orange
                )
            }
            
            // Cancel button
            Button(action: onCancel) {
                Text("Cancel Extraction")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(20)
        .background(.ultraThinMaterial)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.2), radius: 12, y: 6)
        .frame(width: 340)
    }
}



fileprivate struct MetricItem: View {
    let label: String
    let value: String
    let icon: String
    var valueColor: Color = .primary
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(valueColor)
            }
            Spacer()
        }
        .padding(8)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(8)
    }
}

#Preview {
    ZStack {
        Color.black.opacity(0.3)
            .ignoresSafeArea()
        
        ExtractionProgressOverlay(
            progress: BatchExtractionService.Progress(
                completed: 15,
                total: 100,
                currentVideoName: "MVI_9569.MOV"
            ),
            metrics: BatchExtractionService.ExecutionMetrics(
                startTime: Date(),
                processedCount: 15,
                averageTimePerVideo: 1.2,
                estimatedTimeRemaining: 120
            ),
            thermalState: .nominal,
            debugInfo: nil,
            onCancel: {}
        )
    }
}
