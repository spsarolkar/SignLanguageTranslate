import Foundation
import ZIPFoundation

/// Progress information for extraction operations
struct ExtractionProgress: Sendable {
    /// Current file being extracted
    let currentFile: String
    /// Number of files extracted so far
    let filesExtracted: Int
    /// Total number of files to extract
    let totalFiles: Int
    /// Bytes extracted so far
    let bytesExtracted: Int64
    /// Total bytes to extract
    let totalBytes: Int64

    /// Progress as a fraction (0.0 to 1.0)
    var progress: Double {
        guard totalFiles > 0 else { return 0 }
        return Double(filesExtracted) / Double(totalFiles)
    }

    /// Progress as percentage (0-100)
    var progressPercentage: Int {
        Int((progress * 100).rounded())
    }
}

/// Errors that can occur during extraction
enum ExtractionError: LocalizedError, Sendable {
    case fileNotFound(URL)
    case invalidArchive(URL)
    case destinationExists(URL)
    case extractionFailed(String)
    case cancelled
    case insufficientDiskSpace(required: Int64, available: Int64)
    case corruptedArchive(URL)
    case multiPartMismatch(expected: Int, found: Int)

    var errorDescription: String? {
        switch self {
        case .fileNotFound(let url):
            return "Archive not found: \(url.lastPathComponent)"
        case .invalidArchive(let url):
            return "Invalid archive: \(url.lastPathComponent)"
        case .destinationExists(let url):
            return "Destination already exists: \(url.lastPathComponent)"
        case .extractionFailed(let message):
            return "Extraction failed: \(message)"
        case .cancelled:
            return "Extraction was cancelled"
        case .insufficientDiskSpace(let required, let available):
            let requiredStr = ByteCountFormatter.string(fromByteCount: required, countStyle: .file)
            let availableStr = ByteCountFormatter.string(fromByteCount: available, countStyle: .file)
            return "Insufficient disk space. Required: \(requiredStr), Available: \(availableStr)"
        case .corruptedArchive(let url):
            return "Archive is corrupted: \(url.lastPathComponent)"
        case .multiPartMismatch(let expected, let found):
            return "Multi-part archive incomplete. Expected \(expected) parts, found \(found)"
        }
    }
}

