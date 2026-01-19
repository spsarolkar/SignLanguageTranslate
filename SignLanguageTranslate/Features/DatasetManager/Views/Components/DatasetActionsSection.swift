import SwiftUI

/// Action buttons section for dataset management.
/// Shows context-appropriate actions based on dataset status.
struct DatasetActionsSection: View {
    let dataset: Dataset
    var currentSpeed: Double = 0
    var timeRemaining: TimeInterval? = nil

    var onStartDownload: () -> Void
    var onPauseDownload: () -> Void
    var onResumeDownload: () -> Void
    var onCancelDownload: () -> Void
    var onBrowseSamples: () -> Void
    var onViewInFiles: () -> Void
    var onDeleteDataset: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            // Primary action
            primaryActionButton

            // Download progress (if active)
            if dataset.downloadStatus.isActive || dataset.downloadStatus == .paused {
                downloadProgressView
            }

            // Error message (if failed)
            if dataset.downloadStatus == .failed, let error = dataset.lastError {
                errorMessageView(error)
            }

            // Secondary actions
            secondaryActionsRow
        }
    }

    // MARK: - Primary Action Button

    @ViewBuilder
    private var primaryActionButton: some View {
        switch dataset.downloadStatus {
        case .notStarted:
            ActionButton(
                title: "Download Dataset",
                icon: "arrow.down.circle.fill",
                style: .primary,
                action: onStartDownload
            )

        case .downloading:
            ActionButton(
                title: "Pause Download",
                icon: "pause.circle.fill",
                style: .secondary,
                action: onPauseDownload
            )

        case .paused:
            ActionButton(
                title: "Resume Download",
                icon: "play.circle.fill",
                style: .primary,
                action: onResumeDownload
            )

        case .failed:
            ActionButton(
                title: "Retry Download",
                icon: "arrow.clockwise.circle.fill",
                style: .primary,
                action: onStartDownload
            )

        case .completed:
            ActionButton(
                title: "Browse Samples",
                icon: "play.rectangle.fill",
                style: .primary,
                action: onBrowseSamples
            )

        case .processing:
            HStack(spacing: 12) {
                ProgressView()
                    .progressViewStyle(.circular)

                Text("Processing downloaded files...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer()
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
        }
    }

    // MARK: - Download Progress View

    private var downloadProgressView: some View {
        VStack(alignment: .leading, spacing: 8) {
            ProgressView(value: dataset.downloadProgress)
                .progressViewStyle(.linear)
                .tint(dataset.downloadStatus == .paused ? .orange : .blue)

            HStack {
                Text("\(Int(dataset.downloadProgress * 100))%")
                    .font(.caption.monospacedDigit().weight(.medium))
                    .foregroundStyle(dataset.downloadStatus == .paused ? .orange : .blue)

                Spacer()

                if dataset.downloadStatus.isActive && currentSpeed > 0 {
                    HStack(spacing: 4) {
                        Text(formatSpeed(currentSpeed))
                        if let time = timeRemaining {
                            Text("•")
                            Text(formatTime(time))
                        }
                    }
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                } else {
                    Text(dataset.progressText)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Text("\(dataset.downloadedParts) of \(dataset.totalParts) files")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                if dataset.downloadStatus == .downloading {
                    Button("Cancel", role: .destructive) {
                        onCancelDownload()
                    }
                    .font(.caption)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private func formatSpeed(_ bytesPerSec: Double) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useKB]
        formatter.countStyle = .file
        return "\(formatter.string(fromByteCount: Int64(bytesPerSec)))/s"
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        return formatter.string(from: seconds) ?? ""
    }

    // MARK: - Error Message View

    private func errorMessageView(_ error: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)

            Text(error)
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.red.opacity(0.1))
        )
    }

    // MARK: - Secondary Actions Row

    @ViewBuilder
    private var secondaryActionsRow: some View {
        HStack(spacing: 12) {
            if dataset.hasLocalStorage {
                SecondaryActionButton(
                    title: "View in Files",
                    icon: "folder",
                    action: onViewInFiles
                )
            }

            if dataset.downloadStatus == .completed || dataset.hasLocalStorage {
                SecondaryActionButton(
                    title: "Delete",
                    icon: "trash",
                    isDestructive: true,
                    action: onDeleteDataset
                )
            }
        }
    }
}

// MARK: - Action Button

/// Primary action button with full width.
struct ActionButton: View {
    let title: String
    let icon: String
    let style: ActionButtonStyle
    let action: () -> Void

    enum ActionButtonStyle {
        case primary
        case secondary
        case destructive

        var foregroundColor: Color {
            switch self {
            case .primary: return .white
            case .secondary: return .accentColor
            case .destructive: return .white
            }
        }

        var backgroundColor: Color {
            switch self {
            case .primary: return .accentColor
            case .secondary: return .accentColor.opacity(0.15)
            case .destructive: return .red
            }
        }
    }

    var body: some View {
        Button(action: action) {
            SwiftUI.Label(title, systemImage: icon)
                .font(.body.weight(.semibold))
                .foregroundStyle(style.foregroundColor)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(style.backgroundColor)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Secondary Action Button

/// Smaller secondary action button.
struct SecondaryActionButton: View {
    let title: String
    let icon: String
    var isDestructive: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            SwiftUI.Label(title, systemImage: icon)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(isDestructive ? .red : .accentColor)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(
                            isDestructive
                                ? Color.red.opacity(0.1)
                                : Color.accentColor.opacity(0.1)
                        )
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Previews

#Preview("Actions - Not Started") {
    ScrollView {
        DatasetActionsSection(
            dataset: .previewIncludeNotStarted,
            onStartDownload: {},
            onPauseDownload: {},
            onResumeDownload: {},
            onCancelDownload: {},
            onBrowseSamples: {},
            onViewInFiles: {},
            onDeleteDataset: {}
        )
        .padding()
    }
    .background(Color(.systemGroupedBackground))
}

#Preview("Actions - Downloading") {
    ScrollView {
        DatasetActionsSection(
            dataset: .previewIncludeDownloading,
            onStartDownload: {},
            onPauseDownload: {},
            onResumeDownload: {},
            onCancelDownload: {},
            onBrowseSamples: {},
            onViewInFiles: {},
            onDeleteDataset: {}
        )
        .padding()
    }
    .background(Color(.systemGroupedBackground))
}

#Preview("Actions - Paused") {
    ScrollView {
        DatasetActionsSection(
            dataset: .previewPaused,
            onStartDownload: {},
            onPauseDownload: {},
            onResumeDownload: {},
            onCancelDownload: {},
            onBrowseSamples: {},
            onViewInFiles: {},
            onDeleteDataset: {}
        )
        .padding()
    }
    .background(Color(.systemGroupedBackground))
}

#Preview("Actions - Completed") {
    ScrollView {
        DatasetActionsSection(
            dataset: .previewIncludeCompleted,
            onStartDownload: {},
            onPauseDownload: {},
            onResumeDownload: {},
            onCancelDownload: {},
            onBrowseSamples: {},
            onViewInFiles: {},
            onDeleteDataset: {}
        )
        .padding()
    }
    .background(Color(.systemGroupedBackground))
}

#Preview("Actions - Failed") {
    ScrollView {
        DatasetActionsSection(
            dataset: .previewFailed,
            onStartDownload: {},
            onPauseDownload: {},
            onResumeDownload: {},
            onCancelDownload: {},
            onBrowseSamples: {},
            onViewInFiles: {},
            onDeleteDataset: {}
        )
        .padding()
    }
    .background(Color(.systemGroupedBackground))
}

#Preview("Action Button Styles") {
    VStack(spacing: 12) {
        ActionButton(
            title: "Primary Action",
            icon: "arrow.down.circle.fill",
            style: .primary,
            action: {}
        )

        ActionButton(
            title: "Secondary Action",
            icon: "pause.circle.fill",
            style: .secondary,
            action: {}
        )

        ActionButton(
            title: "Destructive Action",
            icon: "trash.fill",
            style: .destructive,
            action: {}
        )
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}
