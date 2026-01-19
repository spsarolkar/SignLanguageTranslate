import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Full-featured download list view showing all download tasks organized by category.
///
/// Features:
/// - Summary section with overall progress
/// - Grouped by category with collapsible sections
/// - Search and filter by status
/// - Batch operations (pause all, resume all, retry failed)
/// - Pull to refresh
/// - Keyboard shortcuts (macOS)
/// - iPad-optimized layout
struct DownloadListView: View {

    // MARK: - Environment

    @Environment(DownloadManager.self) private var downloadManager
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    // MARK: - State

    @State private var searchText = ""
    @State private var filterStatus: DownloadTaskStatus?
    @State private var expandedCategories: Set<String> = []
    @State private var sortOrder: SortOrder = .category
    @State private var selectedTasks: Set<UUID> = []
    @State private var isMultiSelectMode = false
    @State private var showCancelAllConfirmation = false
    @State private var isRefreshing = false

    // MARK: - Sort Order

    enum SortOrder: String, CaseIterable {
        case category = "Category"
        case status = "Status"
        case progress = "Progress"

        var icon: String {
            switch self {
            case .category: return "folder"
            case .status: return "circle.dashed"
            case .progress: return "chart.bar.fill"
            }
        }
    }

    // MARK: - Body

    var body: some View {
        Group {
            if downloadManager.tasks.isEmpty {
                emptyStateView
            } else if filteredTasks.isEmpty {
                noResultsView
            } else {
                downloadList
            }
        }
        .navigationTitle("Downloads")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .searchable(text: $searchText, prompt: "Search downloads")
        .toolbar { toolbarContent }
        .confirmationDialog(
            "Cancel All Downloads",
            isPresented: $showCancelAllConfirmation,
            titleVisibility: .visible
        ) {
            cancelAllConfirmationButtons
        } message: {
            Text("Are you sure you want to cancel all downloads? This cannot be undone.")
        }
        .animation(.easeInOut(duration: 0.2), value: expandedCategories)
        .animation(.easeInOut(duration: 0.3), value: downloadManager.tasks.count)
        .onAppear {
            // Expand all categories by default
            expandedCategories = Set(downloadManager.taskGroups.map { $0.category })
        }
    }

    // MARK: - Download List

    private var downloadList: some View {
        List(selection: isMultiSelectMode ? $selectedTasks : nil) {
            // Network warning banner (if no network)
            if !downloadManager.isNetworkAvailable {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "wifi.exclamationmark")
                            .font(.title2)
                            .foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("No Network Connection")
                                .font(.headline)
                            Text("Downloads will resume automatically when connected")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }
                .listRowBackground(Color.orange.opacity(0.1))
            }

            // Summary section
            DownloadSummarySection(manager: downloadManager)

