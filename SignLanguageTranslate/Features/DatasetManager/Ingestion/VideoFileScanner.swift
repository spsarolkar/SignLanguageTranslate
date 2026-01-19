import Foundation

/// Information about a scanned video file
struct ScannedFile: Sendable {
    /// URL of the video file
    let url: URL
    /// Category name (e.g., "Animals", "Greetings")
    let category: String
    /// Word label parsed from path (e.g., "Dog" from "12. Dog")
    let wordLabel: String
    /// File size in bytes
    let fileSize: Int64
    
    /// Filename without extension
    var filename: String {
        url.deletingPathExtension().lastPathComponent
    }
    
    /// File extension
    var fileExtension: String {
        url.pathExtension
    }
}

/// Scans directories for video files and extracts metadata from file structure
struct VideoFileScanner {
    
    // MARK: - Supported Formats
    
    /// Video file extensions that are supported
    static let supportedExtensions = ["mp4", "mov", "m4v", "avi", "MOV", "MP4"]
    
    // MARK: - Directory Scanning
    
    /// Scan an entire dataset directory for video files
    /// - Parameter directory: Root directory of the dataset (e.g., Documents/Datasets/INCLUDE)
    /// - Returns: Array of scanned files with parsed metadata
    /// - Throws: Error if directory cannot be read
    static func scan(directory: URL) throws -> [ScannedFile] {
        var scannedFiles: [ScannedFile] = []
        
        let fileManager = FileManager.default
        
        // Get all subdirectories (categories)
        guard let categoryURLs = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw ScanError.directoryNotReadable(directory)
        }
        
        // Filter to only directories
        let categories = categoryURLs.filter { url in
            (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
        }
        
        // Scan each category
        for categoryURL in categories {
            let categoryName = categoryURL.lastPathComponent
            let categoryFiles = try scanCategory(
                directory: categoryURL,
                categoryName: categoryName
            )
            scannedFiles.append(contentsOf: categoryFiles)
        }
        
        return scannedFiles
    }
    
    /// Scan a single category directory for video files
    /// - Parameters:
    ///   - directory: Category directory (e.g., Documents/Datasets/INCLUDE/Animals)
    ///   - categoryName: Name of the category
    /// - Returns: Array of scanned files in this category
    /// - Throws: Error if directory cannot be read
    static func scanCategory(
        directory: URL,
        categoryName: String
    ) throws -> [ScannedFile] {
        var scannedFiles: [ScannedFile] = []
        let fileManager = FileManager.default
        
        // INCLUDE structure: Category/Word/video.mp4
        // Get all subdirectories (words)
        guard let wordURLs = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw ScanError.directoryNotReadable(directory)
        }
        
        // Check each item - could be directory (word folder) or direct video file
        for itemURL in wordURLs {
            let isDirectory = (try? itemURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
            
            if isDirectory {
                // Word subdirectory - scan for videos inside
                let wordLabel = parseWordLabel(from: itemURL.lastPathComponent)
                let videoFiles = try scanWordDirectory(
                    directory: itemURL,
                    category: categoryName,
                    wordLabel: wordLabel
                )
                scannedFiles.append(contentsOf: videoFiles)
            } else if isVideoFile(itemURL) {
                // Direct video file in category directory
                let wordLabel = parseWordLabel(from: itemURL.deletingPathExtension().lastPathComponent)
                let fileSize = getFileSize(itemURL)
                
                scannedFiles.append(ScannedFile(
                    url: itemURL,
                    category: categoryName,
                    wordLabel: wordLabel,
                    fileSize: fileSize
                ))
            }
        }
        
        return scannedFiles
    }
    
    /// Scan a word subdirectory for video files
    /// - Parameters:
    ///   - directory: Word directory (e.g., .../Animals/Dog)
    ///   - category: Category name
    ///   - wordLabel: Parsed word label
    /// - Returns: Array of scanned video files
    private static func scanWordDirectory(
        directory: URL,
        category: String,
        wordLabel: String
    ) throws -> [ScannedFile] {
        let fileManager = FileManager.default
        
        guard let files = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        
        return files.compactMap { url in
            guard isVideoFile(url) else { return nil }
            
            let fileSize = getFileSize(url)
            
            return ScannedFile(
                url: url,
                category: category,
                wordLabel: wordLabel,
                fileSize: fileSize
            )
        }
    }
    
    // MARK: - Label Parsing
    
    /// Parse word label from filename or directory name
    ///
    /// Handles formats like:
    /// - "12. Dog" → "Dog"
    /// - "Dog" → "Dog"
    /// - "03. Cat" → "Cat"
    ///
    /// - Parameter name: Filename or directory name
    /// - Returns: Sanitized word label
    static func parseWordLabel(from name: String) -> String {
        // Use String.sanitizedLabel() extension if available
        // This handles numbered prefixes like "12. Dog" → "Dog"
        name.sanitizedLabel()
    }
    
    // MARK: - File Utilities
    
    /// Check if a URL points to a supported video file
    /// - Parameter url: File URL to check
    /// - Returns: True if the file has a supported video extension
    static func isVideoFile(_ url: URL) -> Bool {
        let ext = url.pathExtension
        return supportedExtensions.contains(ext)
    }
    
    /// Get file size in bytes
    /// - Parameter url: File URL
    /// - Returns: File size, or 0 if unavailable
    private static func getFileSize(_ url: URL) -> Int64 {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? Int64 else {
            return 0
        }
        return size
    }
    
    // MARK: - Statistics
    
    /// Get statistics about scanned files
    /// - Parameter files: Array of scanned files
    /// - Returns: Summary statistics
    static func statistics(for files: [ScannedFile]) -> ScanStatistics {
        let totalSize = files.reduce(0) { $0 + $1.fileSize }
        let categories = Set(files.map { $0.category })
        let words = Set(files.map { $0.wordLabel })
        
        return ScanStatistics(
            totalFiles: files.count,
            totalSize: totalSize,
            categoryCount: categories.count,
            wordCount: words.count
        )
    }
}

// MARK: - Supporting Types

/// Statistics about scanned files
struct ScanStatistics {
    let totalFiles: Int
    let totalSize: Int64
    let categoryCount: Int
    let wordCount: Int
    
    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
    }
}

/// Errors that can occur during scanning
enum ScanError: LocalizedError {
    case directoryNotReadable(URL)
    case noVideoFilesFound(URL)
    
    var errorDescription: String? {
        switch self {
        case .directoryNotReadable(let url):
            return "Cannot read directory: \(url.path)"
        case .noVideoFilesFound(let url):
            return "No video files found in: \(url.path)"
        }
    }
}


