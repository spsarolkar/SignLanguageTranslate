import SwiftUI
import SwiftData
import AVKit

/// The detail workspace. Dataset/category/search selection lives in the middle pane.
struct DataPipelineView: View {
    @Bindable var navigation: NavigationState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @EnvironmentObject var batchService: BatchExtractionService

    private var selectedDataset: Dataset? { navigation.pipelineDataset }
    private var selectedVideo: VideoSample? { navigation.pipelineVideo }
    private var selectedCategory: String? { navigation.pipelineCategory }
    private var searchText: String { navigation.pipelineSearch }

    @State private var loadedFeatures: [FrameFeatures] = []
    @State private var isInspectorLoading = false
    @State private var extractingVideoIDs: Set<UUID> = []
    @State private var showSyncSheet = false
    @State private var showError = false
    @State private var errorMessage = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.section) {
                headerView
                if let dataset = selectedDataset {
                    extractionControls
                    VideoExtractionGrid(
                        datasetName: dataset.name,
                        categoryFilter: selectedCategory,
                        searchText: searchText,
                        selectedVideo: $navigation.pipelineVideo,
                        extractingVideoIDs: $extractingVideoIDs,
                        onExtract: extractSingleVideo
                    )
                } else {
                    emptyStateView
                }
            }
            .padding(horizontalSizeClass == .compact ? Spacing.xl : Spacing.pane)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Palette.ground)
        .navigationTitle("Pipeline")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if let progress = batchService.progress {
                ExtractionProgressOverlay(
                    progress: progress,
                    metrics: batchService.executionMetrics,
                    thermalState: batchService.thermalState,
                    debugInfo: batchService.backgroundDebugInfo,
                    onCancel: { batchService.cancel() }
                )
                .padding(Spacing.lg)
                .background(Palette.ground)
            }
        }
        .navigationDestination(item: $navigation.pipelineVideo) { video in
            VideoPlayerContent(
                video: video,
                features: loadedFeatures,
                isLoading: isInspectorLoading,
                onExtract: { extractSingleVideo(video) }
            )
            .navigationTitle(video.wordName ?? video.fileName)
            .navigationBarTitleDisplayMode(.inline)
        }
        .navigationDestination(isPresented: $navigation.pipelineAnalysisPresented) {
            if let dataset = selectedDataset {
                AnalysisDashboardView(dataset: dataset)
            }
        }
        .sheet(isPresented: $showSyncSheet) {
            SyncSettingsView(isPresented: $showSyncSheet, selectedDataset: selectedDataset)
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
        .onChange(of: selectedVideo) {
            loadedFeatures = []
            isInspectorLoading = false
            if let video = selectedVideo { loadFeatures(for: video) }
        }
    }

    private var headerView: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(alignment: .center, spacing: Spacing.md) {
                Text("Pipeline")
                    .font(Typo.largeTitle)
                    .tracking(Tracking.largeTitle)
                    .foregroundStyle(Palette.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: Spacing.sm)
                StatusBadge(
                    state: batchService.isExtracting ? (batchService.isPaused ? .queued : .active) : .idle,
                    text: batchService.isExtracting ? (batchService.isPaused ? "Paused" : "Extracting") : "Idle"
                )
            }
            if let dataset = selectedDataset {
                Text("\(dataset.name) / \(selectedCategory ?? "All categories")")
                    .font(Typo.caption)
                    .foregroundStyle(Palette.textTertiary)
                Text("\(dataset.totalSamples.formatted()) videos in dataset")
                    .font(Typo.monoCaption)
                    .foregroundStyle(Palette.textTertiary)
                if !searchText.isEmpty {
                    Text("Search: \(searchText)")
                        .font(Typo.caption)
                        .foregroundStyle(Palette.textSecondary)
                }
            }
        }
    }

    private var extractionControls: some View {
        Card(padding: Spacing.xl, radius: Radius.panel) {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("On-device extraction")
                        .font(Typo.title2)
                        .foregroundStyle(Palette.textPrimary)
                    Text("Apple Vision · 60 landmarks per frame")
                        .font(Typo.monoCaption)
                        .foregroundStyle(Palette.textTertiary)
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: Spacing.md) {
                        extractionButton
                        analysisButton
                        syncButton
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        extractionButton
                        HStack(spacing: Spacing.md) {
                            analysisButton
                            syncButton
                        }
                    }
                }
                Text("Extract body and hand keypoints, inspect clips, or sync your features.")
                    .font(Typo.caption)
                    .foregroundStyle(Palette.textTertiary)
            }
        }
    }

    @ViewBuilder
    private var extractionButton: some View {
        if batchService.isExtracting {
            SecondaryButton(
                title: batchService.isPaused ? "Resume extraction" : "Pause extraction",
                systemImage: batchService.isPaused ? "play.fill" : "pause.fill"
            ) {
                if batchService.isPaused { batchService.resume() } else { batchService.pause() }
            }
        } else {
            PrimaryButton(title: "Extract all", systemImage: "cpu", action: startBatchExtraction)
                .accessibilityLabel("Extract all videos with Apple Vision")
        }
    }

    private var analysisButton: some View {
        SecondaryButton(title: "Analyze", systemImage: "chart.xyaxis.line") {
            navigation.pipelineAnalysisPresented = true
        }
        .accessibilityLabel("Analyze selected dataset")
    }

    private var syncButton: some View {
        SecondaryButton(title: "Sync", systemImage: "arrow.triangle.2.circlepath") {
            showSyncSheet = true
        }
        .accessibilityLabel("Sync features to Hugging Face")
    }

    // MARK: - Batch Extraction
    
    private func startBatchExtraction() {
        guard let dataset = selectedDataset else { return }
        
        // Get all videos for this dataset
        let datasetName = dataset.name
        let descriptor = FetchDescriptor<VideoSample>(
            predicate: #Predicate { $0.datasetName == datasetName },
            sortBy: [SortDescriptor(\.localPath)]
        )
        
        guard let videos = try? modelContext.fetch(descriptor) else { return }
        
        // Start batch extraction
        batchService.extractAll(
            videos: videos,
            model: .appleVision,
            modelContext: modelContext
        )
    }
    
    // MARK: - Empty State

    private var emptyStateView: some View {
        EmptyDetailView(
            title: "Choose a Dataset",
            systemImage: "waveform.path.ecg",
            description: "Select a downloaded dataset in the middle column to extract and inspect its keypoints."
        )
    }

    private func loadFeatures(for video: VideoSample) {
        isInspectorLoading = true
        Task {
            let candidates = video.featureSets.sorted { ($0.frameCount > 0) && ($1.frameCount <= 0) }
            if let featureSet = candidates.first(where: { $0.modelName == "AppleVision" }) ?? candidates.first {
                do {
                    let features = try FeatureFileManager.shared.loadFeatures(at: featureSet.filePath)
                    await MainActor.run {
                        guard navigation.pipelineVideo?.id == video.id else { return }
                        self.loadedFeatures = features
                        self.isInspectorLoading = false
                    }
                } catch {
                    print("[DataPipelineView] Error loading features for \(video.fileName): \(error)")
                    await MainActor.run {
                        guard navigation.pipelineVideo?.id == video.id else { return }
                        isInspectorLoading = false
                        errorMessage = "Could not load keypoints for \(video.fileName). \(error.localizedDescription)"
                        showError = true
                    }
                }
            } else {
                await MainActor.run {
                    self.loadedFeatures = []
                    self.isInspectorLoading = false
                }
            }
        }
    }
    
    private func extractSingleVideo(_ video: VideoSample, model: BatchExtractionService.ExtractionModel = .appleVision) {
        extractingVideoIDs.insert(video.id)
        Task {
            do {
                let service = VideoFeatureExtractionService()
                let fileManager = FeatureFileManager()
                
                // Use direct absoluteURL from VideoSample
                let videoURL = video.absoluteURL
                
                // Check if file exists
                guard FileManager.default.fileExists(atPath: videoURL.path) else {
                    throw NSError(domain: "VideoExtraction", code: 404, userInfo: [
                        NSLocalizedDescriptionKey: "Video file not found at: \(videoURL.path)"
                    ])
                }
                
                // Extract features
                let features = try await service.extractFeatures(from: videoURL)
                let outputPath = try fileManager.saveFeatures(
                    features,
                    forVideoPath: video.localPath,
                    modelName: model.rawValue
                )
                
                let featureSet = FeatureSet(
                    modelName: model.rawValue,
                    filePath: outputPath,
                    frameCount: features.count
                )
                
                try await MainActor.run {
                    // Purge any existing corrupted or outdated feature sets for this model
                    let existingSets = video.featureSets.filter { $0.modelName == model.rawValue }
                    for oldSet in existingSets {
                        modelContext.delete(oldSet)
                        video.featureSets.removeAll(where: { $0.id == oldSet.id })
                    }
                    
                    featureSet.videoSample = video
                    modelContext.insert(featureSet)
                    video.featureSets.append(featureSet)
                    try modelContext.save()
                    
                    extractingVideoIDs.remove(video.id)
                    if selectedVideo?.id == video.id {
                        loadFeatures(for: video)
                    }
                }
            } catch {
                await MainActor.run {
                    extractingVideoIDs.remove(video.id)
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        }
    }
}

// MARK: - Video Extraction Grid

struct VideoExtractionGrid: View {
    let datasetName: String
    let categoryFilter: String?
    let searchText: String
    @Binding var selectedVideo: VideoSample?
    @Binding var extractingVideoIDs: Set<UUID>
    let onExtract: (VideoSample, BatchExtractionService.ExtractionModel) -> Void
    
    @Query private var videos: [VideoSample]
    
    init(datasetName: String, categoryFilter: String?, searchText: String, selectedVideo: Binding<VideoSample?>, extractingVideoIDs: Binding<Set<UUID>>, onExtract: @escaping (VideoSample, BatchExtractionService.ExtractionModel) -> Void) {
        self.datasetName = datasetName
        self.categoryFilter = categoryFilter
        self.searchText = searchText
        self._selectedVideo = selectedVideo
        self._extractingVideoIDs = extractingVideoIDs
        self.onExtract = onExtract
        
        let predicate = #Predicate<VideoSample> { $0.datasetName == datasetName }
        _videos = Query(filter: predicate, sort: \VideoSample.localPath)
    }
    
    var groupedVideos: [(category: String, videos: [VideoSample])] {
        let filtered = videos.filter { video in
            if !searchText.isEmpty {
                if !video.displayTitle.localizedCaseInsensitiveContains(searchText) { return false }
            }
            if let category = categoryFilter {
                if !video.hasLabel(named: category, type: .category) { return false }
            }
            return true
        }
        
        let grouped = Dictionary(grouping: filtered) { $0.categoryName ?? "Uncategorized" }
        return grouped.sorted { $0.key < $1.key }
            .map { (category: $0.key, videos: $0.value.sorted { $0.displayTitle < $1.displayTitle }) }
    }
    
    var body: some View {
        LazyVStack(spacing: Spacing.md, pinnedViews: [.sectionHeaders]) {
            if groupedVideos.isEmpty {
                ContentUnavailableView("No Matching Clips", systemImage: "film.stack",
                    description: Text("Change the category or search, or ingest videos for this dataset."))
                    .padding(.vertical, Spacing.xxl)
            }
            ForEach(groupedVideos, id: \.category) { group in
                Section {
                    // Single column list
                    ForEach(group.videos) { video in
                        VideoExtractionCard(
                            video: video,
                            isExtracting: extractingVideoIDs.contains(video.id),
                            isSelected: selectedVideo?.id == video.id,
                            onExtract: onExtract,
                            onSelect: { selectedVideo = video }
                        )
                    }
                } header: {
                    CategoryHeader(
                        title: group.category,
                        count: group.videos.count
                    )
                }
            }
        }
    }
}

// MARK: - Video Extraction Card

struct VideoExtractionCard: View {
    let video: VideoSample
    let isExtracting: Bool
    let isSelected: Bool
    let onExtract: (VideoSample, BatchExtractionService.ExtractionModel) -> Void
    let onSelect: () -> Void
    @State private var showDetails = false

    private var visionFeatures: FeatureSet? {
        let candidates = video.featureSets.filter { $0.modelName == "AppleVision" }
        return candidates.first(where: { $0.frameCount > 0 && $0.fileExists }) ?? candidates.first
    }

    private var needsReExtraction: Bool {
        guard let visionFeatures else { return false }
        return visionFeatures.frameCount <= 0 || !visionFeatures.fileExists
    }

    var body: some View {
        Card(variant: isSelected ? .selected : .standard) {
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack(spacing: Spacing.md) {
                    Button(action: onSelect) {
                        HStack(spacing: Spacing.md) {
                            Image(systemName: "film.stack")
                                .font(Typo.title2)
                                .foregroundStyle(Palette.accentBlue)
                                .frame(width: Metrics.touchTarget, height: Metrics.touchTarget)
                                .background(Palette.control, in: RoundedRectangle(cornerRadius: Radius.chip))
                            VStack(alignment: .leading, spacing: Spacing.xxs) {
                                Text(video.wordName ?? video.displayTitle)
                                    .font(Typo.headline)
                                    .foregroundStyle(Palette.textPrimary)
                                    .lineLimit(1)
                                Text(video.fileName)
                                    .font(Typo.monoCaption)
                                    .foregroundStyle(Palette.textSecondary)
                                    .lineLimit(1)
                                Text(video.formattedDuration)
                                    .font(Typo.monoSmall)
                                    .foregroundStyle(Palette.textTertiary)
                            }
                            Spacer(minLength: Spacing.xxs)
                        }
                        .frame(maxWidth: .infinity, minHeight: Metrics.touchTarget, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Inspect \(video.fileName), \(video.wordName ?? "unlabelled clip")")

                    IconButton(
                        systemImage: visionFeatures == nil ? "cpu" : "arrow.clockwise",
                        accessibilityLabel: "\(visionFeatures == nil ? "Extract" : "Re-extract") keypoints for \(video.fileName)",
                        tint: Palette.accent
                    ) { onExtract(video, .appleVision) }
                    .disabled(isExtracting)
                }
                HStack(spacing: Spacing.sm) {
                    StatusBadge(
                        state: isExtracting ? .active : (visionFeatures == nil || needsReExtraction ? .idle : .complete),
                        text: isExtracting ? "Extracting" : (needsReExtraction ? "Needs re-extraction" : (visionFeatures == nil ? "Not extracted" : "Vision ready"))
                    )
                    if isExtracting { ProgressView().tint(Palette.accent) }
                    Spacer(minLength: Spacing.xxs)
                    if let split = video.split {
                        Text(split.capitalized)
                            .font(Typo.caption2)
                            .foregroundStyle(Palette.textTertiary)
                    }
                }
                if needsReExtraction {
                    Text("No usable frames saved. Use Extract all or retry this clip.")
                        .font(Typo.caption)
                        .foregroundStyle(Palette.textSecondary)
                }
                if let featureSet = visionFeatures {
                    SecondaryButton(title: showDetails ? "Hide details" : "Feature details",
                                    systemImage: showDetails ? "chevron.up" : "chevron.down") {
                        showDetails.toggle()
                    }
                    if showDetails {
                        DetailRow(label: "Frames", value: featureSet.frameCount.formatted())
                        DetailRow(label: "Model", value: featureSet.modelName)
                    }
                }
            }
        }
    }
}

struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: Spacing.md) {
            Text(label).font(Typo.caption).foregroundStyle(Palette.textTertiary)
            Spacer(minLength: Spacing.sm)
            Text(value).font(Typo.monoCaption).foregroundStyle(Palette.textSecondary)
        }
    }
}

