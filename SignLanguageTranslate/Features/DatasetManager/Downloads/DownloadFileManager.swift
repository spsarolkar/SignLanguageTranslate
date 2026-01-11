import Foundation

/// Manages file operations for download tasks
///
/// This struct provides file system utilities for the download system:
/// - Moving completed downloads to permanent storage
/// - Managing resume data files for paused downloads
/// - Querying storage space
/// - Cleaning up temporary files
///
/// File Organization:
/// ```
/// Documents/
/// ├── Downloads/           (temporary downloads + resume data)
/// │   ├── temp/           (in-progress downloads)
/// │   ├── resume/         (resume data files)
/// │   └── completed/      (downloads awaiting extraction)
/// └── Datasets/           (extracted dataset files)
///     └── INCLUDE/
///         ├── Animals/
///         ├── Greetings/
///         └── ...
/// ```
struct DownloadFileManager {

    // MARK: - Directory URLs

    /// Base downloads directory: Documents/Downloads/
    var downloadsDirectory: URL {
        FileManager.default.downloadsDirectory
    }

    /// Temporary files directory: Documents/Downloads/temp/
    var tempDirectory: URL {
        let url = downloadsDirectory.appendingPathComponent("temp")
        try? FileManager.default.createDirectoryIfNeeded(at: url)
        return url
    }

    /// Resume data directory: Documents/Downloads/resume/
    var resumeDataDirectory: URL {
        let url = downloadsDirectory.appendingPathComponent("resume")
        try? FileManager.default.createDirectoryIfNeeded(at: url)
        return url
    }

    /// Completed downloads awaiting extraction: Documents/Downloads/completed/
    var completedDownloadsDirectory: URL {
        let url = downloadsDirectory.appendingPathComponent("completed")
        try? FileManager.default.createDirectoryIfNeeded(at: url)
        return url
    }

    /// Final datasets directory: Documents/Datasets/
    var datasetsDirectory: URL {
        FileManager.default.datasetsDirectory
    }

    // MARK: - Initialization

    init() {
        // Ensure all directories exist
        _ = tempDirectory
        _ = resumeDataDirectory
        _ = completedDownloadsDirectory
        _ = datasetsDirectory
    }

    // MARK: - Download File Operations

    /// Move a completed download from temporary location to permanent storage
    /// - Parameters:
    ///   - tempURL: The temporary file URL from URLSession
    ///   - task: The download task containing metadata
    /// - Returns: The permanent file URL
    /// - Throws: File system errors
    func moveCompletedDownload(from tempURL: URL, for task: DownloadTask) throws -> URL {
        let fm = FileManager.default

        // Create destination path: completed/[taskId]_[filename]
        let destinationFilename = "\(task.id.uuidString)_\(task.filename)"
        let destinationURL = completedDownloadsDirectory.appendingPathComponent(destinationFilename)

        // Remove existing file if present
        if fm.fileExists(at: destinationURL) {
            try fm.removeItem(at: destinationURL)
        }

        // Move file to permanent location
        try fm.moveItem(at: tempURL, to: destinationURL)

        return destinationURL
    }

    /// Get the expected location for a completed download
    /// - Parameter task: The download task
    /// - Returns: URL where the completed download should be stored
    func completedDownloadURL(for task: DownloadTask) -> URL {
        let filename = "\(task.id.uuidString)_\(task.filename)"
        return completedDownloadsDirectory.appendingPathComponent(filename)
    }

    /// Delete a completed download file
    /// - Parameter task: The download task
    func deleteCompletedDownload(for task: DownloadTask) {
        let url = completedDownloadURL(for: task)
        FileManager.default.safeDelete(at: url)
    }

    // MARK: - Resume Data Operations

    /// Save resume data to disk
    /// - Parameters:
    ///   - data: The resume data from URLSession
    ///   - taskId: The task ID
    /// - Returns: The path where resume data was saved
    /// - Throws: File system errors
    func saveResumeData(_ data: Data, for taskId: UUID) throws -> URL {
        let url = resumeDataURL(for: taskId)

        // Write resume data atomically
        try data.write(to: url, options: .atomic)

        return url
    }

    /// Load resume data from disk
    /// - Parameter taskId: The task ID
    /// - Returns: The resume data if available
    /// - Throws: File system errors
    func loadResumeData(for taskId: UUID) throws -> Data? {
        let url = resumeDataURL(for: taskId)

        guard FileManager.default.fileExists(at: url) else {
            return nil
        }

        return try Data(contentsOf: url)
    }

    /// Delete resume data file
    /// - Parameter taskId: The task ID
    func deleteResumeData(for taskId: UUID) {
        let url = resumeDataURL(for: taskId)
        FileManager.default.safeDelete(at: url)
    }

    /// Get the URL for resume data
    /// - Parameter taskId: The task ID
    /// - Returns: URL for the resume data file
    func resumeDataURL(for taskId: UUID) -> URL {
        resumeDataDirectory.appendingPathComponent("\(taskId.uuidString).resume")
    }

    /// Check if resume data exists for a task
    /// - Parameter taskId: The task ID
    /// - Returns: True if resume data exists
    func hasResumeData(for taskId: UUID) -> Bool {
        FileManager.default.fileExists(at: resumeDataURL(for: taskId))
    }

    // MARK: - Storage Queries

    /// Get available storage space on device
    /// - Returns: Available space in bytes, or 0 if unavailable
    func availableStorageSpace() -> Int64 {
        do {
            let values = try URL(fileURLWithPath: NSHomeDirectory())
                .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])