/// Actor that handles zip file extraction using ZIPFoundation
///
/// Provides thread-safe extraction operations with progress tracking
/// and cancellation support.
///
/// ## Usage
/// ```swift
/// let extractor = ZipExtractor()
/// let extractedFiles = try await extractor.extract(
///     zipURL: archiveURL,
///     to: destinationURL,
///     progressHandler: { progress in
///         print("Extracting: \(progress.currentFile) (\(progress.progressPercentage)%)")
///     }
/// )
/// ```
actor ZipExtractor {

    // MARK: - Properties

    /// Whether an extraction operation is currently in progress
    private(set) var isExtracting = false

    /// Whether cancellation has been requested
    private var isCancelled = false

    /// Current extraction progress
    private(set) var currentProgress: ExtractionProgress?

    // MARK: - Initialization

    init() {}

    // MARK: - Public Methods

    /// Extract a zip archive to a destination directory
    /// - Parameters:
    ///   - zipURL: URL of the zip file to extract
    ///   - destinationURL: Directory to extract files to
    ///   - overwrite: Whether to overwrite existing files (default: false)
    ///   - progressHandler: Optional closure called with progress updates
    /// - Returns: Array of URLs for all extracted files
    /// - Throws: ExtractionError if extraction fails
    func extract(
        zipURL: URL,
        to destinationURL: URL,
        overwrite: Bool = false,
        progressHandler: ((ExtractionProgress) -> Void)? = nil
    ) async throws -> [URL] {
        guard !isExtracting else {
            throw ExtractionError.extractionFailed("Extraction already in progress")
        }

        isExtracting = true
        isCancelled = false
        currentProgress = nil

        defer {
            isExtracting = false
            currentProgress = nil
        }

        // Validate source file exists
        guard FileManager.default.fileExists(atPath: zipURL.path) else {
            throw ExtractionError.fileNotFound(zipURL)
        }

        // Check destination
        if FileManager.default.fileExists(atPath: destinationURL.path) && !overwrite {
            throw ExtractionError.destinationExists(destinationURL)
        }

        // Create destination directory
        try FileManager.default.createDirectory(
            at: destinationURL,
            withIntermediateDirectories: true
        )

        // Open the archive
        guard let archive = Archive(url: zipURL, accessMode: .read) else {
            throw ExtractionError.invalidArchive(zipURL)
        }

        // Get total count and size for progress tracking
        let entries = Array(archive)
        let totalFiles = entries.count
        let totalBytes = entries.reduce(0) { $0 + Int64($1.uncompressedSize) }

        // Check available disk space
        try await checkDiskSpace(required: totalBytes, at: destinationURL)

        var extractedFiles: [URL] = []
        var filesExtracted = 0
        var bytesExtracted: Int64 = 0

        // Extract each entry
        for entry in entries {
            // Check for cancellation
            if isCancelled {
                // Cleanup partially extracted files
                try? FileManager.default.removeItem(at: destinationURL)
                throw ExtractionError.cancelled
            }

            let entryPath = entry.path
            let destinationPath = destinationURL.appendingPathComponent(entryPath)

            // Update progress
            let progress = ExtractionProgress(
                currentFile: entryPath,
                filesExtracted: filesExtracted,
                totalFiles: totalFiles,
                bytesExtracted: bytesExtracted,
                totalBytes: totalBytes
            )
            currentProgress = progress
            progressHandler?(progress)

            // Create parent directories if needed
            let parentDir = destinationPath.deletingLastPathComponent()
            if !FileManager.default.fileExists(atPath: parentDir.path) {
                try FileManager.default.createDirectory(
                    at: parentDir,
                    withIntermediateDirectories: true
                )
            }

            // Skip directories (they're created above)
            guard entry.type == .file else {
                filesExtracted += 1
                continue
            }

            // Extract file
            do {
                _ = try archive.extract(entry, to: destinationPath, skipCRC32: false)
                extractedFiles.append(destinationPath)
                bytesExtracted += Int64(entry.uncompressedSize)
            } catch {
                throw ExtractionError.extractionFailed("Failed to extract \(entryPath): \(error.localizedDescription)")
            }

            filesExtracted += 1

            // Yield to allow other tasks
            await Task.yield()
        }

        // Final progress update
        let finalProgress = ExtractionProgress(
            currentFile: "",
            filesExtracted: filesExtracted,
            totalFiles: totalFiles,
            bytesExtracted: bytesExtracted,
            totalBytes: totalBytes
        )
        currentProgress = finalProgress
        progressHandler?(finalProgress)

        return extractedFiles
    }

    /// Extract multiple zip archives (multi-part) to a destination directory
    ///
    /// Multi-part archives are extracted in sequence to the same destination.
    /// Files are sorted by part number before extraction.
    ///
    /// - Parameters:
    ///   - zipURLs: Array of zip file URLs (will be sorted by part number)
    ///   - destinationURL: Directory to extract files to
    ///   - progressHandler: Optional closure called with progress updates
    /// - Returns: Array of URLs for all extracted files
    /// - Throws: ExtractionError if extraction fails
    func extractMultiPart(
        zipURLs: [URL],
        to destinationURL: URL,
        progressHandler: ((ExtractionProgress) -> Void)? = nil
    ) async throws -> [URL] {
        guard !zipURLs.isEmpty else {
            return []
        }

        // Sort by part number
        let sortedURLs = MultiPartMerger.sortByPartNumber(zipURLs)

        // Validate all parts are present
        if let partInfo = MultiPartMerger.parsePartInfo(from: sortedURLs.first!) {
            guard sortedURLs.count == partInfo.totalParts else {
                throw ExtractionError.multiPartMismatch(
                    expected: partInfo.totalParts,
                    found: sortedURLs.count
                )
            }
        }

        var allExtractedFiles: [URL] = []

        // Calculate total size across all archives for progress
        var totalBytes: Int64 = 0
        var totalFiles = 0

        for zipURL in sortedURLs {
            guard let archive = Archive(url: zipURL, accessMode: .read) else {
                throw ExtractionError.invalidArchive(zipURL)
            }
            let entries = Array(archive)
            totalFiles += entries.count
            totalBytes += entries.reduce(0) { $0 + Int64($1.uncompressedSize) }
        }

        // Check disk space for total
        try await checkDiskSpace(required: totalBytes, at: destinationURL)

        var overallFilesExtracted = 0
        var overallBytesExtracted: Int64 = 0

        // Extract each part
        for zipURL in sortedURLs {
            if isCancelled {
                throw ExtractionError.cancelled
            }

            // Create a progress wrapper that updates overall progress
            let partProgressHandler: (ExtractionProgress) -> Void = { partProgress in
                let overallProgress = ExtractionProgress(
                    currentFile: partProgress.currentFile,
                    filesExtracted: overallFilesExtracted + partProgress.filesExtracted,
                    totalFiles: totalFiles,
                    bytesExtracted: overallBytesExtracted + partProgress.bytesExtracted,
                    totalBytes: totalBytes
                )
                self.currentProgress = overallProgress
                progressHandler?(overallProgress)
            }

            // Extract this part (allow overwrite since multi-parts may have overlapping structure)
            let extractedFiles = try await extractSingleArchive(
                zipURL: zipURL,
                to: destinationURL,
                overwrite: true,
                progressHandler: partProgressHandler
            )

            allExtractedFiles.append(contentsOf: extractedFiles)

            // Update overall counters
            if let archive = Archive(url: zipURL, accessMode: .read) {
                let entries = Array(archive)
                overallFilesExtracted += entries.count
                overallBytesExtracted += entries.reduce(0) { $0 + Int64($1.uncompressedSize) }
            }
        }

        return allExtractedFiles
    }

    /// List contents of a zip archive without extracting
    /// - Parameter zipURL: URL of the zip file
    /// - Returns: Array of file paths within the archive
    /// - Throws: ExtractionError if archive cannot be read
    func listContents(of zipURL: URL) throws -> [String] {
        guard FileManager.default.fileExists(atPath: zipURL.path) else {
            throw ExtractionError.fileNotFound(zipURL)
        }

        guard let archive = Archive(url: zipURL, accessMode: .read) else {
            throw ExtractionError.invalidArchive(zipURL)
        }

        return archive.map { $0.path }
    }

    /// Cancel the current extraction operation
    ///
    /// The extraction will stop at the next opportunity and cleanup
    /// any partially extracted files.
    func cancel() {
        isCancelled = true
    }

    /// Reset cancellation state
    func resetCancellation() {
        isCancelled = false
    }

    // MARK: - Private Methods

    /// Extract a single archive (internal implementation)
    private func extractSingleArchive(
        zipURL: URL,
        to destinationURL: URL,
        overwrite: Bool,
        progressHandler: ((ExtractionProgress) -> Void)?
    ) async throws -> [URL] {
        // Validate source file exists
        guard FileManager.default.fileExists(atPath: zipURL.path) else {
            print("[ZipExtractor] ERROR: File not found at: \(zipURL.path)")
            throw ExtractionError.fileNotFound(zipURL)
        }

        print("[ZipExtractor] Extracting: \(zipURL.lastPathComponent) to \(destinationURL.path)")

        // Create destination directory
        try FileManager.default.createDirectory(
            at: destinationURL,
            withIntermediateDirectories: true
        )

        // Open the archive
        guard let archive = Archive(url: zipURL, accessMode: .read) else {
            print("[ZipExtractor] ERROR: Could not open archive: \(zipURL.lastPathComponent)")
            throw ExtractionError.invalidArchive(zipURL)
        }

        let entries = Array(archive)
        let totalFiles = entries.count
        let totalBytes = entries.reduce(0) { $0 + Int64($1.uncompressedSize) }

        print("[ZipExtractor] Archive contains \(totalFiles) entries, \(totalBytes) bytes uncompressed")

        var extractedFiles: [URL] = []
        var filesExtracted = 0
        var bytesExtracted: Int64 = 0

        for entry in entries {
            if isCancelled {
                throw ExtractionError.cancelled
            }

            let entryPath = entry.path
            let destinationPath = destinationURL.appendingPathComponent(entryPath)

            // Update progress
            let progress = ExtractionProgress(
                currentFile: entryPath,
                filesExtracted: filesExtracted,
                totalFiles: totalFiles,
                bytesExtracted: bytesExtracted,
                totalBytes: totalBytes
            )
            progressHandler?(progress)

            // Create parent directories if needed
            let parentDir = destinationPath.deletingLastPathComponent()
            if !FileManager.default.fileExists(atPath: parentDir.path) {
                try FileManager.default.createDirectory(
                    at: parentDir,
                    withIntermediateDirectories: true
                )
            }

            // Skip directories
            guard entry.type == .file else {
                filesExtracted += 1
                continue
            }

            // Remove existing file if overwrite is enabled
            if overwrite && FileManager.default.fileExists(atPath: destinationPath.path) {
                try FileManager.default.removeItem(at: destinationPath)
            }

            // Extract file
            do {
                _ = try archive.extract(entry, to: destinationPath, skipCRC32: false)
                extractedFiles.append(destinationPath)
                bytesExtracted += Int64(entry.uncompressedSize)

                if filesExtracted < 3 {
                    print("[ZipExtractor] Extracted: \(entryPath) -> \(destinationPath.path)")
                }
            } catch {
                print("[ZipExtractor] ERROR extracting \(entryPath): \(error)")
                throw ExtractionError.extractionFailed("Failed to extract \(entryPath): \(error.localizedDescription)")
            }

            filesExtracted += 1
            await Task.yield()
        }

        print("[ZipExtractor] Extraction complete: \(extractedFiles.count) files extracted")
        return extractedFiles
    }

    /// Check if sufficient disk space is available
    private func checkDiskSpace(required: Int64, at url: URL) async throws {
        let fileManager = FileManager.default

        // Get the volume URL
        var volumeURL = url
        while !fileManager.fileExists(atPath: volumeURL.path) {
            volumeURL = volumeURL.deletingLastPathComponent()
            if volumeURL.path == "/" {
                break
            }
        }

        do {
            let values = try volumeURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            if let availableSpace = values.volumeAvailableCapacityForImportantUsage {
                // Require 10% buffer
                let requiredWithBuffer = Int64(Double(required) * 1.1)
                if availableSpace < requiredWithBuffer {
                    throw ExtractionError.insufficientDiskSpace(
                        required: requiredWithBuffer,
                        available: availableSpace
                    )
                }
            }
        } catch let error as ExtractionError {
            throw error
        } catch {
            // If we can't check disk space, proceed anyway
            print("[ZipExtractor] Warning: Could not check disk space: \(error)")
        }
    }
}
