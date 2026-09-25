import SwiftUI
import SwiftData
import Combine
import UniformTypeIdentifiers
#if os(iOS)
import UIKit
#endif
/// Detail column that displays content based on the current selection.
struct DetailColumnView: View {
    let selectedSection: NavigationSection?
    @Binding var selectedDataset: Dataset?

    @Query(sort: \Dataset.name) private var allDatasets: [Dataset]

    var body: some View {
        Group {
            switch selectedSection {
            case .datasets:
                datasetDetail
            case .downloads:
                DownloadDetailView()
            case .pipeline:
                EmptyDetailView()
            case .training:
                TrainingDetailPlaceholder()
            case .settings:
                SettingsDetailPlaceholder()
            case nil:
                EmptyDetailView()
            }
        }
        .id(selectedSection)
    }

    @ViewBuilder
    private var datasetDetail: some View {
        if ModelQueries.isFirstRun(allDatasets) {
            FirstRunView(
                dataset: allDatasets.first { $0.datasetType == .include },
                onStarted: { selectedDataset = $0 }
            )
        } else if let dataset = selectedDataset {
            DatasetDetailView(dataset: dataset)
        } else {
            EmptyDetailView(
                title: "Select a Dataset",
                systemImage: "folder.fill",
                description: "Choose a dataset from the list to view its contents and manage downloads."
            )
        }
    }
}

// MARK: - Dataset Detail View

/// Detailed view of a selected dataset.
/// Uses section components for a modular, organized layout.
struct DatasetDetailView: View {
    @Bindable var dataset: Dataset
    @Environment(\.modelContext) private var modelContext
    @Environment(DownloadManager.self) private var downloadManager
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var showDeleteConfirmation = false
    @State private var showFilesApp = false
    @State private var isImporting = false
    @State private var importError: String? = nil
    @State private var showImportError = false
    @State private var showReingestConfirmation = false
    
    @State private var showSamples = false
    
    // Ingestion state
    @State private var isIngesting = false
    @State private var ingestionProgress: String = ""
    
