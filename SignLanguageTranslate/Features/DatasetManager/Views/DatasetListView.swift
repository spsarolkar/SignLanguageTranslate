import SwiftUI
import SwiftData

/// Main list view showing all datasets organized by download status.
///
/// Features:
/// - Sections for Available, Downloading, Ready, and Failed datasets
/// - Pull to refresh
/// - Swipe actions (delete, pause)
/// - Search/filter capability
/// - Sort by name, size, status
/// - Context menu support
/// - Empty state handling
struct DatasetListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(DownloadManager.self) private var downloadManager

    @Query(sort: \Dataset.name) private var allDatasets: [Dataset]
    @Binding var selectedDataset: Dataset?

    // MARK: - State

    @State private var searchText = ""
    @State private var sortOrder: SortOrder = .name
    @State private var showSortMenu = false
    @State private var expandedSections: Set<SectionType> = Set(SectionType.allCases)
    @State private var showDeleteConfirmation = false
    @State private var datasetToDelete: Dataset?
    @State private var isRefreshing = false

    // MARK: - Sort Order

    enum SortOrder: String, CaseIterable {
        case name = "Name"
        case size = "Size"
        case status = "Status"
        case dateAdded = "Date Added"

        var icon: String {
            switch self {
            case .name: return "textformat.abc"
            case .size: return "externaldrive.fill"
            case .status: return "circle.dashed"
            case .dateAdded: return "calendar"
            }
        }
    }

    // MARK: - Section Type

    enum SectionType: String, CaseIterable {
        case available = "Available to Download"
        case downloading = "Downloading"
        case ready = "Ready to Use"
        case failed = "Failed"
    }

    // MARK: - Body

    var body: some View {
        Group {
            if allDatasets.isEmpty {
                DatasetListFullEmptyView(
                    onGetStarted: initializeDefaultDatasets,
                    onLearnMore: nil
                )
            } else if filteredDatasets.isEmpty && !searchText.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else {
                datasetList
            }
        }
        .navigationTitle("Datasets")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .searchable(text: $searchText, prompt: "Search datasets")
        .toolbar { toolbarContent }
        .confirmationDialog(
            "Delete Dataset",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            deleteConfirmationButtons
        } message: {
            if let dataset = datasetToDelete {
                Text("Are you sure you want to delete \"\(dataset.name)\"? This will remove all downloaded files.")
            }
        }
        .animation(.easeInOut(duration: 0.3), value: allDatasets.count)
        .animation(.easeInOut(duration: 0.2), value: expandedSections)
    }

    // MARK: - Dataset List

    private var datasetList: some View {
        List(selection: $selectedDataset) {
            // Downloading section (show first if active)
            if !downloadingDatasets.isEmpty {
                downloadingSection
            }

            // Available section
            if !availableDatasets.isEmpty {
                availableSection
            }

            // Ready section
            if !readyDatasets.isEmpty {
                readySection
            }

            // Failed section
            if !failedDatasets.isEmpty {
                failedSection
            }
        }
        .listStyle(.insetGrouped)
        .refreshable {
            await refreshDatasets()
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var downloadingSection: some View {
        Section {
            if expandedSections.contains(.downloading) {
                ForEach(downloadingDatasets) { dataset in
                    datasetRow(for: dataset)
                        .tag(dataset)
                        .swipeActions(edge: .leading) {
                            pauseSwipeAction(for: dataset)
                        }
                }
            }
        } header: {
            downloadingSectionHeader
        }
    }

    private var downloadingSectionHeader: some View {
        let pauseAction: (() -> Void)? = downloadManager.isDownloading ? { pauseAllDownloads() } : nil
        return sectionHeader(
            for: .downloading,
            count: downloadingDatasets.count,
            action: pauseAction,
            actionLabel: "Pause All",
            actionIcon: "pause.fill"
        )
    }

    @ViewBuilder
    private var availableSection: some View {
        Section {
            if expandedSections.contains(.available) {
                ForEach(availableDatasets) { dataset in
                    datasetRow(for: dataset)
                        .tag(dataset)
                        .swipeActions(edge: .trailing) {
                            downloadSwipeAction(for: dataset)
                        }
                }
            }
        } header: {
            sectionHeader(for: .available, count: availableDatasets.count)
        }
    }

    @ViewBuilder
    private var readySection: some View {
        Section {
            if expandedSections.contains(.ready) {
                ForEach(readyDatasets) { dataset in
                    datasetRow(for: dataset)
                        .tag(dataset)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            deleteSwipeAction(for: dataset)
                        }
                }
            }
        } header: {
            sectionHeader(for: .ready, count: readyDatasets.count)
        }
    }

    @ViewBuilder
    private var failedSection: some View {
        Section {
            if expandedSections.contains(.failed) {
                ForEach(failedDatasets) { dataset in
                    datasetRow(for: dataset)
                        .tag(dataset)
                        .swipeActions(edge: .trailing) {
                            retrySwipeAction(for: dataset)
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            dismissErrorSwipeAction(for: dataset)
                        }
                }
            }
        } header: {
            sectionHeader(
                for: .failed,
                count: failedDatasets.count,
                action: retryAllFailed,
                actionLabel: "Retry All",
                actionIcon: "arrow.clockwise"
            )
        }
    }

    // MARK: - Section Header

    private func sectionHeader(
        for type: SectionType,
        count: Int,
        action: (() -> Void)? = nil,
        actionLabel: String? = nil,
        actionIcon: String? = nil
    ) -> some View {
        DatasetSectionHeader(
            title: type.rawValue,
            count: count,
            systemImage: sectionIcon(for: type),
            isExpanded: expandedSections.contains(type),
            action: action,
            actionLabel: actionLabel,
            actionIcon: actionIcon
        )
        .contentShape(Rectangle())
        .onTapGesture {
            toggleSection(type)
        }
    }

    private func sectionIcon(for type: SectionType) -> String {
        switch type {
        case .available:
            return "arrow.down.circle"
        case .downloading:
            return "arrow.down.circle.fill"
        case .ready:
            return "checkmark.circle.fill"
        case .failed:
            return "exclamationmark.circle.fill"
        }
    }

    // MARK: - Dataset Row

    private func datasetRow(for dataset: Dataset) -> some View {
        DatasetRowView(
            dataset: dataset,
            onStartDownload: { startDownload(for: dataset) },
            onPauseDownload: { pauseDownload(for: dataset) },
            onCancelDownload: { cancelDownload(for: dataset) },
            onDeleteDataset: { confirmDelete(dataset) }
        )
    }

    // MARK: - Swipe Actions

    private func downloadSwipeAction(for dataset: Dataset) -> some View {
        Button {
            startDownload(for: dataset)
        } label: {
            SwiftUI.Label("Download", systemImage: "arrow.down.circle.fill")
        }
        .tint(.blue)
    }

    private func pauseSwipeAction(for dataset: Dataset) -> some View {
        Button {
            pauseDownload(for: dataset)
        } label: {
            SwiftUI.Label("Pause", systemImage: "pause.circle.fill")
        }
        .tint(.orange)
    }

    private func deleteSwipeAction(for dataset: Dataset) -> some View {
        Button(role: .destructive) {
            confirmDelete(dataset)
        } label: {
            SwiftUI.Label("Delete", systemImage: "trash.fill")
        }
    }

    private func retrySwipeAction(for dataset: Dataset) -> some View {
        Button {
            startDownload(for: dataset)
        } label: {
            SwiftUI.Label("Retry", systemImage: "arrow.clockwise")
        }
        .tint(.blue)
    }

    private func dismissErrorSwipeAction(for dataset: Dataset) -> some View {
        Button {
            dismissError(for: dataset)
        } label: {
            SwiftUI.Label("Dismiss", systemImage: "xmark.circle")
        }
        .tint(.gray)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                sortMenuContent
            } label: {
                SwiftUI.Label("Sort", systemImage: "arrow.up.arrow.down")
            }
        }

        ToolbarItem(placement: .primaryAction) {
            Button {
                Task {
                    await refreshDatasets()
                }
            } label: {
                SwiftUI.Label("Refresh", systemImage: "arrow.clockwise")
            }
            .disabled(isRefreshing)
        }

        #if DEBUG
        ToolbarItem(placement: .secondaryAction) {
            Button {
                initializeDefaultDatasets()
            } label: {
                SwiftUI.Label("Add Defaults", systemImage: "plus.circle")
            }
        }
        #endif
    }

    @ViewBuilder
    private var sortMenuContent: some View {
        ForEach(SortOrder.allCases, id: \.self) { order in
            Button {
                sortOrder = order
            } label: {
                SwiftUI.Label(order.rawValue, systemImage: order.icon)
            }
            .disabled(sortOrder == order)
        }
    }

    private var deleteConfirmationButtons: some View {
        Group {
            Button("Delete", role: .destructive) {
                if let dataset = datasetToDelete {
                    deleteDataset(dataset)
                }
            }
            Button("Cancel", role: .cancel) {
                datasetToDelete = nil
            }
        }
    }

    // MARK: - Filtered & Sorted Datasets

    private var filteredDatasets: [Dataset] {
        let datasets = searchText.isEmpty
            ? allDatasets
            : allDatasets.filter { $0.name.localizedCaseInsensitiveContains(searchText) }

        return sortDatasets(datasets)
    }

    private func sortDatasets(_ datasets: [Dataset]) -> [Dataset] {
        switch sortOrder {
        case .name:
            return datasets.sorted { $0.name < $1.name }
        case .size:
            return datasets.sorted { $0.totalBytes > $1.totalBytes }
        case .status:
            return datasets.sorted { $0.downloadStatus.sortPriority < $1.downloadStatus.sortPriority }
        case .dateAdded:
            return datasets.sorted { $0.createdAt > $1.createdAt }
        }
    }

    private var availableDatasets: [Dataset] {
        filteredDatasets.filter { $0.downloadStatus == .notStarted }
    }

    private var downloadingDatasets: [Dataset] {
        filteredDatasets.filter {
            $0.downloadStatus == .downloading ||
            $0.downloadStatus == .processing ||
            $0.downloadStatus == .paused
        }
    }

    private var readyDatasets: [Dataset] {
        filteredDatasets.filter { $0.downloadStatus == .completed }
    }

    private var failedDatasets: [Dataset] {
        filteredDatasets.filter { $0.downloadStatus == .failed }
    }

    // MARK: - Actions

    private func toggleSection(_ type: SectionType) {
        withAnimation(.easeInOut(duration: 0.2)) {
            if expandedSections.contains(type) {
                expandedSections.remove(type)
            } else {
                expandedSections.insert(type)
            }
        }
    }

    private func startDownload(for dataset: Dataset) {
        dataset.startDownload()
        // Note: In a full implementation, this would also trigger
        // the DownloadManager to enqueue download tasks for this dataset
    }

    private func pauseDownload(for dataset: Dataset) {
        dataset.pauseDownload()
    }

    private func cancelDownload(for dataset: Dataset) {
        dataset.pauseDownload()
        // Reset progress
        dataset.downloadedBytes = 0
        dataset.downloadedParts = 0
        dataset.statusRawValue = DownloadStatus.notStarted.rawValue
    }

    private func pauseAllDownloads() {
        for dataset in downloadingDatasets {
            dataset.pauseDownload()
        }
        downloadManager.pauseAll()
    }

    private func retryAllFailed() {
        for dataset in failedDatasets {
            startDownload(for: dataset)
        }
    }

    private func confirmDelete(_ dataset: Dataset) {
        datasetToDelete = dataset
        showDeleteConfirmation = true
    }

    private func deleteDataset(_ dataset: Dataset) {
        // Clear selection if deleting selected dataset
        if selectedDataset == dataset {
            selectedDataset = nil
        }

        // Delete local files
        if dataset.hasLocalStorage {
            try? FileManager.default.removeItem(at: dataset.storageDirectory)
        }

        // Reset dataset to not started state (or delete from DB)
        dataset.statusRawValue = DownloadStatus.notStarted.rawValue
        dataset.downloadedBytes = 0
        dataset.downloadedParts = 0
        dataset.downloadedSamples = 0
        dataset.downloadStartedAt = nil
        dataset.downloadCompletedAt = nil
        dataset.lastError = nil

        datasetToDelete = nil
    }

    private func dismissError(for dataset: Dataset) {
        dataset.statusRawValue = DownloadStatus.notStarted.rawValue
        dataset.lastError = nil
    }

    private func refreshDatasets() async {
        isRefreshing = true
        // Simulate refresh delay
        try? await Task.sleep(for: .milliseconds(500))
        isRefreshing = false
    }

    private func initializeDefaultDatasets() {
        // Check if datasets already exist
        let existingNames = Set(allDatasets.map { $0.name })

        // Create INCLUDE dataset if not exists
        if !existingNames.contains("INCLUDE") {
            let include = Dataset(
                name: "INCLUDE",
                type: .include,
                totalSamples: 15000,
                totalParts: 46,
                totalBytes: 50_000_000_000 // ~50 GB
            )
            modelContext.insert(include)
        }

        // Create ISL-CSLTR dataset if not exists
        if !existingNames.contains("ISL-CSLTR") {
            let islcsltr = Dataset(
                name: "ISL-CSLTR",
                type: .islcsltr,
                totalSamples: 5000,
                totalParts: 12,
                totalBytes: 10_000_000_000 // ~10 GB
            )
            modelContext.insert(islcsltr)
        }

        try? modelContext.save()
    }
}

// MARK: - DownloadStatus Sort Priority Extension

private extension DownloadStatus {
    var sortPriority: Int {
        switch self {
        case .downloading: return 0
        case .processing: return 1
        case .paused: return 2
        case .failed: return 3
        case .notStarted: return 4
        case .completed: return 5
        }
    }
}

// MARK: - Previews

#Preview("Empty State") {
    NavigationStack {
        DatasetListView(selectedDataset: .constant(nil))
    }
    .modelContainer(for: Dataset.self, inMemory: true)
    .environment(DownloadManager())
}

#Preview("With Datasets") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Dataset.self, configurations: config)

    // Add preview datasets
    let datasets = Dataset.previewList
    for dataset in datasets {
        container.mainContext.insert(dataset)
    }

    return NavigationStack {
        DatasetListView(selectedDataset: .constant(nil))
    }
    .modelContainer(container)
    .environment(DownloadManager())
}

#Preview("Search Active") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Dataset.self, configurations: config)

    let include = Dataset.previewIncludeCompleted
    container.mainContext.insert(include)

    return NavigationStack {
        DatasetListView(selectedDataset: .constant(nil))
    }
    .modelContainer(container)
    .environment(DownloadManager())
}
