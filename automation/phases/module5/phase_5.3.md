# Phase 5.3 — Extraction UI and Integration

Create UI for extraction/ingestion progress and integrate with download flow.

## Context

We have:
- ZipExtractor and ExtractionCoordinator
- VideoIngestionService
- Download system that completes with zip files

## Files to Create

### 1. Features/DatasetManager/Views/Components/ExtractionProgressView.swift

Progress view for extraction:

```swift
struct ExtractionProgressView: View {
    let tracker: ExtractionProgressTracker
    
    var body: some View {
        VStack(spacing: 16) {
            // Overall progress
            HStack {
                Image(systemName: "archivebox")
                    .foregroundStyle(.blue)
                Text("Extracting Files")
                    .font(.headline)
                Spacer()
                Text("\(Int(tracker.overallProgress * 100))%")
                    .font(.headline)
            }
            
            ProgressView(value: tracker.overallProgress)
                .tint(.blue)
            
            // Current category
            if let category = tracker.currentCategory {
                HStack {
                    Text("Category: \(category)")
                        .font(.subheadline)
                    Spacer()
                    Text("\(tracker.categoriesCompleted)/\(tracker.totalCategories)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            // Statistics
            HStack {
                StatBadge(title: "Files", value: "\(tracker.filesExtracted)")
                StatBadge(title: "Size", value: formattedSize(tracker.bytesExtracted))
            }
        }
        .padding()
        .background(.regularMaterial)
        .cornerRadius(12)
    }
}
```

### 2. Features/DatasetManager/Views/Components/IngestionProgressView.swift

Progress view for ingestion:

```swift
struct IngestionProgressView: View {
    let tracker: IngestionProgressTracker
    
    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Image(systemName: "square.and.arrow.down.on.square")
                    .foregroundStyle(.green)
                Text("Importing Videos")
                    .font(.headline)
                Spacer()
                Text("\(Int(tracker.progress * 100))%")
                    .font(.headline)
            }
            
            ProgressView(value: tracker.progress)
                .tint(.green)
            
            // Current status
            if let category = tracker.currentCategory {
                Text("Processing: \(category)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            // Statistics
            HStack {
                StatBadge(title: "Videos", value: "\(tracker.filesProcessed)")
                StatBadge(title: "Samples", value: "\(tracker.samplesCreated)")
            }
            
            // Errors (if any)
            if !tracker.errors.isEmpty {
                DisclosureGroup("Errors (\(tracker.errors.count))") {
                    ForEach(tracker.errors, id: \.self) { error in
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
        }
        .padding()
        .background(.regularMaterial)
        .cornerRadius(12)
    }
}
```

### 3. Features/DatasetManager/Views/Components/DatasetProcessingView.swift

Combined view showing full pipeline progress:

```swift
struct DatasetProcessingView: View {
    @ObservedObject var processor: DatasetProcessor
    
    var body: some View {
        VStack(spacing: 20) {
            // Pipeline steps
            ProcessingStepRow(
                step: .download,
                status: processor.downloadStatus,
                progress: processor.downloadProgress
            )
            
            ProcessingStepRow(
                step: .extract,
                status: processor.extractionStatus,
                progress: processor.extractionProgress
            )
            
            ProcessingStepRow(
                step: .ingest,
                status: processor.ingestionStatus,
                progress: processor.ingestionProgress
            )
            
            Divider()
            
            // Overall status
            HStack {
                Text(processor.statusMessage)
                    .font(.subheadline)
                Spacer()
                if processor.isProcessing {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }
            
            // Action buttons
            if processor.canCancel {
                Button("Cancel", role: .destructive) {
                    processor.cancel()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
    }
}

struct ProcessingStepRow: View {
    enum Step: String {
        case download = "Download"
        case extract = "Extract"
        case ingest = "Import"
        
        var icon: String {
            switch self {
            case .download: return "arrow.down.circle"
            case .extract: return "archivebox"
            case .ingest: return "square.and.arrow.down.on.square"
            }
        }
    }
    
    let step: Step
    let status: ProcessingStatus
    let progress: Double
    
    var body: some View {
        HStack(spacing: 12) {
            // Status icon
            Image(systemName: statusIcon)
                .foregroundStyle(statusColor)
                .frame(width: 24)
            
            // Step name
            Text(step.rawValue)
                .font(.subheadline)
            
            Spacer()
            
            // Progress or status
            if status == .inProgress {
                ProgressView(value: progress)
                    .frame(width: 100)
                Text("\(Int(progress * 100))%")
                    .font(.caption)
                    .monospacedDigit()
            } else {
                Text(status.displayText)
                    .font(.caption)
                    .foregroundStyle(statusColor)
            }
        }
    }
}

enum ProcessingStatus {
    case pending, inProgress, completed, failed, skipped
    
    var displayText: String {
        switch self {
        case .pending: return "Pending"
        case .inProgress: return "In Progress"
        case .completed: return "Complete"
        case .failed: return "Failed"
        case .skipped: return "Skipped"
        }
    }
}
```

### 4. Features/DatasetManager/Processing/DatasetProcessor.swift

Orchestrates entire download → extract → ingest pipeline:

```swift
@Observable
class DatasetProcessor {
    private let downloadManager: DownloadManager
    private let extractionCoordinator: ExtractionCoordinator
    private let ingestionService: VideoIngestionService
    
    // Status for each phase
    private(set) var downloadStatus: ProcessingStatus = .pending
    private(set) var extractionStatus: ProcessingStatus = .pending
    private(set) var ingestionStatus: ProcessingStatus = .pending
    
    // Progress for each phase
    private(set) var downloadProgress: Double = 0
    private(set) var extractionProgress: Double = 0
    private(set) var ingestionProgress: Double = 0
    
    // Overall state
    private(set) var isProcessing = false
    private(set) var statusMessage = ""
    var canCancel: Bool { isProcessing }
    
    // Process a dataset from start to finish
    func processDataset(_ dataset: Dataset) async throws {
        isProcessing = true
        
        do {
            // Phase 1: Download
            downloadStatus = .inProgress
            statusMessage = "Downloading dataset files..."
            try await downloadPhase(dataset)
            downloadStatus = .completed
            
            // Phase 2: Extract
            extractionStatus = .inProgress
            statusMessage = "Extracting zip files..."
            try await extractionPhase(dataset)
            extractionStatus = .completed
            
            // Phase 3: Ingest
            ingestionStatus = .inProgress
            statusMessage = "Importing videos..."
            try await ingestionPhase(dataset)
            ingestionStatus = .completed
            
            // Complete
            statusMessage = "Dataset ready!"
            dataset.completeDownload()
            
        } catch {
            statusMessage = "Error: \(error.localizedDescription)"
            throw error
        }
        
        isProcessing = false
    }
    
    private func downloadPhase(_ dataset: Dataset) async throws {
        await downloadManager.loadManifest(for: dataset.type)
        await downloadManager.startDownloads()
        
        // Wait for completion, updating progress
        for await progress in downloadManager.progressStream {
            downloadProgress = progress
        }
    }
    
    private func extractionPhase(_ dataset: Dataset) async throws {
        let zipFiles = downloadManager.completedFileURLs
        
        let result = try await extractionCoordinator.extractDataset(
            datasetName: dataset.name,
            downloadedFiles: zipFiles
        )
        
        extractionProgress = 1.0
    }
    
    private func ingestionPhase(_ dataset: Dataset) async throws {
        let datasetDirectory = FileManager.default.datasetsDirectory
            .appendingPathComponent(dataset.name)
        
        let result = try await ingestionService.ingestDataset(
            name: dataset.name,
            type: dataset.type,
            directory: datasetDirectory
        )
        
        ingestionProgress = 1.0
        
        // Update dataset with counts
        dataset.sampleCount = result.samplesCreated
        dataset.labelCount = result.labelsCreated
    }
    
    func cancel() {
        // Cancel current phase
        Task {
            await downloadManager.cancelAllDownloads()
        }
        isProcessing = false
        statusMessage = "Cancelled"
    }
}
```

### 5. Update DatasetDetailView

Integrate processor:

```swift
struct DatasetDetailView: View {
    @Bindable var dataset: Dataset
    @Environment(\.modelContext) private var modelContext
    @State private var processor: DatasetProcessor?
    @State private var showingProcessingSheet = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                DatasetHeaderSection(dataset: dataset)
                
                // Show processing view if active
                if let processor = processor, processor.isProcessing {
                    DatasetProcessingView(processor: processor)
                } else {
                    DatasetStatsSection(dataset: dataset)
                    DatasetActionsSection(
                        dataset: dataset,
                        onDownload: startProcessing,
                        onBrowse: browseSamples
                    )
                }
                
                if dataset.isReady {
                    DatasetCategoriesSection(dataset: dataset)
                }
            }
            .padding()
        }
        .navigationTitle(dataset.name)
    }
    
    private func startProcessing() {
        let newProcessor = DatasetProcessor(
            downloadManager: DownloadManager(),
            extractionCoordinator: ExtractionCoordinator(),
            ingestionService: VideoIngestionService(modelContext: modelContext)
        )
        processor = newProcessor
        
        Task {
            do {
                try await newProcessor.processDataset(dataset)
                try modelContext.save()
            } catch {
                // Handle error
            }
        }
    }
}
```

### 6. Features/DatasetManager/Views/Components/StatBadge.swift

Reusable stat badge:

```swift
struct StatBadge: View {
    let title: String
    let value: String
    var color: Color = .secondary
    
    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.headline)
                .foregroundStyle(color)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(8)
    }
}
```

### 7. Update Dataset Model

Add processing state:

```swift
extension Dataset {
    var processingState: ProcessingState {
        switch downloadStatus {
        case .notStarted:
            return .notStarted
        case .downloading:
            return .downloading
        case .processing:
            return .extracting // or .importing based on progress
        case .completed:
            return .ready
        case .failed:
            return .failed
        }
    }
    
    enum ProcessingState {
        case notStarted
        case downloading
        case extracting
        case importing
        case ready
        case failed
        
        var displayText: String { ... }
        var icon: String { ... }
    }
}
```

## Integration Flow

```
User taps "Download INCLUDE"
    │
    ▼
DatasetProcessor.processDataset()
    │
    ├─► Download Phase
    │   └─► Shows download progress
    │
    ├─► Extraction Phase
    │   └─► Shows extraction progress
    │
    ├─► Ingestion Phase
    │   └─► Shows import progress
    │
    ▼
Dataset.completeDownload()
    │
    ▼
UI shows "Ready" with sample browser
```

## Requirements

1. Show clear progress for each phase
2. Allow cancellation at any point
3. Handle errors gracefully
4. Update Dataset model throughout
5. Clean up on failure
6. Support background processing where possible
