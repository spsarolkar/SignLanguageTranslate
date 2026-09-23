import SwiftUI

struct AnalysisDashboardView: View {
    let dataset: Dataset
    @StateObject private var viewModel = AnalysisViewModel()
    
    @Environment(\.modelContext) private var modelContext    
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header / Actions
                if viewModel.result == nil {
                    ContentUnavailableView(
                        "No Analysis Data",
                        systemImage: "chart.bar.xaxis",
                        description: Text("Analyze the dataset to view feature insights.")
                    )
                    
                    Button("Analyze Dataset") {
                        viewModel.startAnalysis(modelContext: modelContext)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.isAnalyzing)
                    
                    if viewModel.isAnalyzing {
                        ProgressView("Analyzing features...")
                    }
                } else if let result = viewModel.result {
                    // 1. Key Statistics
                    statsGrid(result)
                    
                    // 2. Variance Chart
                    VStack(alignment: .leading) {
                        Text("Feature Importance (Variance)")
                            .font(.headline)
                        
                        Text("Low variance indicates 'dead' joints that don't move.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        FeatureVarianceChart(variances: result.featureVariances)
                            .frame(height: 250)
                    }
                    .padding()
                    .background(Color(.secondarySystemGroupedBackground))
                    .cornerRadius(12)
                    
                    // 3. Correlation Heatmap
                    VStack(alignment: .leading) {
                        Text("Correlation Heatmap")
                            .font(.headline)
                        
                        Text("Red = Positive, Blue = Negative. Diagonal is always 1.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        CorrelationHeatmap(matrix: result.correlationMatrix)
                            .frame(height: 400) // Square layout
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .padding()
                    .background(Color(.secondarySystemGroupedBackground))
                    .cornerRadius(12)
                    
                    // 4. PCA Scatter Plot
                    VStack(alignment: .leading) {
                        Text("Feature Clustering (PCA)")
                            .font(.headline)
                        
                        Text("2D Projection of 180-dim Features. Clusters indicate separable data.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        if !result.pcaPoints.isEmpty {
                            PCAScatterChart(points: result.pcaPoints)
                                .frame(height: 300)
                        } else {
                            ContentUnavailableView(
                                "No PCA Data",
                                systemImage: "point.3.filled.connected.triangle.path.dotted",
                                description: Text("Not enough data to compute PCA projection.")
                            )
                            .frame(height: 300)
                        }
                    }
                    .padding()
                    .background(Color(.secondarySystemGroupedBackground))
                    .cornerRadius(12)
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Dataset Analysis")
        .task {
            viewModel.setcanDataset(dataset)
        }
        .alert("Error", isPresented: Binding(get: { viewModel.errorMessage != nil }, set: { _ in viewModel.errorMessage = nil })) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }
    
    private func statsGrid(_ result: FeatureAnalyzer.AnalysisResult) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            statCard(
                title: "Mean Value",
                value: String(format: "%.4f", result.globalMean),
                icon: "plus.circle"
            )
            
            statCard(
                title: "Std Dev",
                value: String(format: "%.4f", result.globalStd),
                icon: "waveform.path.ecg"
            )
            
            statCard(
                title: "Dead Features",
                value: "\(result.deadFeatureCount)",
                icon: "exclamationmark.triangle",
                color: result.deadFeatureCount > 0 ? .red : .green
            )
        }
    }
    
    private func statCard(title: String, value: String, icon: String, color: Color = .blue) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Text(value)
                .font(.title2.bold())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
}
