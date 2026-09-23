import SwiftUI
import SwiftData

struct ModelTestingView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var viewModel: ModelTestingViewModel
    
    init(engine: InferenceEngine, modelsDirectory: URL? = nil) {
        _viewModel = StateObject(wrappedValue: ModelTestingViewModel(
            inferenceEngine: engine,
            modelsDirectory: modelsDirectory
        ))
        // engine is typically passed down or shared, here we assume it's passed in
    }
    
    var body: some View {
        Form {
            Section("Model Selection") {
                if viewModel.availableCheckpoints.isEmpty {
                    Text("No checkpoints found")
                        .foregroundStyle(.secondary)
                    Button("Refresh") {
                        Task { await viewModel.fetchCheckpoints() }
                    }
                } else {
                    Picker("Checkpoint", selection: $viewModel.selectedCheckpoint) {
                        ForEach(viewModel.availableCheckpoints) { cp in
                            Text("Epoch \(cp.epoch) (Loss: \(cp.loss.map { String(format: "%.3f", $0) } ?? "N/A"))")
                                .tag(cp as ModelPersistence.CheckpointInfo?)
                        }
                    }
                    .onChange(of: viewModel.selectedCheckpoint) { newValue in
                        if let cp = newValue {
                            Task { await viewModel.loadCheckpoint(cp) }
                        }
                    }
                    
                    if let selected = viewModel.selectedCheckpoint {
                        Text("Loaded: \(selected.timestamp.formatted())")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            Section("Test Set Evaluation") {
                if viewModel.isTesting {
                    VStack(alignment: .leading, spacing: 8) {
                        ProgressView(value: viewModel.progress)
                        Text("Processing sample \(viewModel.processedSamples) of \(viewModel.totalTestSamples)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Button(action: {
                        Task { await viewModel.startEvaluation(modelContext: modelContext) }
                    }) {
                        Text("Evaluate Test Set")
                    }
                }
                
                HStack {
                    Text("Total Samples")
                    Spacer()
                    Text("\(viewModel.totalTestSamples)")
                        .foregroundStyle(.secondary)
                }
                
                HStack {
                    Text("Accuracy")
                    Spacer()
                    Text(String(format: "%.1f%%", viewModel.accuracy))
                        .bold()
                        .foregroundStyle(viewModel.accuracy > 80 ? .green : .orange)
                }
                
                HStack {
                    Text("Correct Predictions")
                    Spacer()
                    Text("\(viewModel.correctPredictions)")
                        .foregroundStyle(.secondary)
                }
            }
            
            Section("Single Sample Verification") {
                Button(action: {
                    viewModel.pickRandomOneOffSample(modelContext: modelContext)
                }) {
                    HStack {
                        Image(systemName: "shuffle")
                        Text("Pick Random Test Sample")
                    }
                }
                
                if let sample = viewModel.currentTestSample {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("File: \(sample.fileName)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        
                        Text("Label: \(sample.wordName ?? sample.labels.first?.name ?? "Unknown")")
                            .font(.headline)
                    }
                    .padding(.vertical, 4)
                    
                    Button(action: {
                        Task { await viewModel.testSingleSample() }
                    }) {
                        if viewModel.isPredictingSingle {
                            ProgressView()
                        } else {
                            Text("Run Prediction")
                        }
                    }
                    .disabled(viewModel.isPredictingSingle)
                    
                    if let result = viewModel.singlePrediction {
                        VStack(alignment: .leading) {
                            Divider()
                            HStack {
                                Text("Prediction:")
                                Spacer()
                                Text(result.label)
                                    .bold()
                                    .foregroundStyle(result.label == (sample.wordName ?? sample.labels.first?.name ?? "") ? .green : .red)
                            }
                            HStack {
                                Text("Confidence:")
                                Spacer()
                                Text(String(format: "%.1f%%", result.confidence * 100))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.top, 4)
                    }
                }
            }
            
            if !viewModel.testResults.isEmpty {
                Section("Detailed Results") {
                    List(viewModel.testResults) { result in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(result.expectedLabel)
                                    .font(.headline)
                                Text("Pred: \(result.predictedLabel)")
                                    .font(.subheadline)
                                    .foregroundStyle(result.isCorrect ? .green : .red)
                            }
                            Spacer()
                            Text("\(Int(result.confidence))%")
                                .font(.caption)
                        }
                    }
                }
            }
        }
        .navigationTitle("Model Testing")
        .alert("Error", isPresented: $viewModel.showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(viewModel.errorMessage)
        }
        .task {
            // Initial fetch
            await viewModel.fetchCheckpoints()
        }
    }
}

#Preview {
    ModelTestingView(engine: InferenceEngine())
}
