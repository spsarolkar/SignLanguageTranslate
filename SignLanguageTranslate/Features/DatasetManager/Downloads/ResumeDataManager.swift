import Foundation

/// Manages resume data files for pausable downloads
///
/// Resume data is binary data from URLSession that allows downloads to continue
/// from where they left off after being paused or interrupted. This manager
/// handles storing, loading, and cleaning up resume data files.
///
/// File Organization:
/// ```
/// Documents/Downloads/resume/
/// ├── [UUID].resume          // Resume data for task UUID
/// └── ...
/// ```
///
/// Usage:
/// ```swift
/// let manager = ResumeDataManager()
///
/// // Save resume data when pausing
/// try manager.save(resumeData, for: taskId)
///
/// // Load when resuming
/// if let data = try manager.load(for: taskId) {
///     session.downloadTask(withResumeData: data)
/// }
///
/// // Clean up after completion
/// manager.delete(for: taskId)
/// ```
struct ResumeDataManager: Sendable {

    // MARK: - Properties

    /// Directory for storing resume data files
    private let resumeDataDirectory: URL

    /// File extension for resume data files
    private let fileExtension = "resume"

    // MARK: - Initialization

    /// Create a resume data manager
    /// - Parameter directory: Optional custom directory (defaults to Documents/Downloads/resume/)
    init(directory: URL? = nil) {
        if let customDir = directory {
            self.resumeDataDirectory = customDir
        } else {
            self.resumeDataDirectory = FileManager.default.downloadsDirectory
                .appendingPathComponent("resume")
        }

        // Ensure directory exists
        try? FileManager.default.createDirectoryIfNeeded(at: resumeDataDirectory)
    }

    // MARK: - Public Methods

    /// Save resume data for a task
    /// - Parameters:
    ///   - data: The resume data from URLSession
    ///   - taskId: The task identifier
    /// - Throws: File system error
    /// - Returns: URL where the data was saved
    @discardableResult
    func save(_ data: Data, for taskId: UUID) throws -> URL {
        let url = fileURL(for: taskId)

        // Write atomically to avoid corruption on crash
        try data.write(to: url, options: .atomic)

        return url
    }

    /// Load resume data for a task
    /// - Parameter taskId: The task identifier
    /// - Returns: Resume data if available, nil otherwise
    /// - Throws: File read error (only if file exists but can't be read)
    func load(for taskId: UUID) throws -> Data? {
        let url = fileURL(for: taskId)

        guard FileManager.default.fileExists(at: url) else {
            return nil
        }

        return try Data(contentsOf: url)
    }

    /// Check if resume data exists for a task
    /// - Parameter taskId: The task identifier
    /// - Returns: True if resume data file exists
    func hasResumeData(for taskId: UUID) -> Bool {
        FileManager.default.fileExists(at: fileURL(for: taskId))
    }

    /// Delete resume data for a task
    /// - Parameter taskId: The task identifier
    func delete(for taskId: UUID) {
        FileManager.default.safeDelete(at: fileURL(for: taskId))
    }

    /// Delete resume data for multiple tasks
    /// - Parameter taskIds: Task identifiers to delete
    func delete(for taskIds: [UUID]) {
        for taskId in taskIds {
            delete(for: taskId)
        }
    }

    /// Get file URL for resume data
    /// - Parameter taskId: The task identifier
    /// - Returns: URL for the resume data file
    func fileURL(for taskId: UUID) -> URL {
        resumeDataDirectory.appendingPathComponent("\(taskId.uuidString).\(fileExtension)")
    }

    /// Get the path string for resume data (for storing in DownloadTask)
    /// - Parameter taskId: The task identifier
    /// - Returns: Path string for the resume data file
    func filePath(for taskId: UUID) -> String {
        fileURL(for: taskId).path
    }

    // MARK: - Cleanup Operations

    /// Clean up orphaned resume data files
    ///
    /// Removes resume data files for tasks that no longer exist.
    ///
    /// - Parameter validTaskIds: Set of task IDs that are still valid
    /// - Returns: Number of files deleted
    @discardableResult
    func cleanupOrphaned(validTaskIds: Set<UUID>) -> Int {
        let fm = FileManager.default
        var deletedCount = 0

        guard let contents = try? fm.contentsOfDirectory(
            at: resumeDataDirectory,
            includingPropertiesForKeys: nil
        ) else {
            return 0
        }

        for url in contents {
            // Parse task ID from filename
            let filename = url.deletingPathExtension().lastPathComponent
            guard let taskId = UUID(uuidString: filename) else {
                // Invalid filename format, delete it
                fm.safeDelete(at: url)
                deletedCount += 1
                continue
            }

            // Check if task still exists
            if !validTaskIds.contains(taskId) {
                fm.safeDelete(at: url)
                deletedCount += 1
            }
        }

        return deletedCount
    }

