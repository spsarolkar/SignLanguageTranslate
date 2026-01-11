import SwiftUI

/// Sheet wrapper for presenting the download list as a modal.
///
/// Features:
/// - NavigationStack with Done button
/// - Presentation detents (.medium and .large)
/// - Drag indicator for easy dismissal
/// - Passes through environment values
///
/// Use this view when presenting downloads as a sheet from another view,
/// such as after starting a download or from a toolbar button.
struct DownloadSheet: View {

    // MARK: - Environment

    @Environment(\.dismiss) private var dismiss
    @Environment(DownloadManager.self) private var downloadManager

    // MARK: - Body

    var body: some View {
        NavigationStack {
            DownloadListView()
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            dismiss()
                        }
                    }
                }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
    }
}

// MARK: - Download Mini View

/// A compact download indicator for use in toolbars or navigation bars.
///
/// Shows:
/// - Mini progress ring when downloads are active
/// - Checkmark when all complete
/// - Number badge for failed downloads
///
/// Tap to present the full download sheet.
struct DownloadMiniIndicator: View {

    // MARK: - Environment

    @Environment(DownloadManager.self) private var downloadManager

    // MARK: - State

    @State private var showDownloadSheet = false

    // MARK: - Body

    var body: some View {
        Button {
            showDownloadSheet = true
        } label: {
            indicatorContent
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showDownloadSheet) {
            DownloadSheet()
        }
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Double tap to view all downloads")
    }

    // MARK: - Indicator Content

    @ViewBuilder
    private var indicatorContent: some View {
        if downloadManager.totalCount == 0 {
            // No downloads
            Image(systemName: "arrow.down.circle")
                .font(.body)
                .foregroundStyle(.secondary)
        } else if downloadManager.isComplete {
            // All complete
            Image(systemName: "checkmark.circle.fill")
                .font(.body)
                .foregroundStyle(.green)
        } else if downloadManager.isDownloading {
            // Active downloads
            ZStack {
                Circle()
                    .stroke(Color.blue.opacity(0.2), lineWidth: 2)

                Circle()
                    .trim(from: 0, to: CGFloat(downloadManager.overallProgress))
                    .stroke(Color.blue, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))

                Text("\(downloadManager.activeCount)")
                    .font(.caption2.monospacedDigit().bold())
                    .foregroundStyle(.blue)
            }
            .frame(width: 24, height: 24)
        } else if downloadManager.hasFailed {
            // Has failures
            ZStack {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.body)
                    .foregroundStyle(.red)

                // Badge for count
                if downloadManager.failedCount > 1 {
                    Text("\(downloadManager.failedCount)")
                        .font(.system(size: 8).bold())
                        .foregroundStyle(.white)
                        .padding(2)
                        .background(Circle().fill(.red))
                        .offset(x: 8, y: -8)
                }
            }
        } else if downloadManager.isPaused {
            // Paused
            Image(systemName: "pause.circle.fill")
                .font(.body)
                .foregroundStyle(.yellow)
        } else {
            // Pending
            ZStack {
                Image(systemName: "arrow.down.circle")
                    .font(.body)
                    .foregroundStyle(.secondary)

                if downloadManager.pendingCount > 0 {
                    Text("\(downloadManager.pendingCount)")
                        .font(.system(size: 8).bold())
                        .foregroundStyle(.white)
                        .padding(2)
                        .background(Circle().fill(.gray))
                        .offset(x: 8, y: -8)
                }
            }
        }
    }

    // MARK: - Accessibility

    private var accessibilityLabel: String {
        if downloadManager.totalCount == 0 {
            return "No downloads"
        } else if downloadManager.isComplete {
            return "All downloads complete"
        } else if downloadManager.isDownloading {
            return "Downloading \(downloadManager.activeCount) of \(downloadManager.totalCount), \(downloadManager.progressPercentage) percent"
        } else if downloadManager.hasFailed {
            return "\(downloadManager.failedCount) downloads failed"
        } else if downloadManager.isPaused {
            return "Downloads paused"
        } else {
            return "\(downloadManager.pendingCount) downloads pending"
        }
    }
}

// MARK: - Download Toolbar Button

/// A toolbar button that shows download status and presents the download sheet.
///
/// This is a convenience view for adding download management to any toolbar.
struct DownloadToolbarButton: View {

    // MARK: - Environment

    @Environment(DownloadManager.self) private var downloadManager

    // MARK: - State

    @State private var showDownloadSheet = false

    // MARK: - Body

    var body: some View {
        Button {
            showDownloadSheet = true
        } label: {
            SwiftUI.Label("Downloads", systemImage: toolbarIcon)
        }
        .badge(badgeCount)
        .sheet(isPresented: $showDownloadSheet) {
            DownloadSheet()
        }
    }

    // MARK: - Computed Properties

    private var toolbarIcon: String {
        if downloadManager.isComplete {
            return "checkmark.circle.fill"
        } else if downloadManager.isDownloading {
            return "arrow.down.circle.fill"
        } else if downloadManager.hasFailed {
            return "exclamationmark.circle.fill"
        } else if downloadManager.isPaused {
            return "pause.circle.fill"
        } else {
            return "arrow.down.circle"
        }
    }

    private var badgeCount: Int {
        if downloadManager.isDownloading {
            return downloadManager.activeCount
        } else if downloadManager.hasFailed {
            return downloadManager.failedCount
        } else {
            return 0
        }
    }
}

// MARK: - Previews

#Preview("Download Sheet") {
    DownloadSheet()
        .environment(DownloadManager())
}

#Preview("Mini Indicator - No Downloads") {
    DownloadMiniIndicator()
        .environment(DownloadManager())
        .padding()
}

#Preview("Mini Indicator States") {
    VStack(spacing: 20) {
        // Note: These would need actual manager state to show different states
        DownloadMiniIndicator()
    }
    .environment(DownloadManager())
    .padding()
}

#Preview("Toolbar Button") {
    NavigationStack {
        Text("Content")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    DownloadToolbarButton()
                }
            }
    }
    .environment(DownloadManager())
}
