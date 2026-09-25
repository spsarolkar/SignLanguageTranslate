import SwiftUI

/// One download task as a `TransferRow`: filename, category and status,
/// progress bar, mono size and rate, and a pause / resume / retry button.
///
/// Shared by the inline Active Transfers section of the dataset detail and
/// the full Downloads list.
///
/// Supports:
/// - Context menus
/// - Swipe actions (leading: prioritize, trailing: cancel) inside a List
/// - VoiceOver labels and actions
struct DownloadTaskRowView: View {

    // MARK: - Properties

    let task: DownloadTask
    let onPause: () -> Void
    let onResume: () -> Void
    let onCancel: () -> Void
    let onRetry: () -> Void
    let onPrioritize: () -> Void
    var onCopyURL: (() -> Void)?
    var onShowInFinder: (() -> Void)?

    // MARK: - Initialization

    init(
        task: DownloadTask,
        onPause: @escaping () -> Void,
        onResume: @escaping () -> Void,
        onCancel: @escaping () -> Void,
        onRetry: @escaping () -> Void,
        onPrioritize: @escaping () -> Void,
        onCopyURL: (() -> Void)? = nil,
        onShowInFinder: (() -> Void)? = nil
    ) {
        self.task = task
        self.onPause = onPause
        self.onResume = onResume
        self.onCancel = onCancel
        self.onRetry = onRetry
        self.onPrioritize = onPrioritize
        self.onCopyURL = onCopyURL
        self.onShowInFinder = onShowInFinder
    }

    // MARK: - Body

    var body: some View {
        TransferRow(
            title: task.filename,
            subtitle: subtitle,
            subtitleTint: subtitleTint,
            progress: task.progress,
            tint: state.color,
            value: valueText
        ) {
            IconButton(
                systemImage: actionIcon,
                accessibilityLabel: actionLabel,
                tint: task.status == .failed ? Palette.danger : Palette.textSecondary,
                action: handleAction
            )
            .disabled(task.status == .completed || task.status == .extracting)
        }
        .contentShape(Rectangle())
        .contextMenu { contextMenuContent }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            leadingSwipeActions
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            trailingSwipeActions
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
        .accessibilityHint(accessibilityHint)
        .accessibilityActions {
            accessibilityActionsContent
        }
    }

    // MARK: - Presentation

    private var state: StateTint {
        switch task.status {
        case .downloading, .extracting: return .active
        case .completed: return .complete
        case .pending, .queued, .paused: return .queued
        case .failed: return .failed
        }
    }

    private var subtitle: String {
        switch task.status {
        case .downloading:
            return task.category
        case .failed:
            return "\(task.category) · \(task.errorMessage ?? task.status.displayName)"
        default:
            return "\(task.category) · \(task.status.displayName)"
        }
    }

    private var subtitleTint: Color {
        switch task.status {
        case .failed: return Palette.danger
        case .paused: return Palette.warning
        default: return Palette.textTertiary
        }
    }

    private var valueText: String {
        if task.status == .downloading && task.downloadSpeed > 0 {
            return "\(task.progressText) · \(formatSpeed(task.downloadSpeed))"
        }
        return task.progressText
    }

    private var actionIcon: String {
        switch task.status {
        case .pending, .queued, .paused: return "play.fill"
        case .downloading: return "pause"
        case .failed: return "arrow.clockwise"
        case .completed: return "checkmark"
        case .extracting: return "gearshape"
        }
    }

    private var actionLabel: String {
        switch task.status {
        case .pending, .queued: return "Start \(task.displayName)"
        case .downloading: return "Pause \(task.displayName)"
        case .paused: return "Resume \(task.displayName)"
        case .failed: return "Retry \(task.displayName)"
        case .completed: return "\(task.displayName) downloaded"
        case .extracting: return "Extracting \(task.displayName)"
        }
    }

    private func handleAction() {
        switch task.status {
        case .pending, .queued, .paused: onResume()
        case .downloading: onPause()
        case .failed: onRetry()
        case .completed, .extracting: break
        }
    }

    // MARK: - Context Menu

