import Foundation

/// Strategy for ingesting the INCLUDE dataset
///
/// INCLUDE dataset structure:
/// ```
/// INCLUDE/
/// ├── Animals/
/// │   ├── Dog/
/// │   │   ├── video1.mp4
/// │   │   └── video2.mp4
/// │   └── Cat/
/// │       └── video1.mp4
/// ├── Greetings/
/// │   └── Hello/
/// │       └── video1.mp4
/// └── ...
/// ```
///
/// Word folders may have numeric prefixes: "12. Dog" → "Dog"
struct INCLUDEIngestionStrategy {
    
    // MARK: - Expected Structure
    
    /// Expected categories in the INCLUDE dataset
    static let expectedCategories = [
        "Adjectives",
        "Animals",
        "Clothes",
        "Colours",
        "Days_and_Time",
        "Electronics",
        "Greetings",
        "Home",
        "Jobs",
        "Means_of_Transportation",
        "People",
        "Places",
        "Pronouns",
        "Seasons",
        "Society"
    ]
    
    /// Total expected categories count
    static let expectedCategoryCount = 15
    
    // MARK: - Parsing
    
    /// Parse category name from a path
    ///
    /// Given a URL like: `.../INCLUDE/Animals/Dog/video.mp4`
    /// Returns: "Animals"
    ///
    /// - Parameters:
    ///   - url: File or directory URL
    ///   - baseURL: Base URL of the dataset (e.g., `.../INCLUDE`)
    /// - Returns: Category name, or nil if not found
    static func parseCategory(from url: URL, baseURL: URL) -> String? {
        let path = url.path
        let basePath = baseURL.path
        
        guard path.hasPrefix(basePath) else { return nil }
        
        // Remove base path to get relative path
        var relativePath = path
        relativePath.removeFirst(basePath.count)
        if relativePath.hasPrefix("/") {
            relativePath.removeFirst()
        }
        
        // First component is the category
        let components = relativePath.components(separatedBy: "/")
        return components.first
    }
    
    /// Parse word label from a directory or filename
    ///
    /// Handles:
    /// - "12. Dog" → "Dog"
    /// - "03. Cat" → "Cat"
    /// - "Dog" → "Dog"
    ///
    /// - Parameter name: Directory or file name
    /// - Returns: Sanitized word label
    static func parseWordLabel(from name: String) -> String {
        name.sanitizedLabel()
    }
    
    /// Parse word label from a full URL path
    ///
    /// Given: `.../Animals/12. Dog/video1.mp4`
    /// Returns: "Dog"
    ///
    /// - Parameter url: File URL
    /// - Returns: Word label, or nil if structure is invalid
    static func parseWordLabel(from url: URL) -> String? {
        let components = url.pathComponents
        
        // Structure should be: .../Category/Word/video.mp4
        guard components.count >= 3 else { return nil }
        
        // Word is the second-to-last component (before the filename)
        let wordComponent = components[components.count - 2]
        return parseWordLabel(from: wordComponent)
    }
    
    // MARK: - Validation
    
    /// Validate that a directory structure matches INCLUDE format
    /// - Parameter directory: Base directory of the dataset
    /// - Returns: True if structure appears valid
    static func validateStructure(_ directory: URL) -> Bool {
        let fileManager = FileManager.default
        
        guard let contents = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return false
        }
        
        // Check for at least some expected categories
        let categoryNames = contents.compactMap { url -> String? in
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
            return isDirectory ? url.lastPathComponent : nil
        }
        
        let matchingCategories = Set(categoryNames).intersection(Set(expectedCategories))
        
        // Should have at least half of expected categories
        return matchingCategories.count >= expectedCategoryCount / 2
    }
    
    /// Get list of missing categories
    /// - Parameter directory: Base directory of the dataset
    /// - Returns: Array of category names that are missing
    static func missingCategories(_ directory: URL) -> [String] {
        let fileManager = FileManager.default
        
        guard let contents = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return expectedCategories
        }
        
        let categoryNames = contents.compactMap { url -> String? in
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
            return isDirectory ? url.lastPathComponent : nil
        }
        
        let present = Set(categoryNames)
        let expected = Set(expectedCategories)
        
        return expected.subtracting(present).sorted()
    }
    
    // MARK: - Category Utilities
    
    /// Get display name for a category
    ///
    /// Converts internal names like "Days_and_Time" to "Days and Time"
    ///
    /// - Parameter category: Category name
    /// - Returns: Display-friendly name
    static func displayName(for category: String) -> String {
        category.replacingOccurrences(of: "_", with: " ")
    }
    
    /// Normalize category name for consistent storage
    ///
    /// Ensures categories are stored with consistent casing and formatting
    ///
    /// - Parameter category: Raw category name
    /// - Returns: Normalized name
    static func normalizeCategory(_ category: String) -> String {
        // INCLUDE uses exact category names, no normalization needed
        // Just ensure it's trimmed
        category.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // MARK: - Statistics
    
    /// Get expected statistics for complete INCLUDE dataset
    static var expectedStatistics: DatasetStatistics {
        DatasetStatistics(
            categoryCount: 15,
            wordCount: 263,  // Approximate total words across all categories
            sampleCount: 15000  // Approximate total samples
        )
    }
}

// MARK: - Supporting Types

/// Expected statistics for a dataset
struct DatasetStatistics {
    let categoryCount: Int
    let wordCount: Int
    let sampleCount: Int
}