    // Transient state for progress display
    @State private var currentSpeed: Double = 0
    @State private var timeRemaining: TimeInterval? = nil

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.section) {
                    DatasetHeaderSection(dataset: dataset)

                    DatasetActionsSection(
                        dataset: dataset,
                        summary: transferSummary,
                        timeRemaining: timeRemaining,
                        isIngesting: isIngesting,
                        ingestionProgress: ingestionProgress,
                        onStartDownload: startDownload,
                        onPauseDownload: pauseDownload,
                        onResumeDownload: resumeDownload,
                        onBrowseSamples: browseSamples,
                        onIngestVideos: ingestVideos
                    )

                    activeTransfers
                    categories
                }
                .padding(horizontalSizeClass == .compact ? Spacing.xl : Spacing.pane)
            }
            .background(Palette.ground)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                toolbarContent
            }
            .navigationDestination(isPresented: $showSamples) {
                DatasetBrowserView(dataset: dataset)
            }
        }
        .confirmationDialog(
            "Delete Dataset",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                deleteDataset()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete \"\(dataset.name)\"? This will remove all downloaded files and cannot be undone.")
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [UTType.zip],
            allowsMultipleSelection: false
        ) { result in
            handleImport(result)
        }
        .alert("Import Failed", isPresented: $showImportError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(importError ?? "Unknown error")
        }
        .alert("Re-ingest Videos?", isPresented: $showReingestConfirmation) {
            Button("Re-ingest", role: .destructive) {
                performIngestion(deleteFirst: true)
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This dataset already has ingested samples. Do you want to delete existing samples and re-ingest all videos?")
        }
        .onAppear {
            syncProgress()
        }
        // One sync per second, whatever the status, so a retry from a failed
        // or paused state is still picked up. Syncing on every task change
        // wrote to SwiftData many times a second during downloads.
        .onReceive(Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()) { _ in
            syncProgress()
        }
        .overlay {
            if downloadManager.isImporting {
                Palette.ground.opacity(Opacity.scrim)
                    .ignoresSafeArea()
                    .overlay {
                        VStack(spacing: Spacing.lg) {
                            ProgressView()
                                .controlSize(.large)
                                .tint(Palette.accent)

                            Text(downloadManager.importStatus)
                                .font(Typo.headline)
                                .foregroundStyle(Palette.textPrimary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(Spacing.section)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Radius.panel, style: .continuous))
                    }
            }
        }
    }
    
    // MARK: - Sections

    @ViewBuilder
    private var activeTransfers: some View {
        let status = dataset.downloadStatus
        if status == .downloading || status == .paused {
            let summary = transferSummary
            let paused = datasetTasks.filter { $0.status == .paused && $0.progress > 0 }
            DatasetActiveTransfersSection(
                tasks: summary.activeTasks + (status == .paused ? paused : []),
                usedSlots: summary.activeCount,
                slotCount: downloadManager.downloadEngine.maxConcurrentDownloads,
                isPaused: status == .paused
            )
        }
    }

    @ViewBuilder
    private var categories: some View {
        if dataset.datasetType == .include {
            let progress = DatasetTransferSummary.categories(
                INCLUDEManifest.categories,
                tasks: datasetTasks,
                datasetCompleted: dataset.downloadStatus == .completed
            )
            DatasetCategoriesSection(categories: progress, onBrowse: browseAction)
        }
    }

    // MARK: - Derived

    /// "Browse ingested →" only once samples are in the database.
    private var browseAction: (() -> Void)? {
        guard dataset.totalSamples > 0 else { return nil }
        return { showSamples = true }
    }

    private var datasetTasks: [DownloadTask] {
        downloadManager.tasks.filter { $0.datasetName == dataset.name }
    }

    private var transferSummary: DatasetTransferSummary {
        DatasetTransferSummary(tasks: datasetTasks)
    }

    // MARK: - Synchronization
    
    private func syncProgress() {
        // Only sync if we have active tasks for this dataset
        let tasks = downloadManager.tasks.filter { $0.datasetName == dataset.name }
        guard !tasks.isEmpty else { return }
        
        // Get comprehensive stats including speed and ETA
        let stats = downloadManager.getDatasetProgress(name: dataset.name)
        
        // Update local transient state
        currentSpeed = stats.speed
        timeRemaining = stats.timeRemaining
        
        // Update dataset properties loosely (without forcing immediate save)
        if dataset.downloadedBytes != stats.downloaded {
            dataset.downloadedBytes = stats.downloaded
        }
        if dataset.totalBytes != stats.total && stats.total > 0 {
             // Sync total bytes from tasks to fix percentage mismatch
             dataset.totalBytes = stats.total
        }
        
        let completedParts = tasks.filter { $0.status == .completed }.count
        if dataset.downloadedParts != completedParts {
            dataset.downloadedParts = completedParts
        }

        dataset.syncStatus(with: tasks)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                // Import Option
                Button {
                    isImporting = true
                } label: {
                    SwiftUI.Label("Import Zip", systemImage: "square.and.arrow.down")
                }
                
                Divider()

                if dataset.hasLocalStorage {
                    Button {
                        viewInFiles()
                    } label: {
                        SwiftUI.Label("View in Files", systemImage: "folder")
                    }
                }

                if dataset.downloadStatus == .downloading {
                    Divider()

                    Button(role: .destructive) {
                        cancelDownload()
                    } label: {
                        SwiftUI.Label("Cancel Download", systemImage: "xmark.circle")
                    }
                }

                if dataset.downloadStatus == .completed || dataset.hasLocalStorage {
                    Divider()

                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        SwiftUI.Label("Delete Dataset", systemImage: "trash")
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(Palette.textSecondary)
            }
            .accessibilityLabel("Dataset actions")
        }
    }
    
    // MARK: - Download and Import

    private var downloadActions: DatasetDownloadActions {
        DatasetDownloadActions(
            dataset: dataset,
            modelContext: modelContext,
            downloadManager: downloadManager,
            setIngesting: { isIngesting = $0 },
            setIngestionProgress: { ingestionProgress = $0 },
            onImportError: { message in
                importError = message
                showImportError = true
            }
        )
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        downloadActions.handleImport(result)
    }

    // MARK: - Actions

    private func startDownload() {
        downloadActions.startDownload()
    }

    // Setting only the dataset status left the transfers running, and the
    // next sync tick flipped it back to downloading. Pause and resume the
    // tasks themselves. The engine has no per-dataset pause, so this pauses
    // every dataset (recorded in docs/status.md).
    private func pauseDownload() {
        downloadManager.pauseAll()
        dataset.pauseDownload()
    }

    // `resumeAll()` only lifts the queue pause; paused tasks need an explicit
    // resume to restart from their resume data.
    private func resumeDownload() {
        downloadManager.resumeAll()
        for task in downloadManager.tasks
        where task.datasetName == dataset.name && task.status == .paused {
            downloadManager.resumeTask(task.id)
        }
        dataset.startDownload()
    }

    private func cancelDownload() {
        dataset.pauseDownload()
        dataset.downloadedBytes = 0
        dataset.downloadedParts = 0
        dataset.statusRawValue = DownloadStatus.notStarted.rawValue
        
        // Cancel this dataset's unfinished parts. Completed parts are kept:
        // cancelTask deletes a completed part's zip from disk.
        let managerTasks = downloadManager.getTasksForDataset(dataset.name)
            .filter { $0.status != .completed }
        for task in managerTasks {
            downloadManager.cancelTask(task.id)
        }
    }

    private func browseSamples() {
        showSamples = true
    }
    
    private func ingestVideos() {
        if dataset.totalSamples > 0 {
            showReingestConfirmation = true
        } else {
            performIngestion(deleteFirst: false)
        }
    }
    
    private func performIngestion(deleteFirst: Bool) {
        Task {
            await MainActor.run {
                isIngesting = true
                ingestionProgress = "Starting ingestion..."
            }
            
            do {
                let ingestionService = VideoIngestionService(modelContext: modelContext)
                let datasetDir = dataset.storageDirectory
                
                // Define progress callback
                let onProgress: @Sendable (IngestionProgress) -> Void = { progress in
                    Task { @MainActor in
                        // Format: "Processing Category [Cat] (File N/M) - Category X/Y"
                        ingestionProgress = "Processing Category \(progress.currentCategory) (\(progress.filesProcessedInCategory)/\(progress.totalFilesInCategory)) - Category \(progress.categoriesProcessed + 1)/\(progress.totalCategories)"
                    }
                }
                
                if deleteFirst {
                     await MainActor.run {
                        ingestionProgress = "Deleting existing samples..."
                    }
                    try await ingestionService.deleteSamples(for: dataset.name)
                }
                
                let result = try await ingestionService.ingestDataset(
                    name: dataset.name,
                    type: DatasetType(rawValue: dataset.typeRawValue) ?? .include,
                    directory: datasetDir,
                    onProgress: onProgress
                )
                
                await MainActor.run {
                    isIngesting = false
                    ingestionProgress = "Completed: \(result.samplesCreated) samples, \(result.labelsCreated) labels"
                    // Update dataset count immediately
                    dataset.totalSamples = result.samplesCreated
                }
                
                print("[DetailColumnView] Ingestion complete: \(result.samplesCreated) samples")
                if !result.errors.isEmpty {
                    print("[DetailColumnView] Errors: \(result.errors.count)")
                }
                
                // Clear progress message after 3 seconds
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                await MainActor.run {
                    ingestionProgress = ""
                }
                
            } catch {
                await MainActor.run {
                    isIngesting = false
                    ingestionProgress = "Failed: \(error.localizedDescription)"
                }
                print("[DetailColumnView] Ingestion failed: \(error)")
            }
        }
    }

    private func viewInFiles() {
        #if os(iOS)
        // Open the Files app to the dataset directory
        let url = dataset.storageDirectory
        if FileManager.default.fileExists(atPath: url.path) {
            UIApplication.shared.open(url)
        }
        #endif
    }

    private func deleteDataset() {
        // Delete local files
        if dataset.hasLocalStorage {
            try? FileManager.default.removeItem(at: dataset.storageDirectory)
        }

        // Reset dataset to not started state
        dataset.statusRawValue = DownloadStatus.notStarted.rawValue
        dataset.downloadedBytes = 0
        dataset.downloadedParts = 0
        dataset.downloadedSamples = 0
        dataset.downloadStartedAt = nil
        dataset.downloadCompletedAt = nil
        dataset.lastError = nil
    }
}

