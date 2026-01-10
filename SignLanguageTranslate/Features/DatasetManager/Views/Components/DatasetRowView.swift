import SwiftUI

/// Row view for displaying a dataset in a list.
///
/// Shows:
/// - Large icon based on DatasetType
/// - Dataset name (bold)
/// - Short description or sample count
/// - Status badge (color-coded)
/// - Progress indicator if downloading
/// - File size info
/// - Chevron for navigation
///
/// Supports:
/// - Context menus (right-click)
/// - Highlight state for selection
/// - Smooth animations for progress updates
/// - Accessibility labels
struct DatasetRowView: View {

    // MARK: - Properties

    let dataset: Dataset
    var onStartDownload: (() -> Void)?
    var onPauseDownload: (() -> Void)?
    var onCancelDownload: (() -> Void)?
    var onDeleteDataset: (() -> Void)?

    // MARK: - Body

    var body: some View {
        HStack(spacing: 12) {
            // Dataset icon
            DatasetIconView(type: dataset.datasetType, size: .medium)

            // Main content
            VStack(alignment: .leading, spacing: 4) {
                // Title row
                HStack {
                    Text(dataset.name)
                        .font(.headline)

                    Spacer()

                    DatasetStatusBadge(status: dataset.downloadStatus, mode: .full)
                }

                // Description
                Text(dataset.datasetType.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                // Progress or info row
                if dataset.downloadStatus == .downloading {
                    DatasetProgressIndicatorCompact(dataset: dataset)
                } else {
                    infoRow
                }
            }

            // Navigation chevron
            Image(systemName: "chevron.right")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .contextMenu { contextMenuContent }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
        .accessibilityHint("Double tap to view details")
    }

    // MARK: - Info Row

    private var infoRow: some View {
        HStack(spacing: 8) {
            // Sample count
            HStack(spacing: 4) {
                Image(systemName: "video.fill")
                Text(sampleCountText)
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Text("•")
                .foregroundStyle(.tertiary)

            // Size info
            HStack(spacing: 4) {
                Image(systemName: "internaldrive.fill")
                Text(sizeText)
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Spacer()
        }
    }

    // MARK: - Computed Properties

    private var sampleCountText: String {
        if dataset.downloadStatus == .completed {
            return "\(dataset.downloadedSamples.formatted()) samples"
        } else if dataset.totalSamples > 0 {
            return "\(dataset.totalSamples.formatted()) samples"
        } else {
            return "Unknown samples"
        }
    }

    private var sizeText: String {
        switch dataset.downloadStatus {
        case .completed:
            return dataset.formattedActualStorage
        case .downloading, .paused:
            return dataset.progressText
        case .notStarted, .failed, .processing:
            return dataset.formattedTotalSize
        }
    }

    private var accessibilityDescription: String {
        var description = "\(dataset.name) dataset, \(dataset.datasetType.displayName)"
        description += ", Status: \(dataset.downloadStatus.displayName)"

        if dataset.downloadStatus == .downloading {
            description += ", \(Int(dataset.downloadProgress * 100)) percent complete"
        } else if dataset.downloadStatus == .completed {
            description += ", \(dataset.downloadedSamples) samples"
        }

        return description
    }

    // MARK: - Context Menu

    @ViewBuilder
    private var contextMenuContent: some View {
        switch dataset.downloadStatus {
        case .notStarted, .failed:
            Button {
                onStartDownload?()
            } label: {
                SwiftUI.Label("Download", systemImage: "arrow.down.circle")
            }

        case .downloading:
            Button {
                onPauseDownload?()
            } label: {
                SwiftUI.Label("Pause", systemImage: "pause.circle")
            }

            Button(role: .destructive) {
                onCancelDownload?()
            } label: {
                SwiftUI.Label("Cancel", systemImage: "xmark.circle")
            }

        case .paused:
            Button {
                onStartDownload?()
            } label: {
                SwiftUI.Label("Resume", systemImage: "play.circle")
            }

            Button(role: .destructive) {
                onCancelDownload?()
            } label: {
                SwiftUI.Label("Cancel", systemImage: "xmark.circle")
            }

        case .completed:
            Button(role: .destructive) {
                onDeleteDataset?()
            } label: {
                SwiftUI.Label("Delete", systemImage: "trash")
            }

        case .processing:
            // No actions available during processing
            EmptyView()
        }

        Divider()

        Button {
            // Show in Finder action would go here
        } label: {
            SwiftUI.Label("Show in Finder", systemImage: "folder")
        }
        .disabled(!dataset.hasLocalStorage)
    }
}

// MARK: - Previews

#Preview("Not Started") {
    List {
        DatasetRowView(dataset: .previewIncludeNotStarted)
        DatasetRowView(dataset: .previewISLCSLTR)
    }
    .listStyle(.insetGrouped)
}

#Preview("Downloading") {
    List {
        DatasetRowView(dataset: .previewIncludeDownloading)
    }
    .listStyle(.insetGrouped)
}

#Preview("Completed") {
    List {
        DatasetRowView(dataset: .previewIncludeCompleted)
    }
    .listStyle(.insetGrouped)
}

#Preview("Paused") {
    List {
        DatasetRowView(dataset: .previewPaused)
    }
    .listStyle(.insetGrouped)
}

#Preview("Failed") {
    List {
        DatasetRowView(dataset: .previewFailed)
    }
    .listStyle(.insetGrouped)
}

#Preview("All States") {
    List {
        DatasetRowView(dataset: .previewIncludeNotStarted)
        DatasetRowView(dataset: .previewIncludeDownloading)
        DatasetRowView(dataset: .previewPaused)
        DatasetRowView(dataset: .previewIncludeCompleted)
        DatasetRowView(dataset: .previewFailed)
        DatasetRowView(dataset: .previewISLCSLTR)
    }
    .listStyle(.insetGrouped)
}

#Preview("With Actions") {
    List {
        DatasetRowView(
            dataset: .previewIncludeNotStarted,
            onStartDownload: { print("Start download") },
            onPauseDownload: { print("Pause download") },
            onCancelDownload: { print("Cancel download") },
            onDeleteDataset: { print("Delete dataset") }
        )
    }
    .listStyle(.insetGrouped)
}
