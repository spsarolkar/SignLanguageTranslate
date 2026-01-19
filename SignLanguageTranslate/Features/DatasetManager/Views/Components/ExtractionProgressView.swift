import SwiftUI

/// Displays extraction progress for a dataset
///
/// Shows current category being extracted, overall progress,
/// and statistics about files and bytes extracted.
struct ExtractionProgressView: View {
    var tracker: ExtractionProgressTracker
    
    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Image(systemName: "archivebox")
                    .foregroundStyle(.purple)
                    .font(.title3)
                
                Text("Extracting Files")
                    .font(.headline)
                
                Spacer()
                
                Text("\(Int(tracker.overallProgress * 100))%")
                    .font(.headline)
                    .foregroundStyle(.purple)
            }
            
            // Progress bar
            ProgressView(value: tracker.overallProgress)
                .tint(.purple)
            
            // Current category
            if let category = tracker.currentCategory {
                HStack {
                    Text("Category:")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    Text(category)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Spacer()
                    
                    Text("\(tracker.categoriesCompleted)/\(tracker.totalCategories)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            // Statistics
            HStack(spacing: 12) {
                StatBadge(
                    title: "Files",
                    value: "\(tracker.filesExtracted)",
                    color: .purple
                )
                
                StatBadge(
                    title: "Size",
                    value: "0 MB",  // TODO: Track bytes
                    color: .purple
                )
                
                if let timeRemaining = tracker.estimatedTimeRemaining {
                    StatBadge(
                        title: "Remaining",
                        value: tracker.formattedTimeRemaining ?? "--",
                        color: .secondary
                    )
                }
            }
            
            // Status message
            if tracker.status != .extracting {
                Text(tracker.statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.regularMaterial)
        .cornerRadius(12)
    }
    
    private func formattedSize(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

