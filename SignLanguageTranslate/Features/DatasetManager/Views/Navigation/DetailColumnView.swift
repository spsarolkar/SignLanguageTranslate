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
    let selectedDataset: Dataset?

    var body: some View {
        Group {
            switch selectedSection {
            case .datasets:
                datasetDetail
            case .downloads:
                DownloadDetailView()
            case .training:
                TrainingDetailPlaceholder()
            case .settings:
                SettingsDetailPlaceholder()
            case nil:
                EmptyDetailView()
            }
        }
    }

    @ViewBuilder
    private var datasetDetail: some View {
        if let dataset = selectedDataset {
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

    @State private var showDeleteConfirmation = false
    @State private var showFilesApp = false
    @State private var isImporting = false
    @State private var importError: String? = nil
    @State private var showImportError = false
    
    @State private var showSamples = false
    
    // Transient state for progress display
    @State private var currentSpeed: Double = 0
    @State private var timeRemaining: TimeInterval? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header with icon, name, status
                DatasetHeaderSection(dataset: dataset)

                // Statistics cards
                DatasetStatsSection(
                    dataset: dataset,
                    speed: currentSpeed,
                    timeRemaining: timeRemaining
                )

                // Actions (Download, Browse, Delete)
                DatasetActionsSection(
                    dataset: dataset,
                    currentSpeed: currentSpeed,
                    timeRemaining: timeRemaining,
                    onStartDownload: startDownload,
                    onPauseDownload: pauseDownload,
                    onResumeDownload: resumeDownload,
                    onCancelDownload: cancelDownload,
                    onBrowseSamples: browseSamples,
                    onViewInFiles: viewInFiles,
                    onDeleteDataset: { showDeleteConfirmation = true }
                )

                // Categories list (if downloaded)
                if dataset.isReady {
                    DatasetCategoriesSection(
                        dataset: dataset,
                        onCategorySelected: browseCategory
                    )
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(dataset.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        .toolbar {
            toolbarContent
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
        .onAppear {
            syncProgress()
        }
        .onChange(of: downloadManager.tasks) {
            syncProgress()
        }
        .onReceive(Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()) { _ in
            if dataset.downloadStatus.isActive {
                syncProgress()
            }
        }
        .overlay {
            if downloadManager.isImporting {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .overlay {
                        VStack(spacing: 16) {
                            ProgressView()
                                .controlSize(.large)
                                .tint(.white)
                            
                            Text(downloadManager.importStatus)
                                .font(.headline)
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.center)
                        }
                        .padding(32)
                        .background(.ultraThinMaterial)
                        .cornerRadius(16)
                    }
            }
        }
        .navigationDestination(isPresented: $showSamples) {
            DatasetSamplesView(dataset: dataset)
        }
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
        
        // Sync status roughly
        // If any task is downloading -> Downloading
        // If all completed -> Completed
        let isDownloading = tasks.contains { $0.status == .downloading }
        let isPaused = tasks.contains { $0.status == .paused } && !isDownloading
        let isFailed = tasks.contains { $0.status == .failed } && !isDownloading && !isPaused
        
        // Only update status if it differs significantly to avoid fighting with UI controls
        // But for Progress visualization, bytes/parts are key.
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

                if dataset.downloadStatus == .completed {
                    Divider()

                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        SwiftUI.Label("Delete Dataset", systemImage: "trash")
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }
    
    // MARK: - Import Handler
    
    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            
            // Access security scoped resource
            guard url.startAccessingSecurityScopedResource() else {
                importError = "Permission denied to access the file."
                showImportError = true
                return
            }
            
            Task {
                defer { url.stopAccessingSecurityScopedResource() }
                do {
                    try await downloadManager.importFromLocalZip(url: url)
                    await MainActor.run {
                        // Refresh UI if needed, though manager updates should propagate
                    }
                } catch {
                    await MainActor.run {
                        importError = error.localizedDescription
                        showImportError = true
                    }
                }
            }
            
        case .failure(let error):
            importError = error.localizedDescription
            showImportError = true
        }
    }

    // MARK: - Actions

    private func startDownload() {
        dataset.startDownload()
        try? modelContext.save()
        
        // Load manifest and start downloads via the engine
        Task {
            await downloadManager.loadINCLUDEManifest(datasetName: dataset.name)
            await downloadManager.startDownloads()
        }
    }

    private func pauseDownload() {
        dataset.pauseDownload()
    }

    private func resumeDownload() {
        dataset.startDownload()
    }

    private func cancelDownload() {
        dataset.pauseDownload()
        dataset.downloadedBytes = 0
        dataset.downloadedParts = 0
        dataset.statusRawValue = DownloadStatus.notStarted.rawValue
    }

    private func browseSamples() {
        showSamples = true
    }

    private func browseCategory(_ label: Label) {
        // Navigate to category browser (to be implemented)
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

/// Placeholder detail view for Training section.
struct TrainingDetailPlaceholder: View {
    var body: some View {
        EmptyDetailView(
            title: "Training Models",
            systemImage: "brain.head.profile",
            description: "Select a training configuration to view details and start training."
        )
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
            selectedDataset: nil
        )
    }
    .modelContainer(PersistenceController.preview.container)
    .environment(DownloadManager())
}

#Preview("Detail - Downloads") {
    NavigationStack {
        DetailColumnView(
            selectedSection: .downloads,
            selectedDataset: nil
        )
    }
    .modelContainer(PersistenceController.preview.container)
    .environment(DownloadManager())
}

#Preview("Detail - Training") {
    NavigationStack {
        DetailColumnView(
            selectedSection: .training,
            selectedDataset: nil
        )
    }
    .modelContainer(PersistenceController.preview.container)
    .environment(DownloadManager())
}
