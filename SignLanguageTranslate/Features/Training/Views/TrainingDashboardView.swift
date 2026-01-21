import SwiftUI
import SwiftData
import Charts

/// Main training dashboard showing metrics, progress, and controls
struct TrainingDashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var trainingManager = TrainingSessionManager()

    // Model configuration
    @State private var selectedModelSize: ModelSize = .default
    @State private var batchSize: Int = 32
    @State private var epochs: Int = 10
    @State private var learningRate: Float = 1e-4

    // UI State
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var showingSettings = false
    @State private var selectedTab: DashboardTab = .metrics

    enum DashboardTab: String, CaseIterable {
        case metrics = "Metrics"
        case logs = "Logs"
        case config = "Configuration"
    }

    enum ModelSize: String, CaseIterable {
        case small = "Small"
        case `default` = "Default"
        case large = "Large"

        var config: SignLanguageModelConfig {
            switch self {
            case .small: return .small
            case .default: return .default
            case .large: return .large
            }
        }

        var description: String {
            switch self {
            case .small: return "2 layers, 128 dims - Fast training"
            case .default: return "4 layers, 256 dims - Balanced"
            case .large: return "6 layers, 512 dims - Best accuracy"
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header with status
                headerView

                // Tab selector
                Picker("View", selection: $selectedTab) {
                    ForEach(DashboardTab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                // Content based on selected tab
                switch selectedTab {
                case .metrics:
                    metricsView
                case .logs:
                    logsView
                case .config:
                    configurationView
                }

                Spacer(minLength: 20)

                // Control buttons
                controlsView
            }
            .padding(.vertical)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Training")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            await trainingManager.prepare()
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }

    // MARK: - Header

    private var headerView: some View {
        VStack(spacing: 12) {
            // Status badge
            HStack(spacing: 8) {
                StatusIndicator(status: trainingManager.state)
                Text(trainingManager.state.rawValue.capitalized)
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(Color(.tertiarySystemBackground))
            )

            // Progress ring (when training)
            if trainingManager.state == .training {
                ZStack {
                    Circle()
                        .stroke(Color.gray.opacity(0.2), lineWidth: 8)

                    Circle()
                        .trim(from: 0, to: trainingManager.progress)
                        .stroke(
                            AngularGradient(
                                colors: [.blue, .purple, .blue],
                                center: .center
                            ),
                            style: StrokeStyle(lineWidth: 8, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))

                    VStack(spacing: 4) {
                        Text("\(Int(trainingManager.progress * 100))%")
                            .font(.title2.bold().monospacedDigit())

                        Text("Epoch \(trainingManager.currentEpoch)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 120, height: 120)
                .animation(.easeInOut, value: trainingManager.progress)
            }
        }
        .padding()
    }

    // MARK: - Metrics View

    private var metricsView: some View {
        VStack(spacing: 16) {
            // Metrics Grid
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                MetricCard(
                    title: "Epoch",
                    value: "\(trainingManager.currentEpoch) / \(trainingManager.config.epochs)",
                    icon: "clock.arrow.circlepath",
                    color: .blue
                )
                MetricCard(
                    title: "Batch",
                    value: "\(trainingManager.currentBatch)",
                    icon: "square.stack.3d.up",
                    color: .purple
                )
                MetricCard(
                    title: "Loss",
                    value: String(format: "%.4f", trainingManager.lastLoss),
                    icon: "chart.line.downtrend.xyaxis",
                    color: trainingManager.lastLoss < 0.5 ? .green : .orange
                )
                MetricCard(
                    title: "Learning Rate",
                    value: String(format: "%.2e", trainingManager.config.learningRate),
                    icon: "dial.medium",
                    color: .teal
                )
            }
            .padding(.horizontal)

            // Loss Chart
            chartView
        }
    }

    private var chartView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Training Loss")
                .font(.headline)
                .padding(.horizontal)

            if !trainingManager.metrics.isEmpty {
                Chart(trainingManager.metrics.suffix(100)) { metric in
                    LineMark(
                        x: .value("Step", metric.batchIndex + (metric.epoch * 100)),
                        y: .value("Loss", metric.trainingLoss)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )

                    AreaMark(
                        x: .value("Step", metric.batchIndex + (metric.epoch * 100)),
                        y: .value("Loss", metric.trainingLoss)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue.opacity(0.3), .purple.opacity(0.1)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }
                .chartYScale(domain: 0...max(1.0, trainingManager.metrics.map { $0.trainingLoss }.max() ?? 1.0))
                .frame(height: 200)
                .padding()
                .background(Color(.secondarySystemGroupedBackground))
                .cornerRadius(12)
                .padding(.horizontal)
            } else {
                ContentUnavailableView(
                    "No Training Data",
                    systemImage: "chart.xyaxis.line",
                    description: Text("Start training to see the loss curve")
                )
                .frame(height: 200)
                .background(Color(.secondarySystemGroupedBackground))
                .cornerRadius(12)
                .padding(.horizontal)
            }
        }
    }

    // MARK: - Logs View

    private var logsView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Training Logs")
                    .font(.headline)

                Spacer()

                Button {
                    // Copy logs to clipboard
                    #if os(iOS)
                    UIPasteboard.general.string = trainingManager.logs.joined(separator: "\n")
                    #endif
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(trainingManager.logs.enumerated()), id: \.offset) { index, log in
                            Text(log)
                                .font(.caption)
                                .fontDesign(.monospaced)
                                .foregroundStyle(logColor(for: log))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(index)
                        }
                    }
                    .padding()
                }
                .frame(height: 300)
                .background(Color.black.opacity(0.9))
                .cornerRadius(8)
                .onChange(of: trainingManager.logs.count) { _, newCount in
                    withAnimation {
                        proxy.scrollTo(newCount - 1, anchor: .bottom)
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    private func logColor(for log: String) -> Color {
        if log.contains("Error") || log.contains("error") {
            return .red
        } else if log.contains("Warning") || log.contains("warning") {
            return .orange
        } else if log.contains("finished") || log.contains("completed") {
            return .green
        }
        return .gray
    }

    // MARK: - Configuration View

    private var configurationView: some View {
        VStack(spacing: 16) {
            // Model Size
            VStack(alignment: .leading, spacing: 8) {
                Text("Model Size")
                    .font(.headline)

                Picker("Model Size", selection: $selectedModelSize) {
                    ForEach(ModelSize.allCases, id: \.self) { size in
                        Text(size.rawValue).tag(size)
                    }
                }
                .pickerStyle(.segmented)

                Text(selectedModelSize.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
            .cornerRadius(12)

            // Training Parameters
            VStack(alignment: .leading, spacing: 12) {
                Text("Training Parameters")
                    .font(.headline)

                LabeledContent("Batch Size") {
                    Stepper("\(batchSize)", value: $batchSize, in: 8...128, step: 8)
                }

                LabeledContent("Epochs") {
                    Stepper("\(epochs)", value: $epochs, in: 1...100)
                }

                LabeledContent("Learning Rate") {
                    Picker("", selection: $learningRate) {
                        Text("1e-3").tag(Float(1e-3))
                        Text("5e-4").tag(Float(5e-4))
                        Text("1e-4").tag(Float(1e-4))
                        Text("5e-5").tag(Float(5e-5))
                        Text("1e-5").tag(Float(1e-5))
                    }
                    .pickerStyle(.menu)
                }
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
            .cornerRadius(12)

            // Model Info
            VStack(alignment: .leading, spacing: 8) {
                Text("Model Architecture")
                    .font(.headline)

                let config = selectedModelSize.config
                Group {
                    LabeledContent("Input Dimensions", value: "\(config.inputDim)")
                    LabeledContent("Model Dimensions", value: "\(config.modelDim)")
                    LabeledContent("Output Dimensions", value: "\(config.outputDim)")
                    LabeledContent("Transformer Layers", value: "\(config.numLayers)")
                    LabeledContent("Attention Heads", value: "\(config.numHeads)")
                    LabeledContent("Pooling", value: config.poolingType.rawValue.capitalized)
                }
                .font(.subheadline)
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
            .cornerRadius(12)
        }
        .padding(.horizontal)
        .disabled(trainingManager.state == .training)
    }

    // MARK: - Controls

    private var controlsView: some View {
        VStack(spacing: 12) {
            // Primary action button
            if trainingManager.state == .idle || trainingManager.state == .completed || trainingManager.state == .failed {
                Button(action: startTraining) {
                    HStack {
                        Image(systemName: "play.fill")
                        Text("Start Training")
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
            } else {
                HStack(spacing: 12) {
                    if trainingManager.state == .paused {
                        Button(action: resumeTraining) {
                            HStack {
                                Image(systemName: "play.fill")
                                Text("Resume")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                    } else if trainingManager.state == .training {
                        Button(action: trainingManager.pauseTraining) {
                            HStack {
                                Image(systemName: "pause.fill")
                                Text("Pause")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                        }
                        .buttonStyle(.bordered)
                    }

                    Button(role: .destructive, action: trainingManager.stopTraining) {
                        HStack {
                            Image(systemName: "stop.fill")
                            Text("Stop")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Actions

    private func startTraining() {
        // Update config with selected values
        trainingManager.config = TrainingConfig(
            batchSize: batchSize,
            learningRate: learningRate,
            epochs: epochs,
            validationInterval: 10,
            device: "gpu"
        )

        let dummyPath = URL(fileURLWithPath: NSTemporaryDirectory())
        trainingManager.startTraining(datasetPath: dummyPath, modelContext: modelContext)
    }

    private func resumeTraining() {
        let dummyPath = URL(fileURLWithPath: NSTemporaryDirectory())
        trainingManager.startTraining(datasetPath: dummyPath, modelContext: modelContext)
    }
}

// MARK: - Helper Views

struct MetricCard: View {
    let title: String
    let value: String
    let icon: String
    var color: Color = .blue

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Text(title)
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Text(value)
                .font(.title3)
                .fontWeight(.semibold)
                .fontDesign(.rounded)
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
}

struct StatusIndicator: View {
    let status: TrainingState

    var color: Color {
        switch status {
        case .idle: return .gray
        case .preparing: return .blue
        case .training: return .green
        case .paused: return .orange
        case .completing: return .purple
        case .completed: return .green
        case .failed: return .red
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)

            if status == .training {
                Circle()
                    .fill(color.opacity(0.5))
                    .frame(width: 10, height: 10)
                    .scaleEffect(1.5)
                    .opacity(0.5)
                    .animation(
                        .easeInOut(duration: 1).repeatForever(autoreverses: true),
                        value: status
                    )
            }
        }
    }
}

// MARK: - Previews

#Preview("Dashboard - Idle") {
    NavigationStack {
        TrainingDashboardView()
    }
    .modelContainer(PersistenceController.preview.container)
}