    @ViewBuilder
    private var contextMenuContent: some View {
        // Pause/Resume
        switch task.status {
        case .downloading, .queued:
            Button {
                onPause()
            } label: {
                SwiftUI.Label("Pause", systemImage: "pause.circle")
            }
        case .pending, .paused:
            Button {
                onResume()
            } label: {
                SwiftUI.Label("Resume", systemImage: "play.circle")
            }
        case .failed:
            Button {
                onRetry()
            } label: {
                SwiftUI.Label("Retry", systemImage: "arrow.clockwise")
            }
        case .completed, .extracting:
            EmptyView()
        }

        // Prioritize (move to front of queue)
        if task.status == .pending || task.status == .queued {
            Button {
                onPrioritize()
            } label: {
                SwiftUI.Label("Prioritize", systemImage: "arrow.up.to.line")
            }
        }

        Divider()

        // Cancel (for active or pending tasks)
        if !task.status.isTerminal {
            Button(role: .destructive) {
                onCancel()
            } label: {
                SwiftUI.Label("Cancel", systemImage: "xmark.circle")
            }
        }

        Divider()

        // Copy URL
        Button {
            if let onCopyURL {
                onCopyURL()
            } else {
                copyURLToClipboard()
            }
        } label: {
            SwiftUI.Label("Copy URL", systemImage: "doc.on.doc")
        }

        // Show in Finder (if completed)
        if task.status == .completed {
            Button {
                onShowInFinder?()
            } label: {
                SwiftUI.Label("Show in Finder", systemImage: "folder")
            }
        }
    }

    // MARK: - Swipe Actions

    @ViewBuilder
    private var leadingSwipeActions: some View {
        if task.status == .pending || task.status == .queued {
            Button {
                onPrioritize()
            } label: {
                SwiftUI.Label("Prioritize", systemImage: "arrow.up.to.line")
            }
            .tint(.orange)
        }
    }

    @ViewBuilder
    private var trailingSwipeActions: some View {
        if !task.status.isTerminal {
            Button(role: .destructive) {
                onCancel()
            } label: {
                SwiftUI.Label("Cancel", systemImage: "xmark.circle")
            }
        }

        if task.status == .completed {
            Button(role: .destructive) {
                onCancel() // Used for "Remove" in completed state
            } label: {
                SwiftUI.Label("Remove", systemImage: "trash")
            }
        }
    }

    // MARK: - Accessibility

    private var accessibilityDescription: String {
        var description = "\(task.displayName), \(task.status.displayName)"

        switch task.status {
        case .downloading:
            description += ", \(task.progressPercentage) percent complete"
            if let timeRemaining = task.estimatedTimeRemainingText {
                description += ", \(timeRemaining) remaining"
            }
        case .failed:
            if let error = task.errorMessage {
                description += ", Error: \(error)"
            }
        case .completed:
            description += ", \(task.progressText)"
        default:
            break
        }

        return description
    }

    private var accessibilityHint: String {
        switch task.status {
        case .pending, .queued:
            return "Double tap to start download. Swipe right to prioritize."
        case .downloading:
            return "Double tap to pause. Swipe left to cancel."
        case .paused:
            return "Double tap to resume. Swipe left to cancel."
        case .failed:
            return "Double tap to retry."
        case .completed:
            return "Download complete."
        case .extracting:
            return "Extracting files, please wait."
        }
    }

    @ViewBuilder
    private var accessibilityActionsContent: some View {
        switch task.status {
        case .pending, .queued:
            Button("Start") { onResume() }
            Button("Prioritize") { onPrioritize() }
            Button("Cancel") { onCancel() }
        case .downloading:
            Button("Pause") { onPause() }
            Button("Cancel") { onCancel() }
        case .paused:
            Button("Resume") { onResume() }
            Button("Cancel") { onCancel() }
        case .failed:
            Button("Retry") { onRetry() }
            Button("Cancel") { onCancel() }
        case .completed:
            Button("Copy URL") { copyURLToClipboard() }
            if onShowInFinder != nil {
                Button("Show in Finder") { onShowInFinder?() }
            }
        case .extracting:
            EmptyView()
        }
    }

    // MARK: - Helper Methods

    private func copyURLToClipboard() {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(task.url.absoluteString, forType: .string)
        #endif
    }

    private func formatSpeed(_ bytesPerSec: Double) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useKB]
        formatter.countStyle = .file
        return "\(formatter.string(fromByteCount: Int64(bytesPerSec)))/s"
    }
}

