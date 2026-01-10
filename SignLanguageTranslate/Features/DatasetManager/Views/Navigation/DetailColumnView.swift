import SwiftUI
import SwiftData

/// Detail column that displays content based on the current selection.
struct DetailColumnView: View {
    let selectedSection: NavigationSection?
    let selectedDataset: Dataset?

    var body: some View {
        Group {
            switch selectedSection {
            case .datasets:
                datasetDetail
            case .downloads:
                DownloadDetailView()
            case .training:
                TrainingDetailPlaceholder()
            case .settings:
                SettingsDetailPlaceholder()
            case nil:
                EmptyDetailView()
            }
        }
    }

    @ViewBuilder
    private var datasetDetail: some View {
        if let dataset = selectedDataset {
            DatasetDetailView(dataset: dataset)
        } else {
            EmptyDetailView(
                title: "Select a Dataset",
                systemImage: "folder.fill",
                description: "Choose a dataset from the list to view its contents and manage downloads."
            )
        }
    }
}

// MARK: - Dataset Detail View

/// Detailed view of a selected dataset.
struct DatasetDetailView: View {
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
            // Dataset Info Section
            Section {
                datasetInfoCard
            }

            // Download Progress Section
            if dataset.downloadStatus.isActive || dataset.downloadStatus == .paused {
                Section("Download Progress") {
                    downloadProgressView
                }
            }

            // Storage Section
            Section("Storage") {
                storageInfoView
            }

            // Actions Section
            Section {
                actionButtons
            }

            // Samples Section
            if !samples.isEmpty {
                Section("Samples (\(samples.count))") {
                    samplesListView
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(dataset.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
    }

    // MARK: - Dataset Info Card

    private var datasetInfoCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 16) {
                Image(systemName: dataset.datasetType.iconName)
                    .font(.largeTitle)
                    .foregroundStyle(dataset.datasetType.color)
                    .frame(width: 60, height: 60)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(dataset.datasetType.color.opacity(0.15))
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(dataset.datasetType.displayName)
                        .font(.headline)

                    Text(dataset.datasetType.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    statusBadge
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var statusBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: dataset.downloadStatus.iconName)
            Text(dataset.downloadStatus.displayName)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(statusColor)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(statusColor.opacity(0.15))
        )
    }

    private var statusColor: Color {
        switch dataset.downloadStatus {
        case .completed: return .green
        case .downloading: return .blue
        case .paused: return .orange
        case .failed: return .red
        case .processing: return .purple
        case .notStarted: return .secondary
        }
    }

    // MARK: - Download Progress

