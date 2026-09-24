import SwiftUI

/// Top of the dataset detail: the section's large title and a status badge.
/// The title follows `NavigationSection`, not the artboard ("Data Pipeline").
struct DatasetHeaderSection: View {
    let dataset: Dataset

    var body: some View {
        HStack(alignment: .center, spacing: Spacing.lg) {
            Text(NavigationSection.datasets.rawValue)
                .font(Typo.largeTitle)
                .tracking(Tracking.largeTitle)
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: Spacing.md)
            StatusBadge(state: badgeState, text: dataset.downloadStatus.displayName)
        }
    }

    private var badgeState: StateTint {
        switch dataset.downloadStatus {
        case .notStarted: return .idle
        case .downloading, .processing: return .active
        case .paused: return .queued
        case .completed: return .complete
        case .failed: return .failed
        }
    }
}

// MARK: - Previews

#Preview("Header states") {
    VStack(alignment: .leading, spacing: Spacing.xxl) {
        DatasetHeaderSection(dataset: .previewIncludeNotStarted)
        DatasetHeaderSection(dataset: .previewIncludeDownloading)
        DatasetHeaderSection(dataset: .previewPaused)
        DatasetHeaderSection(dataset: .previewIncludeCompleted)
        DatasetHeaderSection(dataset: .previewFailed)
    }
    .padding(Spacing.pane)
    .frame(width: 700)
    .background(Palette.ground)
    .preferredColorScheme(.dark)
}
