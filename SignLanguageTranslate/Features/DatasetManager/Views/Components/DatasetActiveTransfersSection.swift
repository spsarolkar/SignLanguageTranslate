import SwiftUI

/// Inline "Active transfers" in the dataset detail: one `DownloadTaskRowView`
/// per part that is transferring or extracting (or paused mid-transfer, while
/// the dataset is paused), and the slot count.
struct DatasetActiveTransfersSection: View {
    let tasks: [DownloadTask]
    /// Slots in use; paused parts do not hold one.
    let usedSlots: Int
    let slotCount: Int
    let isPaused: Bool
    @Environment(DownloadManager.self) private var downloadManager

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeader(eyebrow: "Active transfers", trailing: "\(usedSlots) of \(slotCount) slots")

            if tasks.isEmpty {
                DashedEmptyCard(
                    title: "No active transfers",
                    message: isPaused
                        ? "Downloads are paused. Resume to continue."
                        : "Parts start here as download slots free up."
                )
            } else {
                VStack(spacing: Spacing.sm) {
                    ForEach(tasks) { task in
                        DownloadTaskRowView(
                            task: task,
                            onPause: { downloadManager.pauseTask(task.id) },
                            onResume: { downloadManager.resumeTask(task.id) },
                            onCancel: { downloadManager.cancelTask(task.id) },
                            onRetry: { downloadManager.retryTask(task.id) },
                            onPrioritize: { downloadManager.prioritizeTask(task.id) }
                        )
                    }
                }
            }
        }
    }
}

// MARK: - Previews

#Preview("Active transfers") {
    VStack(spacing: Spacing.section) {
        DatasetActiveTransfersSection(
            tasks: [.previewDownloading, .previewExtracting],
            usedSlots: 2,
            slotCount: 3,
            isPaused: false
        )
        DatasetActiveTransfersSection(tasks: [.previewPaused], usedSlots: 0, slotCount: 3, isPaused: true)
    }
    .padding(Spacing.pane)
    .frame(width: 760)
    .background(Palette.ground)
    .environment(DownloadManager())
    .preferredColorScheme(.dark)
}
