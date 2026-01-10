import SwiftUI

/// Action button that adapts its icon and behavior based on download task status.
///
/// The button displays different icons and colors for each download state:
/// - Pending/Queued: Play icon (start)
/// - Downloading: Pause icon
/// - Paused: Play icon (resume)
/// - Failed: Retry icon
/// - Completed: Checkmark icon (disabled)
/// - Extracting: Gear icon (spinning, disabled)
struct DownloadActionButton: View {

    // MARK: - Properties

    let task: DownloadTask
    let onPause: () -> Void
    let onResume: () -> Void
    let onRetry: () -> Void

    // MARK: - State

    @State private var isSpinning = false

    // MARK: - Initialization

    init(
        task: DownloadTask,
        onPause: @escaping () -> Void,
        onResume: @escaping () -> Void,
        onRetry: @escaping () -> Void
    ) {
        self.task = task
        self.onPause = onPause
        self.onResume = onResume
        self.onRetry = onRetry
    }

    // MARK: - Computed Properties

    private var iconName: String {
        switch task.status {
        case .pending, .queued:
            return "play.fill"
        case .downloading:
            return "pause.fill"
        case .paused:
            return "play.fill"
        case .failed:
            return "arrow.clockwise"
        case .completed:
            return "checkmark"
        case .extracting:
            return "gearshape"
        }
    }

    private var tintColor: Color {
        switch task.status {
        case .pending, .queued:
            return .blue
        case .downloading:
            return .orange
        case .paused:
            return .blue
        case .failed:
            return .red
        case .completed:
            return .green
        case .extracting:
            return .purple
        }
    }

    private var isDisabled: Bool {
        task.status == .completed || task.status == .extracting
    }

    private var accessibilityLabel: String {
        switch task.status {
        case .pending, .queued:
            return "Start download"
        case .downloading:
            return "Pause download"
        case .paused:
            return "Resume download"
        case .failed:
            return "Retry download"
        case .completed:
            return "Download completed"
        case .extracting:
            return "Extracting files"
        }
    }

    // MARK: - Body

    var body: some View {
        Button(action: handleAction) {
            Image(systemName: iconName)
                .font(.body.weight(.medium))
                .symbolEffect(.rotate, options: .repeating, isActive: task.status == .extracting)
        }
        .buttonStyle(.bordered)
        .tint(tintColor)
        .disabled(isDisabled)
        .accessibilityLabel(accessibilityLabel)
    }

    // MARK: - Actions

    private func handleAction() {
        switch task.status {
        case .pending, .queued:
            onResume()
        case .downloading:
            onPause()
        case .paused:
            onResume()
        case .failed:
            onRetry()
        case .completed, .extracting:
            break
        }
    }
}

// MARK: - Previews

#Preview("All States") {
    VStack(spacing: 16) {
        ForEach(DownloadTaskStatus.allCases, id: \.self) { status in
            HStack {
                Text(status.displayName)
                    .frame(width: 100, alignment: .leading)
                Spacer()
                DownloadActionButton(
                    task: previewTask(with: status),
                    onPause: { print("Pause") },
                    onResume: { print("Resume") },
                    onRetry: { print("Retry") }
                )
            }
        }
    }
    .padding()
}

#Preview("In Row Context") {
    List {
        ForEach(DownloadTaskStatus.allCases, id: \.self) { status in
            HStack(spacing: 12) {
                CategoryIconView(category: "Animals", size: .medium)
                VStack(alignment: .leading) {
                    Text("Animals Part 1")
                        .font(.headline)
                    Text(status.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                DownloadActionButton(
                    task: previewTask(with: status),
                    onPause: {},
                    onResume: {},
                    onRetry: {}
                )
            }
            .padding(.vertical, 4)
        }
    }
}

private func previewTask(with status: DownloadTaskStatus) -> DownloadTask {
    DownloadTask(
        url: URL(string: "https://example.com/test.zip")!,
        category: "Animals",
        partNumber: 1,
        totalParts: 2,
        datasetName: "INCLUDE",
        status: status,
        progress: status == .downloading ? 0.45 : (status == .completed ? 1.0 : 0.0),
        bytesDownloaded: status == .downloading ? 540_000_000 : 0,
        totalBytes: 1_200_000_000
    )
}
