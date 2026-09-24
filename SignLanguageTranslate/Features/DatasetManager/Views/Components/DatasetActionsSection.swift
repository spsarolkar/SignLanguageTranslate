import SwiftUI

/// The dataset card in the detail: name, meta line, state-dependent actions,
/// overall progress (complete solid, in-flight faded) and a mono summary line.
///
/// Delete, View in Files and Cancel live in the detail's toolbar menu.
struct DatasetActionsSection: View {
    let dataset: Dataset
    let summary: DatasetTransferSummary
    var timeRemaining: TimeInterval? = nil
    var isIngesting: Bool = false
    var ingestionProgress: String = ""

    var onStartDownload: () -> Void
    var onPauseDownload: () -> Void
    var onResumeDownload: () -> Void
    var onBrowseSamples: () -> Void
    var onIngestVideos: () -> Void

    @State private var contentWidth: CGFloat = 0

    var body: some View {
        Card(padding: Spacing.xxl, radius: Radius.panel) {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                if contentWidth < Metrics.cardSideBySideMinWidth {
                    VStack(alignment: .leading, spacing: Spacing.lg) {
                        titleBlock
                        buttons
                    }
                } else {
                    HStack(alignment: .top, spacing: Spacing.xl) {
                        titleBlock
                        Spacer(minLength: 0)
                        buttons
                            .fixedSize()
                    }
                }

                if dataset.downloadStatus == .processing {
                    processingRow
                } else {
                    progressBlock
                }

                if dataset.downloadStatus == .failed, let error = dataset.lastError {
                    errorRow(error)
                }

                if dataset.downloadStatus == .completed {
                    ingestionStatus
                }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { contentWidth = $0 }
        }
    }

    // MARK: - Title

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(dataset.name)
                .font(Typo.title)
                .foregroundStyle(Palette.textPrimary)
            Text(metaLine)
                .font(Typo.caption)
                .foregroundStyle(Palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// "Word-level · Zenodo record 4010759 · 15 categories · 44 parts".
    private var metaLine: String {
        var parts: [String] = []
        switch dataset.datasetType {
        case .include:
            parts = [
                "Word-level",
                "Zenodo record \(INCLUDEManifest.zenodoRecordID)",
                "\(INCLUDEManifest.categories.count) categories",
                "\(INCLUDEManifest.totalPartCount) parts",
            ]
        case .islcsltr:
            parts = ["Sentence-level", "\(dataset.totalParts) parts"]
        }
        if dataset.totalSamples > 0 {
            parts.append("\(dataset.totalSamples.formatted()) samples")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Buttons

    private var buttons: some View {
        HStack(spacing: Spacing.md) {
            switch dataset.downloadStatus {
            case .notStarted:
                PrimaryButton(title: "Download All", action: onStartDownload)
            case .downloading:
                SecondaryButton(title: "Pause All", action: onPauseDownload)
                PrimaryButton(title: "Download All") {}
                    .disabled(true)
            case .paused:
                PrimaryButton(title: "Resume All", action: onResumeDownload)
            case .failed:
                PrimaryButton(title: "Retry Download", action: onStartDownload)
            case .completed:
                SecondaryButton(title: "Ingest Videos", action: onIngestVideos)
                    .disabled(isIngesting)
                PrimaryButton(title: "Browse Samples", action: onBrowseSamples)
            case .processing:
                EmptyView()
            }
        }
    }

    // MARK: - Progress

    private var progressBlock: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            if summary.totalCount > 0 {
                ProgressBar(value: summary.completeFraction, inFlight: summary.inFlightFraction)
            } else {
                ProgressBar(value: dataset.downloadProgress)
            }
            ViewThatFits(in: .horizontal) {
                HStack {
                    countsText
                    Spacer(minLength: Spacing.md)
                    bytesText
                }
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    countsText
                    bytesText
                }
            }
            .font(Typo.monoCaption)
            .foregroundStyle(Palette.textTertiary)
        }
    }

    /// "19 complete · 3 active · 22 queued", or parts when no tasks exist.
    private var countsText: some View {
        let text: String
        if summary.totalCount > 0 {
            var parts = [
                "\(summary.completeCount) complete",
                "\(summary.activeCount) active",
                "\(summary.queuedCount) queued",
            ]
            if summary.failedCount > 0 {
                parts.append("\(summary.failedCount) failed")
            }
            text = parts.joined(separator: " · ")
        } else {
            text = "\(dataset.downloadedParts) of \(dataset.totalParts) parts"
        }
        return Text(text).lineLimit(1).fixedSize()
    }

    /// "184.2 GB of 428.6 GB", plus time left while downloading.
    private var bytesText: some View {
        var text = "\(FileManager.formattedSize(dataset.downloadedBytes)) of \(FileManager.formattedSize(dataset.totalBytes))"
        if dataset.downloadStatus == .downloading, let timeRemaining, let left = formatTime(timeRemaining) {
            text += " · \(left) left"
        }
        return Text(text).lineLimit(1).fixedSize()
    }

    private func formatTime(_ seconds: TimeInterval) -> String? {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        return formatter.string(from: seconds)
    }

    // MARK: - States

    private var processingRow: some View {
        HStack(spacing: Spacing.md) {
            ProgressView()
                .tint(Palette.accent)
            Text("Processing downloaded files…")
                .font(Typo.caption)
                .foregroundStyle(Palette.textSecondary)
        }
    }

    private func errorRow(_ error: String) -> some View {
        let shape = RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
        return HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Palette.danger)
                .accessibilityHidden(true)
            Text(error)
                .font(Typo.caption)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.dangerFill, in: shape)
        .overlay(shape.strokeBorder(StateTint.failed.border, lineWidth: Metrics.borderWidth))
    }

    @ViewBuilder
    private var ingestionStatus: some View {
        if isIngesting {
            HStack(spacing: Spacing.sm) {
                ProgressView()
                    .tint(Palette.accent)
                Text(ingestionProgress)
                    .font(Typo.caption)
                    .foregroundStyle(Palette.textSecondary)
            }
        } else if !ingestionProgress.isEmpty {
            Text(ingestionProgress)
                .font(Typo.caption)
                .foregroundStyle(ingestionProgress.contains("Failed") ? Palette.danger : Palette.accent)
        } else {
            Text(dataset.totalSamples == 0
                 ? "Videos are downloaded but not in the database yet. Ingest them to browse and train."
                 : "\(dataset.totalSamples.formatted()) samples in the database. Ingest again to rescan.")
                .font(Typo.caption)
                .foregroundStyle(Palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Previews

private func actionsPreview(_ dataset: Dataset, tasks: [DownloadTask] = []) -> some View {
    DatasetActionsSection(
        dataset: dataset,
        summary: DatasetTransferSummary(tasks: tasks),
        onStartDownload: {},
        onPauseDownload: {},
        onResumeDownload: {},
        onBrowseSamples: {},
        onIngestVideos: {}
    )
}

#Preview("Dataset card states") {
    ScrollView {
        VStack(spacing: Spacing.xl) {
            actionsPreview(.previewIncludeNotStarted)
            actionsPreview(.previewIncludeDownloading, tasks: [.previewCompleted, .previewDownloading, .previewPending])
            actionsPreview(.previewPaused)
            actionsPreview(.previewIncludeCompleted)
            actionsPreview(.previewFailed)
        }
        .padding(Spacing.pane)
    }
    .frame(width: 760)
    .background(Palette.ground)
    .preferredColorScheme(.dark)
}
