import SwiftUI
import SwiftData

/// The middle column contains selection and filters, never the full workspace.
struct PipelineSelectionView: View {
    @Bindable var navigation: NavigationState
    var onShowWorkspace: () -> Void = {}
    @Query(sort: \Dataset.name) private var datasets: [Dataset]

    private var downloadedDatasets: [Dataset] {
        datasets.filter { $0.downloadStatus == .completed }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                SectionHeader(eyebrow: "Dataset")
                if downloadedDatasets.isEmpty {
                    Text("Download and ingest a dataset to extract its keypoints.")
                        .font(Typo.body)
                        .foregroundStyle(Palette.textTertiary)
                }
                ForEach(downloadedDatasets) { dataset in
                    Button {
                        navigation.selectPipelineDataset(dataset)
                        onShowWorkspace()
                    } label: {
                        Card(variant: navigation.pipelineDataset?.id == dataset.id ? .selected : .standard) {
                            VStack(alignment: .leading, spacing: Spacing.sm) {
                                Text(dataset.name)
                                    .font(Typo.headline)
                                    .foregroundStyle(Palette.textPrimary)
                                    .lineLimit(1)
                                Text("\(dataset.totalSamples.formatted()) videos")
                                    .font(Typo.monoCaption)
                                    .foregroundStyle(Palette.textTertiary)
                            }
                            .frame(minHeight: Metrics.touchTarget, alignment: .leading)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityValue(navigation.pipelineDataset?.id == dataset.id ? "Selected" : "")
                }

                if let dataset = navigation.pipelineDataset {
                    SectionHeader(eyebrow: "Find clips")
                    TextField("Search videos…", text: Binding(
                        get: { navigation.pipelineSearch },
                        set: { navigation.searchPipeline($0) }
                    ))
                    .font(Typo.body)
                    .padding(.horizontal, Spacing.md)
                    .frame(minHeight: Metrics.touchTarget)
                    .background(Palette.control, in: RoundedRectangle(cornerRadius: Radius.control))
                    .accessibilityLabel("Search pipeline videos")
                    .submitLabel(.search)
                    .onSubmit(onShowWorkspace)

                    PipelineCategorySelection(datasetName: dataset.name, navigation: navigation)
                }
            }
            .padding(Spacing.lg)
        }
        .background(Palette.chrome)
        .navigationTitle("Pipeline")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if navigation.pipelineDataset != nil {
                PrimaryButton(title: "Open pipeline", systemImage: "arrow.right", action: onShowWorkspace)
                    .padding(Spacing.lg)
                    .frame(maxWidth: .infinity)
                    .background(Palette.chrome)
            }
        }
        .task { selectAvailableDatasetIfNeeded() }
        .onChange(of: downloadedDatasets.map(\.id)) { selectAvailableDatasetIfNeeded() }
    }

    private func selectAvailableDatasetIfNeeded() {
        if !downloadedDatasets.contains(where: { $0.id == navigation.pipelineDataset?.id }) {
            navigation.selectPipelineDataset(downloadedDatasets.first)
        }
    }
}

private struct PipelineCategorySelection: View {
    @Bindable var navigation: NavigationState
    @Query private var videos: [VideoSample]

    init(datasetName: String, navigation: NavigationState) {
        self.navigation = navigation
        _videos = Query(filter: #Predicate<VideoSample> { $0.datasetName == datasetName })
    }

    private var categories: [(name: String, count: Int)] {
        Dictionary(grouping: videos.compactMap(\.categoryName), by: { $0 })
            .map { (name: $0.key, count: $0.value.count) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            SectionHeader(eyebrow: "Categories")
            categoryRow(title: "All categories", category: nil, count: videos.count)
            ForEach(categories, id: \.name) { category in
                categoryRow(title: category.name, category: category.name, count: category.count)
            }
        }
    }

    private func categoryRow(title: String, category: String?, count: Int) -> some View {
        let isSelected = navigation.pipelineCategory == category
        return Button {
            navigation.selectPipelineCategory(category)
        } label: {
            HStack(spacing: Spacing.sm) {
                Text(title)
                    .font(Typo.callout)
                    .foregroundStyle(isSelected ? Palette.accent : Palette.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: Spacing.xxs)
                Text(count.formatted())
                    .font(Typo.monoCaption)
                    .foregroundStyle(Palette.textTertiary)
            }
            .padding(.horizontal, Spacing.md)
            .frame(minHeight: Metrics.touchTarget)
            .background(isSelected ? Palette.surfaceRaised : Palette.chrome,
                        in: RoundedRectangle(cornerRadius: Radius.control))
        }
        .buttonStyle(.plain)
        .accessibilityValue(isSelected ? "Selected" : "")
    }
}

#Preview("Pipeline selectors") {
    NavigationStack {
        PipelineSelectionView(navigation: NavigationState(section: .pipeline))
    }
    .modelContainer(PersistenceController.preview.container)
    .preferredColorScheme(.dark)
}
