import SwiftUI

/// Statistics section showing dataset metrics in a card grid.
/// Displays total samples, categories/labels, storage used, and download date.
struct DatasetStatsSection: View {
    let dataset: Dataset
    var speed: Double = 0
    var timeRemaining: TimeInterval? = nil

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            // Total samples card
            StatCard(
                title: "Total Samples",
                value: formattedSamples,
                icon: "video.fill",
                color: .blue
            )

            // Categories/Parts card
            StatCard(
                title: dataset.datasetType.usesCategories ? "Categories" : "Parts",
                value: "\(dataset.totalParts)",
                icon: dataset.datasetType.usesCategories ? "folder.fill" : "doc.fill",
                color: .purple
            )

            // Storage card
            StatCard(
                title: "Total Size",
                value: dataset.formattedTotalSize,
                icon: "externaldrive.fill",
                color: .orange
            )

            // Downloaded/Progress card
            if dataset.downloadStatus == .completed {
                StatCard(
                    title: "Downloaded",
                    value: dataset.formattedDownloadedSize,
                    icon: "checkmark.circle.fill",
                    color: .green
                )
            } else if dataset.downloadStatus.isActive || dataset.downloadStatus == .paused {
                StatCard(
                    title: "Downloaded",
                    value: progressText,
                    icon: "arrow.down.circle.fill",
                    color: .blue
                )
            } else {
                StatCard(
                    title: "Estimated Size",
                    value: dataset.datasetType.estimatedSizeDescription,
                    icon: "info.circle.fill",
                    color: .secondary
                )
            }
        }
    }

    // MARK: - Computed Properties

    private var formattedSamples: String {
        if dataset.downloadStatus == .completed {
            return dataset.downloadedSamples.formatted()
        } else if dataset.downloadedSamples > 0 {
            return "\(dataset.downloadedSamples.formatted()) / \(dataset.totalSamples.formatted())"
        } else {
            return dataset.totalSamples.formatted()
        }
    }

    private var progressText: String {
        let percentage = Int(dataset.downloadProgress * 100)
        return "\(percentage)%"
    }
}

// MARK: - Stat Card

/// Individual statistic card component.
struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.callout)
                    .foregroundStyle(color)

                Spacer()
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }
}

// MARK: - Previews

#Preview("Stats - Not Started") {
    ScrollView {
        DatasetStatsSection(dataset: .previewIncludeNotStarted)
            .padding()
    }
    .background(Color(.systemGroupedBackground))
}

#Preview("Stats - Downloading") {
    ScrollView {
        DatasetStatsSection(dataset: .previewIncludeDownloading)
            .padding()
    }
    .background(Color(.systemGroupedBackground))
}

#Preview("Stats - Completed") {
    ScrollView {
        DatasetStatsSection(dataset: .previewIncludeCompleted)
            .padding()
    }
    .background(Color(.systemGroupedBackground))
}

#Preview("Stats - ISL-CSLTR") {
    ScrollView {
        DatasetStatsSection(dataset: .previewISLCSLTR)
            .padding()
    }
    .background(Color(.systemGroupedBackground))
}

#Preview("Stat Card") {
    VStack(spacing: 12) {
        StatCard(
            title: "Total Samples",
            value: "15,000",
            icon: "video.fill",
            color: .blue
        )
        StatCard(
            title: "Storage Used",
            value: "50.0 GB",
            icon: "externaldrive.fill",
            color: .orange
        )
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}
