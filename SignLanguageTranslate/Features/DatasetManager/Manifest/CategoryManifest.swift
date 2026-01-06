import Foundation

/// Represents a single category in the INCLUDE dataset
///
/// Categories in the INCLUDE dataset on Zenodo are organized as zip files.
/// Some categories are split into multiple parts due to file size limits,
/// while others are single files.
///
/// Naming conventions:
/// - Single part: "CategoryName.zip"
/// - Multiple parts: "CategoryName_1of2.zip", "CategoryName_2of2.zip", etc.
struct CategoryManifest: Codable, Hashable, Identifiable {

    // MARK: - Properties

    /// Category name (e.g., "Animals", "Greetings")
    let name: String

    /// Number of zip file parts for this category
    /// Single-file categories have partCount = 1
    let partCount: Int

    /// Estimated total size for all parts in this category (optional)
    let estimatedTotalSize: Int64?

    /// Unique identifier based on category name
    var id: String { name }

    // MARK: - Computed Properties

    /// Whether this category is split into multiple parts
    var isMultiPart: Bool {
        partCount > 1
    }

    /// Whether this is a single-file category
    var isSingleFile: Bool {
        partCount == 1
    }

    // MARK: - Initialization

    /// Create a category manifest
    /// - Parameters:
    ///   - name: Category name
    ///   - partCount: Number of parts (default 1)
    ///   - estimatedTotalSize: Estimated total size in bytes
    init(name: String, partCount: Int = 1, estimatedTotalSize: Int64? = nil) {
        self.name = name
        self.partCount = partCount
        self.estimatedTotalSize = estimatedTotalSize
    }

    // MARK: - Filename Generation

    /// Generate filenames for all parts in this category
    /// - Returns: Array of filenames
    ///
    /// Examples:
    /// - Single part: ["Seasons.zip"]
    /// - Multiple parts: ["Animals_1of2.zip", "Animals_2of2.zip"]
    func generateFilenames() -> [String] {
        if partCount == 1 {
            // Single file: just the category name
            return ["\(name).zip"]
        } else {
            // Multiple parts: CategoryName_XofY.zip
            return (1...partCount).map { partNumber in
                "\(name)_\(partNumber)of\(partCount).zip"
            }
        }
    }

    /// Generate filename for a specific part number
    /// - Parameter partNumber: Part number (1-indexed)
    /// - Returns: Filename for that part, or nil if partNumber is invalid
    func filename(forPart partNumber: Int) -> String? {
        guard partNumber >= 1 && partNumber <= partCount else {
            return nil
        }

        if partCount == 1 {
            return "\(name).zip"
        } else {
            return "\(name)_\(partNumber)of\(partCount).zip"
        }
    }

    /// Generate manifest entries for all parts with given base URL
    /// - Parameters:
    ///   - baseURL: Base URL for the dataset repository
    ///   - estimatedSizePerPart: Optional estimated size per part
    /// - Returns: Array of ManifestEntry objects
    func generateManifestEntries(
        baseURL: URL,
        estimatedSizePerPart: Int64? = nil
    ) -> [ManifestEntry] {
        let filenames = generateFilenames()

        return filenames.enumerated().map { index, filename in
            let partNumber = index + 1
            let fileURL = baseURL.appendingPathComponent(filename)

            // Use provided size per part, or divide total size by part count
            let partSize: Int64?
            if let sizePerPart = estimatedSizePerPart {
                partSize = sizePerPart
            } else if let totalSize = estimatedTotalSize {
                partSize = totalSize / Int64(partCount)
            } else {
                partSize = nil
            }

            return ManifestEntry(
                category: name,
                partNumber: partNumber,
                totalParts: partCount,
                filename: filename,
                url: fileURL,
                estimatedSize: partSize
            )
        }
    }
}

// MARK: - Preview Helpers

extension CategoryManifest {

    /// Sample single-file category
    static var previewSingleFile: CategoryManifest {
        CategoryManifest(
            name: "Seasons",
            partCount: 1,
            estimatedTotalSize: 500_000_000
        )
    }

    /// Sample multi-part category
    static var previewMultiPart: CategoryManifest {
        CategoryManifest(
            name: "Animals",
            partCount: 2,
            estimatedTotalSize: 2_300_000_000
        )
    }

    /// Sample list of categories
    static var previewList: [CategoryManifest] {
        [
            CategoryManifest(name: "Animals", partCount: 2),
            CategoryManifest(name: "Greetings", partCount: 2),
            CategoryManifest(name: "Seasons", partCount: 1),
            CategoryManifest(name: "Adjectives", partCount: 8)
        ]
    }
}