struct CategoryHeader: View {
    let title: String
    let count: Int

    var body: some View {
        SectionHeader(eyebrow: title) {
            Text("\(count.formatted()) clips")
                .font(Typo.monoCaption)
                .foregroundStyle(Palette.textTertiary)
        }
        .padding(.vertical, Spacing.md)
        .background(Palette.ground)
    }
}

// MARK: - Video Card

struct VideoCard: View {
    let video: VideoSample
    let isExtracting: Bool
    let isSelected: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.blue : Color.blue.opacity(0.1))
                    .frame(width: 48, height: 48)
                
                Image(systemName: "film.stack")
                    .font(.system(size: 20))
                    .foregroundStyle(isSelected ? .white : .blue)
            }
            
            // Content
            VStack(alignment: .leading, spacing: 4) {
                Text(video.displayTitle)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                
                HStack(spacing: 6) {
                    if let word = video.wordName {
                        Text(word)
                            .font(.caption2)
                            .foregroundStyle(.blue)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(4)
                    }
                    
                    Text(video.formattedDuration)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            
            Spacer(minLength: 8)
            
            // Status
            if isExtracting {
                ProgressView()
                    .scaleEffect(0.8)
            } else if !video.featureSets.isEmpty {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                    .font(.body)
            }
        }
        .padding(12)
        .background(isSelected ? Color.blue.opacity(0.1) : Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(isSelected ? Color.blue : Color.clear, lineWidth: 2)
        )
    }
}