    /// Clean up all resume data older than a specified age
    /// - Parameter maxAge: Maximum age in seconds (default 7 days)
    /// - Returns: Number of files deleted
    @discardableResult
    func cleanupOld(maxAge: TimeInterval = 7 * 24 * 60 * 60) -> Int {
        let fm = FileManager.default
        var deletedCount = 0
        let cutoffDate = Date().addingTimeInterval(-maxAge)

        guard let contents = try? fm.contentsOfDirectory(
            at: resumeDataDirectory,
            includingPropertiesForKeys: [.creationDateKey]
        ) else {
            return 0
        }

        for url in contents {
            guard let values = try? url.resourceValues(forKeys: [.creationDateKey]),
                  let createdDate = values.creationDate else {
                continue
            }

            if createdDate < cutoffDate {
                fm.safeDelete(at: url)
                deletedCount += 1
            }
        }

        return deletedCount
    }

    /// Delete all resume data files
    /// - Returns: Number of files deleted
    @discardableResult
    func deleteAll() -> Int {
        let fm = FileManager.default
        var deletedCount = 0

        guard let contents = try? fm.contentsOfDirectory(
            at: resumeDataDirectory,
            includingPropertiesForKeys: nil
        ) else {
            return 0
        }

        for url in contents {
            fm.safeDelete(at: url)
            deletedCount += 1
        }

        return deletedCount
    }

    // MARK: - Query Methods

    /// Get total size of all resume data files
    /// - Returns: Total size in bytes
    func totalSize() -> Int64 {
        FileManager.default.directorySize(at: resumeDataDirectory)
    }

    /// Get formatted total size (e.g., "12.5 MB")
    var formattedTotalSize: String {
        FileManager.formattedSize(totalSize())
    }

    /// Get count of resume data files
    /// - Returns: Number of resume data files
    func count() -> Int {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: resumeDataDirectory,
            includingPropertiesForKeys: nil
        ) else {
            return 0
        }

        return contents.filter { $0.pathExtension == fileExtension }.count
    }

    /// Get all task IDs that have resume data
    /// - Returns: Array of task IDs with resume data
    func allTaskIds() -> [UUID] {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: resumeDataDirectory,
            includingPropertiesForKeys: nil
        ) else {
            return []
        }

        return contents.compactMap { url -> UUID? in
            let filename = url.deletingPathExtension().lastPathComponent
            return UUID(uuidString: filename)
        }
    }

    /// Get the resume data directory URL
    var directoryURL: URL {
        resumeDataDirectory
    }
}

// MARK: - Resume Data Validation

extension ResumeDataManager {

    /// Validate resume data integrity
    ///
    /// Checks if resume data appears to be valid URLSession resume data.
    /// Note: This is a heuristic check, not a guarantee of validity.
    ///
    /// - Parameter data: Resume data to validate
    /// - Returns: True if data appears valid
    func isValidResumeData(_ data: Data) -> Bool {
        // Resume data should be a plist (bplist magic bytes or XML plist)
        guard data.count > 8 else {
            return false
        }

        // Check for binary plist magic bytes "bplist"
        let bplistMagic = Data([0x62, 0x70, 0x6C, 0x69, 0x73, 0x74])
        if data.prefix(6) == bplistMagic {
            return true
        }

        // Check for XML plist header
        if let prefix = String(data: data.prefix(50), encoding: .utf8) {
            if prefix.contains("<?xml") && prefix.contains("plist") {
                return true
            }
        }

        return false
    }

    /// Load and validate resume data
    /// - Parameter taskId: The task identifier
    /// - Returns: Resume data if valid, nil if invalid or not found
    func loadValidated(for taskId: UUID) -> Data? {
        guard let data = try? load(for: taskId) else {
            return nil
        }

        if isValidResumeData(data) {
            return data
        }

        // Invalid resume data, delete it
        delete(for: taskId)
        return nil
    }
}

// MARK: - Diagnostic Information

extension ResumeDataManager {

    /// Diagnostic information about resume data storage
    struct DiagnosticInfo: Sendable {
        let directoryPath: String
        let fileCount: Int
        let totalSize: Int64
        let formattedSize: String
        let taskIds: [UUID]
    }

    /// Get diagnostic information
    var diagnosticInfo: DiagnosticInfo {
        let ids = allTaskIds()
        let size = totalSize()

        return DiagnosticInfo(
            directoryPath: resumeDataDirectory.path,
            fileCount: ids.count,
            totalSize: size,
            formattedSize: FileManager.formattedSize(size),
            taskIds: ids
        )
    }
}
