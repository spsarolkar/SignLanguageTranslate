import SwiftUI
import SwiftData

/// Section displaying categories for downloaded datasets.
/// Shows category names, icons, sample counts, and allows browsing.
struct DatasetCategoriesSection: View {
    let dataset: Dataset
    var onCategorySelected: ((Label) -> Void)?

    @Query(
        filter: #Predicate<Label> { label in
            label.typeRawValue == "category"
        },
        sort: [SortDescriptor(\Label.name)]
    )
    private var allCategoryLabels: [Label]

    init(dataset: Dataset, onCategorySelected: ((Label) -> Void)? = nil) {
        self.dataset = dataset
        self.onCategorySelected = onCategorySelected
    }

    /// Filter category labels that belong to this dataset.
    /// We do this filtering in Swift since SwiftData predicates don't support
    /// optional chaining with contains closures.
    private var categoryLabels: [Label] {
        allCategoryLabels.filter { label in
            guard let samples = label.videoSamples else { return false }
            return samples.contains { $0.datasetName == dataset.name }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header
            HStack {
                Text("Categories")
                    .font(.headline)

                Spacer()

                if !categoryLabels.isEmpty {
                    Text("\(categoryLabels.count) categories")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if categoryLabels.isEmpty {
                emptyStateView
            } else {
                categoriesGrid
            }
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 8) {
            Image(systemName: "folder")
                .font(.title)
                .foregroundStyle(.secondary)

            Text("No categories found")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text("Categories will appear here after the dataset is processed.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    // MARK: - Categories Grid

    private var categoriesGrid: some View {
        LazyVStack(spacing: 8) {
            ForEach(categoryLabels) { label in
                CategoryRowView(
                    label: label,
                    onSelect: { onCategorySelected?(label) }
                )
            }
        }
    }
}

// MARK: - Category Row View

/// Individual row for displaying a category.
struct CategoryRowView: View {
    let label: Label
    let onSelect: () -> Void

    private var sampleCount: Int {
        label.videoSamples?.count ?? 0
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                // Category icon
                Image(systemName: categoryIcon)
                    .font(.title3)
                    .foregroundStyle(.blue)
                    .frame(width: 40, height: 40)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.blue.opacity(0.15))
                    )

                // Category info
                VStack(alignment: .leading, spacing: 2) {
                    Text(label.name)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)

                    Text("\(sampleCount) samples")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Chevron
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
        }
        .buttonStyle(.plain)
    }

    private var categoryIcon: String {
        // Return appropriate icon based on category name
        switch label.name.lowercased() {
        case let name where name.contains("animal"):
            return "pawprint.fill"
        case let name where name.contains("greeting") || name.contains("hello"):
            return "hand.wave.fill"
        case let name where name.contains("color"):
            return "paintpalette.fill"
        case let name where name.contains("number") || name.contains("count"):
            return "number"
        case let name where name.contains("food") || name.contains("eat"):
            return "fork.knife"
        case let name where name.contains("weather"):
            return "cloud.sun.fill"
        case let name where name.contains("family") || name.contains("people"):
            return "person.2.fill"
        case let name where name.contains("adjective"):
            return "textformat.size"
        case let name where name.contains("action") || name.contains("verb"):
            return "figure.walk"
        case let name where name.contains("time") || name.contains("day"):
            return "clock.fill"
        default:
            return "folder.fill"
        }
    }
}

// MARK: - Static Category Row (for previews without SwiftData)

/// Static category row that doesn't require SwiftData context.
struct StaticCategoryRowView: View {
    let name: String
    let sampleCount: Int
    let icon: String
    var onSelect: (() -> Void)?

    var body: some View {
        Button(action: { onSelect?() }) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(.blue)
                    .frame(width: 40, height: 40)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.blue.opacity(0.15))
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)

                    Text("\(sampleCount) samples")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Previews

#Preview("Categories Section - Empty") {
    ScrollView {
        DatasetCategoriesSection(dataset: .previewIncludeNotStarted)
            .padding()
    }
    .background(Color(.systemGroupedBackground))
    .modelContainer(for: [Dataset.self, Label.self, VideoSample.self], inMemory: true)
}

#Preview("Category Rows - Static") {
    ScrollView {
        VStack(spacing: 8) {
            StaticCategoryRowView(
                name: "Animals",
                sampleCount: 245,
                icon: "pawprint.fill"
            )
            StaticCategoryRowView(
                name: "Greetings",
                sampleCount: 128,
                icon: "hand.wave.fill"
            )
            StaticCategoryRowView(
                name: "Colors",
                sampleCount: 56,
                icon: "paintpalette.fill"
            )
            StaticCategoryRowView(
                name: "Numbers",
                sampleCount: 89,
                icon: "number"
            )
            StaticCategoryRowView(
                name: "Food",
                sampleCount: 167,
                icon: "fork.knife"
            )
        }
        .padding()
    }
    .background(Color(.systemGroupedBackground))
}

#Preview("Single Category Row") {
    StaticCategoryRowView(
        name: "Animals",
        sampleCount: 245,
        icon: "pawprint.fill"
    )
    .padding()
    .background(Color(.systemGroupedBackground))
}
