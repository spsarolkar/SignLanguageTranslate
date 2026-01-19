import SwiftUI
import SwiftData

struct FeatureExtractionView: View {
    let video: VideoSample
    @Environment(\.modelContext) private var modelContext
    
    @State private var inputVideoURL: URL?
    @State private var processingStatus: String = "Ready"
    @State private var progress: Double = 0.0
    @State private var isProcessing: Bool = false
    @State private var errorMessage: String?
    
    var body: some View {
        VStack(spacing: 20) {
            
            // Header
            VStack(alignment: .leading, spacing: 8) {
                Text("Feature Extraction")
                    .font(.title2)
                    .fontWeight(.bold)
                Text(video.fileName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            Divider()
            
            // Stats Section
            if !video.featureSets.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Extracted Features:")
                        .font(.headline)
                    
                    ForEach(video.featureSets) { featureSet in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(featureSet.modelName)
                                    .fontWeight(.medium)
                                Text("\(featureSet.frameCount) frames")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(featureSet.extractedAt, style: .date)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding()
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(8)
                    }
                }
            } else {
                ContentUnavailableView(
                    "No Features Extracted",
                    systemImage: "wand.and.stars",
                    description: Text("Extract body and hand keypoints using Apple Vision.")
                )
            }
            
            Spacer()
            
            // Progress Bar
            if isProcessing {
                VStack {
                    ProgressView(value: progress)
                        .tint(.blue)
                    Text("\(Int(progress * 100))%")
                        .font(.caption)
                        .monospacedDigit()
                }
                .padding()
            }
            
            // Action Button
            if let error = errorMessage {
                Text("Error: \(error)")
                    .foregroundStyle(.red)
                    .font(.caption)
                    .multilineTextAlignment(.center)
            }
            
            Button {
                Task {
                    await startExtraction()
                }
            } label: {
                HStack {
                    if isProcessing {
                        ProgressView()
                            .padding(.trailing, 5)
                    } else {
                        Image(systemName: "cpu")
                    }
                    Text(isProcessing ? "Extracting..." : "Run Feature Extraction")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(isProcessing ? Color.gray : Color.blue)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
            .disabled(isProcessing)
        }
        .padding()
        .navigationTitle("Feature Extraction")
    }
    
    private func startExtraction() async {
        isProcessing = true
        progress = 0.0
        errorMessage = nil
        processingStatus = "Initializing..."
        
        let coordinator = FeatureProcessingCoordinator(modelContext: modelContext)
        
        do {
            _ = try await coordinator.processVideo(video) { prog in
                Task { @MainActor in
                    self.progress = prog
                }
            }
            processingStatus = "Complete"
        } catch {
            errorMessage = error.localizedDescription
            processingStatus = "Failed"
        }
        
        isProcessing = false
        progress = 1.0 // Ensure full bar on completion
    }
}

// #Preview {
//    FeatureExtractionView(video: .preview)
// }
