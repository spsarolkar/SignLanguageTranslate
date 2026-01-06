import SwiftUI
import SwiftData

struct ContentView: View {

    @Environment(\.modelContext) private var modelContext
    @Query(ModelQueries.allDatasets) private var datasets: [Dataset]
    @Query(ModelQueries.categoryLabels) private var categories: [Label]

    @State private var selectedDataset: Dataset?
    @State private var showingStats = false

    var body: some View {
        NavigationSplitView {
            // Sidebar
            List(selection: $selectedDataset) {
                Section("Datasets") {
                    ForEach(datasets) { dataset in
                        DatasetRowView(dataset: dataset)
                            .tag(dataset)
                    }
                }

                Section("Categories (\(categories.count))") {
                    ForEach(categories) { category in
                        SwiftUI.Label(category.name, systemImage: category.type.iconName)
                    }
                }
            }
            .navigationTitle("SignLanguageTranslate")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingStats = true
                    } label: {
                        Image(systemName: "chart.bar.fill")
                    }
                }
            }
        } detail: {
            if let dataset = selectedDataset {
                DatasetDetailPlaceholder(dataset: dataset)
            } else {
                ContentUnavailableView(
                    "Select a Dataset",
                    systemImage: "hand.raised.fingers.spread.fill",
                    description: Text("Choose a dataset from the sidebar to view its contents")
                )
            }
        }
        .sheet(isPresented: $showingStats) {
            StatsSheet()
        }
    }
}

// MARK: - Dataset Row View

struct DatasetRowView: View {
    let dataset: Dataset

    var body: some View {
        HStack(spacing: 12) {
            // Icon
            Image(systemName: dataset.datasetType.iconName)
                .font(.title2)
                .foregroundStyle(dataset.datasetType.color)
                .frame(width: 32)

            // Info
            VStack(alignment: .leading, spacing: 2) {
                Text(dataset.name)
                    .font(.headline)

                Text(dataset.downloadStatus.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Status indicator
            statusIndicator
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var statusIndicator: some View {
        switch dataset.downloadStatus {
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .downloading:
            ProgressView(value: dataset.downloadProgress)
                .progressViewStyle(.circular)
                .frame(width: 24, height: 24)
        case .paused:
            Image(systemName: "pause.circle.fill")
                .foregroundStyle(.orange)
        case .failed:
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
        case .processing:
            ProgressView()
                .frame(width: 24, height: 24)
        case .notStarted:
            Image(systemName: "arrow.down.circle")
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Dataset Detail Placeholder

struct DatasetDetailPlaceholder: View {
    let dataset: Dataset

    @Query private var samples: [VideoSample]

    init(dataset: Dataset) {
        self.dataset = dataset
        let datasetName = dataset.name
        _samples = Query(
            filter: #Predicate<VideoSample> { $0.datasetName == datasetName },
            sort: [SortDescriptor(\VideoSample.localPath)]
        )
    }

    var body: some View {
        List {
            Section("Dataset Info") {
                LabeledContent("Name", value: dataset.name)
                LabeledContent("Type", value: dataset.datasetType.displayName)
                LabeledContent("Status", value: dataset.downloadStatus.displayName)
                LabeledContent("Progress", value: "\(Int(dataset.downloadProgress * 100))%")
            }

            Section("Storage") {
                LabeledContent("Total Size", value: dataset.formattedTotalSize)
                LabeledContent("Downloaded", value: dataset.formattedDownloadedSize)
                LabeledContent("Parts", value: dataset.partsProgressText)
            }

            Section("Samples (\(samples.count))") {
                ForEach(samples.prefix(10)) { sample in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(sample.displayTitle)
                            .font(.headline)
                        Text(sample.localPath)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if !sample.labels.isEmpty {
                            HStack {
                                ForEach(sample.labels) { label in
                                    Text(label.name)
                                        .font(.caption2)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 2)
                                        .background(
                                            Capsule()
                                                .fill(Color(label.type.colorName).opacity(0.2))
                                        )
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }

                if samples.count > 10 {
                    Text("And \(samples.count - 10) more...")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(dataset.name)
    }
}

// MARK: - Stats Sheet

struct StatsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query(ModelQueries.allDatasets) private var datasets: [Dataset]
    @Query(ModelQueries.allLabels) private var labels: [Label]
    @Query(ModelQueries.allVideoSamples) private var samples: [VideoSample]

    var body: some View {
        NavigationStack {
            List {
                Section("Overview") {
                    LabeledContent("Datasets", value: "\(datasets.count)")
                    LabeledContent("Total Labels", value: "\(labels.count)")
                    LabeledContent("Total Samples", value: "\(samples.count)")
                }

                Section("Labels by Type") {
                    let categoryCount = labels.filter { $0.type == .category }.count
                    let wordCount = labels.filter { $0.type == .word }.count
                    let sentenceCount = labels.filter { $0.type == .sentence }.count

                    LabeledContent("Categories", value: "\(categoryCount)")
                    LabeledContent("Words", value: "\(wordCount)")
                    LabeledContent("Sentences", value: "\(sentenceCount)")
                }

                Section("Samples by Dataset") {
                    ForEach(datasets) { dataset in
                        let count = samples.filter { $0.datasetName == dataset.name }.count
                        LabeledContent(dataset.name, value: "\(count)")
                    }
                }

                Section("Relationship Test") {
                    if let firstSample = samples.first {
                        Text("First sample: \(firstSample.fileName)")
                        Text("Labels: \(firstSample.labels.map(\.name).joined(separator: ", "))")

                        if let categoryLabel = firstSample.categoryLabel {
                            let linkedCount = categoryLabel.videoSamples?.count ?? 0
                            Text("Category '\(categoryLabel.name)' links to \(linkedCount) videos")
                        }
                    } else {
                        Text("No samples found")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Database Stats")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    ContentView()
        .modelContainer(PersistenceController.preview.container)
}
