import SwiftUI

/// Header view for a category section in the download list.
///
/// Displays:
/// - Category icon with consistent color
/// - Category name and completion count
/// - Mini progress indicator or completion checkmark
/// - Expand/collapse chevron with rotation animation
///
/// The header is tappable to expand/collapse the section.
struct DownloadCategoryHeaderView: View {

    // MARK: - Properties

    let group: DownloadTaskGroup
    var isExpanded: Bool = true

    // MARK: - Environment

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Body

    var body: some View {
        HStack(spacing: 12) {
            // Category icon
            CategoryIconView(category: group.category, size: .small)

            // Category info
            VStack(alignment: .leading, spacing: 2) {
                Text(group.category)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text(subtitleText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Status indicator
            statusIndicator

            // Expand/collapse chevron
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: isExpanded)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
        .accessibilityHint(isExpanded ? "Double tap to collapse" : "Double tap to expand")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Subtitle Text

    private var subtitleText: String {
        if group.allCompleted {
            return "\(group.totalCount) complete"
        } else if group.anyActive {
            return "\(group.completedCount)/\(group.totalCount) complete • \(group.progressPercentage)%"
        } else if group.anyFailed {
            return "\(group.failedCount) failed • \(group.completedCount)/\(group.totalCount) complete"
        } else {
            return "\(group.completedCount)/\(group.totalCount) complete"
        }
    }

    // MARK: - Status Indicator

    @ViewBuilder
    private var statusIndicator: some View {
        if group.allCompleted {
            // All complete checkmark
            Image(systemName: "checkmark.circle.fill")
                .font(.body)
                .foregroundStyle(.green)
        } else if group.anyActive {
            // Mini progress bar
            MiniProgressBar(progress: group.totalProgress, status: group.overallStatus)
        } else if group.anyFailed {
            // Failed indicator
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                Text("\(group.failedCount)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.red)
            }
        } else if group.allPending {
            // Pending indicator
            Image(systemName: "clock")
                .font(.body)
                .foregroundStyle(.secondary)
        } else {
            // Mixed state - show progress
            MiniProgressBar(progress: group.totalProgress, status: group.overallStatus)
        }
    }

    // MARK: - Accessibility

    private var accessibilityDescription: String {
        var description = "\(group.category) category"
        description += ", \(group.completedCount) of \(group.totalCount) complete"

        if group.anyActive {
            description += ", \(group.progressPercentage) percent progress"
        }

        if group.anyFailed {
            description += ", \(group.failedCount) failed"
        }

        return description
    }
}

// MARK: - Mini Progress Bar

/// A compact progress bar for use in headers.
private struct MiniProgressBar: View {

    // MARK: - Properties

    let progress: Double
    let status: DownloadTaskStatus

    // MARK: - Environment

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Body

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background track
                RoundedRectangle(cornerRadius: 2)
                    .fill(status.color.opacity(0.2))

                // Progress fill
                RoundedRectangle(cornerRadius: 2)
                    .fill(status.color)
                    .frame(width: geometry.size.width * CGFloat(min(max(progress, 0), 1)))
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: progress)
            }
        }
        .frame(width: 60, height: 4)
    }
}

// MARK: - Previews

#Preview("All States") {
    List {
        Section {
            Text("Sample content")
        } header: {
            DownloadCategoryHeaderView(
                group: .previewInProgress,
                isExpanded: true
            )
        }

        Section {
            Text("Sample content")
        } header: {
            DownloadCategoryHeaderView(
                group: .previewCompleted,
                isExpanded: true
            )
        }

        Section {
            Text("Sample content")
        } header: {
            DownloadCategoryHeaderView(
                group: .previewFailed,
                isExpanded: false
            )
        }

        Section {
            Text("Sample content")
        } header: {
            DownloadCategoryHeaderView(
                group: .previewPending,
                isExpanded: true
            )
        }
    }
    .listStyle(.insetGrouped)
}

#Preview("In Progress Header") {
    List {
        Section {
            ForEach(0..<3, id: \.self) { index in
                Text("Task \(index + 1)")
            }
        } header: {
            DownloadCategoryHeaderView(
                group: .previewInProgress,
                isExpanded: true
            )
        }
    }
    .listStyle(.insetGrouped)
}

#Preview("Completed Header") {
    List {
        Section {
            Text("All tasks completed!")
        } header: {
            DownloadCategoryHeaderView(
                group: .previewCompleted,
                isExpanded: true
            )
        }
    }
    .listStyle(.insetGrouped)
}

#Preview("Failed Header") {
    List {
        Section {
            Text("Some tasks failed")
        } header: {
            DownloadCategoryHeaderView(
                group: .previewFailed,
                isExpanded: true
            )
        }
    }
    .listStyle(.insetGrouped)
}

#Preview("Mini Progress Bars") {
    VStack(spacing: 16) {
        HStack {
            Text("0%")
            MiniProgressBar(progress: 0.0, status: .downloading)
        }
        HStack {
            Text("25%")
            MiniProgressBar(progress: 0.25, status: .downloading)
        }
        HStack {
            Text("50%")
            MiniProgressBar(progress: 0.5, status: .downloading)
        }
        HStack {
            Text("75%")
            MiniProgressBar(progress: 0.75, status: .downloading)
        }
        HStack {
            Text("100%")
            MiniProgressBar(progress: 1.0, status: .completed)
        }
        HStack {
            Text("Paused")
            MiniProgressBar(progress: 0.67, status: .paused)
        }
        HStack {
            Text("Failed")
            MiniProgressBar(progress: 0.23, status: .failed)
        }
    }
    .padding()
}