// MARK: - Sample Row View

/// Row displaying a video sample.
struct SampleRowView: View {
    let sample: VideoSample

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(sample.displayTitle)
                .font(.subheadline.weight(.medium))

            Text(sample.localPath)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if !sample.labels.isEmpty {
                labelBadges
            }
        }
        .padding(.vertical, 4)
    }

    private var labelBadges: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(sample.labels) { label in
                    Text(label.name)
                        .font(.caption2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(Color(label.type.colorName).opacity(0.2))
                        )
                        .foregroundStyle(Color(label.type.colorName))
                }
            }
        }
    }
}

// MARK: - Download Detail View

/// Detail view for the Downloads section.
struct DownloadDetailView: View {
    @Environment(DownloadManager.self) private var downloadManager

    var body: some View {
        if downloadManager.totalCount == 0 {
            EmptyDetailView(
                title: "No Active Downloads",
                systemImage: "arrow.down.circle",
                description: "Start downloading a dataset to track progress here."
            )
        } else {
            List {
                Section("Overview") {
                    LabeledContent("Total Tasks", value: "\(downloadManager.totalCount)")
                    LabeledContent("Active", value: "\(downloadManager.activeCount)")
                    LabeledContent("Completed", value: "\(downloadManager.completedCount)")
                    LabeledContent("Failed", value: "\(downloadManager.failedCount)")
                    LabeledContent("Pending", value: "\(downloadManager.pendingCount)")
                }

                Section("Progress") {
                    VStack(alignment: .leading, spacing: 8) {
                        ProgressView(value: downloadManager.overallProgress)
                            .progressViewStyle(.linear)

                        HStack {
                            Text("\(downloadManager.progressPercentage)%")
                                .font(.caption.monospacedDigit())

                            Spacer()

                            Text(downloadManager.bytesProgressText)
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if downloadManager.failedCount > 0 {
                    Section {
                        Button {
                            Task {
                                await downloadManager.retryFailed()
                            }
                        } label: {
                            SwiftUI.Label("Retry Failed Downloads", systemImage: "arrow.clockwise")
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Downloads")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            #endif
        }
    }
}

// MARK: - Placeholder Detail Views

/// Detail view for Training section showing the full dashboard
struct TrainingDetailPlaceholder: View {
    var body: some View {
        TrainingDashboardView()
    }
}

/// Settings detail view with debugging and reset options.
struct SettingsDetailPlaceholder: View {
    @Environment(DownloadManager.self) private var downloadManager
    @Environment(\.modelContext) private var modelContext
    @State private var showResetConfirmation = false
    @State private var showClearDataConfirmation = false
    @State private var isResetting = false
    
    var body: some View {
        List {
            // MARK: - Download Settings
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Active Downloads: \(downloadManager.activeCount)")
                    Text("Pending: \(downloadManager.pendingCount)")
                    Text("Completed: \(downloadManager.completedCount)")
                    Text("Failed: \(downloadManager.failedCount)")
                    Text("Total: \(downloadManager.totalCount)")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            } header: {
                SwiftUI.Label("Download Status", systemImage: "arrow.down.circle")
            }
            
            // MARK: - Debug Actions
            Section {
                Button(role: .destructive) {
                    showResetConfirmation = true
                } label: {
                    SwiftUI.Label("Reset Download Queue", systemImage: "arrow.counterclockwise")
                }
                .disabled(isResetting)
                
                Button(role: .destructive) {
                    showClearDataConfirmation = true
                } label: {
                    SwiftUI.Label("Clear All App Data", systemImage: "trash")
                }
                .disabled(isResetting)
            } header: {
                SwiftUI.Label("Debug Actions", systemImage: "hammer")
            } footer: {
                Text("These actions are for testing purposes. Reset Download Queue clears all download tasks. Clear All App Data removes everything including downloaded files.")
            }
            
            // MARK: - App Info
            Section {
                LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                LabeledContent("Build", value: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1")
            } header: {
                SwiftUI.Label("App Info", systemImage: "info.circle")
            }
        }
        .navigationTitle("Settings")
        .confirmationDialog(
            "Reset Download Queue?",
            isPresented: $showResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Reset Downloads", role: .destructive) {
                resetDownloads()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will cancel all downloads and clear the download queue. You'll need to start downloads again.")
        }
        .confirmationDialog(
            "Clear All App Data?",
            isPresented: $showClearDataConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear All Data", role: .destructive) {
                clearAllData()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove all downloaded files, clear the database, and reset the app to a fresh state.")
        }
        .overlay {
            if isResetting {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .overlay {
                        ProgressView("Resetting...")
                            .padding()
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    }
            }
        }
    }
    
    private func resetDownloads() {
        isResetting = true
        Task {
            // Cancel all downloads and clear queue
            await downloadManager.cancelAll()
            
            await MainActor.run {
                // Reset SwiftData state
                do {
                    let descriptor = FetchDescriptor<Dataset>()
                    let datasets = try modelContext.fetch(descriptor)
                    for dataset in datasets {
                        dataset.resetDownload()
                    }
                    try modelContext.save()
                    print("[Settings] Reset \(datasets.count) datasets in SwiftData")
                } catch {
                    print("[Settings] Failed to reset datasets: \(error)")
                }
                
                isResetting = false
            }
            
            print("[Settings] Download queue reset complete")
        }
    }
    
    private func clearAllData() {
        isResetting = true
        Task {
            // Cancel all downloads
            await downloadManager.cancelAll()
            
            // Clear download files directory
            let fileManager = FileManager.default
            if let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
                let downloadsPath = documentsPath.appendingPathComponent("Downloads")
                try? fileManager.removeItem(at: downloadsPath)
                print("[Settings] Cleared downloads directory")
            }
            
            // Clear persistence state (Documents/download_state.json)
            if let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
                let statePath = documentsPath.appendingPathComponent("download_state.json")
                try? fileManager.removeItem(at: statePath)
                print("[Settings] Cleared persistence state")
                
                // Also clear backups
                let backupPath = documentsPath.appendingPathComponent("download_state.backup.json")
                try? fileManager.removeItem(at: backupPath)
            }
            
            await MainActor.run {
                // Clear SwiftData state
                do {
                    try modelContext.delete(model: Dataset.self)
                    try modelContext.save()
                    print("[Settings] Deleted all datasets from SwiftData")
                } catch {
                    print("[Settings] Failed to delete datasets: \(error)")
                }
                
                isResetting = false
            }
            
            print("[Settings] All data cleared - you may need to restart the app")
        }
    }
}

// MARK: - Previews

#Preview("Detail - Not Started") {
    NavigationStack {
        DatasetDetailView(dataset: .previewIncludeNotStarted)
    }
    .modelContainer(PersistenceController.preview.container)
    .environment(DownloadManager())
}

#Preview("Detail - Downloading") {
    NavigationStack {
        DatasetDetailView(dataset: .previewIncludeDownloading)
    }
    .modelContainer(PersistenceController.preview.container)
    .environment(DownloadManager())
}

#Preview("Detail - Completed") {
    NavigationStack {
        DatasetDetailView(dataset: .previewIncludeCompleted)
    }
    .modelContainer(PersistenceController.preview.container)
    .environment(DownloadManager())
}

#Preview("Detail - Paused") {
    NavigationStack {
        DatasetDetailView(dataset: .previewPaused)
    }
    .modelContainer(PersistenceController.preview.container)
    .environment(DownloadManager())
}

#Preview("Detail - Failed") {
    NavigationStack {
        DatasetDetailView(dataset: .previewFailed)
    }
    .modelContainer(PersistenceController.preview.container)
    .environment(DownloadManager())
}

#Preview("Detail - No Dataset Selected") {
    NavigationStack {
        DetailColumnView(
            selectedSection: .datasets,
            selectedDataset: .constant(nil)
        )
    }
    .modelContainer(PersistenceController.preview.container)
    .environment(DownloadManager())
}

#Preview("Detail - Downloads") {
    NavigationStack {
        DetailColumnView(
            selectedSection: .downloads,
            selectedDataset: .constant(nil)
        )
    }
    .modelContainer(PersistenceController.preview.container)
    .environment(DownloadManager())
}

#Preview("Detail - Training") {
    NavigationStack {
        DetailColumnView(
            selectedSection: .training,
            selectedDataset: .constant(nil)
        )
    }
    .modelContainer(PersistenceController.preview.container)
    .environment(DownloadManager())
}
