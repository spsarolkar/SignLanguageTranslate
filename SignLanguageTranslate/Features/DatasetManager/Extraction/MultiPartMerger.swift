import Foundation

/// Information about a single part of a multi-part archive
struct PartInfo: Sendable, Hashable {
    /// Base name of the category (e.g., "Animals" from "Animals_1of2.zip")
    let baseName: String
    /// Part number (1-indexed)
    let partNumber: Int
    /// Total number of parts
    let totalParts: Int
    /// URL of the zip file
    let url: URL

    /// Display name for UI (e.g., "Animals Part 1 of 2")
    var displayName: String {
        "\(baseName) Part \(partNumber) of \(totalParts)"
    }

    /// Short display name (e.g., "Animals 1/2")
    var shortDisplayName: String {
        "\(baseName) \(partNumber)/\(totalParts)"
    }
}

/// Helper for detecting, parsing, and sorting multi-part zip archives
///
/// Multi-part archives follow the naming convention: `CategoryName_XofY.zip`
/// where X is the part number and Y is the total number of parts.
///
/// ## Examples
/// - `Animals_1of2.zip` - Part 1 of 2 for Animals category
/// - `Greetings_3of5.zip` - Part 3 of 5 for Greetings category
/// - `Seasons.zip` - Single part (not multi-part)
///
/// ## Usage
/// ```swift
/// let files = [url1, url2, url3]
/// let grouped = MultiPartMerger.groupParts(files)
/// for (category, parts) in grouped {
///     if MultiPartMerger.validateParts(parts) {
///         // All parts present, safe to extract
///     }
/// }
/// ```
enum MultiPartMerger {

    // MARK: - Pattern

    /// Regex pattern for multi-part archive filenames
    /// Matches: `CategoryName_XofY.zip` where X and Y are numbers
    ///
    /// Groups:
    /// - 1: Base name (e.g., "Animals")
    /// - 2: Part number (e.g., "1")
    /// - 3: Total parts (e.g., "2")
    static let multiPartPattern = /(.+)_(\d+)of(\d+)\.zip$/

    // MARK: - Detection

    /// Check if a filename represents a multi-part archive
    /// - Parameter filename: The filename to check
    /// - Returns: True if the filename matches the multi-part pattern
    static func isMultiPart(_ filename: String) -> Bool {
        filename.wholeMatch(of: multiPartPattern) != nil
    }

    /// Check if a URL represents a multi-part archive
    /// - Parameter url: The URL to check
    /// - Returns: True if the filename matches the multi-part pattern
    static func isMultiPart(_ url: URL) -> Bool {
        isMultiPart(url.lastPathComponent)
    }

    // MARK: - Parsing

    /// Parse part information from a filename
    /// - Parameter filename: The filename to parse
    /// - Returns: PartInfo if the filename matches, nil otherwise
    static func parsePartInfo(from filename: String, url: URL? = nil) -> PartInfo? {
        guard let match = filename.wholeMatch(of: multiPartPattern) else {
            return nil
        }

        let baseName = String(match.1)
        guard let partNumber = Int(match.2),
              let totalParts = Int(match.3) else {
            return nil
        }

        return PartInfo(
            baseName: baseName,
            partNumber: partNumber,
            totalParts: totalParts,
            url: url ?? URL(fileURLWithPath: filename)
        )
    }

    /// Parse part information from a URL
    /// - Parameter url: The URL to parse
    /// - Returns: PartInfo if the filename matches, nil otherwise
    static func parsePartInfo(from url: URL) -> PartInfo? {
        parsePartInfo(from: url.lastPathComponent, url: url)
    }

    // MARK: - Grouping

    /// Group files by category, identifying multi-part archives
    /// - Parameter files: Array of file URLs
    /// - Returns: Dictionary mapping category names to their parts
    ///
    /// Single-part archives are returned with a single PartInfo entry
    /// where partNumber = 1 and totalParts = 1
    static func groupParts(_ files: [URL]) -> [String: [PartInfo]] {
        var grouped: [String: [PartInfo]] = [:]

        for url in files {
            let filename = url.lastPathComponent

            if let partInfo = parsePartInfo(from: filename, url: url) {
                // Multi-part archive
                grouped[partInfo.baseName, default: []].append(partInfo)
            } else if filename.hasSuffix(".zip") {
                // Single-part archive
                let baseName = String(filename.dropLast(4)) // Remove ".zip"
                let partInfo = PartInfo(
                    baseName: baseName,
                    partNumber: 1,
                    totalParts: 1,
                    url: url
                )
                grouped[baseName, default: []].append(partInfo)
            }
        }

        // Sort parts within each group
        for (category, parts) in grouped {
            grouped[category] = parts.sorted { $0.partNumber < $1.partNumber }
        }

        return grouped
    }