// MARK: - Previews

#Preview("All States") {
    List {
        DownloadTaskRowView(
            task: .previewPending,
            onPause: {},
            onResume: {},
            onCancel: {},
            onRetry: {},
            onPrioritize: {}
        )

        DownloadTaskRowView(
            task: DownloadTask(
                url: URL(string: "https://example.com/queued.zip")!,
                category: "Greetings",
                partNumber: 1,
                totalParts: 2,
                datasetName: "INCLUDE",
                status: .queued
            ),
            onPause: {},
            onResume: {},
            onCancel: {},
            onRetry: {},
            onPrioritize: {}
        )

        DownloadTaskRowView(
            task: .previewDownloading,
            onPause: {},
            onResume: {},
            onCancel: {},
            onRetry: {},
            onPrioritize: {}
        )

        DownloadTaskRowView(
            task: .previewPaused,
            onPause: {},
            onResume: {},
            onCancel: {},
            onRetry: {},
            onPrioritize: {}
        )

        DownloadTaskRowView(
            task: .previewExtracting,
            onPause: {},
            onResume: {},
            onCancel: {},
            onRetry: {},
            onPrioritize: {}
        )

        DownloadTaskRowView(
            task: .previewCompleted,
            onPause: {},
            onResume: {},
            onCancel: {},
            onRetry: {},
            onPrioritize: {},
            onShowInFinder: {}
        )

        DownloadTaskRowView(
            task: .previewFailed,
            onPause: {},
            onResume: {},
            onCancel: {},
            onRetry: {},
            onPrioritize: {}
        )
    }
    .listStyle(.inset)
    .preferredColorScheme(.dark)
}

#Preview("Visual States") {
    VStack(alignment: .leading, spacing: 0) {
        Text("Pending:     [▷] Animals Part 1     ○ Pending")
            .font(.caption.monospaced())
            .padding(.horizontal)

        DownloadTaskRowView(
            task: .previewPending,
            onPause: {},
            onResume: {},
            onCancel: {},
            onRetry: {},
            onPrioritize: {}
        )
        .padding(.horizontal)

        Divider()

        Text("Downloading: [⏸] Clothes Part 1     ████░░ 45%")
            .font(.caption.monospaced())
            .padding(.horizontal)

        DownloadTaskRowView(
            task: .previewDownloading,
            onPause: {},
            onResume: {},
            onCancel: {},
            onRetry: {},
            onPrioritize: {}
        )
        .padding(.horizontal)

        Divider()

        Text("Failed:      [↻] Jobs Part 1        ✗ Failed")
            .font(.caption.monospaced())
            .padding(.horizontal)

        DownloadTaskRowView(
            task: .previewFailed,
            onPause: {},
            onResume: {},
            onCancel: {},
            onRetry: {},
            onPrioritize: {}
        )
        .padding(.horizontal)
    }
    .frame(width: 500)
}

#Preview("Downloading with Progress") {
    VStack(spacing: 16) {
        ForEach([0.0, 0.25, 0.5, 0.75, 1.0], id: \.self) { progress in
            DownloadTaskRowView(
                task: DownloadTask(
                    url: URL(string: "https://example.com/test.zip")!,
                    category: "Animals",
                    partNumber: 1,
                    totalParts: 2,
                    datasetName: "INCLUDE",
                    status: .downloading,
                    progress: progress,
                    bytesDownloaded: Int64(progress * 1_200_000_000),
                    totalBytes: 1_200_000_000,
                    startedAt: Date().addingTimeInterval(-60)
                ),
                onPause: {},
                onResume: {},
                onCancel: {},
                onRetry: {},
                onPrioritize: {}
            )
        }
    }
    .padding()
    .frame(width: 500)
}

#Preview("With Actions") {
    List {
        DownloadTaskRowView(
            task: .previewDownloading,
            onPause: { print("Pause") },
            onResume: { print("Resume") },
            onCancel: { print("Cancel") },
            onRetry: { print("Retry") },
            onPrioritize: { print("Prioritize") },
            onCopyURL: { print("Copy URL") },
            onShowInFinder: { print("Show in Finder") }
        )
    }
    .listStyle(.inset)
}