// MARK: - Inspector Panel

struct InspectorPanel: View {
    let video: VideoSample?
    let features: [FrameFeatures]
    let isLoading: Bool
    let extractingIDs: Set<UUID>
    let onExtract: (VideoSample) -> Void
    
    var body: some View {
        Group {
            if let video = video {
                if !features.isEmpty {
                    extractedView(video: video)
                } else if isLoading || extractingIDs.contains(video.id) {
                    loadingView
                } else {
                    noFeaturesView(video: video)
                }
            } else {
                placeholderView
            }
        }
        .background(Color(.systemBackground))
    }
    
    private func extractedView(video: VideoSample) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                // Video Player
                VideoAnnotationPlayer(
                    videoURL: video.absoluteURL,
                    features: features
                )
                .frame(height: 400)
                .cornerRadius(12)
                .shadow(color: Color.black.opacity(0.1), radius: 8, y: 4)
                
                // Metadata
                VStack(spacing: 16) {
                    HStack {
                        Text("Video Details")
                            .font(.headline)
                        Spacer()
                    }
                    
                    MetadataRow(label: "Duration", value: video.formattedDuration)
                    MetadataRow(label: "File Size", value: video.formattedFileSize)
                    MetadataRow(label: "Keyframes", value: "\(features.count)")
                    if let first = features.first {
                        MetadataRow(label: "Model", value: first.sourceModel)
                    }
                }
                .padding()
                .background(Color(.secondarySystemGroupedBackground))
                .cornerRadius(12)
                
