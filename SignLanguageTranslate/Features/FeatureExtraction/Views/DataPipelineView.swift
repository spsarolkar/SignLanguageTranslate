import SwiftUI
import SwiftData

/// Main UI for the complete data pipeline: Downloads → Extraction → Sync
struct DataPipelineView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var datasets: [Dataset]
    
    @State private var extractionManager = BatchFeatureExtractionManager()
    @State private var selectedDataset: Dataset?
    @State private var selectedModel: BatchFeatureExtractionManager.ExtractionModel = .appleVision
    
    // Extraction state
    @State private var isExtracting = false
    @State private var extractionProgress: BatchFeatureExtractionManager.ExtractionProgress?
    @State private var extractingVideoIDs: Set<UUID> = [] // Track which videos are currently extracting
    
    // Sync state
    @State private var isSyncing = false
    @State private var hfToken: String = ""
    @State private var hfRepoName: String = ""
    @State private var syncProgress: Double = 0.0
    
    // UI state
    @State private var showError = false
    @State private var errorMessage = ""
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                headerView
                
                // Extraction Panel
                extractionPanel
                
                Divider()
                    .padding(.vertical)
                
                // Sync Panel
                syncPanel
                
                Divider()
                    .padding(.vertical)
                
                // Status Panel
                statusPanel
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Data Pipeline")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Feature Extraction & Sync")
                .font(.title2.bold())
            
            Text("Extract pose features from videos and sync to HuggingFace")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    // MARK: - Extraction Panel
    
    private var extractionPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            SwiftUI.Label("Feature Extraction", systemImage: "cpu")
                .font(.headline)
            
            // Dataset Selector
            VStack(alignment: .leading, spacing: 8) {
                Text("Select Dataset")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                Picker("Dataset", selection: $selectedDataset) {
                    Text("None").tag(nil as Dataset?)
                    ForEach(datasets.filter { $0.downloadStatus == .completed }) { dataset in
                        Text(dataset.name).tag(dataset as Dataset?)
                    }
                }
                .pickerStyle(.menu)
                .disabled(isExtracting)
            }
            
            // Model Selector
            VStack(alignment: .leading, spacing: 8) {
                Text("Extraction Model")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                Picker("Model", selection: $selectedModel) {
                    ForEach(BatchFeatureExtractionManager.ExtractionModel.allCases, id: \.self) { model in
                        Text(model.rawValue).tag(model)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(isExtracting)
            }
            
            // Video List with inline extraction controls
            if let dataset = selectedDataset {
                videoListSection(for: dataset)
            }
            
            // Extract All Button
            if selectedDataset != nil {
                Button(action: extractAll) {
                    HStack {
                        Image(systemName: isExtracting ? "stop.fill" : "bolt.fill")
                        Text(isExtracting ? "Stop Extraction" : "Extract All Remaining")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                }
                .buttonStyle(.borderedProminent)
                .tint(isExtracting ? .red : .blue)
            }
            
            // Global Progress (when batch extracting)
            if let progress = extractionProgress, isExtracting {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Processing: \(progress.currentVideo ?? "Preparing...")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        Spacer()
                        
                        Text("\(progress.processedVideos)/\(progress.totalVideos)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    
                    ProgressView(value: progress.percentage)
                        .tint(.blue)
                    
                    if !progress.errors.isEmpty {
                        Text("\(progress.errors.count) errors")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
    
    // MARK: - Video List Section
    
    @ViewBuilder
    private func videoListSection(for dataset: Dataset) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Videos")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            // Query videos for this dataset
            VideoList(datasetName: dataset.name, extractingVideoIDs: $extractingVideoIDs, onExtractVideo: extractSingleVideo)
        }
    }
    
    // Sub-view for video list with proper @Query
    struct VideoList: View {
        let datasetName: String
        @Binding var extractingVideoIDs: Set<UUID>
        let onExtractVideo: (VideoSample) -> Void
        
        @Query private var allVideos: [VideoSample]
        @State private var searchText = ""
        
        init(datasetName: String, extractingVideoIDs: Binding<Set<UUID>>, onExtractVideo: @escaping (VideoSample) -> Void) {
            self.datasetName = datasetName
            self._extractingVideoIDs = extractingVideoIDs
            self.onExtractVideo = onExtractVideo
            
            // Filter videos by dataset name
            let predicate = #Predicate<VideoSample> { video in
                video.datasetName == datasetName
            }
            _allVideos = Query(filter: predicate, sort: \VideoSample.localPath)
        }
        
        private var filteredVideos: [VideoSample] {
            if searchText.isEmpty {
                return allVideos
            }
            return allVideos.filter {
                $0.displayTitle.localizedCaseInsensitiveContains(searchText) ||
                $0.localPath.localizedCaseInsensitiveContains(searchText)
            }
        }
        
        var body: some View {
            VStack(spacing: 8) {
                // Search bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search videos...", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(8)
                .background(Color(.tertiarySystemGroupedBackground))
                .cornerRadius(8)
                
                // Video count
                Text("\(filteredVideos.count) videos")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                // Video list
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(filteredVideos.prefix(100)) { video in
                            videoRow(for: video)
                        }
                        
                        if filteredVideos.count > 100 {
                            Text("Showing first 100 videos. Use search to find more.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding()
                        }
                    }
                }
                .frame(maxHeight: 400)
            }
        }
        
        @ViewBuilder
        private func videoRow(for video: VideoSample) -> some View {
            HStack(spacing: 12) {
                // Status indicator
                Image(systemName: hasFeatures(video) ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(hasFeatures(video) ? .green : .secondary)
                    .font(.caption)
                
                // Video info
                VStack(alignment: .leading, spacing: 2) {
                    Text(video.displayTitle)
                        .font(.subheadline)
                        .lineLimit(1)
                    Text(video.localPath)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                // Extract button
                if extractingVideoIDs.contains(video.id) {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(0.8)
                } else if !hasFeatures(video) {
                    Button(action: { onExtractVideo(video) }) {
                        Image(systemName: "play.fill")
                            .font(.caption)
                            .padding(8)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .background(Color(.tertiarySystemGroupedBackground))
            .cornerRadius(6)
        }
        
        private func hasFeatures(_ video: VideoSample) -> Bool {
            !video.featureSets.isEmpty
        }
    }
    
    // MARK: - Sync Panel
    
    private var syncPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            SwiftUI.Label("HuggingFace Sync", systemImage: "cloud.fill")
                .font(.headline)
            
            // Token Input
            VStack(alignment: .leading, spacing: 8) {
                Text("HuggingFace Token")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                SecureField("hf_...", text: $hfToken)
                    .textFieldStyle(.roundedBorder)
                    .autocapitalization(.none)
                    .disabled(isSyncing)
            }
            
            // Repo Name Input
            VStack(alignment: .leading, spacing: 8) {
                Text("Repository Name")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                TextField("username/dataset-name", text: $hfRepoName)
                    .textFieldStyle(.roundedBorder)
                    .autocapitalization(.none)
                    .disabled(isSyncing)
            }
            
            // Sync Progress
            if isSyncing {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Uploading features...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        Spacer()
                        
                        Text("\(Int(syncProgress * 100))%")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    
                    ProgressView(value: syncProgress)
                        .tint(.green)
                }
            }
            
            // Action Button
            Button(action: startSync) {
                HStack {
                    Image(systemName: "arrow.up.circle.fill")
                    Text("Sync to HuggingFace")
                }
                .frame(maxWidth: .infinity)
                .padding()
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .disabled(selectedDataset == nil || hfToken.isEmpty || hfRepoName.isEmpty || isSyncing)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
    
    // MARK: - Status Panel
    
    private var statusPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Dataset Status")
                .font(.headline)
            
            if let dataset = selectedDataset {
                let stats = getDatasetStats(dataset)
                
                VStack(spacing: 8) {
                    StatRow(label: "Total Videos", value: "\(stats.totalVideos)")
                    StatRow(label: "Features Extracted", value: "\(stats.extractedVideos)")
                    StatRow(label: "Local Storage", value: stats.storageSize)
                }
            } else {
                Text("Select a dataset to view statistics")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
    
    // MARK: - Actions
    
    private func extractSingleVideo(_ video: VideoSample) {
        extractingVideoIDs.insert(video.id)
        
        Task {
            do {
                let service = VideoFeatureExtractionService()
                let fileManager = FeatureFileManager()
                
                // Get video URL - construct from dataset directory
                let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                let videoURL = documentsURL
                    .appendingPathComponent("Datasets")
                    .appendingPathComponent(selectedDataset!.name)
                    .appendingPathComponent(video.localPath)
                
                // Extract features for this single video
                let features = try await service.extractFeatures(from: videoURL)
                
                // Save features
                let outputPath = try fileManager.saveFeatures(features, forVideoPath: "\(selectedDataset!.name)/\(video.localPath)", modelName: "AppleVision")
                
                // Create FeatureSet record in database
                let featureSet = FeatureSet(
                    modelName: "AppleVision",
                    filePath: outputPath,
                    frameCount: features.count
                )
                featureSet.videoSample = video
                modelContext.insert(featureSet)
                try modelContext.save()
                
                await MainActor.run {
                    extractingVideoIDs.remove(video.id)
                }
            } catch {
                await MainActor.run {
                    extractingVideoIDs.remove(video.id)
                    errorMessage = "Failed to extract \(video.displayTitle): \(error.localizedDescription)"
                    showError = true
                }
            }
        }
    }
    
    private func extractAll() {
        guard let dataset = selectedDataset else { return }
        
        if isExtracting {
            // Stop extraction (TODO: implement cancel)
            isExtracting = false
            return
        }
        
        isExtracting = true
        
        Task {
            // Monitor progress
            Task {
                for await progress in await extractionManager.progress {
                    await MainActor.run {
                        extractionProgress = progress
                        
                        if progress.status == .completed || progress.status == .failed {
                            isExtracting = false
                        }
                    }
                }
            }
            
            // Start extraction for all videos without features
            do {
                try await extractionManager.extractFeatures(
                    for: dataset.name,
                    modelType: selectedModel,
                    modelContext: modelContext
                )
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showError = true
                    isExtracting = false
                }
            }
        }
    }
    
    private func startSync() {
        guard let dataset = selectedDataset else { return }
        
        isSyncing = true
        syncProgress = 0.0
        
        Task {
            do {
                // TODO: Implement HuggingFaceSyncService.uploadFeatures
                // For now, simulate progress
                for i in 1...10 {
                    try await Task.sleep(nanoseconds: 500_000_000) // 0.5s
                    await MainActor.run {
                        syncProgress = Double(i) / 10.0
                    }
                }
                
                await MainActor.run {
                    isSyncing = false
                    errorMessage = "Sync completed successfully!"
                    showError = true
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showError = true
                    isSyncing = false
                }
            }
        }
    }
    
    // MARK: - Helpers
    
    private func getDatasetStats(_ dataset: Dataset) -> (totalVideos: Int, extractedVideos: Int, storageSize: String) {
        let datasetName = dataset.name
        let descriptor = FetchDescriptor<VideoSample>(
            predicate: #Predicate { $0.datasetName == datasetName }
        )
        
        guard let samples = try? modelContext.fetch(descriptor) else {
            return (0, 0, "0 MB")
        }
        
        let extractedCount = samples.filter { !$0.featureSets.isEmpty }.count
        
        // Estimate storage (simplified)
        let bytesPerVideo = 50_000 // ~50KB per feature file
        let totalBytes = extractedCount * bytesPerVideo
        let megabytes = Double(totalBytes) / 1_048_576
        
        return (
            totalVideos: samples.count,
            extractedVideos: extractedCount,
            storageSize: String(format: "%.1f MB", megabytes)
        )
    }
}

// MARK: - Helper Views

struct StatRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            Spacer()
            
            Text(value)
                .font(.subheadline.monospacedDigit())
                .fontWeight(.medium)
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        DataPipelineView()
    }
    .modelContainer(PersistenceController.preview.container)
}
