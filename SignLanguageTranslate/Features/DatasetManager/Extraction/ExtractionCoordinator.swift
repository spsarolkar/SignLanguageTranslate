import Foundation

/// Result of a dataset extraction operation
struct ExtractionResult: Sendable {
    /// Name of the dataset
    let datasetName: String
    /// Categories that were extracted
    let categories: [CategoryExtractionResult]
    /// Total number of files extracted
    let totalFilesExtracted: Int
    /// Total bytes extracted
    let totalBytesExtracted: Int64
    /// Time taken for extraction
    let duration: TimeInterval
    /// Whether extraction completed successfully
    let success: Bool
    /// Error message if extraction failed
    let errorMessage: String?

    /// All extracted file URLs across all categories
    var allExtractedFiles: [URL] {
        categories.flatMap { $0.extractedFiles }
    }
}

/// Result of extracting a single category
struct CategoryExtractionResult: Sendable {
    /// Category name
    let category: String
    /// Number of parts that were extracted
    let partsExtracted: Int
    /// Files that were extracted
    let extractedFiles: [URL]
    /// Destination directory
    let destinationURL: URL
    /// Whether this category completed successfully
    let success: Bool
    /// Error message if extraction failed
    let errorMessage: String?
}

/// Progress information for dataset extraction
struct DatasetExtractionProgress: Sendable {
    /// Name of the dataset being extracted
    let datasetName: String
    /// Current category being extracted (nil if complete)
    let currentCategory: String?
    /// Number of categories completed
    let categoriesCompleted: Int
    /// Total number of categories
    let totalCategories: Int
    /// Progress within the current category (0.0 to 1.0)
    let currentCategoryProgress: Double
    /// Overall extraction progress (0.0 to 1.0)
    let overallProgress: Double
    /// Current status
    let status: ExtractionStatus
    /// Current file being extracted
    var currentFile: String?
    /// Number of files extracted in current category
    var filesExtracted: Int?
    /// Total files in current category
    var totalFiles: Int?

    /// Progress as percentage (0-100)
    var progressPercentage: Int {
        Int((overallProgress * 100).rounded())
    }
}

/// Status of extraction operation
enum ExtractionStatus: String, Sendable {
    case pending
    case extracting
    case completed
    case failed
    case cancelled
}

