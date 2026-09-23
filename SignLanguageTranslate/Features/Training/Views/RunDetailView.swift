import SwiftUI
import Charts

/// Detailed view for a historical training run
struct RunDetailView: View {
    let run: TrainingRun
    
    @State private var selectedTab: DetailTab = .metrics
    
    enum DetailTab: String, CaseIterable {
        case metrics = "Metrics"
        case architecture = "Model"
        case config = "Config"
        case logs = "Logs"
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header
                headerView
                
                Picker("View", selection: $selectedTab) {
                    ForEach(DetailTab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                
                switch selectedTab {
                case .metrics:
                    metricsView
                case .architecture:
                    if let config = run.config {
                        NeuralNetVisualizer(config: config)
                            .frame(height: 500)
                            .padding(.horizontal)
                    } else {
                        ContentUnavailableView("No Data", systemImage: "cpu", description: Text("Configuration missing for this run."))
                    }
                case .config:
                    configView
                case .logs:
                    logsView
                }
            }
            .padding(.vertical)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(run.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
    
    // MARK: - Components
    
    @ObservedObject private var trainingManager = TrainingSessionManager.shared
    @Environment(\.dismiss) var dismiss
    
    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(run.timestamp.formatted(date: .long, time: .shortened))
                    .foregroundStyle(.secondary)
                    .font(.caption)
                
                StatusBadge(status: run.status)
            }
            Spacer()
            
            // Continuation Action
            Button(action: {
                trainingManager.prepareFineTuning(run: run)
                // Go back to Dashboard (assuming this view is pushed from there)
                // Actually need to ensure Dashboard pops.
                // Or we can use deep linking logic.
                // Simplest: Dismiss and Dashboard will see state.
                dismiss()
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.triangle.pull")
                    Text("Fine-tune")
                }
                .font(.caption.bold())
                .padding(6)
            }
            .buttonStyle(.bordered)
            .tint(.orange)
            
            if let config = run.config {
                Text(config.device.uppercased())
                    .font(.caption.bold())
                    .padding(6)
                    .background(Color.gray.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
    }
    
    private var metricsView: some View {
        VStack(spacing: 16) {
            // Metrics Summary
            if let last = run.metrics.last {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    MetricCard(title: "Training Loss", value: String(format: "%.4f", last.trainingLoss), icon: "scalemass.fill", color: .blue)
                    if let val = run.metrics.last(where: { $0.validationLoss != nil })?.validationLoss {
                        MetricCard(title: "Validation Loss", value: String(format: "%.4f", val), icon: "checkmark.shield.fill", color: .orange)
                    }
                    MetricCard(title: "Epochs", value: "\(run.metrics.last?.epoch ?? 0)", icon: "arrow.triangle.2.circlepath", color: .purple)
                }
                .padding(.horizontal)
            }
            
            // Chart
            if !run.metrics.isEmpty {
                VStack(alignment: .leading) {
                    Text("Loss History")
                        .font(.headline)
                        .padding(.horizontal)
                    
                    Chart {
                        ForEach(Array(run.metrics.enumerated()), id: \.offset) { index, metric in
                            LineMark(
                                x: .value("Step", index),
                                y: .value("Loss", metric.trainingLoss),
                                series: .value("Type", "Train")
                            )
                            .foregroundStyle(.blue)
                            
                            if let valLoss = metric.validationLoss {
                                LineMark(
                                    x: .value("Step", index),
                                    y: .value("Loss", valLoss),
                                    series: .value("Type", "Validation")
                                )
                                .foregroundStyle(.orange)
                            }
                        }
                    }
                    .frame(height: 250)
                    .padding()
                    .background(Color(.secondarySystemGroupedBackground))
                    .cornerRadius(12)
                    .padding(.horizontal)
                }
            }
        }
    }
    
    private var logsView: some View {
        VStack(alignment: .leading, spacing: 12) {
            
            if run.logs.isEmpty {
                 ContentUnavailableView("No Logs", systemImage: "text.alignleft", description: Text("No logs recorded for this run."))
            } else {
                 ScrollView {
                     LazyVStack(alignment: .leading, spacing: 4) {
                         ForEach(Array(run.logs.enumerated()), id: \.offset) { _, log in
                             Text(log)
                                 .font(.caption.monospaced())
                                 .foregroundStyle(.primary)
                                 .textSelection(.enabled) // Allow copying
                         }
                     }
                     .padding()
                 }
                 .frame(height: 400)
                 .background(Color.black.opacity(0.05))
                 .cornerRadius(8)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
        .padding(.horizontal)
    }
    
    private var configView: some View {
        VStack(spacing: 12) {
            if let config = run.config {
                configRow(label: "Model Type", value: config.useLegacyModel ? "LSTM" : "Transformer")
                configRow(label: "Batch Size", value: "\(config.batchSize)")
                configRow(label: "Learning Rate", value: String(format: "%.0e", config.learningRate))
                configRow(label: "Epochs", value: "\(config.epochs)")
                configRow(label: "Augmentation", value: config.augmentData ? "Enabled" : "Disabled")
                configRow(label: "Val Split", value: "\(Int(config.validationSplitRatio * 100))%")
                // Check if patience is present (old configs might miss it)
                configRow(label: "Patience", value: "\(config.patience)")
            } else {
                Text("Configuration data unavailable.")
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
        .padding(.horizontal)
    }
    
    private func configRow(label: String, value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).bold()
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
    }
}