                // Re-extract Button
                Button(action: { onExtract(video) }) {
                    SwiftUI.Label("Re-extract Features", systemImage: "arrow.triangle.2.circlepath")
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .buttonStyle(.bordered)
            }
            .padding()
        }
    }
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Extracting Features...")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func noFeaturesView(video: VideoSample) -> some View {
        VStack(spacing: 24) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 60))
                .foregroundStyle(.blue)
            
            VStack(spacing: 8) {
                Text("No Features Extracted")
                    .font(.title3.bold())
                
                Text("Extract keypoint features from this video to enable training and analysis.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            
            Button(action: { onExtract(video) }) {
                SwiftUI.Label("Extract Features", systemImage: "cpu")
                    .frame(maxWidth: 200)
                    .padding()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var placeholderView: some View {
        ContentUnavailableView {
            SwiftUI.Label("Select a Video", systemImage: "hand.tap")
        } description: {
            Text("Choose a video from the list to view details and extract features.")
        }
    }
}

struct MetadataRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
        }
    }
}

// MARK: - Sync Settings View

struct SyncSettingsView: View {
    @Binding var isPresented: Bool
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Dataset.name) private var datasets: [Dataset]

    @StateObject private var syncManager = SyncManager()
    @StateObject private var legacyFixer = LegacyFeatureFixer()

    @State private var hfToken = ""
    @State private var repoId = ""
    @State private var selectedDataset: Dataset?
    @State private var showTokenHelp = false
    @State private var tokenSaved = false

    init(isPresented: Binding<Bool>, selectedDataset: Dataset? = nil) {
        self._isPresented = isPresented
        self._selectedDataset = State(initialValue: selectedDataset)
    }

    private var downloadedDatasets: [Dataset] {
        datasets.filter { $0.downloadStatus == .completed }
    }

    var body: some View {
        NavigationStack {
            Form {
                // Credentials Section
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "key.fill")
                                .foregroundStyle(.orange)
                            Text("HuggingFace Token")
                                .font(.subheadline.bold())
                            Spacer()
                            Button(action: { showTokenHelp = true }) {
                                Image(systemName: "questionmark.circle")
                                    .foregroundStyle(.secondary)
                            }
                        }

                        if syncManager.hasToken && hfToken.isEmpty {
                            HStack {
                                Image(systemName: "checkmark.shield.fill")
                                    .foregroundStyle(.green)
                                Text("Token saved securely")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button("Change") {
                                    syncManager.deleteToken()
                                    tokenSaved = false
                                }
                                .font(.caption)
                            }
                        } else {
                            SecureField("hf_xxxxxxxxxxxx", text: $hfToken)
                                .textFieldStyle(.roundedBorder)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)

                            if !hfToken.isEmpty {
                                Button(action: saveToken) {
                                    HStack {
                                        Image(systemName: "lock.shield")
                                        Text("Save to Keychain")
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "folder.fill")
                                .foregroundStyle(.blue)
                            Text("Repository ID")
                                .font(.subheadline.bold())
                        }

                        TextField("username/dataset-name", text: $repoId)
                            .textFieldStyle(.roundedBorder)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .onChange(of: repoId) { _, newValue in
                                syncManager.saveRepoId(newValue)
                            }

                        Text("e.g., your-username/sign-language-features")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("HuggingFace Hub Credentials")
                } footer: {
                    Text("Your token is stored securely in the iOS Keychain.")
                }

                // Dataset Selection
                Section("Select Dataset to Sync") {
                    if downloadedDatasets.isEmpty {
                        HStack {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundStyle(.orange)
                            Text("No datasets available. Download a dataset first.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        ForEach(downloadedDatasets) { dataset in
                            DatasetSyncRow(
                                dataset: dataset,
                                isSelected: selectedDataset?.id == dataset.id,
                                onSelect: { selectedDataset = dataset }
                            )
                        }
                    }
                }

                // Sync Status
                if let progress = syncManager.syncProgress {
                    Section("Sync Progress") {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                switch progress.status {
                                case .preparing:
                                    ProgressView()
                                        .scaleEffect(0.8)
                                    Text("Preparing...")
                                case .uploading:
                                    ProgressView()
                                        .scaleEffect(0.8)
                                    Text("Uploading features...")
                                case .uploadingMetadata:
                                    ProgressView()
                                        .scaleEffect(0.8)
                                    Text("Uploading metadata...")
                                case .completed:
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                    Text("Sync completed!")
                                case .failed(let error):
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.red)
                                    Text("Failed: \(error)")
                                        .lineLimit(2)
                                }
                                Spacer()
                            }
                            .font(.subheadline)

                            if progress.totalFiles > 0 {
                                ProgressView(value: progress.percentage)
                                    .tint(.blue)

                                Text("\(progress.uploadedFiles) / \(progress.totalFiles) files")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                // Last Sync Info
                if let lastSync = syncManager.lastSyncDate {
                    Section {
                        HStack {
                            Text("Last synced")
                            Spacer()
                            Text(lastSync, style: .relative)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // Sync Button
                Section {
                    Button(action: startSync) {
                        HStack {
                            if syncManager.isSyncing {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "arrow.triangle.2.circlepath")
                            }
                            Text(syncManager.isSyncing ? "Syncing..." : "Sync to HuggingFace")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSync || syncManager.isSyncing)
                } footer: {
                    if !canSync {
                        Text("Configure credentials and select a dataset to enable sync.")
                    }
                }
                
                // Emergency Legacy Data Fix
                Section {
                    Button(action: startLegacyFix) {
                        HStack {
                            if legacyFixer.isFixing {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "wrench.and.screwdriver")
                            }
                            Text(legacyFixer.isFixing ? "Fixing Old Features..." : "Fix Corrupted Extracted Features")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.orange)
                    .disabled(legacyFixer.isFixing || selectedDataset == nil)
                } footer: {
                    Text("Use this if your batch-extracted datasets from older app versions are showing 'No Features Extracted'. This bypasses re-processing videos.")
                }

                // Error Display
                if let error = syncManager.lastError {
                    Section {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                            Text(error)
                                .font(.subheadline)
                                .foregroundStyle(.red)
                        }
                    }
                }
            }
            .navigationTitle("Sync Features")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { isPresented = false }
                }
            }
            .alert("HuggingFace Token", isPresented: $showTokenHelp) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Get your token from huggingface.co/settings/tokens. Create a token with 'write' permissions to upload data.")
            }
            .onAppear {
                repoId = syncManager.repoId
                tokenSaved = syncManager.hasToken
            }
        }
    }

    private var canSync: Bool {
        (syncManager.hasToken || !hfToken.isEmpty) && !repoId.isEmpty && selectedDataset != nil
    }

    private func saveToken() {
        if syncManager.saveToken(hfToken) {
            tokenSaved = true
            hfToken = ""
        }
    }

    private func startSync() {
        guard let dataset = selectedDataset else { return }

        // Save token if entered but not saved
        if !hfToken.isEmpty {
            _ = syncManager.saveToken(hfToken)
            hfToken = ""
        }

        Task {
            await syncManager.syncDataset(name: dataset.name, modelContext: modelContext)
        }
    }
    
    private func startLegacyFix() {
        guard let dataset = selectedDataset else { return }
        legacyFixer.fixLegacyFeatures(for: dataset, in: modelContext)
    }
}

// MARK: - Dataset Sync Row

struct DatasetSyncRow: View {
    let dataset: Dataset
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? .blue : .secondary)
                    .font(.title3)

                VStack(alignment: .leading, spacing: 4) {
                    Text(dataset.name)
                        .font(.subheadline.bold())
                        .foregroundStyle(.primary)

                    HStack(spacing: 8) {
                        SwiftUI.Label("\(dataset.totalSamples) videos", systemImage: "video")

                        if dataset.totalSamples > 0 {
                            SwiftUI.Label("Ready to sync", systemImage: "checkmark.circle")
                                .foregroundStyle(.green)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()
            }
        }
        .buttonStyle(.plain)
    }
}
