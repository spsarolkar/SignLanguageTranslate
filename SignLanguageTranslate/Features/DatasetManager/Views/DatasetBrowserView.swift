import SwiftUI
import AVKit
#if os(iOS)
import UIKit
#endif

/// Represents a category folder in the dataset
struct BrowserCategoryItem: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let url: URL
    let wordCount: Int
    let videoCount: Int
}

/// Represents a word folder within a category
struct BrowserWordItem: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let url: URL
    let videoCount: Int
    let videos: [BrowserVideoItem]
}

/// Represents a single video file
struct BrowserVideoItem: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let url: URL
    let fileSize: Int64

    var formattedSize: String {
        FileManager.formattedSize(fileSize)
    }
}

/// A view for browsing extracted dataset samples organized by category and word
///
/// This view scans the file system directly for better performance instead of
/// relying on SwiftData queries which can be slow for large datasets.
struct DatasetBrowserView: View {
    let dataset: Dataset

    @Environment(\.dismiss) private var dismiss
    @Environment(ExtractionProgressTracker.self) private var extractionTracker

    @State private var categories: [BrowserCategoryItem] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var selectedCategory: BrowserCategoryItem?
    @State private var searchText = ""
    @State private var needsExtraction = false
    @State private var isExtracting = false
    @State private var showDeleteConfirmation = false

