import SwiftUI
import SwiftData
import Charts

struct DatasetEDAView: View {
    let dataset: Dataset
    
    @Query private var samples: [VideoSample]
    @Environment(\.dismiss) private var dismiss
    
    // Derived stats
    @State private var classDistribution: [(String, Int)] = []
    @State private var missingFeaturesCount: Int = 0
    @State private var totalDuration: TimeInterval = 0
    @State private var isLoading = true
    
    init(dataset: Dataset) {
        self.dataset = dataset
        // Predicate to filter samples for this dataset
        let name = dataset.name
        _samples = Query(filter: #Predicate<VideoSample> { sample in
            sample.datasetName == name
        })
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if isLoading {
                    ProgressView("Analyzing Dataset...")
                        .frame(height: 200)
                } else {
                    // 1. Summary Cards
                    summarySection
                    
                    // 2. Class Distribution
                    distributionSection
                    
                    // 3. Quality Checks
                    qualitySection
                    
                    // 4. Sample Review
                    samplePreviewSection
                }
            }
            .padding()
        }
        .navigationTitle("Dataset Analysis")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await analyzeData()
        }
    }
    
    // MARK: - Sections
    
    private var summarySection: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
            InfoCard(title: "Total Samples", value: "\(samples.count)", icon: "video.fill", color: .blue)
            InfoCard(title: "Classes", value: "\(classDistribution.count)", icon: "tag.fill", color: .purple)
            InfoCard(title: "Total Duration", value: formatDuration(totalDuration), icon: "clock.fill", color: .orange)
            InfoCard(title: "Avg Duration", value: samples.isEmpty ? "0s" : String(format: "%.1fs", totalDuration / Double(samples.count)), icon: "stopwatch.fill", color: .green)
        }
    }
    
    private var distributionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Top 10 Classes")
                .font(.headline)
            
            if classDistribution.isEmpty {
                ContentUnavailableView("No Labels Found", systemImage: "tag.slash")
            } else {
                Chart(classDistribution.prefix(10), id: \.0) { item in
                    BarMark(
                        x: .value("Count", item.1),
                        y: .value("Class", item.0)
                    )
                    .foregroundStyle(.blue.gradient)
                    .annotation(position: .trailing) {
                        Text("\(item.1)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(height: 300)
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
    
    private var qualitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Data Quality")
                .font(.headline)
            
            HStack {
                VStack(alignment: .leading) {
                    Text("Missing Features")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("\(missingFeaturesCount)")
                        .font(.title2.bold())
                        .foregroundStyle(missingFeaturesCount > 0 ? .red : .green)
                }
                Spacer()
                if missingFeaturesCount > 0 {
                    Text("Run Pipeline to extract features")
                        .font(.caption)
                        .padding(6)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(6)
                }
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
    
    private var samplePreviewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Samples")
                .font(.headline)
            
            ForEach(samples.prefix(5)) { sample in
                HStack {
                    Image(systemName: "video.fill")
                        .foregroundStyle(.blue)
                    VStack(alignment: .leading) {
                        Text(sample.displayTitle)
                            .font(.subheadline.bold())
                        Text(sample.formattedDuration)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if !sample.featureSets.isEmpty {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }
                .padding(.vertical, 4)
                Divider()
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
    
    // MARK: - Analysis Logic
    
    private func analyzeData() async {
        // Offload to background thread
        await Task.detached(priority: .userInitiated) {
            // Compute stats
            // Thread-safe access via copies? SwiftData Query results are main-thread bound usually, 
            // but we can access properties if we map them first on MainActor then process.
            // Actually, we are in a View, so Query is main thread.
            // We can process light data here or use background context.
            // For now, process on MainActor is simpler for UI unless dataset is huge.
            // If huge, Query might lag.
        }.value
        
        // Simple main thread processing for Beta
        var dist: [String: Int] = [:]
        var missing = 0
        var duration: TimeInterval = 0
        
        for sample in samples {
            // Class distribution
            if let label = sample.wordName ?? sample.sentenceText {
                dist[label, default: 0] += 1
            } else {
                dist["Unknown", default: 0] += 1
            }
            
            // Missing features
            if sample.featureSets.isEmpty {
                missing += 1
            }
            
            duration += sample.duration
        }
        
        let sortedDist = dist.sorted { $0.value > $1.value }
        
        await MainActor.run {
            self.classDistribution = sortedDist
            self.missingFeaturesCount = missing
            self.totalDuration = duration
            self.isLoading = false
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: duration) ?? "0s"
    }
}

fileprivate struct InfoCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.title3.bold())
                .minimumScaleFactor(0.8)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(10)
    }
}