    private var downloadProgressView: some View {
        VStack(alignment: .leading, spacing: 8) {
            ProgressView(value: dataset.downloadProgress)
                .progressViewStyle(.linear)

            HStack {
                Text("\(Int(dataset.downloadProgress * 100))%")
                    .font(.caption.monospacedDigit())

                Spacer()

                Text("\(dataset.formattedDownloadedSize) / \(dataset.formattedTotalSize)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Storage Info

    private var storageInfoView: some View {
        Group {
            LabeledContent("Total Size", value: dataset.formattedTotalSize)
            LabeledContent("Downloaded", value: dataset.formattedDownloadedSize)
            LabeledContent("Parts", value: dataset.partsProgressText)

            if dataset.downloadStatus == .completed {
                LabeledContent("Samples", value: "\(samples.count)")
            }
        }
    }

    // MARK: - Action Buttons

    @ViewBuilder
    private var actionButtons: some View {
        switch dataset.downloadStatus {
        case .notStarted:
            Button {
                // Start download action
            } label: {
                SwiftUI.Label("Start Download", systemImage: "arrow.down.circle.fill")
            }

        case .downloading:
            Button {
                // Pause download action
            } label: {
                SwiftUI.Label("Pause Download", systemImage: "pause.circle.fill")
            }

        case .paused:
            Button {
                // Resume download action
            } label: {
                SwiftUI.Label("Resume Download", systemImage: "play.circle.fill")
            }

        case .failed:
            Button {
                // Retry download action
            } label: {
                SwiftUI.Label("Retry Download", systemImage: "arrow.clockwise.circle.fill")
            }

            if let error = dataset.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

        case .completed:
            Button(role: .destructive) {
                // Delete dataset action
            } label: {
                SwiftUI.Label("Delete Dataset", systemImage: "trash.fill")
            }

        case .processing:
            HStack {
                ProgressView()
                    .padding(.trailing, 8)
                Text("Processing downloaded files...")
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Samples List

    private var samplesListView: some View {
        Group {
            ForEach(samples.prefix(20)) { sample in
                SampleRowView(sample: sample)
            }

            if samples.count > 20 {
                Text("And \(samples.count - 20) more...")
                    .foregroundStyle(.secondary)
                    .italic()
            }
        }
    }
}

// MARK: - Sample Row View

/// Row displaying a video sample.
struct SampleRowView: View {
    let sample: VideoSample

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(sample.displayTitle)
                .font(.subheadline.weight(.medium))

            Text(sample.localPath)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if !sample.labels.isEmpty {
                labelBadges
            }
        }
        .padding(.vertical, 4)
    }

    private var labelBadges: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(sample.labels) { label in
                    Text(label.name)
                        .font(.caption2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(Color(label.type.colorName).opacity(0.2))
                        )
                        .foregroundStyle(Color(label.type.colorName))
                }
            }
        }
    }
}

// MARK: - Download Detail View

/// Detail view for the Downloads section.
struct DownloadDetailView: View {
    @Environment(DownloadManager.self) private var downloadManager

    var body: some View {
        if downloadManager.totalCount == 0 {
            EmptyDetailView(
                title: "No Active Downloads",
                systemImage: "arrow.down.circle",
                description: "Start downloading a dataset to track progress here."
            )
        } else {
            List {
                Section("Overview") {
                    LabeledContent("Total Tasks", value: "\(downloadManager.totalCount)")
                    LabeledContent("Active", value: "\(downloadManager.activeCount)")
                    LabeledContent("Completed", value: "\(downloadManager.completedCount)")
                    LabeledContent("Failed", value: "\(downloadManager.failedCount)")
                    LabeledContent("Pending", value: "\(downloadManager.pendingCount)")
                }

                Section("Progress") {
                    VStack(alignment: .leading, spacing: 8) {
                        ProgressView(value: downloadManager.overallProgress)
                            .progressViewStyle(.linear)

                        HStack {
                            Text("\(downloadManager.progressPercentage)%")
                                .font(.caption.monospacedDigit())

                            Spacer()

                            Text(downloadManager.bytesProgressText)
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if downloadManager.failedCount > 0 {
                    Section {
                        Button {
                            Task {
                                await downloadManager.retryFailed()
                            }
                        } label: {
                            SwiftUI.Label("Retry Failed Downloads", systemImage: "arrow.clockwise")
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Downloads")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            #endif
        }
    }
}

// MARK: - Placeholder Detail Views

/// Placeholder detail view for Training section.
struct TrainingDetailPlaceholder: View {
    var body: some View {
        EmptyDetailView(
            title: "Training Models",
            systemImage: "brain.head.profile",
            description: "Select a training configuration to view details and start training."
        )
    }
}

/// Placeholder detail view for Settings section.
struct SettingsDetailPlaceholder: View {
    var body: some View {
        EmptyDetailView(
            title: "Settings",
            systemImage: "gearshape.fill",
            description: "Select a setting category to configure."
        )
    }
}

// MARK: - Previews

#Preview("Detail - Dataset Selected") {
    NavigationStack {
        DetailColumnView(
            selectedSection: .datasets,
            selectedDataset: Dataset.previewIncludeDownloading
        )
    }
    .modelContainer(PersistenceController.preview.container)
    .environment(DownloadManager())
}

#Preview("Detail - No Dataset Selected") {
    NavigationStack {
        DetailColumnView(
            selectedSection: .datasets,
            selectedDataset: nil
        )
    }
    .modelContainer(PersistenceController.preview.container)
    .environment(DownloadManager())
}

#Preview("Detail - Downloads") {
    NavigationStack {
        DetailColumnView(
            selectedSection: .downloads,
            selectedDataset: nil
        )
    }
    .modelContainer(PersistenceController.preview.container)
    .environment(DownloadManager())
}

#Preview("Detail - Training") {
    NavigationStack {
        DetailColumnView(
            selectedSection: .training,
            selectedDataset: nil
        )
    }
    .modelContainer(PersistenceController.preview.container)
    .environment(DownloadManager())
}
