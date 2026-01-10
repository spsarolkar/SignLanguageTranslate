import SwiftUI

/// Header section for the dataset detail view.
/// Displays the dataset icon, name, description, status badge, and last updated date.
struct DatasetHeaderSection: View {
    let dataset: Dataset

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 16) {
                // Large dataset icon
                DatasetIconView(type: dataset.datasetType, size: .large)

                VStack(alignment: .leading, spacing: 6) {
                    // Dataset name
                    Text(dataset.datasetType.fullName)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    // Status badge
                    statusBadge
                }

                Spacer()
            }

            // Description
            Text(dataset.datasetType.description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            // Dates row
            datesRow
        }
        .padding(.vertical, 8)
    }

    // MARK: - Status Badge

    private var statusBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: dataset.downloadStatus.iconName)
            Text(dataset.downloadStatus.displayName)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(dataset.downloadStatus.color)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(dataset.downloadStatus.color.opacity(0.15))
        )
    }

    // MARK: - Dates Row

    private var datesRow: some View {
        HStack(spacing: 16) {
            if let completedAt = dataset.downloadCompletedAt {
                dateLabel(
                    title: "Downloaded",
                    date: completedAt,
                    icon: "checkmark.circle"
                )
            } else if let startedAt = dataset.downloadStartedAt {
                dateLabel(
                    title: "Started",
                    date: startedAt,
                    icon: "arrow.down.circle"
                )
            }

            dateLabel(
                title: "Added",
                date: dataset.createdAt,
                icon: "calendar"
            )

            Spacer()
        }
    }

    private func dateLabel(title: String, date: Date, icon: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                Text(date, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Previews

#Preview("Header - Not Started") {
    List {
        Section {
            DatasetHeaderSection(dataset: .previewIncludeNotStarted)
        }
    }
    .listStyle(.insetGrouped)
}

#Preview("Header - Downloading") {
    List {
        Section {
            DatasetHeaderSection(dataset: .previewIncludeDownloading)
        }
    }
    .listStyle(.insetGrouped)
}

#Preview("Header - Completed") {
    List {
        Section {
            DatasetHeaderSection(dataset: .previewIncludeCompleted)
        }
    }
    .listStyle(.insetGrouped)
}

#Preview("Header - Failed") {
    List {
        Section {
            DatasetHeaderSection(dataset: .previewFailed)
        }
    }
    .listStyle(.insetGrouped)
}

#Preview("Header - ISL-CSLTR") {
    List {
        Section {
            DatasetHeaderSection(dataset: .previewISLCSLTR)
        }
    }
    .listStyle(.insetGrouped)
}