    private var filteredCategories: [BrowserCategoryItem] {
        if searchText.isEmpty {
            return categories
        }
        return categories.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        Group {
            if needsExtraction {
                extractionNeededView
            } else if isLoading {
                loadingView
            } else if let error = errorMessage {
                errorView(error)
            } else if categories.isEmpty {
                emptyView
            } else {
                categoryListView
            }
        }
        .navigationTitle("Browse \(dataset.name)")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .searchable(text: $searchText, prompt: "Search categories")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        SwiftUI.Label("Delete Extracted Files", systemImage: "trash")
                    }
                    .disabled(categories.isEmpty && !needsExtraction)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .confirmationDialog(
            "Delete Extracted Files?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                deleteExtractedFiles()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will delete all extracted category folders for \(dataset.name). You can re-extract from the downloaded zip files.")
        }
        .task {
            await loadCategories()
        }
    }

    // MARK: - Actions

    private func deleteExtractedFiles() {
        let fileManager = FileManager.default
        let datasetURL = dataset.storageDirectory

        // Delete the entire dataset folder
        if fileManager.fileExists(atPath: datasetURL.path) {
            do {
                try fileManager.removeItem(at: datasetURL)
                print("[DatasetBrowser] Deleted extracted files at: \(datasetURL.path)")

                // Reload to show extraction needed view
                Task {
                    await loadCategories()
                }
            } catch {
                print("[DatasetBrowser] Failed to delete: \(error)")
                errorMessage = "Failed to delete files: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Views

    private var extractionNeededView: some View {
        ContentUnavailableView {
            SwiftUI.Label("Extraction Required", systemImage: "archivebox")
        } description: {
            Text("The downloaded files need to be extracted before you can browse samples.")
        } actions: {
            if isExtracting {
                VStack(spacing: 12) {
                    ProgressView(value: extractionTracker.overallProgress)
                        .progressViewStyle(.linear)
                        .frame(width: 200)

                    Text(extractionTracker.statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Button {
                    Task {
                        await startExtraction()
                    }
                } label: {
                    SwiftUI.Label("Extract Files", systemImage: "archivebox.fill")
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text("Scanning dataset...")
                .foregroundStyle(.secondary)
        }
    }

    private func errorView(_ error: String) -> some View {
        ContentUnavailableView {
            SwiftUI.Label("Error", systemImage: "exclamationmark.triangle")
        } description: {
            Text(error)
        } actions: {
            Button("Retry") {
                Task {
                    await loadCategories()
                }
            }
        }
    }

    private var emptyView: some View {
        ContentUnavailableView(
            "No Categories Found",
            systemImage: "folder.badge.questionmark",
            description: Text("The dataset folder is empty or not yet extracted.")
        )
    }

    private var categoryListView: some View {
        List(filteredCategories) { category in
            NavigationLink {
                BrowserCategoryDetailView(category: category, datasetName: dataset.name)
            } label: {
                BrowserCategoryRowView(category: category)
            }
        }
        .listStyle(.insetGrouped)
    }
}

// MARK: - Browser Category Row View

struct BrowserCategoryRowView: View {
    let category: BrowserCategoryItem

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "folder.fill")
                .font(.title2)
                .foregroundStyle(.blue)
                .frame(width: 40)

            VStack(alignment: .leading, spacing: 4) {
                Text(category.name)
                    .font(.headline)

                HStack(spacing: 8) {
                    SwiftUI.Label("\(category.wordCount) words", systemImage: "textformat.abc")
                    SwiftUI.Label("\(category.videoCount) videos", systemImage: "video")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Browser Category Detail View

struct BrowserCategoryDetailView: View {
    let category: BrowserCategoryItem
    let datasetName: String

    @State private var words: [BrowserWordItem] = []
    @State private var isLoading = true
    @State private var searchText = ""

    private var filteredWords: [BrowserWordItem] {
        if searchText.isEmpty {
            return words
        }
        return words.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        Group {
            if isLoading {
                VStack(spacing: 16) {
                    ProgressView()
                    Text("Loading words...")
                        .foregroundStyle(.secondary)
                }
            } else if words.isEmpty {
                ContentUnavailableView(
                    "No Words Found",
                    systemImage: "textformat.abc",
                    description: Text("This category appears to be empty.")
                )
            } else {
                List(filteredWords) { word in
                    NavigationLink {
                        BrowserWordDetailView(word: word, categoryName: category.name, datasetName: datasetName)
                    } label: {
                        BrowserWordRowView(word: word)
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle(category.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .searchable(text: $searchText, prompt: "Search words")
        .task {
            await loadWords()
        }
    }

    private func loadWords() async {
        isLoading = true
        let categoryURL = category.url

        let loadedWords = await Task.detached(priority: .userInitiated) {
            let fileManager = FileManager.default
            var results: [BrowserWordItem] = []

            guard let contents = try? fileManager.contentsOfDirectory(
                at: categoryURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else {
                return results
            }

            for itemURL in contents.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                guard let resourceValues = try? itemURL.resourceValues(forKeys: [.isDirectoryKey]),
                      let isDirectory = resourceValues.isDirectory,
                      isDirectory else {
                    continue
                }

                // Get videos in this word folder
                let videos = browserScanVideos(in: itemURL)

                if !videos.isEmpty {
                    let wordName = browserCleanWordName(itemURL.lastPathComponent)
                    results.append(BrowserWordItem(
                        name: wordName,
                        url: itemURL,
                        videoCount: videos.count,
                        videos: videos
                    ))
                }
            }

            return results
        }.value

        await MainActor.run {
            self.words = loadedWords
            self.isLoading = false
        }
    }

}

// MARK: - File System Helpers (nonisolated)

/// Helper functions for file system operations during dataset browsing
/// These are nonisolated to allow calling from detached tasks
private nonisolated func browserCleanWordName(_ name: String) -> String {
    // Remove numbered prefixes like "12. Dog" -> "Dog"
    let pattern = /^\d+\.\s*/
    return name.replacing(pattern, with: "")
}

private nonisolated func browserScanVideos(in directory: URL) -> [BrowserVideoItem] {
    let fileManager = FileManager.default
    let videoExtensions = ["mp4", "mov", "m4v", "avi"]
    var videos: [BrowserVideoItem] = []

    guard let contents = try? fileManager.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: [.fileSizeKey],
        options: [.skipsHiddenFiles]
    ) else {
        return []
    }

    for fileURL in contents.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
        let ext = fileURL.pathExtension.lowercased()
        guard videoExtensions.contains(ext) else { continue }

        let fileSize = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0

        videos.append(BrowserVideoItem(
            name: fileURL.lastPathComponent,
            url: fileURL,
            fileSize: Int64(fileSize)
        ))
    }

    return videos
}

private nonisolated func browserCountContents(in categoryURL: URL) -> (words: Int, videos: Int) {
    let fileManager = FileManager.default
    let videoExtensions = ["mp4", "mov", "m4v", "avi"]

    var wordCount = 0
    var videoCount = 0

    guard let contents = try? fileManager.contentsOfDirectory(
        at: categoryURL,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: [.skipsHiddenFiles]
    ) else {
        return (0, 0)
    }

    for itemURL in contents {
        guard let resourceValues = try? itemURL.resourceValues(forKeys: [.isDirectoryKey]),
              let isDirectory = resourceValues.isDirectory else {
            continue
        }

        if isDirectory {
            wordCount += 1
            // Count videos in this word folder
            if let wordContents = try? fileManager.contentsOfDirectory(
                at: itemURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) {
                videoCount += wordContents.filter {
                    videoExtensions.contains($0.pathExtension.lowercased())
                }.count
            }
        }
    }

    return (wordCount, videoCount)
}

// MARK: - Browser Word Row View

struct BrowserWordRowView: View {
    let word: BrowserWordItem

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "hand.wave.fill")
                .font(.title3)
                .foregroundStyle(.orange)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(word.name)
                    .font(.body.weight(.medium))

                Text("\(word.videoCount) video\(word.videoCount == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Browser Word Detail View

struct BrowserWordDetailView: View {
    let word: BrowserWordItem
    let categoryName: String
    let datasetName: String

    @State private var selectedVideo: BrowserVideoItem?

    var body: some View {
        List {
            Section {
                ForEach(word.videos) { video in
                    Button {
                        selectedVideo = video
                    } label: {
                        BrowserVideoRowView(video: video)
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("\(word.videos.count) Video\(word.videos.count == 1 ? "" : "s")")
            } footer: {
                Text("Tap a video to preview it")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(word.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .sheet(item: $selectedVideo) { video in
            BrowserVideoPreviewSheet(video: video, wordName: word.name, categoryName: categoryName)
        }
    }
}

// MARK: - Browser Video Row View

struct BrowserVideoRowView: View {
    let video: BrowserVideoItem

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 60, height: 45)

                Image(systemName: "play.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.white.opacity(0.9))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(video.name)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)

                Text(video.formattedSize)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
        .padding(.vertical, 4)
    }
}

// MARK: - Browser Video Preview Sheet

struct BrowserVideoPreviewSheet: View {
    let video: BrowserVideoItem
    let wordName: String
    let categoryName: String

    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?
    @State private var isPlaying = false
    @State private var showFullScreenPlayer = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Video Player
                    videoPlayerView
                        .padding(.horizontal)

                    // Info section
                    VStack(alignment: .leading, spacing: 12) {
                        BrowserInfoRow(label: "Word", value: wordName)
                        BrowserInfoRow(label: "Category", value: categoryName)
                        BrowserInfoRow(label: "File", value: video.name)
                        BrowserInfoRow(label: "Size", value: video.formattedSize)
                    }
                    .padding()
                    .background(Color(.secondarySystemGroupedBackground))
                    .cornerRadius(12)
                    .padding(.horizontal)

                    // Action buttons
                    HStack(spacing: 16) {
                        Button {
                            showFullScreenPlayer = true
                        } label: {
                            SwiftUI.Label("Full Screen", systemImage: "arrow.up.left.and.arrow.down.right")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)

                        ShareLink(item: video.url) {
                            SwiftUI.Label("Share", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(wordName)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        player?.pause()
                        dismiss()
                    }
                }
            }
            .onAppear {
                setupPlayer()
            }
            .onDisappear {
                player?.pause()
                player = nil
            }
            .fullScreenCover(isPresented: $showFullScreenPlayer) {
                FullScreenVideoPlayer(url: video.url)
            }
        }
    }

    // MARK: - Video Player View

    @ViewBuilder
    private var videoPlayerView: some View {
        ZStack {
            if let player = player {
                VideoPlayer(player: player)
                    .aspectRatio(16/9, contentMode: .fit)
                    .cornerRadius(12)
                    .onTapGesture {
                        togglePlayback()
                    }
            } else {
                // Loading placeholder
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.black)
                    .aspectRatio(16/9, contentMode: .fit)
                    .overlay {
                        ProgressView()
                            .tint(.white)
                    }
            }
        }
    }

    // MARK: - Player Setup

    private func setupPlayer() {
        let playerItem = AVPlayerItem(url: video.url)
        player = AVPlayer(playerItem: playerItem)

        // Loop the video
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { _ in
            player?.seek(to: .zero)
            player?.play()
        }

        // Auto-play
        player?.play()
        isPlaying = true
    }

    private func togglePlayback() {
        guard let player = player else { return }

        if isPlaying {
            player.pause()
        } else {
            player.play()
        }
        isPlaying.toggle()
    }
}

// MARK: - Full Screen Video Player

struct FullScreenVideoPlayer: View {
    let url: URL

    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let player = player {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
            }

            // Close button
            VStack {
                HStack {
                    Spacer()
                    Button {
                        player?.pause()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                            .foregroundStyle(.white.opacity(0.8))
                            .padding()
                    }
                }
                Spacer()
            }
        }
        .onAppear {
            player = AVPlayer(url: url)
            player?.play()
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
    }
}

// MARK: - Info Row Helper

private struct BrowserInfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
    }
}

// MARK: - Loading Logic

extension DatasetBrowserView {

    /// Check if a directory is empty or contains no meaningful content
    private func isDirectoryEmpty(_ url: URL) -> Bool {
        let fileManager = FileManager.default
        guard let contents = try? fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return true
        }
        return contents.isEmpty
    }

    private func loadCategories() async {
        isLoading = true
        errorMessage = nil

        let datasetURL = dataset.storageDirectory
        let fileManager = FileManager.default

        // Check if dataset directory exists with extracted content
        let hasExtractedContent = fileManager.directoryExists(at: datasetURL)

        // Check if we have downloaded zip files that need extraction
        let downloadedFiles = findDownloadedZipFiles()
        let hasDownloadedFiles = !downloadedFiles.isEmpty

        // If no extracted content, check what state we're in
        if !hasExtractedContent || isDirectoryEmpty(datasetURL) {
            if hasDownloadedFiles {
                // We have downloaded files but haven't extracted yet
                await MainActor.run {
                    needsExtraction = true
                    isLoading = false
                }
                return
            }

            // No downloaded files either - dataset not yet downloaded
            await MainActor.run {
                let message: String
                switch dataset.downloadStatus {
                case .notStarted:
                    message = "Dataset not downloaded yet. Tap 'Download' to start downloading this dataset."
                case .downloading:
                    message = "Download in progress. Please wait for the download to complete."
                case .paused:
                    message = "Download paused. Resume the download to continue."
                case .failed:
                    message = "Download failed. Please retry the download."
                case .processing:
                    message = "Processing download. Please wait."
                case .completed:
                    // Completed but no files - something went wrong
                    message = "Download marked as complete but no files found. Try re-downloading the dataset."
                }
                errorMessage = message
                isLoading = false
            }
            return
        }

        // Scan for categories in background
        let loadedCategories = await Task.detached(priority: .userInitiated) {
            var results: [BrowserCategoryItem] = []

            guard let contents = try? fileManager.contentsOfDirectory(
                at: datasetURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else {
                return results
            }

            for itemURL in contents.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                guard let resourceValues = try? itemURL.resourceValues(forKeys: [.isDirectoryKey]),
                      let isDirectory = resourceValues.isDirectory,
                      isDirectory else {
                    continue
                }

                // Count words and videos in this category
                let (wordCount, videoCount) = browserCountContents(in: itemURL)

                if wordCount > 0 || videoCount > 0 {
                    results.append(BrowserCategoryItem(
                        name: itemURL.lastPathComponent,
                        url: itemURL,
                        wordCount: wordCount,
                        videoCount: videoCount
                    ))
                }
            }

            return results
        }.value

        await MainActor.run {
            self.categories = loadedCategories
            self.isLoading = false

            // If no categories found but directory exists, might need extraction
            if loadedCategories.isEmpty {
                let downloadedFiles = self.findDownloadedZipFiles()
                if !downloadedFiles.isEmpty {
                    self.needsExtraction = true
                }
            }
        }
    }

    private func findDownloadedZipFiles() -> [URL] {
        let fileManager = FileManager.default
        // Downloaded files go to Documents/Downloads/completed/ with format: [UUID]_[filename].zip
        let completedDir = fileManager.downloadsDirectory.appendingPathComponent("completed")

        guard fileManager.directoryExists(at: completedDir),
              let contents = try? fileManager.contentsOfDirectory(
                at: completedDir,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
              ) else {
            return []
        }

        // Filter for zip files - for now return all zip files
        // The extraction coordinator will group them by category
        return contents.filter { $0.pathExtension.lowercased() == "zip" }
    }

    /// Strip UUID prefix from downloaded file and return original filename
    /// Format: {UUID}_{original_filename}.zip -> {original_filename}.zip
    private func stripUUIDPrefix(from filename: String) -> String {
        // Look for first underscore after UUID (36 chars)
        guard filename.count > 37,
              let underscoreIndex = filename.index(filename.startIndex, offsetBy: 36, limitedBy: filename.endIndex),
              filename[underscoreIndex] == "_" else {
            return filename
        }
        return String(filename[filename.index(after: underscoreIndex)...])
    }

    private func startExtraction() async {
        isExtracting = true

        let downloadedFiles = findDownloadedZipFiles()
        guard !downloadedFiles.isEmpty else {
            isExtracting = false
            return
        }

        // Build mapping from original filenames to actual file URLs
        // This allows the extraction coordinator to use correct category names
        var fileMapping: [String: URL] = [:]
        for file in downloadedFiles {
            let originalFilename = stripUUIDPrefix(from: file.lastPathComponent)
            fileMapping[originalFilename] = file
        }

        let coordinator = ExtractionCoordinator()

        do {
            _ = try await coordinator.extractDatasetWithMapping(
                datasetName: dataset.name,
                fileMapping: fileMapping,
                progressHandler: extractionTracker.progressHandler
            )

            // Reload categories after extraction
            needsExtraction = false
            await loadCategories()
        } catch {
            await MainActor.run {
                errorMessage = "Extraction failed: \(error.localizedDescription)"
            }
        }

        isExtracting = false
    }
}

// MARK: - Previews

#Preview("Browser") {
    NavigationStack {
        DatasetBrowserView(dataset: .previewIncludeCompleted)
    }
    .environment(ExtractionProgressTracker())
}

#Preview("Category Row") {
    List {
        BrowserCategoryRowView(category: BrowserCategoryItem(
            name: "Animals",
            url: URL(fileURLWithPath: "/tmp"),
            wordCount: 25,
            videoCount: 250
        ))
        BrowserCategoryRowView(category: BrowserCategoryItem(
            name: "Greetings",
            url: URL(fileURLWithPath: "/tmp"),
            wordCount: 15,
            videoCount: 150
        ))
    }
}

#Preview("Word Row") {
    List {
        BrowserWordRowView(word: BrowserWordItem(
            name: "Dog",
            url: URL(fileURLWithPath: "/tmp"),
            videoCount: 10,
            videos: []
        ))
        BrowserWordRowView(word: BrowserWordItem(
            name: "Cat",
            url: URL(fileURLWithPath: "/tmp"),
            videoCount: 8,
            videos: []
        ))
    }
}
