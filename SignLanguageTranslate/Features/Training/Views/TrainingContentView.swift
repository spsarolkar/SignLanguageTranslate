import SwiftUI
import SwiftUI
import SwiftData

// Disambiguate SwiftUI.Label from our model's Label class
typealias SwiftUILabel = SwiftUI.Label

/// Training section content view with dataset selection and training controls
struct TrainingContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<Dataset> { $0.downloadedParts > 0 })
    private var availableDatasets: [Dataset]

    @State private var selectedDataset: Dataset?
    @State private var showDashboard = false

    var body: some View {
        List(selection: $selectedDataset) {
            Section {
                if availableDatasets.isEmpty {
                    ContentUnavailableView(
                        "No Datasets Available",
                        systemImage: "folder.badge.questionmark",
                        description: Text("Download a dataset first to enable training.")
                    )
                    .frame(minHeight: 200)
                } else {
                    ForEach(availableDatasets) { dataset in
                        TrainingDatasetRow(dataset: dataset)
                            .tag(dataset)
                    }
                }
            } header: {
                Text("Select Dataset for Training")
            } footer: {
                Text("Select a downloaded dataset to train the sign language recognition model.")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Training")
        .navigationDestination(item: $selectedDataset) { dataset in
            TrainingDashboardView(targetDataset: dataset)
        }
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

/// Row displaying a dataset available for training
struct TrainingDatasetRow: View {
    let dataset: Dataset

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "folder.fill")
                .font(.title2)
                .foregroundStyle(.blue)
                .frame(width: 40, height: 40)
                .background(Color.blue.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                Text(dataset.name)
                    .font(.headline)

                HStack(spacing: 8) {
                    SwiftUILabel("\(dataset.downloadedParts) parts", systemImage: "doc.zipper")
                    SwiftUILabel("\(dataset.downloadedSamples) samples", systemImage: "video")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}

#Preview("Training Content - Empty") {
    NavigationStack {
        TrainingContentView()
    }
    .modelContainer(PersistenceController.preview.container)
}

#Preview("Training Content - With Datasets") {
    NavigationStack {
        TrainingContentView()
    }
    .modelContainer(PersistenceController.preview.container)
}
