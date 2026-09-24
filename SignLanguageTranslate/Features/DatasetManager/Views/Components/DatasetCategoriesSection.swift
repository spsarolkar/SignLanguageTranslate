import SwiftUI

/// Categories grid in the dataset detail: one tile per manifest category with
/// its downloaded parts. Accent when complete, amber when partial, track when
/// none. "Browse ingested →" appears once samples are in the database.
struct DatasetCategoriesSection: View {
    let categories: [DatasetTransferSummary.CategoryProgress]
    /// Nil hides the browse link.
    var onBrowse: (() -> Void)? = nil

    @State private var width: CGFloat = 0

    /// As many tile columns as fit, capped at `Metrics.categoryColumnsMax`.
    private var columns: [GridItem] {
        let fit = Int((width + Spacing.md) / (Metrics.categoryTileMinWidth + Spacing.md))
        let count = min(max(fit, 1), Metrics.categoryColumnsMax)
        return Array(repeating: GridItem(.flexible(), spacing: Spacing.md), count: count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeader(eyebrow: "Categories") {
                if let onBrowse {
                    Button("Browse ingested →", action: onBrowse)
                        .font(Typo.pill)
                        .foregroundStyle(Palette.accent)
                        .frame(minHeight: Metrics.touchTarget)
                        .contentShape(Rectangle())
                }
            }

            LazyVGrid(columns: columns, alignment: .leading, spacing: Spacing.md) {
                ForEach(categories) { category in
                    CategoryTile(
                        name: category.displayName,
                        progress: category.fraction,
                        tint: tint(for: category.state),
                        detail: "\(category.done) / \(category.total)"
                    )
                }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        }
    }

    private func tint(for state: DatasetTransferSummary.CategoryProgress.State) -> Color {
        switch state {
        case .complete: return StateTint.complete.color
        case .partial: return StateTint.queued.color
        case .none: return Palette.track
        }
    }
}

// MARK: - Previews

#Preview("Categories grid") {
    let tasks: [DownloadTask] = [.previewCompleted, .previewDownloading, .previewPending]
    return ScrollView {
        DatasetCategoriesSection(
            categories: DatasetTransferSummary.categories(
                INCLUDEManifest.categories, tasks: tasks, datasetCompleted: false
            ),
            onBrowse: {}
        )
        .padding(Spacing.pane)
    }
    .frame(width: 760)
    .background(Palette.ground)
    .preferredColorScheme(.dark)
}
