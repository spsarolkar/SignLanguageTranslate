import Foundation

/// Represents a single downloadable file in a dataset manifest
///
/// Each manifest entry corresponds to one zip file that needs to be downloaded
/// from the dataset repository. For datasets split into multiple parts, each
/// part gets its own manifest entry.
struct ManifestEntry: Identifiable, Codable, Hashable {

    // MARK: - Properties

    /// Unique identifier for this manifest entry
    let id: UUID

    /// Category name (e.g., "Animals", "Greetings")
    let category: String

    /// Part number (1-indexed) for this file within its category
    /// For single-file categories, this is always 1
    let partNumber: Int

    /// Total number of parts in this category
    /// For single-file categories, this is always 1
    let totalParts: Int

    /// Filename for this zip file (e.g., "Animals_1of2.zip")
    let filename: String

    /// Full URL to download this file
    let url: URL

    /// Estimated size of this file in bytes (optional)
    /// Can be used for progress indicators and storage calculations
    let estimatedSize: Int64?

    // MARK: - Computed Properties

    /// Whether this is a single-file category (no parts)
    var isSingleFile: Bool {
        totalParts == 1
    }

    /// Whether this is a multi-part category
    var isMultiPart: Bool {
        totalParts > 1
    }

    /// Display name for UI (e.g., "Animals (Part 1 of 2)")
    var displayName: String {
        if isSingleFile {
            return category
        } else {
            return "\(category) (Part \(partNumber) of \(totalParts))"
        }
    }

    /// Short display name (e.g., "Animals 1/2")
    var shortDisplayName: String {
        if isSingleFile {
            return category
        } else {
            return "\(category) \(partNumber)/\(totalParts)"
        }
    }

    /// Formatted estimated size (if available)
    var formattedEstimatedSize: String? {
        guard let size = estimatedSize else { return nil }
        return FileManager.formattedSize(size)
    }

    // MARK: - Initialization

    /// Create a manifest entry
    /// - Parameters:
    ///   - id: Unique identifier (defaults to new UUID)
    ///   - category: Category name
    ///   - partNumber: Part number (1-indexed)
    ///   - totalParts: Total parts in category
    ///   - filename: Filename for the zip file
    ///   - url: Download URL
    ///   - estimatedSize: Estimated file size in bytes
    init(
        id: UUID = UUID(),
        category: String,
        partNumber: Int,
        totalParts: Int,
        filename: String,
        url: URL,
        estimatedSize: Int64? = nil
    ) {
        self.id = id
        self.category = category
        self.partNumber = partNumber
        self.totalParts = totalParts
        self.filename = filename
        self.url = url
        self.estimatedSize = estimatedSize
    }
}

// MARK: - Preview Helpers

extension ManifestEntry {

    /// Sample single-file manifest entry
    static var previewSingleFile: ManifestEntry {
        ManifestEntry(
            category: "Seasons",
            partNumber: 1,
            totalParts: 1,
            filename: "Seasons.zip",
            url: URL(string: "https://zenodo.org/api/records/4010759/files/Seasons.zip")!,
            estimatedSize: 500_000_000
        )
    }

    /// Sample multi-part manifest entry
    static var previewMultiPart: ManifestEntry {
        ManifestEntry(
            category: "Animals",
            partNumber: 1,
            totalParts: 2,
            filename: "Animals_1of2.zip",
            url: URL(string: "https://zenodo.org/api/records/4010759/files/Animals_1of2.zip")!,
            estimatedSize: 1_200_000_000
        )
    }

    /// Sample list of manifest entries
    static var previewList: [ManifestEntry] {
        [
            previewSingleFile,
            previewMultiPart,
            ManifestEntry(
                category: "Animals",
                partNumber: 2,
                totalParts: 2,
                filename: "Animals_2of2.zip",
                url: URL(string: "https://zenodo.org/api/records/4010759/files/Animals_2of2.zip")!,
                estimatedSize: 1_100_000_000
            )
        ]
    }
}