            // Grouped by category
            ForEach(filteredGroups) { group in
                Section {
                    if expandedCategories.contains(group.category) {
                        ForEach(group.sortedTasks) { task in
                            DownloadTaskRowView(
                                task: task,
                                onPause: { downloadManager.pauseTask(task.id) },
                                onResume: { downloadManager.resumeTask(task.id) },
                                onCancel: { Task { await downloadManager.remove(task.id) } },
                                onRetry: { downloadManager.retryTask(task.id) },
                                onPrioritize: { downloadManager.prioritizeTask(task.id) },
                                onCopyURL: { copyURLToClipboard(task.url) },
                                onShowInFinder: task.status == .completed ? { showInFinder(task) } : nil
                            )
                            .tag(task.id)
                        }
                    }
                } header: {
                    DownloadCategoryHeaderView(
                        group: group,
                        isExpanded: expandedCategories.contains(group.category)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        toggleCategory(group.category)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable {
            await refreshDownloads()
        }
    }

    // MARK: - Empty States

    @ViewBuilder
    private var emptyStateView: some View {
        if downloadManager.isComplete && downloadManager.totalCount > 0 {
            allCompletedEmptyState
        } else {
            noDownloadsEmptyState
        }
    }

    private var noDownloadsEmptyState: some View {
        ContentUnavailableView {
            SwiftUI.Label("No Downloads", systemImage: "arrow.down.circle")
        } description: {
            Text("Start a download to see progress here")
        }
    }

    private var allCompletedEmptyState: some View {
        ContentUnavailableView {
            SwiftUI.Label("All Complete!", systemImage: "checkmark.circle.fill")
        } description: {
            Text("All downloads have finished successfully")
        }
    }

    private var noResultsView: some View {
        ContentUnavailableView {
            SwiftUI.Label("No Results", systemImage: "magnifyingglass")
        } description: {
            if let status = filterStatus {
                Text("No downloads match \"\(searchText)\" with status \"\(status.displayName)\"")
            } else {
                Text("No downloads match \"\(searchText)\"")
            }
        } actions: {
            Button("Clear Filters") {
                searchText = ""
                filterStatus = nil
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        // Start Downloads button (when tasks are pending but not started)
        ToolbarItem(placement: .primaryAction) {
            if !downloadManager.isEngineRunning && downloadManager.pendingCount > 0 && !downloadManager.isDownloading {
                Button {
                    Task {
                        await downloadManager.startDownloads()
                    }
                } label: {
                    SwiftUI.Label("Start Downloads", systemImage: "arrow.down.circle.fill")
                }
                .help("Start downloading all pending tasks")
            }
        }

        // Pause/Resume All
        ToolbarItem(placement: .primaryAction) {
            if downloadManager.isPaused {
                Button {
                    downloadManager.resumeAll()
                } label: {
                    SwiftUI.Label("Resume All", systemImage: "play.fill")
                }
                .help("Resume all downloads (⌘R)")
            } else if downloadManager.isDownloading {
                Button {
                    downloadManager.pauseAll()
                } label: {
                    SwiftUI.Label("Pause All", systemImage: "pause.fill")
                }
                .help("Pause all downloads (⌘P)")
            }
        }

        // Retry Failed
        ToolbarItem(placement: .primaryAction) {
            if downloadManager.hasFailed {
                Button {
                    downloadManager.retryFailed()
                } label: {
                    SwiftUI.Label("Retry Failed", systemImage: "arrow.clockwise")
                }
                .help("Retry all failed downloads")
            }
        }

        // Filter menu
        ToolbarItem(placement: .secondaryAction) {
            Menu {
                filterMenuContent
            } label: {
                SwiftUI.Label(
                    filterStatus?.displayName ?? "Filter",
                    systemImage: filterStatus != nil ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle"
                )
            }
        }

        // Sort menu
        ToolbarItem(placement: .secondaryAction) {
            Menu {
                sortMenuContent
            } label: {
                SwiftUI.Label("Sort", systemImage: "arrow.up.arrow.down")
            }
        }

        // More options menu
        ToolbarItem(placement: .secondaryAction) {
            Menu {
                moreOptionsMenuContent
            } label: {
                SwiftUI.Label("More", systemImage: "ellipsis.circle")
            }
        }

        // Multi-select toggle (iPad/Mac)
        #if os(iOS)
        if horizontalSizeClass == .regular {
            ToolbarItem(placement: .secondaryAction) {
                Button {
                    isMultiSelectMode.toggle()
                    if !isMultiSelectMode {
                        selectedTasks.removeAll()
                    }
                } label: {
                    SwiftUI.Label(
                        isMultiSelectMode ? "Done" : "Select",
                        systemImage: isMultiSelectMode ? "checkmark.circle.fill" : "checkmark.circle"
                    )
                }
            }
        }
        #endif

        // Batch action toolbar (when in multi-select mode)
        if isMultiSelectMode && !selectedTasks.isEmpty {
            ToolbarItemGroup(placement: .bottomBar) {
                batchActionButtons
            }
        }
    }

    // MARK: - Menu Content

    @ViewBuilder
    private var filterMenuContent: some View {
        Button {
            filterStatus = nil
        } label: {
            SwiftUI.Label("All", systemImage: "circle")
        }
        .disabled(filterStatus == nil)

        Divider()

        ForEach(DownloadTaskStatus.allCases, id: \.self) { status in
            Button {
                filterStatus = filterStatus == status ? nil : status
            } label: {
                SwiftUI.Label(status.displayName, systemImage: status.iconName)
            }
            .disabled(filterStatus == status)
        }
    }

    @ViewBuilder
    private var sortMenuContent: some View {
        ForEach(SortOrder.allCases, id: \.self) { order in
            Button {
                sortOrder = order
            } label: {
                HStack {
                    SwiftUI.Label(order.rawValue, systemImage: order.icon)
                    if sortOrder == order {
                        Image(systemName: "checkmark")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var moreOptionsMenuContent: some View {
        // Expand/Collapse all
        Button {
            if expandedCategories.isEmpty {
                expandedCategories = Set(downloadManager.taskGroups.map { $0.category })
            } else {
                expandedCategories.removeAll()
            }
        } label: {
            SwiftUI.Label(
                expandedCategories.isEmpty ? "Expand All" : "Collapse All",
                systemImage: expandedCategories.isEmpty ? "chevron.down" : "chevron.up"
            )
        }

        Divider()

        // Cancel all (destructive)
        if !downloadManager.tasks.isEmpty {
            Button(role: .destructive) {
                showCancelAllConfirmation = true
            } label: {
                SwiftUI.Label("Cancel All", systemImage: "xmark.circle")
            }
        }
    }

    // MARK: - Batch Action Buttons

    @ViewBuilder
    private var batchActionButtons: some View {
        Button {
            pauseSelectedTasks()
        } label: {
            SwiftUI.Label("Pause", systemImage: "pause.fill")
        }

        Button {
            resumeSelectedTasks()
        } label: {
            SwiftUI.Label("Resume", systemImage: "play.fill")
        }

        Button {
            retrySelectedTasks()
        } label: {
            SwiftUI.Label("Retry", systemImage: "arrow.clockwise")
        }

        Spacer()

        Button(role: .destructive) {
            cancelSelectedTasks()
        } label: {
            SwiftUI.Label("Cancel", systemImage: "xmark.circle")
        }
    }

    private var cancelAllConfirmationButtons: some View {
        Group {
            Button("Cancel All", role: .destructive) {
                Task {
                    await downloadManager.clear()
                }
            }
            Button("Keep Downloads", role: .cancel) {}
        }
    }

    // MARK: - Filtered & Sorted Data

    private var filteredTasks: [DownloadTask] {
        var tasks = downloadManager.tasks

        // Apply search filter
        if !searchText.isEmpty {
            tasks = tasks.filter {
                $0.category.localizedCaseInsensitiveContains(searchText) ||
                $0.displayName.localizedCaseInsensitiveContains(searchText)
            }
        }

        // Apply status filter
        if let status = filterStatus {
            tasks = tasks.filter { $0.status == status }
        }

        return tasks
    }

    private var filteredGroups: [DownloadTaskGroup] {
        let groups = filteredTasks.groupedByCategory()

        switch sortOrder {
        case .category:
            return groups.sorted { $0.category < $1.category }
        case .status:
            return groups.sorted { $0.overallStatus.rawValue < $1.overallStatus.rawValue }
        case .progress:
            return groups.sorted { $0.totalProgress > $1.totalProgress }
        }
    }

    // MARK: - Actions

    private func toggleCategory(_ category: String) {
        withAnimation(.easeInOut(duration: 0.2)) {
            if expandedCategories.contains(category) {
                expandedCategories.remove(category)
            } else {
                expandedCategories.insert(category)
            }
        }
    }

    private func refreshDownloads() async {
        isRefreshing = true
        await downloadManager.refresh()
        isRefreshing = false
    }

    private func handlePauseShortcut() {
        if downloadManager.isPaused {
            downloadManager.resumeAll()
        } else {
            downloadManager.pauseAll()
        }
    }

    // MARK: - Batch Operations

    private func pauseSelectedTasks() {
        for id in selectedTasks {
            downloadManager.pauseTask(id)
        }
        selectedTasks.removeAll()
        isMultiSelectMode = false
    }

    private func resumeSelectedTasks() {
        for id in selectedTasks {
            downloadManager.resumeTask(id)
        }
        selectedTasks.removeAll()
        isMultiSelectMode = false
    }

    private func retrySelectedTasks() {
        for id in selectedTasks {
            downloadManager.retryTask(id)
        }
        selectedTasks.removeAll()
        isMultiSelectMode = false
    }

    private func cancelSelectedTasks() {
        Task {
            for id in selectedTasks {
                await downloadManager.remove(id)
            }
            selectedTasks.removeAll()
            isMultiSelectMode = false
        }
    }

    // MARK: - Helper Methods

    private func copyURLToClipboard(_ url: URL) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
        #elseif os(iOS)
        UIPasteboard.general.string = url.absoluteString
        #endif
    }

    private func showInFinder(_ task: DownloadTask) {
        #if os(macOS)
        // Would need to construct the actual file path from task info
        // For now, this is a placeholder
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: NSHomeDirectory())
        #endif
    }
}

// MARK: - Previews

#Preview("With Downloads") {
    let manager = DownloadManager()
    // Note: In a real preview, you'd populate the manager with preview tasks

    return NavigationStack {
        DownloadListView()
    }
    .environment(manager)
}

#Preview("Empty State") {
    NavigationStack {
        DownloadListView()
    }
    .environment(DownloadManager())
}

#Preview("With Search") {
    NavigationStack {
        DownloadListView()
    }
    .environment(DownloadManager())
}
