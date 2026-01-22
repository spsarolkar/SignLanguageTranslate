import SwiftUI
import SwiftData
import AVKit

/// Professional Pipeline UI - Clean, Simple, Intuitive
struct DataPipelineView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Dataset.name) private var datasets: [Dataset]
    
    // Core State
    @State private var selectedDataset: Dataset?
    @State private var selectedVideo: VideoSample?
    @State private var selectedCategory: String?
    @State private var searchText: String = ""
    @State private var selectedModel: String = "AppleVision"
    
    // UI State
    @State private var showFilters = false
    @State private var loadedFeatures: [FrameFeatures] = []
    @State private var isInspectorLoading = false
    @State private var extractingVideoIDs: Set<UUID> = []
    @State private var showSyncSheet = false
    @State private var showError = false
    @State private var errorMessage = ""
    
    // Computed
    private var downloadedDatasets: [Dataset] {
        datasets.filter { $0.downloadStatus == .completed }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // MARK: - Elegant Header
            headerView
            
            Divider()
            
            // MARK: - Main Content
            if selectedDataset != nil {
                mainContentView
            } else {
                emptyStateView
            }
        }
        .background(Color(.systemGroupedBackground))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .sheet(isPresented: $showSyncSheet) {
            SyncSettingsView(isPresented: $showSyncSheet)
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
        .onChange(of: selectedVideo) {
            if let video = selectedVideo {
                loadFeatures(for: video)
            } else {
                loadedFeatures = []
            }
        }
        .onAppear {
            // Auto-select first downloaded dataset
            if selectedDataset == nil, let first = downloadedDatasets.first {
                selectedDataset = first
            }
        }
    }
    
    // MARK: - Header View
    private var headerView: some View {
        VStack(spacing: 12) {
            // Title Row
            HStack {
                Text("Feature Extraction")
                    .font(.title2.bold())
                
                Spacer()
                
                // Model Picker
                if selectedDataset != nil {
                    Menu {
                        Button(action: { selectedModel = "AppleVision" }) {
                            HStack {
                                Text("Apple Vision")
                                if selectedModel == "AppleVision" {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                        Button(action: { selectedModel = "MediaPipe" }) {
                            HStack {
                                Text("MediaPipe")
                                if selectedModel == "MediaPipe" {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "cpu")
                                .font(.system(size: 14))
                            Text(selectedModel == "AppleVision" ? "Vision" : "Pipe")
                                .font(.caption)
                                .fontWeight(.medium)
                            Image(systemName: "chevron.down")
                                .font(.caption2)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color(.secondarySystemGroupedBackground))
                        .cornerRadius(8)
                    }
                }
                
                // Sync Button
                if selectedDataset != nil {
                    Button(action: { showSyncSheet = true }) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .padding(8)
                            .background(Color(.secondarySystemGroupedBackground))
                            .cornerRadius(8)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.top)
            
            // Dataset + Info Row
            if let dataset = selectedDataset {
                HStack(spacing: 12) {
                    Menu {
                        ForEach(downloadedDatasets) { dataset in
                            Button(action: {
                                selectedDataset = dataset
                                selectedVideo = nil
                                selectedCategory = nil
                            }) {
                                HStack {
                                    Text(dataset.name)
                                    if dataset.id == selectedDataset?.id {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "folder")
                                .font(.system(size: 14))
                            Text(dataset.name)
                                .fontWeight(.medium)
                                .lineLimit(1)
                            Image(systemName: "chevron.down")
                                .font(.caption)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color(.secondarySystemGroupedBackground))
                        .cornerRadius(8)
                    }
                    
                    Text("\(dataset.totalSamples) videos")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    Spacer()
                }
                .padding(.horizontal)
            } else {
                HStack {
                    Menu {
                        ForEach(downloadedDatasets) { dataset in
                            Button(action: {
                                selectedDataset = dataset
                                selectedVideo = nil
                                selectedCategory = nil
                            }) {
                                Text(dataset.name)
                            }
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "folder")
                                .font(.system(size: 14))
                            Text("Select Dataset")
                                .fontWeight(.medium)
                            Image(systemName: "chevron.down")
                                .font(.caption)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color(.secondarySystemGroupedBackground))
                        .cornerRadius(8)
                    }
                    
                    Spacer()
                }
                .padding(.horizontal)
            }
            
            // Search + Filters
            if selectedDataset != nil {
                HStack(spacing: 12) {
                    // Search
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("Search videos...", text: $searchText)
                            .textFieldStyle(.plain)
                        
                        if !searchText.isEmpty {
                            Button(action: { searchText = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(10)
                    .background(Color(.secondarySystemGroupedBackground))
                    .cornerRadius(10)
                    
                    // Filter Toggle
                    Button(action: { withAnimation { showFilters.toggle() } }) {
                        HStack(spacing: 6) {
                            Image(systemName: showFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                            if selectedCategory != nil {
                                Circle()
                                    .fill(Color.blue)
                                    .frame(width: 8, height: 8)
                            }
                        }
                        .padding(10)
                        .background(showFilters ? Color.blue.opacity(0.1) : Color(.secondarySystemGroupedBackground))
                        .cornerRadius(10)
                    }
                }
                .padding(.horizontal)
                
                // Expandable Filters
                if showFilters, let dataset = selectedDataset {
                    CategoryFilterView(
                        selectedCategory: $selectedCategory,
                        categories: getCategories(for: dataset)
                    )
                    .padding(.horizontal)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
        .padding(.bottom)
        .background(Color(.systemBackground))
    }
    
    // MARK: - Main Content
    private var mainContentView: some View {
        ScrollView {
            VStack(spacing: 20) {
                if let dataset = selectedDataset {
                    VideoExtractionGrid(
                        datasetName: dataset.name,
                        categoryFilter: selectedCategory,
                        searchText: searchText,
                        selectedVideo: $selectedVideo,
                        extractingVideoIDs: $extractingVideoIDs,
                        onExtract: extractSingleVideo
                    )
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationDestination(item: $selectedVideo) { video in
            VideoPlayerContent(
                video: video,
                features: loadedFeatures,
                isLoading: isInspectorLoading,
                onExtract: { extractSingleVideo(video) }
            )
        }
    }
    
    // MARK: - Empty State
    private var emptyStateView: some View {
        ContentUnavailableView {
            SwiftUI.Label("No Dataset Available", systemImage: "tray")
        } description: {
            Text("Download a dataset from the Datasets tab to get started with feature extraction.")
        } actions: {
            if !downloadedDatasets.isEmpty {
                Button("Select Dataset") {
                    selectedDataset = downloadedDatasets.first
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
    
    // MARK: - Data Helpers
    
    private func getCategories(for dataset: Dataset) -> [String] {
        let descriptor = FetchDescriptor<Label>(
            predicate: #Predicate<Label> { $0.typeRawValue == "category" },
            sortBy: [.init(\.name)]
        )
        guard let labels = try? modelContext.fetch(descriptor) else { return [] }
        return labels.map { $0.name }
    }
    
    private func loadFeatures(for video: VideoSample) {
        isInspectorLoading = true
        Task {
            if let featureSet = video.featureSets.first(where: { $0.modelName == "AppleVision" }) ?? video.featureSets.last {
                do {
                    let features = try FeatureFileManager.shared.loadFeatures(at: featureSet.filePath)
                    await MainActor.run {
                        self.loadedFeatures = features
                        self.isInspectorLoading = false
                    }
                } catch {
                    await MainActor.run { isInspectorLoading = false }
                }
            } else {
                await MainActor.run {
                    self.loadedFeatures = []
                    self.isInspectorLoading = false
                }
            }
        }
    }
    
    private func extractSingleVideo(_ video: VideoSample) {
        extractingVideoIDs.insert(video.id)
        Task {
            do {
                let service = VideoFeatureExtractionService()
                let fileManager = FeatureFileManager()
                
                // Use direct absoluteURL from VideoSample
                let videoURL = video.absoluteURL
                
                // Debug logging
                print("[Extraction] Video localPath: \(video.localPath)")
                print("[Extraction] Attempting extraction from: \(videoURL.path)")
                print("[Extraction] File exists: \(FileManager.default.fileExists(atPath: videoURL.path))")
                
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
                    modelName: selectedModel
                )
                
                // Create and save feature set
                let featureSet = FeatureSet(
                    modelName: selectedModel,
                    filePath: outputPath,
                    frameCount: features.count
                )
                featureSet.videoSample = video
                modelContext.insert(featureSet)
                try modelContext.save()
                
                await MainActor.run {
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

// MARK: - Category Filter View

struct CategoryFilterView: View {
    @Binding var selectedCategory: String?
    let categories: [String]
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // All Categories
                FilterChip(
                    title: "All",
                    isSelected: selectedCategory == nil,
                    action: { selectedCategory = nil }
                )
                
                // Category Chips
                ForEach(categories, id: \.self) { category in
                    FilterChip(
                        title: category,
                        isSelected: selectedCategory == category,
                        action: { selectedCategory = category }
                    )
                }
            }
            .padding(.vertical, 4)
        }
    }
}

struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundStyle(isSelected ? .white : .primary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(isSelected ? Color.blue : Color(.tertiarySystemGroupedBackground))
                .cornerRadius(20)
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
    let onExtract: (VideoSample) -> Void
    
    @Query private var videos: [VideoSample]
    
    init(datasetName: String, categoryFilter: String?, searchText: String, selectedVideo: Binding<VideoSample?>, extractingVideoIDs: Binding<Set<UUID>>, onExtract: @escaping (VideoSample) -> Void) {
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
        LazyVStack(spacing: 20, pinnedViews: [.sectionHeaders]) {
            ForEach(groupedVideos, id: \.category) { group in
                Section {
                    // Single column list
                    ForEach(group.videos) { video in
                        VideoExtractionCard(
                            video: video,
                            isExtracting: extractingVideoIDs.contains(video.id),
                            isSelected: selectedVideo?.id == video.id,
                            onExtract: { onExtract(video) },
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
    let onExtract: () -> Void
    let onSelect: () -> Void
    
    @State private var showDetails = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Main Card Content
            HStack(spacing: 12) {
                // Thumbnail
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.blue.opacity(0.1))
                        .frame(width: 60, height: 60)
                    
                    Image(systemName: "film.stack")
                        .font(.system(size: 24))
                        .foregroundStyle(.blue)
                }
                
                // Info
                VStack(alignment: .leading, spacing: 4) {
                    Text(video.fileName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    
                    HStack(spacing: 6) {
                        if let word = video.wordName {
                            Text(word)
                                .font(.caption2)
                                .foregroundStyle(.blue)
                        }
                        
                        Text(video.formattedDuration)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer(minLength: 8)
                
                // Status Icon
                if isExtracting {
                    ProgressView()
                        .scaleEffect(0.8)
                } else if !video.featureSets.isEmpty {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                        .font(.title3)
                } else {
                    Image(systemName: "exclamationmark.circle")
                        .foregroundStyle(.orange)
                        .font(.title3)
                }
            }
            .padding(12)
            .background(isSelected ? Color.blue.opacity(0.15) : Color(.secondarySystemGroupedBackground))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
            )
            .contentShape(Rectangle())
            .simultaneousGesture(TapGesture().onEnded {
                onSelect()
            })
            
            // Extract Button (if not extracted)
            if !video.featureSets.isEmpty {
                if showDetails {
                    VStack(spacing: 8) {
                        Divider()
                        
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Details")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.secondary)
                                Spacer()
                            }
                            
                            DetailRow(label: "Frames", value: "\(video.featureSets.first?.frameCount ?? 0)")
                            if let model = video.featureSets.first?.modelName {
                                DetailRow(label: "Model", value: model)
                            }
                        }
                        
                        Button(action: onExtract) {
                            HStack {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                Text("Re-extract")
                            }
                            .font(.caption)
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding(12)
                    .background(Color(.tertiarySystemGroupedBackground))
                }
            } else if !isExtracting {
                Button(action: onExtract) {
                    HStack {
                        Image(systemName: "cpu")
                        Text("Extract Features")
                    }
                    .font(.subheadline)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 8)
            }
        }
    }
}

struct DetailRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
        }
    }
}

// MARK: - Category Header

struct CategoryHeader: View {
    let title: String
    let count: Int
    
    var body: some View {
        HStack {
            Text(title.uppercased())
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            
            Spacer()
            
            Text("\(count)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color(.tertiarySystemGroupedBackground))
                .cornerRadius(4)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
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
    @State private var hfToken = ""
    
    var body: some View {
        NavigationStack {
            Form {
                Section("HuggingFace Credentials") {
                    SecureField("Token", text: $hfToken)
                }
                
                Section {
                    Button("Start Sync") {
                        // TODO
                    }
                }
            }
            .navigationTitle("Sync Settings")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { isPresented = false }
                }
            }
        }
    }
}
