import SwiftUI
import SwiftData

/// Video selection view for choosing specific videos to test feature extraction
struct VideoSelectionView: View {
    let datasetName: String
    @Binding var selectedVideoIDs: Set<UUID>
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var videos: [VideoSample] = []
    @State private var searchText = ""
    
    var body: some View {
        NavigationStack {
            VStack {
                // Search bar
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
                .padding(8)
                .background(Color(.secondarySystemGroupedBackground))
                .cornerRadius(8)
                .padding()
                
                // Video list
                List {
                    ForEach(filteredVideos) { video in
                        VideoRow(
                            video: video,
                            isSelected: selectedVideoIDs.contains(video.id)
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            toggleSelection(for: video)
                        }
                    }
                }
                .listStyle(.plain)
                
                // Selection summary
                HStack {
                    Text("\(selectedVideoIDs.count) selected")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    Spacer()
                    
                    Button("Clear") {
                        selectedVideoIDs.removeAll()
                    }
                    .disabled(selectedVideoIDs.isEmpty)
                    
                    Button("Select All") {
                        selectedVideoIDs = Set(filteredVideos.map { $0.id })
                    }
                }
                .padding()
            }
            .navigationTitle("Select Videos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .disabled(selectedVideoIDs.isEmpty)
                }
            }
            .task {
                await loadVideos()
            }
        }
    }
    
    private var filteredVideos: [VideoSample] {
        if searchText.isEmpty {
            return videos
        }
        return videos.filter { video in
            video.displayTitle.localizedCaseInsensitiveContains(searchText) ||
            video.labels.contains { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
    }
    
    private func toggleSelection(for video: VideoSample) {
        if selectedVideoIDs.contains(video.id) {
            selectedVideoIDs.remove(video.id)
        } else {
            selectedVideoIDs.insert(video.id)
        }
    }
    
    private func loadVideos() async {
        let descriptor = FetchDescriptor<VideoSample>(
            predicate: #Predicate { $0.datasetName == datasetName },
            sortBy: [SortDescriptor(\.originalFilename)]
        )
        
        if let fetchedVideos = try? modelContext.fetch(descriptor) {
            await MainActor.run {
                videos = fetchedVideos
            }
        }
    }
}

// MARK: - Video Row

struct VideoRow: View {
    let video: VideoSample
    let isSelected: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            // Checkbox
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isSelected ? .blue : .secondary)
                .font(.title3)
            
            // Video info
            VStack(alignment: .leading, spacing: 4) {
                Text(video.displayTitle)
                    .font(.subheadline)
                    .lineLimit(1)
                
                HStack {
                    if let label = video.labels.first {
                        Text(label.name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Text("•")
                        .foregroundStyle(.secondary)
                    
                    Text(formatDuration(video.duration))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    if !video.featureSets.isEmpty {
                        Text("•")
                            .foregroundStyle(.secondary)
                        Text("✓ Features")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
    
    private func formatDuration(_ seconds: Double) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", minutes, secs)
    }
}

// MARK: - Preview

#Preview {
    VideoSelectionView(
        datasetName: "INCLUDE",
        selectedVideoIDs: .constant([])
    )
    .modelContainer(PersistenceController.preview.container)
}
