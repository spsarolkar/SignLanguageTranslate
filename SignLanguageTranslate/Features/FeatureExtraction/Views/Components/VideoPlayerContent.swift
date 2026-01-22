import SwiftUI
import AVKit

/// Main content area showing video player with keypoint overlay
struct VideoPlayerContent: View {
    let video: VideoSample
    let features: [FrameFeatures]
    let isLoading: Bool
    let onExtract: () -> Void
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Video Player with Keypoint Overlay
                if !features.isEmpty {
                    VStack(spacing: 16) {
                        Text("Video Playback")
                            .font(.title2.bold())
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        VideoAnnotationPlayer(
                            videoURL: video.absoluteURL,
                            features: features
                        )
                        .frame(height: 500)
                        .cornerRadius(12)
                        .shadow(color: Color.black.opacity(0.1), radius: 8, y: 4)
                    }
                } else if isLoading {
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("Loading features...")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(height: 400)
                } else {
                    // No features extracted
                    VStack(spacing: 24) {
                        Image(systemName: "waveform.path.ecg")
                            .font(.system(size: 60))
                            .foregroundStyle(.blue)
                        
                        VStack(spacing: 8) {
                            Text("No Features Extracted")
                                .font(.title3.bold())
                            
                            Text("Extract keypoint features from this video to visualize the overlay.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        
                        Button(action: onExtract) {
                            SwiftUI.Label("Extract Features", systemImage: "cpu")
                                .frame(minWidth: 200)
                                .padding()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    }
                    .frame(height: 400)
                }
                
                // Video Metadata
                VStack(spacing: 16) {
                    HStack {
                        Text("Video Information")
                            .font(.title3.bold())
                        Spacer()
                    }
                    
                    VStack(spacing: 12) {
                        MetadataCard(label: "Filename", value: video.fileName)
                        
                        if let category = video.categoryName {
                            MetadataCard(label: "Category", value: category, icon: "folder")
                        }
                        
                        if let word = video.wordName {
                            MetadataCard(label: "Word", value: word, icon: "text.bubble")
                        }
                        
                        MetadataCard(label: "Duration", value: video.formattedDuration, icon: "clock")
                        MetadataCard(label: "File Size", value: video.formattedFileSize, icon: "doc")
                        
                        if !features.isEmpty {
                            MetadataCard(label: "Keyframes", value: "\(features.count)", icon: "waveform")
                            
                            if let model = features.first?.sourceModel {
                                MetadataCard(label: "Model", value: model, icon: "cpu")
                            }
                        }
                    }
                }
                
                // Re-extract button
                if !features.isEmpty {
                    Button(action: onExtract) {
                        SwiftUI.Label("Re-extract Features", systemImage: "arrow.triangle.2.circlepath")
                            .frame(maxWidth: .infinity)
                            .padding()
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(24)
        }
        .background(Color(.systemBackground))
    }
}

struct MetadataCard: View {
    let label: String
    let value: String
    var icon: String? = nil
    
    var body: some View {
        HStack(spacing: 12) {
            if let icon = icon {
                Image(systemName: icon)
                    .foregroundStyle(.blue)
                    .frame(width: 24)
            }
            
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            Spacer()
            
            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(8)
    }
}
