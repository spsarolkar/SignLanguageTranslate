import SwiftUI
import SwiftData

/// Database inspector view for debugging SwiftData content
struct DatabaseInspectorView: View {
    @Environment(\.modelContext) private var modelContext
    
    @Query private var videoSamples: [VideoSample]
    @Query private var labels: [Label]
    @Query private var datasets: [Dataset]
    
    @State private var selectedTab: InspectorTab = .videos
    @State private var searchText = ""
    
    enum InspectorTab: String, CaseIterable {
        case videos = "Videos"
        case labels = "Labels"
        case datasets = "Datasets"
        case summary = "Summary"
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Tab Picker
            Picker("Table", selection: $selectedTab) {
                ForEach(InspectorTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding()
            
            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search...", text: $searchText)
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
            .padding(.horizontal)
            
            Divider()
            
            // Content
            TabView(selection: $selectedTab) {
                videoSamplesView
                    .tag(InspectorTab.videos)
                
                labelsView
                    .tag(InspectorTab.labels)
                
                datasetsView
                    .tag(InspectorTab.datasets)
                
                summaryView
                    .tag(InspectorTab.summary)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
        .navigationTitle("Database Inspector")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
    
    // MARK: - Video Samples View
    
    private var videoSamplesView: some View {
        List {
            Section {
                Text("\(filteredVideos.count) total records")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            ForEach(filteredVideos, id: \.id) { video in
                VStack(alignment: .leading, spacing: 4) {
                    Text(video.displayTitle)
                        .font(.subheadline.bold())
                    
                    HStack {
                        SwiftUI.Label(video.datasetName.isEmpty ? "No dataset" : video.datasetName, systemImage: "folder")
                        Spacer()
                        Text(video.id.uuidString.prefix(8))
                            .font(.caption2.monospaced())
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    
                    if !video.labels.isEmpty {
                        Text("Labels: \(video.labels.map { $0.name }.joined(separator: ", "))")
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }
                    
                    if !video.featureSets.isEmpty {
                        Text("Features: \(video.featureSets.map { $0.modelName }.joined(separator: ", "))")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                    
                    Text("Path: \(video.localPath)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(.vertical, 4)
            }
        }
        .listStyle(.plain)
    }
    
    private var filteredVideos: [VideoSample] {
        if searchText.isEmpty {
            return videoSamples
        }
        return videoSamples.filter {
            $0.displayTitle.localizedCaseInsensitiveContains(searchText) ||
            $0.datasetName.localizedCaseInsensitiveContains(searchText) ||
            $0.localPath.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    // MARK: - Labels View
    
    private var labelsView: some View {
        List {
            Section {
                Text("\(filteredLabels.count) total records")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            ForEach(filteredLabels, id: \.id) { label in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(label.name)
                            .font(.subheadline.bold())
                        Spacer()
                        Text(label.type.rawValue.capitalized)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(label.type == .word ? Color.blue.opacity(0.2) : Color.purple.opacity(0.2))
                            .cornerRadius(4)
                    }
                    
                    Text("ID: \(label.id.uuidString.prefix(8))")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                    
                    if let samples = label.videoSamples, !samples.isEmpty {
                        Text("\(samples.count) video(s)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    if let embedding = label.embedding {
                        Text("Embedding: \(embedding.count) dimensions")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .listStyle(.plain)
    }
    
    private var filteredLabels: [Label] {
        if searchText.isEmpty {
            return labels
        }
        return labels.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    // MARK: - Datasets View
    
    private var datasetsView: some View {
        List {
            Section {
                Text("\(filteredDatasets.count) total records")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            ForEach(filteredDatasets, id: \.id) { dataset in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(dataset.name)
                            .font(.subheadline.bold())
                        Spacer()
                        Circle()
                            .fill(statusColor(for: dataset.downloadStatus))
                            .frame(width: 8, height: 8)
                    }
                    
                    Text("ID: \(dataset.id.uuidString.prefix(8))")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                    
                    Text("Status: \(dataset.downloadStatus.rawValue)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    // Count videos for this dataset
                    let videoCount = videoSamples.filter { $0.datasetName == dataset.name }.count
                    Text("Videos in DB: \(videoCount)")
                        .font(.caption)
                        .foregroundStyle(videoCount > 0 ? .green : .red)
                }
                .padding(.vertical, 4)
            }
        }
        .listStyle(.plain)
    }
    
    private var filteredDatasets: [Dataset] {
        if searchText.isEmpty {
            return datasets
        }
        return datasets.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    private func statusColor(for status: DownloadStatus) -> Color {
        switch status {
        case .notStarted: return .gray
        case .downloading: return .blue
        case .processing: return .orange
        case .paused: return .yellow
        case .completed: return .green
        case .failed: return .red
        }
    }
    
    // MARK: - Summary View
    
    private var summaryView: some View {
        List {
            Section("Database Statistics") {
                DBStatRow(label: "Total Videos", value: "\(videoSamples.count)")
                DBStatRow(label: "Total Labels", value: "\(labels.count)")
                DBStatRow(label: "Total Datasets", value: "\(datasets.count)")
            }
            
            Section("Video Breakdown") {
                let withDataset = videoSamples.filter { !$0.datasetName.isEmpty }.count
                let withoutDataset = videoSamples.count - withDataset
                let withFeatures = videoSamples.filter { !$0.featureSets.isEmpty }.count
                
                DBStatRow(label: "With Dataset Name", value: "\(withDataset)")
                DBStatRow(label: "Without Dataset Name", value: "\(withoutDataset)")
                DBStatRow(label: "With Features", value: "\(withFeatures)")
            }
            
            Section("By Dataset") {
                ForEach(datasetGroups, id: \.name) { group in
                    DBStatRow(label: group.name.isEmpty ? "(No Dataset)" : group.name, value: "\(group.count)")
                }
            }
            
            Section("Label Types") {
                let wordLabels = labels.filter { $0.type == .word }.count
                let categoryLabels = labels.filter { $0.type == .category }.count
                
                DBStatRow(label: "Words", value: "\(wordLabels)")
                DBStatRow(label: "Categories", value: "\(categoryLabels)")
            }
            
            Section("Actions") {
                Button("Fix Missing Dataset Names") {
                    fixMissingDatasetNames()
                }
                .foregroundStyle(.blue)
                
                Button(role: .destructive) {
                    clearOrphanedRecords()
                } label: {
                    Text("Clear Orphaned Records")
                }
            }
        }
        .listStyle(.insetGrouped)
    }
    
    private var datasetGroups: [(name: String, count: Int)] {
        let groups = Dictionary(grouping: videoSamples) { $0.datasetName }
        return groups.map { (name: $0.key, count: $0.value.count) }
            .sorted { $0.count > $1.count }
    }
    
    // MARK: - Actions
    
    private func fixMissingDatasetNames() {
        let videosWithoutDataset = videoSamples.filter { $0.datasetName.isEmpty }
        
        for video in videosWithoutDataset {
            // Try to infer from path
            let components = video.localPath.components(separatedBy: "/")
            if components.count > 1 {
                // First component is likely the dataset name
                video.datasetName = components[0]
            }
        }
        
        try? modelContext.save()
        print("[DatabaseInspector] Fixed \(videosWithoutDataset.count) videos")
    }
    
    private func clearOrphanedRecords() {
        // Remove videos without files
        // Remove labels without videos
        // This is destructive, implement carefully
        print("[DatabaseInspector] Clear orphaned records (not implemented)")
    }
}

// MARK: - Helper Views

private struct DBStatRow: View {
    let label: String
    let value: String
    var color: Color = .primary
    
    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
            Spacer()
            Text(value)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(color)
                .fontWeight(.medium)
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        DatabaseInspectorView()
    }
    .modelContainer(PersistenceController.preview.container)
}