            return values.volumeAvailableCapacityForImportantUsage ?? 0
        } catch {
            return 0
        }
    }

    /// Check if there's enough storage for a download
    /// - Parameter bytes: Required bytes
    /// - Returns: True if sufficient space available
    func hasStorageSpace(for bytes: Int64) -> Bool {
        // Add 10% buffer for safety
        let requiredSpace = Int64(Double(bytes) * 1.1)
        return availableStorageSpace() >= requiredSpace
    }

    /// Get size of a downloaded file
    /// - Parameter task: The download task
    /// - Returns: File size in bytes, or nil if not found
    func downloadedFileSize(for task: DownloadTask) -> Int64? {
        let url = completedDownloadURL(for: task)

        guard FileManager.default.fileExists(at: url) else {
            return nil
        }

        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            return attributes[.size] as? Int64
        } catch {
            return nil
        }
    }

    /// Get total size of downloads directory
    /// - Returns: Total size in bytes
    func totalDownloadsSize() -> Int64 {
        FileManager.default.directorySize(at: downloadsDirectory)
    }

    /// Get total size of datasets directory
    /// - Returns: Total size in bytes
    func totalDatasetsSize() -> Int64 {
        FileManager.default.directorySize(at: datasetsDirectory)
    }

    // MARK: - Cleanup Operations

    /// Clean up all temporary files
    func cleanupTempDirectory() {
        let fm = FileManager.default

        guard let contents = try? fm.contentsOfDirectory(
            at: tempDirectory,
            includingPropertiesForKeys: nil
        ) else {
            return
        }

        for url in contents {
            fm.safeDelete(at: url)
        }
    }

    /// Clean up orphaned resume data (for tasks that no longer exist)
    /// - Parameter validTaskIds: Set of task IDs that are still valid
    func cleanupOrphanedResumeData(validTaskIds: Set<UUID>) {
        let fm = FileManager.default

        guard let contents = try? fm.contentsOfDirectory(
            at: resumeDataDirectory,
            includingPropertiesForKeys: nil
        ) else {
            return
        }

        for url in contents {
            let filename = url.deletingPathExtension().lastPathComponent
            guard let taskId = UUID(uuidString: filename) else {
                // Invalid filename, delete it
                fm.safeDelete(at: url)
                continue
            }

            if !validTaskIds.contains(taskId) {
                // Task no longer exists, delete resume data
                fm.safeDelete(at: url)
            }
        }
    }

    /// Clean up orphaned completed downloads (for tasks that no longer exist)
    /// - Parameter validTaskIds: Set of task IDs that are still valid
    func cleanupOrphanedDownloads(validTaskIds: Set<UUID>) {
        let fm = FileManager.default

        guard let contents = try? fm.contentsOfDirectory(
            at: completedDownloadsDirectory,
            includingPropertiesForKeys: nil
        ) else {
            return
        }

        for url in contents {
            let filename = url.lastPathComponent

            // Extract task ID from filename (format: [UUID]_[original_filename])
            guard let underscoreIndex = filename.firstIndex(of: "_"),
                  let taskId = UUID(uuidString: String(filename[..<underscoreIndex])) else {
                // Can't parse, leave it alone
                continue
            }

            if !validTaskIds.contains(taskId) {
                // Task no longer exists, delete file
                fm.safeDelete(at: url)
            }
        }
    }

    /// Full cleanup of orphaned files
    /// - Parameter validTaskIds: Set of task IDs that are still valid
    func cleanupOrphanedFiles(validTaskIds: Set<UUID>) {
        cleanupOrphanedResumeData(validTaskIds: validTaskIds)
        cleanupOrphanedDownloads(validTaskIds: validTaskIds)
        cleanupTempDirectory()
    }

    // MARK: - Dataset Directory Operations

    /// Get directory for a specific dataset
    /// - Parameter datasetName: Name of the dataset
    /// - Returns: URL for the dataset directory
    func datasetDirectory(for datasetName: String) -> URL {
        let url = datasetsDirectory.appendingPathComponent(datasetName)
        try? FileManager.default.createDirectoryIfNeeded(at: url)
        return url
    }

    /// Get directory for a category within a dataset
    /// - Parameters:
    ///   - category: Category name
    ///   - datasetName: Dataset name
    /// - Returns: URL for the category directory
    func categoryDirectory(for category: String, in datasetName: String) -> URL {
        let url = datasetDirectory(for: datasetName).appendingPathComponent(category)
        try? FileManager.default.createDirectoryIfNeeded(at: url)
        return url
    }

    /// Check if a category is fully downloaded
    /// - Parameters:
    ///   - category: Category name
    ///   - datasetName: Dataset name
    /// - Returns: True if the category directory exists and is not empty
    func isCategoryDownloaded(_ category: String, in datasetName: String) -> Bool {
        let url = categoryDirectory(for: category, in: datasetName)
        let fm = FileManager.default

        guard fm.directoryExists(at: url) else {
            return false
        }

        // Check if directory has any contents
        guard let contents = try? fm.contentsOfDirectory(atPath: url.path) else {
            return false
        }

        return !contents.isEmpty
    }
}

// MARK: - Errors

/// Errors that can occur during file operations
enum DownloadFileError: LocalizedError {
    case insufficientStorage(required: Int64, available: Int64)
    case fileNotFound(URL)
    case moveFailed(from: URL, to: URL, underlying: Error)
    case resumeDataCorrupted

    var errorDescription: String? {
        switch self {
        case .insufficientStorage(let required, let available):
            let requiredStr = FileManager.formattedSize(required)
            let availableStr = FileManager.formattedSize(available)
            return "Insufficient storage: \(requiredStr) required, \(availableStr) available"
        case .fileNotFound(let url):
            return "File not found: \(url.lastPathComponent)"
        case .moveFailed(_, let to, let underlying):
            return "Failed to move file to \(to.lastPathComponent): \(underlying.localizedDescription)"
        case .resumeDataCorrupted:
            return "Resume data is corrupted and cannot be used"
        }
    }
}
