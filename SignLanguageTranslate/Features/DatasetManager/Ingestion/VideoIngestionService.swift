import Foundation
import SwiftData

/// Result of a video ingestion operation
struct IngestionResult: Sendable {
    let samplesCreated: Int
    let labelsCreated: Int
    let categoriesCreated: Int
    let errors: [IngestionError]
    let duration: TimeInterval
    
    var success: Bool {
        errors.isEmpty
    }
    
    var errorCount: Int {
        errors.count
    }
}

/// Error occurring during ingestion
struct IngestionError: Sendable {
    let filePath: String
    let error: Error
    
    var localizedDescription: String {
        "\(filePath): \(error.localizedDescription)"
    }
}

/// Progress information for ingestion
struct IngestionProgress: Sendable {
    let currentFile: String
    let filesProcessed: Int
    let totalFiles: Int
    let progress: Double
}

/// Actor that manages video file ingestion into SwiftData
///
/// Scans extracted video files, creates VideoSample records,
/// and links them to appropriate Labels (categories and words).
///
/// ## Usage
/// ```swift
/// let service = VideoIngestionService(modelContext: context)
/// let result = try await service.ingestDataset(
///     name: "INCLUDE",
///     type: .include,
///     directory: datasetsURL.appendingPathComponent("INCLUDE")
/// )
/// print("Created \(result.samplesCreated) samples")
/// ```
actor VideoIngestionService {
    
    // MARK: - Properties
    
    /// The ModelContext for SwiftData operations
    let modelContext: ModelContext
    
    /// Progress callback
    var onProgress: (@Sendable (IngestionProgress) -> Void)?
    
    // MARK: - Initialization
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    // MARK: - Public Methods
    
    /// Ingest an entire dataset
    /// - Parameters:
    ///   - name: Dataset name (e.g., "INCLUDE")
    ///   - type: Dataset type
    ///   - directory: Directory containing extracted files
    /// - Returns: IngestionResult with statistics and errors
    func ingestDataset(
        name: String,
        type: DatasetType,
        directory: URL
    ) async throws -> IngestionResult {
        let startTime = Date()
        
        // Scan for video files
        let scannedFiles = try VideoFileScanner.scan(directory: directory)
        
        guard !scannedFiles.isEmpty else {
            throw IngestionServiceError.noFilesFound(directory)
        }
        
        var samplesCreated = 0
        var labelsCreated = 0
        var categoriesProcessed = Set<String>()
        var errors: [IngestionError] = []
        
        // Group files by category
        let groupedByCategory = Dictionary(grouping: scannedFiles) { $0.category }
        
        // Process each category
        for (category, files) in groupedByCategory {
            do {
                let categoryResult = try await ingestCategory(
                    name: category,
                    files: files,
                    datasetName: name
                )
                
                samplesCreated += categoryResult.samplesCreated
                labelsCreated += categoryResult.labelsCreated
                categoriesProcessed.insert(category)
                errors.append(contentsOf: categoryResult.errors)
                
            } catch {
                errors.append(IngestionError(
                    filePath: category,
                    error: error
                ))
            }
        }
        
        // Save all changes
        try modelContext.save()
        
        let duration = Date().timeIntervalSince(startTime)
        
        return IngestionResult(
            samplesCreated: samplesCreated,
            labelsCreated: labelsCreated,
            categoriesCreated: categoriesProcessed.count,
            errors: errors,
            duration: duration
        )
    }
    
    /// Ingest a single category
    /// - Parameters:
    ///   - name: Category name
    ///   - files: Scanned files in this category
    ///   - datasetName: Name of the parent dataset
    /// - Returns: Category ingestion result
    private func ingestCategory(
        name: String,
        files: [ScannedFile],
        datasetName: String
    ) async throws -> CategoryIngestionResult {
        var samplesCreated = 0
        var labelsCreatedCount = 0
        var errors: [IngestionError] = []
        
        // Find or create category label
        let categoryLabel = try await findOrCreateLabel(name: name, type: .category)
        if categoryLabel.videoSamples == nil || categoryLabel.videoSamples!.isEmpty {
            labelsCreatedCount += 1
        }
        
        // Group files by word
        let groupedByWord = Dictionary(grouping: files) { $0.wordLabel }
        
        // Process each word
        for (wordName, wordFiles) in groupedByWord {
            do {
                // Find or create word label
                let wordLabel = try await findOrCreateLabel(name: wordName, type: .word)
                if wordLabel.videoSamples == nil || wordLabel.videoSamples!.isEmpty {
                    labelsCreatedCount += 1
                }
                
                // Create video samples for each file
                for file in wordFiles {
                    do {
                        // Extract metadata
                        let metadata = try? await VideoMetadataExtractor.extract(from: file.url)
                        
                        // Create relative path from datasets directory
                        // Create relative path from datasets directory
                        let datasetsDir = await MainActor.run { FileManager.default.datasetsDirectory }
                        let relativePath = file.url.path.replacingOccurrences(
                            of: datasetsDir.path + "/",
                            with: ""
                        )
                        
                        // Create video sample
                        let sample = VideoSample(
                            localPath: relativePath,
                            datasetName: datasetName,
                            originalFilename: file.url.lastPathComponent,
                            fileSize: file.fileSize,
                            duration: metadata?.duration ?? 0
                        )
                        
                        // Link labels
                        sample.addLabel(categoryLabel)
                        sample.addLabel(wordLabel)
                        
                        // Insert into context
                        modelContext.insert(sample)
                        samplesCreated += 1
                        
                        // Report progress
                        let progress = IngestionProgress(
                            currentFile: file.url.lastPathComponent,
                            filesProcessed: samplesCreated,
                            totalFiles: files.count,
                            progress: Double(samplesCreated) / Double(files.count)
                        )
                        onProgress?(progress)
                        
                    } catch {
                        errors.append(IngestionError(
                            filePath: file.url.path,
                            error: error
                        ))
                    }
                }
                
            } catch {
                errors.append(IngestionError(
                    filePath: wordName,
                    error: error
                ))
            }
        }
        
        // Batch save for performance
        if samplesCreated > 0 {
            try modelContext.save()
        }
        
        return CategoryIngestionResult(
            category: name,
            samplesCreated: samplesCreated,
            labelsCreated: labelsCreatedCount,
            errors: errors
        )
    }
    
    // MARK: - Label Management
    
    /// Find or create a label (idempotent)
    /// - Parameters:
    ///   - name: Label name
    ///   - type: Label type
    /// - Returns: Existing or newly created label
    private func findOrCreateLabel(
        name: String,
        type: LabelType
    ) async throws -> Label {
        // Create fetch descriptor
        let predicate = #Predicate<Label> { label in
            label.name == name && label.typeRawValue == type.rawValue
        }
        
        var descriptor = FetchDescriptor<Label>(predicate: predicate)
        descriptor.fetchLimit = 1
        
        // Try to fetch existing label
        let existing = try modelContext.fetch(descriptor)
        
        if let label = existing.first {
            return label
        }
        
        // Create new label
        let label = Label(name: name, type: type)
        modelContext.insert(label)
        
        return label
    }
}

// MARK: - Supporting Types

/// Result of ingesting a single category
private struct CategoryIngestionResult {
    let category: String
    let samplesCreated: Int
    let labelsCreated: Int
    let errors: [IngestionError]
}

/// Errors specific to ingestion service
enum IngestionServiceError: LocalizedError {
    case noFilesFound(URL)
    case invalidDirectory(URL)
    case contextNotAvailable
    
    var errorDescription: String? {
        switch self {
        case .noFilesFound(let url):
            return "No video files found in: \(url.path)"
        case .invalidDirectory(let url):
            return "Invalid directory: \(url.path)"
        case .contextNotAvailable:
            return "Model context not available"
        }
    }
}
