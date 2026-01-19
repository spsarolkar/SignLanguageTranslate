import SwiftUI

/// Displays ingestion progress for importing videos into SwiftData
///
/// Shows samples created, current file being processed,
/// and any errors encountered during ingestion.
struct IngestionProgressView: View {
    var tracker: IngestionProgressTracker
    
    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Image(systemName: "square.and.arrow.down.on.square")
                    .foregroundStyle(.green)
                    .font(.title3)
                
                Text("Importing Videos")
                    .font(.headline)
                
                Spacer()
                
                Text("\(tracker.progressPercentage)%")
                    .font(.headline)
                    .foregroundStyle(.green)
            }
            
            // Progress bar
            ProgressView(value: tracker.progress)
                .tint(.green)
            
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
                }
            }
            
            // Current file
            if let file = tracker.currentFile {
                Text(file)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            
            // Statistics
            HStack(spacing: 12) {
                StatBadge(
                    title: "Files",
                    value: "\(tracker.filesProcessed)",
                    color: .green
                )
                
                StatBadge(
                    title: "Samples",
                    value: "\(tracker.samplesCreated)",
                    color: .green
                )
                
                StatBadge(
                    title: "Labels",
                    value: "\(tracker.labelsCreated)",
                    color: .green
                )
                
                if tracker.hasErrors {
                    StatBadge(
                        title: "Errors",
                        value: "\(tracker.errors.count)",
                        color: .red
                    )
                }
            }
            
            // Errors (if any)
            if tracker.hasErrors {
                DisclosureGroup("Errors (\(tracker.errors.count))") {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(tracker.errors.prefix(10).enumerated()), id: \.offset) { _, error in
                                Text(error)
                                    .font(.caption2)
                                    .foregroundStyle(.red)
                                    .lineLimit(2)
                            }
                            
                            if tracker.errors.count > 10 {
                                Text("... and \(tracker.errors.count - 10) more")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .frame(maxHeight: 100)
                }
                .tint(.red)
            }
            
            // Status message
            if tracker.status != .ingesting {
                Text(tracker.status.displayText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.regularMaterial)
        .cornerRadius(12)
    }
}

