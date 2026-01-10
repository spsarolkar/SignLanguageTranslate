import SwiftUI
import SwiftData
#if os(iOS)
import UIKit
#endif

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
/// Uses section components for a modular, organized layout.
struct DatasetDetailView: View {
    @Bindable var dataset: Dataset
    @Environment(\.modelContext) private var modelContext

    @State private var showDeleteConfirmation = false
    @State private var showFilesApp = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header with icon, name, status
                DatasetHeaderSection(dataset: dataset)

                // Statistics cards
                DatasetStatsSection(dataset: dataset)

                // Actions (Download, Browse, Delete)
                DatasetActionsSection(
                    dataset: dataset,
                    onStartDownload: startDownload,
                    onPauseDownload: pauseDownload,
                    onResumeDownload: resumeDownload,
                    onCancelDownload: cancelDownload,
                    onBrowseSamples: browseSamples,
                    onViewInFiles: viewInFiles,
                    onDeleteDataset: { showDeleteConfirmation = true }
                )

                // Categories list (if downloaded)
                if dataset.isReady {
                    DatasetCategoriesSection(
                        dataset: dataset,
                        onCategorySelected: browseCategory
                    )
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(dataset.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        .toolbar {
            toolbarContent
        }
        .confirmationDialog(
            "Delete Dataset",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                deleteDataset()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete \"\(dataset.name)\"? This will remove all downloaded files and cannot be undone.")
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                if dataset.hasLocalStorage {
                    Button {
                        viewInFiles()
                    } label: {
                        SwiftUI.Label("View in Files", systemImage: "folder")
                    }
                }

                if dataset.downloadStatus == .completed {
                    Divider()

                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        SwiftUI.Label("Delete Dataset", systemImage: "trash")
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }

    // MARK: - Actions

    private func startDownload() {
        dataset.startDownload()
    }

    private func pauseDownload() {
        dataset.pauseDownload()
    }

    private func resumeDownload() {
        dataset.startDownload()
    }

    private func cancelDownload() {
        dataset.pauseDownload()
        dataset.downloadedBytes = 0
        dataset.downloadedParts = 0
        dataset.statusRawValue = DownloadStatus.notStarted.rawValue
    }

    private func browseSamples() {
        // Navigate to samples browser (to be implemented)
    }

    private func browseCategory(_ label: Label) {
        // Navigate to category browser (to be implemented)
    }

    private func viewInFiles() {
        #if os(iOS)
        // Open the Files app to the dataset directory
        let url = dataset.storageDirectory
        if FileManager.default.fileExists(atPath: url.path) {
            UIApplication.shared.open(url)
        }
        #endif
    }

    private func deleteDataset() {
        // Delete local files
        if dataset.hasLocalStorage {
            try? FileManager.default.removeItem(at: dataset.storageDirectory)
        }

        // Reset dataset to not started state
        dataset.statusRawValue = DownloadStatus.notStarted.rawValue
        dataset.downloadedBytes = 0
        dataset.downloadedParts = 0
        dataset.downloadedSamples = 0
        dataset.downloadStartedAt = nil
        dataset.downloadCompletedAt = nil
        dataset.lastError = nil
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

#Preview("Detail - Not Started") {
    NavigationStack {
        DatasetDetailView(dataset: .previewIncludeNotStarted)
    }
    .modelContainer(PersistenceController.preview.container)
    .environment(DownloadManager())
}

#Preview("Detail - Downloading") {
    NavigationStack {
        DatasetDetailView(dataset: .previewIncludeDownloading)
    }
    .modelContainer(PersistenceController.preview.container)
    .environment(DownloadManager())
}

#Preview("Detail - Completed") {
    NavigationStack {
        DatasetDetailView(dataset: .previewIncludeCompleted)
    }
    .modelContainer(PersistenceController.preview.container)
    .environment(DownloadManager())
}

#Preview("Detail - Paused") {
    NavigationStack {
        DatasetDetailView(dataset: .previewPaused)
    }
    .modelContainer(PersistenceController.preview.container)
    .environment(DownloadManager())
}

#Preview("Detail - Failed") {
    NavigationStack {
        DatasetDetailView(dataset: .previewFailed)
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
