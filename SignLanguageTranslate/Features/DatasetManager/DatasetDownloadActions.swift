import Foundation
import SwiftData

/// Start-download and zip-import actions for one dataset.
///
/// Shared by `DatasetDetailView` and the first-run screen. Moved from
/// `DatasetDetailView`; view state is updated through the callbacks.
@MainActor
struct DatasetDownloadActions {
    let dataset: Dataset
    let modelContext: ModelContext
    let downloadManager: DownloadManager

    /// Called with `true` when extraction/ingestion starts and `false` when it ends.
    var setIngesting: (Bool) -> Void = { _ in }
    /// Called with a human-readable ingestion progress line ("" clears it).
    var setIngestionProgress: (String) -> Void = { _ in }
    /// Called with a message when an import fails.
    var onImportError: (String) -> Void = { _ in }

    // MARK: - Download

    func startDownload() {
        dataset.startDownload()
        try? modelContext.save()

        // Load manifest and start downloads via the engine
        Task {
            await downloadManager.loadINCLUDEManifest(datasetName: dataset.name)
            await downloadManager.startDownloads()
        }
    }

    // MARK: - Import

    func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }

            // Access security scoped resource
            guard url.startAccessingSecurityScopedResource() else {
                onImportError("Permission denied to access the file.")
                return
            }

            Task {
                defer { url.stopAccessingSecurityScopedResource() }
                do {
                    // Start download tracking if not present so tasks exist for the zip importer
                    if downloadManager.getTasksForDataset(dataset.name).isEmpty {
                        await downloadManager.loadINCLUDEManifest(datasetName: dataset.name)
                        dataset.startDownload()
                        try? modelContext.save()
                    }

                    try await downloadManager.importFromLocalZip(url: url)
                    await MainActor.run {
                        // Refresh UI if needed, though manager updates should propagate
                        // Ensure it's not paused so it detects completion
                        if dataset.downloadStatus == .paused || dataset.downloadStatus == .notStarted {
                            dataset.startDownload()
                        }


                        // Automatically ingest videos to populate the Data Pipeline dataset tables
                        performExtractionAndIngestion()
                    }
                } catch {
                    await MainActor.run {
                        onImportError(error.localizedDescription)
                    }
                }
            }

        case .failure(let error):
            onImportError(error.localizedDescription)
        }
    }

    /// Maps part filenames ("Adjectives_1of8.zip") to downloaded files, which
    /// are stored as "<task UUID>_<filename>". Only this dataset's parts are
    /// included. (Previously this required the dataset name in the filename,
    /// which no INCLUDE part has, so nothing was extracted after an import.)
    nonisolated static func partFileMapping(files: [URL], partNames: Set<String>) -> [String: URL] {
        var mapping: [String: URL] = [:]
        for file in files {
            let name = originalFilename(file.lastPathComponent)
            if partNames.contains(name) {
                mapping[name] = file
            }
        }
        return mapping
    }

    /// Strips the "<36-char UUID>_" prefix a completed download is stored with.
    nonisolated static func originalFilename(_ filename: String) -> String {
        guard filename.count > 37,
              let underscoreIndex = filename.index(filename.startIndex, offsetBy: 36, limitedBy: filename.endIndex),
              filename[underscoreIndex] == "_" else {
            return filename
        }
        return String(filename[filename.index(after: underscoreIndex)...])
    }

    private func performExtractionAndIngestion() {
        Task {
            await MainActor.run {
                setIngesting(true)
                setIngestionProgress("Starting extraction...")
            }

            do {
                // 1. Find Downloaded ZIP Files
                let fileManager = DownloadFileManager()
                let dir = fileManager.completedDownloadsDirectory
                let contents = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
                let downloadedFiles = (contents ?? []).filter { $0.pathExtension.lowercased() == "zip" }

                if !downloadedFiles.isEmpty {
                    let partNames = Set(downloadManager.getTasksForDataset(dataset.name).map(\.filename))
                    let fileMapping = Self.partFileMapping(files: downloadedFiles, partNames: partNames)

                    if !fileMapping.isEmpty {
                        // 2. Extract
                        let coordinator = ExtractionCoordinator()
                        _ = try await coordinator.extractDatasetWithMapping(
                            datasetName: dataset.name,
                            fileMapping: fileMapping,
                            progressHandler: nil
                        )
                    }
                }

                // 3. Ingest
                await MainActor.run {
                    setIngestionProgress("Starting ingestion...")
                }

                let ingestionService = VideoIngestionService(modelContext: modelContext)
                let datasetDir = dataset.storageDirectory

                let setIngestionProgress = self.setIngestionProgress
                let onProgress: @Sendable (IngestionProgress) -> Void = { progress in
                    Task { @MainActor in
                        setIngestionProgress("Processing (\(progress.filesProcessedInCategory)/\(progress.totalFilesInCategory))")
                    }
                }

                let result = try await ingestionService.ingestDataset(
                    name: dataset.name,
                    type: DatasetType(rawValue: dataset.typeRawValue) ?? .include,
                    directory: datasetDir,
                    onProgress: onProgress
                )

                await MainActor.run {
                    setIngesting(false)
                    setIngestionProgress("Completed: \(result.samplesCreated) samples")
                    dataset.totalSamples = result.samplesCreated
                }

                try? await Task.sleep(nanoseconds: 3_000_000_000)
                await MainActor.run {
                    setIngestionProgress("")
                }

            } catch {
                await MainActor.run {
                    setIngesting(false)
                    setIngestionProgress("Failed: \(error.localizedDescription)")
                }
                print("[DetailColumnView] Extraction/Ingestion failed: \(error)")
            }
        }
    }
}
