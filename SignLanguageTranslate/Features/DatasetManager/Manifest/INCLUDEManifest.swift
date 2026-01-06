import Foundation

/// Manifest for the INCLUDE (Indian Sign Language) dataset from Zenodo
///
/// The INCLUDE dataset is hosted at: https://zenodo.org/records/4010759
///
/// Dataset structure:
/// - 15 categories of sign language words
/// - 46 total zip files (some categories split into multiple parts)
/// - Approximately 50 GB total size
/// - Categories include: Adjectives, Animals, Clothes, Colors, Days and Time,
///   Electronics, Greetings, Home, Jobs, Transportation, People, Places,
///   Pronouns, Seasons, and Society
///
/// File naming convention:
/// - Single file: "CategoryName.zip"
/// - Multi-part: "CategoryName_1of2.zip", "CategoryName_2of2.zip", etc.
enum INCLUDEManifest {

    // MARK: - Constants

    /// Base URL for the Zenodo dataset files
    static let baseURL = URL(string: "https://zenodo.org/api/records/4010759/files/")!

    /// Estimated total size of the entire dataset (approximately 50 GB)
    static let estimatedTotalSize: Int64 = 50_000_000_000

    // MARK: - Category Definitions

    /// All categories in the INCLUDE dataset with their part counts
    ///
    /// The estimated sizes are rough approximations based on typical file sizes
    /// for sign language video datasets. Actual sizes may vary.
    static let categories: [CategoryManifest] = [
        CategoryManifest(
            name: "Adjectives",
            partCount: 8,
            estimatedTotalSize: 8_000_000_000  // ~8 GB (1 GB per part)
        ),
        CategoryManifest(
            name: "Animals",
            partCount: 2,
            estimatedTotalSize: 2_300_000_000  // ~2.3 GB
        ),
        CategoryManifest(
            name: "Clothes",
            partCount: 2,
            estimatedTotalSize: 2_000_000_000  // ~2 GB
        ),
        CategoryManifest(
            name: "Colours",
            partCount: 2,
            estimatedTotalSize: 1_800_000_000  // ~1.8 GB
        ),
        CategoryManifest(
            name: "Days_and_Time",
            partCount: 3,
            estimatedTotalSize: 3_000_000_000  // ~3 GB
        ),
        CategoryManifest(
            name: "Electronics",
            partCount: 2,
            estimatedTotalSize: 2_000_000_000  // ~2 GB
        ),
        CategoryManifest(
            name: "Greetings",
            partCount: 2,
            estimatedTotalSize: 2_200_000_000  // ~2.2 GB
        ),
        CategoryManifest(
            name: "Home",
            partCount: 4,
            estimatedTotalSize: 4_500_000_000  // ~4.5 GB
        ),
        CategoryManifest(
            name: "Jobs",
            partCount: 2,
            estimatedTotalSize: 2_000_000_000  // ~2 GB
        ),
        CategoryManifest(
            name: "Means_of_Transportation",
            partCount: 2,
            estimatedTotalSize: 2_000_000_000  // ~2 GB
        ),
        CategoryManifest(
            name: "People",
            partCount: 5,
            estimatedTotalSize: 5_500_000_000  // ~5.5 GB
        ),
        CategoryManifest(
            name: "Places",
            partCount: 4,
            estimatedTotalSize: 4_200_000_000  // ~4.2 GB
        ),
        CategoryManifest(
            name: "Pronouns",
            partCount: 2,
            estimatedTotalSize: 1_800_000_000  // ~1.8 GB
        ),
        CategoryManifest(
            name: "Seasons",
            partCount: 1,
            estimatedTotalSize: 700_000_000  // ~700 MB
        ),
        CategoryManifest(
            name: "Society",
            partCount: 3,
            estimatedTotalSize: 3_000_000_000  // ~3 GB
        )
    ]

    // MARK: - Computed Properties

    /// Total number of files in the manifest (should be 46)
    static var totalFileCount: Int {
        categories.reduce(0) { $0 + $1.partCount }
    }

    /// Total number of categories
    static var categoryCount: Int {
        categories.count
    }

    /// All category names
    static var categoryNames: [String] {
        categories.map(\.name)
    }

    // MARK: - Query Methods