    /// Group files by category from an array of URLs
    /// - Parameter urls: Array of file URLs
    /// - Returns: Dictionary mapping category names to arrays of URLs (sorted by part number)
    static func groupByCategory(_ urls: [URL]) -> [String: [URL]] {
        let grouped = groupParts(urls)
        var result: [String: [URL]] = [:]

        for (category, parts) in grouped {
            result[category] = parts.map { $0.url }
        }

        return result
    }

    // MARK: - Validation

    /// Validate that all parts of a multi-part archive are present
    /// - Parameter parts: Array of PartInfo for a single category
    /// - Returns: True if all parts are present and valid
    static func validateParts(_ parts: [PartInfo]) -> Bool {
        guard !parts.isEmpty else { return false }

        // Single part is always valid
        if parts.count == 1 && parts[0].totalParts == 1 {
            return true
        }

        // Check that all parts have the same total
        let expectedTotal = parts[0].totalParts
        guard parts.allSatisfy({ $0.totalParts == expectedTotal }) else {
            return false
        }

        // Check that we have all parts
        guard parts.count == expectedTotal else {
            return false
        }

        // Check that all part numbers are present (1 to totalParts)
        let partNumbers = Set(parts.map { $0.partNumber })
        let expectedNumbers = Set(1...expectedTotal)

        return partNumbers == expectedNumbers
    }

    /// Get missing part numbers for a multi-part archive
    /// - Parameter parts: Array of PartInfo for a single category
    /// - Returns: Array of missing part numbers (empty if all present)
    static func missingParts(_ parts: [PartInfo]) -> [Int] {
        guard !parts.isEmpty else { return [] }

        let expectedTotal = parts[0].totalParts
        let presentParts = Set(parts.map { $0.partNumber })
        let allParts = Set(1...expectedTotal)

        return allParts.subtracting(presentParts).sorted()
    }

    // MARK: - Sorting

    /// Sort URLs by part number
    /// - Parameter urls: Array of file URLs
    /// - Returns: Sorted array with multi-part archives in order
    static func sortByPartNumber(_ urls: [URL]) -> [URL] {
        urls.sorted { url1, url2 in
            let part1 = parsePartInfo(from: url1)?.partNumber ?? 0
            let part2 = parsePartInfo(from: url2)?.partNumber ?? 0
            return part1 < part2
        }
    }

    /// Sort PartInfo array by part number
    /// - Parameter parts: Array of PartInfo
    /// - Returns: Sorted array
    static func sortByPartNumber(_ parts: [PartInfo]) -> [PartInfo] {
        parts.sorted { $0.partNumber < $1.partNumber }
    }

    // MARK: - URL Generation

    /// Generate expected URLs for all parts of a multi-part archive
    /// - Parameters:
    ///   - baseName: Category name
    ///   - totalParts: Total number of parts
    ///   - baseURL: Base URL directory
    /// - Returns: Array of expected URLs for all parts
    static func generatePartURLs(
        baseName: String,
        totalParts: Int,
        baseURL: URL
    ) -> [URL] {
        (1...totalParts).map { partNumber in
            baseURL.appendingPathComponent("\(baseName)_\(partNumber)of\(totalParts).zip")
        }
    }

    /// Generate filename for a specific part
    /// - Parameters:
    ///   - baseName: Category name
    ///   - partNumber: Part number (1-indexed)
    ///   - totalParts: Total number of parts
    /// - Returns: Filename string
    static func generateFilename(baseName: String, partNumber: Int, totalParts: Int) -> String {
        if totalParts == 1 {
            return "\(baseName).zip"
        }
        return "\(baseName)_\(partNumber)of\(totalParts).zip"
    }
}

// MARK: - PartInfo Extensions

extension PartInfo: Comparable {
    static func < (lhs: PartInfo, rhs: PartInfo) -> Bool {
        if lhs.baseName != rhs.baseName {
            return lhs.baseName < rhs.baseName
        }
        return lhs.partNumber < rhs.partNumber
    }
}

extension PartInfo: CustomStringConvertible {
    var description: String {
        displayName
    }
}
