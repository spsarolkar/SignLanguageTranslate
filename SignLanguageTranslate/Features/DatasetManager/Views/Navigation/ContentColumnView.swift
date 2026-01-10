import SwiftUI
import SwiftData

/// Content column that displays different views based on the selected navigation section.
struct ContentColumnView: View {
    let selectedSection: NavigationSection?
    @Binding var selectedDataset: Dataset?

    var body: some View {
        Group {
            switch selectedSection {
            case .datasets:
                DatasetListView(selectedDataset: $selectedDataset)
            case .downloads:
                DownloadListView()
            case .training:
                TrainingPlaceholderView()
            case .settings:
                SettingsPlaceholderView()
            case nil:
                ContentUnavailableView(
                    "No Section Selected",
                    systemImage: "sidebar.left",
                    description: Text("Select a section from the sidebar")
                )
            }
        }
    }
}

// MARK: - Download List View

/// Displays the list of active and completed downloads.
struct DownloadListView: View {
    @Environment(DownloadManager.self) private var downloadManager

    var body: some View {
        Group {
            if downloadManager.totalCount == 0 {
                ContentUnavailableView(
                    "No Downloads",
                    systemImage: "arrow.down.circle",
                    description: Text("Start downloading a dataset to see progress here")
                )
            } else {
                List {
                    if !downloadManager.taskGroups.isEmpty {
                        ForEach(downloadManager.taskGroups) { group in
                            DownloadGroupRow(group: group)
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Downloads")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if downloadManager.isDownloading {
                    Button {
                        Task {
                            await downloadManager.pauseAll()
                        }
                    } label: {
                        Image(systemName: "pause.fill")
                    }
                } else if downloadManager.pendingCount > 0 || downloadManager.tasks.contains(where: { $0.status == .paused }) {
                    Button {
                        Task {
                            await downloadManager.resumeAll()
                        }
                    } label: {
                        Image(systemName: "play.fill")
                    }
                }
            }
        }
    }
}

// MARK: - Download Group Row

/// Row displaying a download task group.
struct DownloadGroupRow: View {
    let group: DownloadTaskGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(group.category)
                    .font(.headline)

                Spacer()

                Text(group.statusSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: group.totalProgress)
                .progressViewStyle(.linear)

            HStack {
                Text(group.progressText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                statusBadge
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var statusBadge: some View {
        if group.anyFailed {
            SwiftUI.Label("\(group.failedCount) failed", systemImage: "exclamationmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.red)
        } else if group.anyActive {
            SwiftUI.Label("Downloading", systemImage: "arrow.down.circle.fill")
                .font(.caption)
                .foregroundStyle(.blue)
        } else if group.allCompleted {
            SwiftUI.Label("Completed", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        }
    }
}

// MARK: - Placeholder Views

/// Placeholder view for the Training section.
struct TrainingPlaceholderView: View {
    var body: some View {
        ContentUnavailableView(
            "Training",
            systemImage: "brain.head.profile",
            description: Text("Train sign language recognition models using your datasets. Coming soon.")
        )
        .navigationTitle("Training")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

/// Placeholder view for the Settings section.
struct SettingsPlaceholderView: View {
    var body: some View {
        ContentUnavailableView(
            "Settings",
            systemImage: "gearshape.fill",
            description: Text("Configure app preferences and manage storage. Coming soon.")
        )
        .navigationTitle("Settings")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

// MARK: - Previews

#Preview("Content - Datasets") {
    NavigationStack {
        ContentColumnView(
            selectedSection: .datasets,
            selectedDataset: .constant(nil)
        )
    }
    .modelContainer(PersistenceController.preview.container)
    .environment(DownloadManager())
}

#Preview("Content - Downloads Empty") {
    NavigationStack {
        ContentColumnView(
            selectedSection: .downloads,
            selectedDataset: .constant(nil)
        )
    }
    .modelContainer(PersistenceController.preview.container)
    .environment(DownloadManager())
}

#Preview("Content - Training") {
    NavigationStack {
        ContentColumnView(
            selectedSection: .training,
            selectedDataset: .constant(nil)
        )
    }
    .modelContainer(PersistenceController.preview.container)
    .environment(DownloadManager())
}

#Preview("Content - Settings") {
    NavigationStack {
        ContentColumnView(
            selectedSection: .settings,
            selectedDataset: .constant(nil)
        )
    }
    .modelContainer(PersistenceController.preview.container)
    .environment(DownloadManager())
}