    /// Get manifest for a specific category by name
    /// - Parameter name: Category name
    /// - Returns: CategoryManifest if found, nil otherwise
    static func category(named name: String) -> CategoryManifest? {
        categories.first { $0.name == name }
    }

    /// Check if a category exists
    /// - Parameter name: Category name
    /// - Returns: True if category exists
    static func hasCategory(named name: String) -> Bool {
        category(named: name) != nil
    }

    /// Get all single-file categories
    static var singleFileCategories: [CategoryManifest] {
        categories.filter { $0.isSingleFile }
    }

    /// Get all multi-part categories
    static var multiPartCategories: [CategoryManifest] {
        categories.filter { $0.isMultiPart }
    }

    // MARK: - Manifest Entry Generation

    /// Generate all manifest entries for the entire dataset
    /// - Returns: Array of 46 ManifestEntry objects
    static func generateAllEntries() -> [ManifestEntry] {
        categories.flatMap { category in
            category.generateManifestEntries(baseURL: baseURL)
        }
    }

    /// Generate manifest entries for a specific category
    /// - Parameter categoryName: Name of the category
    /// - Returns: Array of ManifestEntry objects for that category, or empty array if not found
    static func generateEntries(forCategory categoryName: String) -> [ManifestEntry] {
        guard let category = category(named: categoryName) else {
            return []
        }
        return category.generateManifestEntries(baseURL: baseURL)
    }

    /// Generate all download URLs with metadata
    /// - Returns: Array of tuples containing metadata and URL for each file
    static func generateAllURLs() -> [(category: String, partNumber: Int, totalParts: Int, url: URL)] {
        let entries = generateAllEntries()
        return entries.map { entry in
            (
                category: entry.category,
                partNumber: entry.partNumber,
                totalParts: entry.totalParts,
                url: entry.url
            )
        }
    }

    /// Get download URL for a specific category and part
    /// - Parameters:
    ///   - categoryName: Category name
    ///   - partNumber: Part number (1-indexed)
    /// - Returns: URL if found, nil otherwise
    static func url(forCategory categoryName: String, part partNumber: Int) -> URL? {
        guard let category = category(named: categoryName),
              let filename = category.filename(forPart: partNumber) else {
            return nil
        }
        return baseURL.appendingPathComponent(filename)
    }
}

// MARK: - Statistics and Validation

extension INCLUDEManifest {

    /// Validate that the manifest is correctly configured
    /// - Returns: Array of validation errors, empty if valid
    static func validate() -> [String] {
        var errors: [String] = []

        // Check total file count
        if totalFileCount != 46 {
            errors.append("Total file count should be 46, got \(totalFileCount)")
        }

        // Check category count
        if categoryCount != 15 {
            errors.append("Total category count should be 15, got \(categoryCount)")
        }

        // Check for duplicate category names
        let uniqueNames = Set(categoryNames)
        if uniqueNames.count != categoryNames.count {
            errors.append("Duplicate category names detected")
        }

        // Check that all categories have valid part counts
        for category in categories {
            if category.partCount < 1 {
                errors.append("Category '\(category.name)' has invalid part count: \(category.partCount)")
            }
        }

        // Verify specific known categories exist
        let requiredCategories = ["Animals", "Greetings", "Seasons"]
        for required in requiredCategories {
            if !hasCategory(named: required) {
                errors.append("Missing required category: \(required)")
            }
        }

        // Verify Seasons is single file
        if let seasons = category(named: "Seasons"), !seasons.isSingleFile {
            errors.append("Seasons should be a single file")
        }

        // Verify Adjectives has 8 parts
        if let adjectives = category(named: "Adjectives"), adjectives.partCount != 8 {
            errors.append("Adjectives should have 8 parts, got \(adjectives.partCount)")
        }

        return errors
    }

    /// Check if the manifest is valid
    static var isValid: Bool {
        validate().isEmpty
    }

    /// Get statistics about the manifest
    static func statistics() -> [String: Any] {
        [
            "totalCategories": categoryCount,
            "totalFiles": totalFileCount,
            "singleFileCategories": singleFileCategories.count,
            "multiPartCategories": multiPartCategories.count,
            "estimatedTotalSize": estimatedTotalSize,
            "estimatedTotalSizeFormatted": FileManager.formattedSize(estimatedTotalSize),
            "baseURL": baseURL.absoluteString,
            "isValid": isValid
        ]
    }
}
