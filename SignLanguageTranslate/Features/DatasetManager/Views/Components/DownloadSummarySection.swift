import SwiftUI

/// Summary section displayed at the top of the download list.
///
/// Shows:
/// - Overall status text and progress ring
/// - Progress bar for overall completion
/// - Quick stats (active, pending, completed, failed counts)
///
/// This section provides a quick overview of all download activity
/// and updates in real-time as downloads progress.
struct DownloadSummarySection: View {

    // MARK: - Properties

    let manager: DownloadManager

    // MARK: - Environment

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Body

    var body: some View {
        Section {
            VStack(spacing: 16) {
                // Header row: status text + progress ring
                HStack(alignment: .center, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(manager.statusText)
                            .font(.headline)

                        // Progress info with optional speed and ETA
                        if manager.totalBytes > 0 {
                            HStack(spacing: 6) {
                                Text(manager.bytesProgressText)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()

                                // Show speed when actively downloading
                                if manager.isDownloading && manager.currentDownloadRate > 0 {
                                    Text("•")
                                        .foregroundStyle(.tertiary)
                                    Text(manager.formattedDownloadRate)
                                        .font(.subheadline)
                                        .foregroundStyle(.blue)
                                        .monospacedDigit()
                                }
                            }
                        } else if manager.totalCount > 0 {
                            Text("\(manager.progressPercentage)% complete")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }

                        // Show ETA on separate line when downloading
                        if manager.isDownloading, let eta = manager.formattedTimeRemaining {
                            HStack(spacing: 4) {
                                Image(systemName: "clock")
                                    .font(.caption)
                                Text(eta + " remaining")
                                    .font(.caption)
                            }
                            .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    DownloadProgressRing(
                        progress: manager.overallProgress,
                        status: currentStatus,
                        size: .large
                    )
                }

                // Progress bar
                if manager.totalCount > 0 {
                    ProgressView(value: manager.overallProgress)
                        .tint(currentStatus.color)
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: manager.overallProgress)
                }

                // Quick stats row
                if manager.totalCount > 0 {
                    HStack(spacing: 0) {
                        StatItem(
                            title: "Active",
                            value: "\(manager.activeCount)",
                            color: .blue
                        )

                        Spacer()

                        StatItem(
                            title: "Pending",
                            value: "\(manager.pendingCount)",
                            color: .gray
                        )

                        Spacer()

                        StatItem(
                            title: "Completed",
                            value: "\(manager.completedCount)",
                            color: .green
                        )

                        Spacer()

                        StatItem(
                            title: "Failed",
                            value: "\(manager.failedCount)",
                            color: manager.failedCount > 0 ? .red : .gray
                        )
                    }
                }
            }
            .padding(.vertical, 8)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }

    // MARK: - Computed Properties

    private var currentStatus: DownloadTaskStatus {
        if manager.isComplete {
            return .completed
        } else if manager.isDownloading {
            return .downloading
        } else if manager.isPaused {
            return .paused
        } else if manager.hasFailed {
            return .failed
        } else if manager.pendingCount > 0 {
            return .pending
        } else {
            return .pending
        }
    }

    private var accessibilityDescription: String {
        var description = "Download summary: \(manager.statusText)"

        if manager.totalCount > 0 {
            description += ". \(manager.progressPercentage) percent complete."
            description += " \(manager.activeCount) active,"
            description += " \(manager.pendingCount) pending,"
            description += " \(manager.completedCount) completed,"
            description += " \(manager.failedCount) failed."
        }

        return description
    }
}

// MARK: - Stat Item

/// A single statistic display item for the summary section.
private struct StatItem: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title2.monospacedDigit())
                .fontWeight(.semibold)
                .foregroundStyle(color)

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 60)
    }
}

// MARK: - Download Progress Ring

/// Circular progress indicator with status-aware styling.
struct DownloadProgressRing: View {

    // MARK: - Properties

    let progress: Double
    let status: DownloadTaskStatus
    let size: RingSize

    // MARK: - Environment

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - State

    @State private var isAnimating = false

    // MARK: - Ring Size

    enum RingSize {
        case small
        case medium
        case large

        var dimension: CGFloat {
            switch self {
            case .small: return 32
            case .medium: return 48
            case .large: return 64
            }
        }

        var lineWidth: CGFloat {
            switch self {
            case .small: return 3
            case .medium: return 4
            case .large: return 5
            }
        }

        var font: Font {
            switch self {
            case .small: return .caption2.monospacedDigit()
            case .medium: return .caption.monospacedDigit()
            case .large: return .callout.monospacedDigit()
            }
        }
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            // Background ring
            Circle()
                .stroke(
                    status.color.opacity(0.2),
                    lineWidth: size.lineWidth
                )

            // Progress ring
            Circle()
                .trim(from: 0, to: CGFloat(min(max(progress, 0), 1)))
                .stroke(
                    status.color,
                    style: StrokeStyle(
                        lineWidth: size.lineWidth,
                        lineCap: .round
                    )
                )
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: progress)

            // Center content
            if status == .completed {
                Image(systemName: "checkmark")
                    .font(size.font.weight(.bold))
                    .foregroundStyle(status.color)
            } else if status.isActive && progress < 1.0 {
                Text("\(Int(progress * 100))")
                    .font(size.font.weight(.semibold))
                    .foregroundStyle(status.color)
            } else {
                Image(systemName: status.iconName)
                    .font(size.font)
                    .foregroundStyle(status.color)
                    .symbolEffect(.pulse, options: .repeating, isActive: status.isActive && isAnimating)
            }
        }
        .frame(width: size.dimension, height: size.dimension)
        .onAppear {
            if status.isActive {
                isAnimating = true
            }
        }
        .onChange(of: status) { _, newStatus in
            isAnimating = newStatus.isActive
        }
        .accessibilityLabel("\(Int(progress * 100)) percent complete, \(status.displayName)")
    }
}

// MARK: - Previews

#Preview("Summary Section - Downloading") {
    let manager = DownloadManager()
    // In a real scenario, we'd set up the manager with tasks

    return List {
        DownloadSummarySection(manager: manager)
    }
    .listStyle(.insetGrouped)
    .environment(manager)
}

#Preview("Summary Section - Complete") {
    let manager = DownloadManager()

    return List {
        DownloadSummarySection(manager: manager)
    }
    .listStyle(.insetGrouped)
    .environment(manager)
}

#Preview("Progress Rings - All Sizes") {
    VStack(spacing: 20) {
        HStack(spacing: 20) {
            DownloadProgressRing(progress: 0.45, status: .downloading, size: .small)
            DownloadProgressRing(progress: 0.45, status: .downloading, size: .medium)
            DownloadProgressRing(progress: 0.45, status: .downloading, size: .large)
        }

        HStack(spacing: 20) {
            DownloadProgressRing(progress: 1.0, status: .completed, size: .small)
            DownloadProgressRing(progress: 1.0, status: .completed, size: .medium)
            DownloadProgressRing(progress: 1.0, status: .completed, size: .large)
        }

        HStack(spacing: 20) {
            DownloadProgressRing(progress: 0.0, status: .pending, size: .small)
            DownloadProgressRing(progress: 0.67, status: .paused, size: .medium)
            DownloadProgressRing(progress: 0.23, status: .failed, size: .large)
        }
    }
    .padding()
}

#Preview("Stat Items") {
    HStack(spacing: 24) {
        StatItem(title: "Active", value: "3", color: .blue)
        StatItem(title: "Pending", value: "12", color: .gray)
        StatItem(title: "Completed", value: "8", color: .green)
        StatItem(title: "Failed", value: "1", color: .red)
    }
    .padding()
}