/// Actor that coordinates the extraction of downloaded dataset files
///
/// Handles:
/// - Grouping files by category
/// - Detecting and handling multi-part archives
/// - Coordinating extraction to proper destination directories
/// - Progress tracking across the entire dataset
///
/// ## Dataset Directory Structure
/// ```
/// Documents/
/// └── Datasets/
///     └── INCLUDE/
///         ├── Animals/
///         │   └── (extracted video files)
///         ├── Greetings/
///         │   └── (extracted video files)
///         └── Seasons/
///             └── (extracted video files)
/// ```
actor ExtractionCoordinator {

    // MARK: - Properties

    /// The zip extractor instance
    private let zipExtractor: ZipExtractor

    /// Base directory for extracted datasets
    private let datasetsBaseURL: URL

    /// Whether an extraction is in progress
    private(set) var isExtracting = false

    /// Current extraction progress
    private(set) var currentProgress: DatasetExtractionProgress?

    // MARK: - Initialization

    init(
        zipExtractor: ZipExtractor? = nil,
        datasetsBaseURL: URL? = nil
    ) {
        self.zipExtractor = zipExtractor ?? ZipExtractor()

        // Default to Documents/Datasets
        if let baseURL = datasetsBaseURL {
            self.datasetsBaseURL = baseURL
        } else {
            let documentsURL = FileManager.default.urls(
                for: .documentDirectory,
                in: .userDomainMask
            ).first!
            self.datasetsBaseURL = documentsURL.appendingPathComponent("Datasets")
        }
    }

    // MARK: - Public Methods

    /// Extract a dataset from downloaded files
    ///
    /// Groups files by category, handles multi-part archives,
    /// and extracts to the proper directory structure.
    ///
    /// - Parameters:
    ///   - datasetName: Name of the dataset (e.g., "INCLUDE")
    ///   - downloadedFiles: Array of downloaded zip file URLs
    ///   - progressHandler: Optional closure for progress updates (called on MainActor)
    /// - Returns: ExtractionResult with details about the extraction
    /// - Throws: ExtractionError if extraction fails
    func extractDataset(
        datasetName: String,
        downloadedFiles: [URL],
        progressHandler: (@Sendable (DatasetExtractionProgress) -> Void)? = nil
    ) async throws -> ExtractionResult {
        guard !isExtracting else {
            throw ExtractionError.extractionFailed("Extraction already in progress")
        }

        isExtracting = true
        let startTime = Date()

        defer {
            isExtracting = false
            currentProgress = nil
        }

        // Create dataset directory
        let datasetURL = datasetsBaseURL.appendingPathComponent(datasetName)
        try FileManager.default.createDirectory(
            at: datasetURL,
            withIntermediateDirectories: true
        )

        // Group files by category
        let groupedFiles = MultiPartMerger.groupByCategory(downloadedFiles)
        let totalCategories = groupedFiles.count

        var categoryResults: [CategoryExtractionResult] = []
        var totalFilesExtracted = 0
        var totalBytesExtracted: Int64 = 0
        var categoryIndex = 0

        // Extract each category
        for (category, files) in groupedFiles.sorted(by: { $0.key < $1.key }) {
            categoryIndex += 1

            // Update progress
            let progress = DatasetExtractionProgress(
                datasetName: datasetName,
                currentCategory: category,
                categoriesCompleted: categoryIndex - 1,
                totalCategories: totalCategories,
                currentCategoryProgress: 0,
                overallProgress: Double(categoryIndex - 1) / Double(totalCategories),
                status: .extracting
            )
            currentProgress = progress
            progressHandler?(progress)

            // Destination for this category
            let categoryDestination = datasetURL.appendingPathComponent(category)

            do {
                // Check if multi-part
                let parts = MultiPartMerger.groupParts(files)[category] ?? []

                var extractedFiles: [URL]

                if parts.count > 1 {
                    // Multi-part extraction
                    extractedFiles = try await extractMultiPartCategory(
                        category: category,
                        datasetName: datasetName,
                        parts: parts.map { $0.url },
                        destination: categoryDestination,
                        categoryIndex: categoryIndex,
                        totalCategories: totalCategories,
                        progressHandler: progressHandler
                    )
                } else {
                    // Single file extraction
                    extractedFiles = try await extractSingleCategory(
                        category: category,
                        datasetName: datasetName,
                        zipURL: files.first!,
                        destination: categoryDestination,
                        categoryIndex: categoryIndex,
                        totalCategories: totalCategories,
                        progressHandler: progressHandler
                    )
                }

                let result = CategoryExtractionResult(
                    category: category,
                    partsExtracted: files.count,
                    extractedFiles: extractedFiles,
                    destinationURL: categoryDestination,
                    success: true,
                    errorMessage: nil
                )
                categoryResults.append(result)

                totalFilesExtracted += extractedFiles.count
                totalBytesExtracted += extractedFiles.reduce(0) { sum, url in
                    let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
                    return sum + size
                }

            } catch {
                let result = CategoryExtractionResult(
                    category: category,
                    partsExtracted: 0,
                    extractedFiles: [],
                    destinationURL: categoryDestination,
                    success: false,
                    errorMessage: error.localizedDescription
                )
                categoryResults.append(result)
            }
        }

        let duration = Date().timeIntervalSince(startTime)
        let allSuccess = categoryResults.allSatisfy { $0.success }

        // Final progress update
        let finalProgress = DatasetExtractionProgress(
            datasetName: datasetName,
            currentCategory: nil,
            categoriesCompleted: totalCategories,
            totalCategories: totalCategories,
            currentCategoryProgress: 1.0,
            overallProgress: 1.0,
            status: allSuccess ? .completed : .failed
        )
        currentProgress = finalProgress
        progressHandler?(finalProgress)

        return ExtractionResult(
            datasetName: datasetName,
            categories: categoryResults,
            totalFilesExtracted: totalFilesExtracted,
            totalBytesExtracted: totalBytesExtracted,
            duration: duration,
            success: allSuccess,
            errorMessage: allSuccess ? nil : "Some categories failed to extract"
        )
    }

    /// Extract a dataset using a filename-to-URL mapping
    ///
    /// This variant allows specifying the original filenames separately from the actual
    /// file URLs. Useful when downloaded files have been renamed (e.g., with UUID prefixes).
    ///
    /// - Parameters:
    ///   - datasetName: Name of the dataset (e.g., "INCLUDE")
    ///   - fileMapping: Dictionary mapping original filenames to actual file URLs
    ///   - progressHandler: Optional closure for progress updates
    /// - Returns: ExtractionResult with details about the extraction
    /// - Throws: ExtractionError if extraction fails
    func extractDatasetWithMapping(
        datasetName: String,
        fileMapping: [String: URL],
        progressHandler: (@Sendable (DatasetExtractionProgress) -> Void)? = nil
    ) async throws -> ExtractionResult {
        guard !isExtracting else {
            throw ExtractionError.extractionFailed("Extraction already in progress")
        }

        isExtracting = true
        let startTime = Date()

        defer {
            isExtracting = false
            currentProgress = nil
        }

        // Create dataset directory
        let datasetURL = datasetsBaseURL.appendingPathComponent(datasetName)
        try FileManager.default.createDirectory(
            at: datasetURL,
            withIntermediateDirectories: true
        )

        print("[ExtractionCoordinator] Starting extraction for dataset: \(datasetName)")
        print("[ExtractionCoordinator] File mapping has \(fileMapping.count) entries:")
        for (name, url) in fileMapping.prefix(5) {
            print("  - \(name) -> \(url.lastPathComponent)")
        }

        // Group files by category using the original filenames
        // Create fake URLs with original names for grouping, then map back to real URLs
        let fakeURLs = fileMapping.keys.map { filename in
            URL(fileURLWithPath: "/tmp/\(filename)")
        }
        let groupedByOriginalName = MultiPartMerger.groupByCategory(fakeURLs)

        print("[ExtractionCoordinator] Grouped by original name: \(groupedByOriginalName.keys.sorted())")

        // Now map back to real URLs
        var groupedFiles: [String: [URL]] = [:]
        for (category, fakeUrls) in groupedByOriginalName {
            let realURLs = fakeUrls.compactMap { fakeURL -> URL? in
                let originalFilename = fakeURL.lastPathComponent
                return fileMapping[originalFilename]
            }
            if !realURLs.isEmpty {
                groupedFiles[category] = realURLs
                print("[ExtractionCoordinator] Category '\(category)' has \(realURLs.count) files")
            }
        }

        // Also need to track original filenames for multi-part detection
        let filenameToURL: [String: URL] = fileMapping

        let totalCategories = groupedFiles.count
        print("[ExtractionCoordinator] Total categories to extract: \(totalCategories)")

        var categoryResults: [CategoryExtractionResult] = []
        var totalFilesExtracted = 0
        var totalBytesExtracted: Int64 = 0
        var categoryIndex = 0

        // Extract each category
        for (category, files) in groupedFiles.sorted(by: { $0.key < $1.key }) {
            categoryIndex += 1

            // Update progress
            let progress = DatasetExtractionProgress(
                datasetName: datasetName,
                currentCategory: category,
                categoriesCompleted: categoryIndex - 1,
                totalCategories: totalCategories,
                currentCategoryProgress: 0,
                overallProgress: Double(categoryIndex - 1) / Double(totalCategories),
                status: .extracting
            )
            currentProgress = progress
            progressHandler?(progress)

            // Extract to dataset root - the zip already contains the category folder inside
            // e.g., Animals.zip contains Animals/Dog/video.mp4
            // So we extract to Documents/Datasets/INCLUDE/ (not .../INCLUDE/Animals/)
            let extractionDestination = datasetURL
            // The actual category destination is where files will be after extraction
            let categoryDestination = datasetURL.appendingPathComponent(category)

            print("[ExtractionCoordinator] Extracting category '\(category)' to dataset root: \(extractionDestination.path)")
            print("[ExtractionCoordinator] Source files for '\(category)':")
            for file in files {
                print("  - \(file.path)")
            }

            do {
                // Get original filenames for these files to detect multi-part
                let originalFilenames = files.compactMap { url -> String? in
                    for (filename, fileURL) in filenameToURL {
                        if fileURL == url {
                            return filename
                        }
                    }
                    return nil
                }
                print("[ExtractionCoordinator] Original filenames: \(originalFilenames)")

                // Check if multi-part using original filenames
                let fakeURLsForParts = originalFilenames.map { URL(fileURLWithPath: "/tmp/\($0)") }
                let parts = MultiPartMerger.groupParts(fakeURLsForParts)[category] ?? []

                var extractedFiles: [URL]

                if parts.count > 1 {
                    // Multi-part extraction - sort files by part number
                    let sortedFiles = parts.compactMap { partInfo -> URL? in
                        filenameToURL[partInfo.url.lastPathComponent]
                    }

                    extractedFiles = try await extractMultiPartCategory(
                        category: category,
                        datasetName: datasetName,
                        parts: sortedFiles,
                        destination: extractionDestination,
                        categoryIndex: categoryIndex,
                        totalCategories: totalCategories,
                        progressHandler: progressHandler
                    )
                } else {
                    // Single file extraction
                    extractedFiles = try await extractSingleCategory(
                        category: category,
                        datasetName: datasetName,
                        zipURL: files.first!,
                        destination: extractionDestination,
                        categoryIndex: categoryIndex,
                        totalCategories: totalCategories,
                        progressHandler: progressHandler
                    )
                }

                let result = CategoryExtractionResult(
                    category: category,
                    partsExtracted: files.count,
                    extractedFiles: extractedFiles,
                    destinationURL: categoryDestination,
                    success: true,
                    errorMessage: nil
                )
                categoryResults.append(result)

                totalFilesExtracted += extractedFiles.count
                totalBytesExtracted += extractedFiles.reduce(0) { sum, url in
                    let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
                    return sum + size
                }

            } catch {
                let result = CategoryExtractionResult(
                    category: category,
                    partsExtracted: 0,
                    extractedFiles: [],
                    destinationURL: categoryDestination,
                    success: false,
                    errorMessage: error.localizedDescription
                )
                categoryResults.append(result)
            }
        }

        let duration = Date().timeIntervalSince(startTime)
        let allSuccess = categoryResults.allSatisfy { $0.success }

        // Final progress update
        let finalProgress = DatasetExtractionProgress(
            datasetName: datasetName,
            currentCategory: nil,
            categoriesCompleted: totalCategories,
            totalCategories: totalCategories,
            currentCategoryProgress: 1.0,
            overallProgress: 1.0,
            status: allSuccess ? .completed : .failed
        )
        currentProgress = finalProgress
        progressHandler?(finalProgress)

        return ExtractionResult(
            datasetName: datasetName,
            categories: categoryResults,
            totalFilesExtracted: totalFilesExtracted,
            totalBytesExtracted: totalBytesExtracted,
            duration: duration,
            success: allSuccess,
            errorMessage: allSuccess ? nil : "Some categories failed to extract"
        )
    }

    /// Group downloaded files by category
    /// - Parameter files: Array of file URLs
    /// - Returns: Dictionary mapping category names to file URLs
    nonisolated func groupByCategory(_ files: [URL]) -> [String: [URL]] {
        MultiPartMerger.groupByCategory(files)
    }

    /// Extract a multi-part category
    /// - Parameters:
    ///   - category: Category name
    ///   - parts: Array of zip file URLs for this category
    ///   - destination: Destination directory
    /// - Returns: URL of the extraction destination
    func mergeMultiPartCategory(
        category: String,
        parts: [URL],
        destination: URL
    ) async throws -> URL {
        _ = try await zipExtractor.extractMultiPart(
            zipURLs: parts,
            to: destination
        )
        return destination
    }

    /// Cancel the current extraction
    func cancel() async {
        await zipExtractor.cancel()
    }

    /// Get the destination URL for a dataset
    /// - Parameter datasetName: Name of the dataset
    /// - Returns: URL where the dataset will be extracted
    nonisolated func destinationURL(for datasetName: String) -> URL {
        datasetsBaseURL.appendingPathComponent(datasetName)
    }

    /// Check if a dataset has already been extracted
    /// - Parameter datasetName: Name of the dataset
    /// - Returns: True if the dataset directory exists and contains files
    nonisolated func isDatasetExtracted(_ datasetName: String) -> Bool {
        let url = destinationURL(for: datasetName)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return false
        }

        // Check if directory contains any files
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: url.path) else {
            return false
        }

        return !contents.isEmpty
    }

    /// Get list of extracted categories for a dataset
    /// - Parameter datasetName: Name of the dataset
    /// - Returns: Array of category names that have been extracted
    nonisolated func extractedCategories(for datasetName: String) -> [String] {
        let url = destinationURL(for: datasetName)
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: url.path) else {
            return []
        }

        return contents.filter { name in
            var isDirectory: ObjCBool = false
            let path = url.appendingPathComponent(name).path
            return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
        }
    }

    /// Delete extracted dataset
    /// - Parameter datasetName: Name of the dataset to delete
    nonisolated func deleteDataset(_ datasetName: String) throws {
        let url = destinationURL(for: datasetName)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    // MARK: - Private Methods

    private func extractSingleCategory(
        category: String,
        datasetName: String,
        zipURL: URL,
        destination: URL,
        categoryIndex: Int,
        totalCategories: Int,
        progressHandler: (@Sendable (DatasetExtractionProgress) -> Void)?
    ) async throws -> [URL] {
        // Create a Sendable progress wrapper
        let progressWrapper: @Sendable (ExtractionProgress) -> Void = { extractionProgress in
            let categoryProgress = extractionProgress.progress
            let overallBase = Double(categoryIndex - 1) / Double(totalCategories)
            let overallIncrement = categoryProgress / Double(totalCategories)

            let datasetProgress = DatasetExtractionProgress(
                datasetName: datasetName,
                currentCategory: category,
                categoriesCompleted: categoryIndex - 1,
                totalCategories: totalCategories,
                currentCategoryProgress: categoryProgress,
                overallProgress: overallBase + overallIncrement,
                status: .extracting,
                currentFile: extractionProgress.currentFile,
                filesExtracted: extractionProgress.filesExtracted,
                totalFiles: extractionProgress.totalFiles
            )

            progressHandler?(datasetProgress)
        }

        return try await zipExtractor.extract(
            zipURL: zipURL,
            to: destination,
            overwrite: true,
            progressHandler: progressWrapper
        )
    }

    private func extractMultiPartCategory(
        category: String,
        datasetName: String,
        parts: [URL],
        destination: URL,
        categoryIndex: Int,
        totalCategories: Int,
        progressHandler: (@Sendable (DatasetExtractionProgress) -> Void)?
    ) async throws -> [URL] {
        // Create a Sendable progress wrapper
        let progressWrapper: @Sendable (ExtractionProgress) -> Void = { extractionProgress in
            let categoryProgress = extractionProgress.progress
            let overallBase = Double(categoryIndex - 1) / Double(totalCategories)
            let overallIncrement = categoryProgress / Double(totalCategories)

            let datasetProgress = DatasetExtractionProgress(
                datasetName: datasetName,
                currentCategory: category,
                categoriesCompleted: categoryIndex - 1,
                totalCategories: totalCategories,
                currentCategoryProgress: categoryProgress,
                overallProgress: overallBase + overallIncrement,
                status: .extracting,
                currentFile: extractionProgress.currentFile,
                filesExtracted: extractionProgress.filesExtracted,
                totalFiles: extractionProgress.totalFiles
            )

            progressHandler?(datasetProgress)
        }

        return try await zipExtractor.extractMultiPart(
            zipURLs: parts,
            to: destination,
            progressHandler: progressWrapper
        )
    }
}
