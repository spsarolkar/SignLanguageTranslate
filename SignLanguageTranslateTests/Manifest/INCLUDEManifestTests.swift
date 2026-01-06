import XCTest
@testable import SignLanguageTranslate

/// Unit tests for the INCLUDE dataset manifest system
final class INCLUDEManifestTests: XCTestCase {

    // MARK: - Basic Manifest Tests

    /// Test that total file count is exactly 46
    func test_totalFileCount_isExactly46() {
        XCTAssertEqual(
            INCLUDEManifest.totalFileCount,
            46,
            "INCLUDE dataset should have exactly 46 files"
        )
    }

    /// Test that there are exactly 15 categories
    func test_categoryCount_isExactly15() {
        XCTAssertEqual(
            INCLUDEManifest.categoryCount,
            15,
            "INCLUDE dataset should have exactly 15 categories"
        )
    }

    /// Test that base URL is correct
    func test_baseURL_isCorrect() {
        XCTAssertEqual(
            INCLUDEManifest.baseURL.absoluteString,
            "https://zenodo.org/api/records/4010759/files/",
            "Base URL should point to Zenodo INCLUDE dataset"
        )
    }

    /// Test that manifest is valid
    func test_manifest_isValid() {
        let errors = INCLUDEManifest.validate()
        XCTAssertTrue(
            errors.isEmpty,
            "Manifest should be valid. Errors: \(errors.joined(separator: ", "))"
        )
        XCTAssertTrue(INCLUDEManifest.isValid)
    }

    // MARK: - Single-Part Category Tests

    /// Test that single-part categories generate correct filename (not _1of1)
    func test_singlePartCategory_generatesCorrectFilename() {
        // Given: Seasons is a single-part category
        guard let seasons = INCLUDEManifest.category(named: "Seasons") else {
            XCTFail("Seasons category should exist")
            return
        }

        // Then: Should generate single filename without part numbering
        XCTAssertTrue(seasons.isSingleFile)
        XCTAssertEqual(seasons.partCount, 1)

        let filenames = seasons.generateFilenames()
        XCTAssertEqual(filenames.count, 1)
        XCTAssertEqual(filenames.first, "Seasons.zip", "Should be 'Seasons.zip', not 'Seasons_1of1.zip'")
    }

    /// Test that all single-file categories generate correct filenames
    func test_allSingleFileCategories_generateCorrectFilenames() {
        let singleFileCategories = INCLUDEManifest.singleFileCategories

        XCTAssertEqual(singleFileCategories.count, 1, "Should have exactly 1 single-file category")

        for category in singleFileCategories {
            let filenames = category.generateFilenames()
            XCTAssertEqual(filenames.count, 1)
            XCTAssertEqual(
                filenames.first,
                "\(category.name).zip",
                "Single-file category should not have _1of1 suffix"
            )
            XCTAssertFalse(filenames.first?.contains("_1of1") ?? false)
        }
    }

    // MARK: - Multi-Part Category Tests

    /// Test that multi-part categories generate correct filenames
    func test_multiPartCategory_generatesCorrectFilenames() {
        // Given: Animals is a 2-part category
        guard let animals = INCLUDEManifest.category(named: "Animals") else {
            XCTFail("Animals category should exist")
            return
        }

        // Then: Should generate two filenames with proper numbering
        XCTAssertTrue(animals.isMultiPart)
        XCTAssertEqual(animals.partCount, 2)

        let filenames = animals.generateFilenames()
        XCTAssertEqual(filenames.count, 2)
        XCTAssertEqual(filenames[0], "Animals_1of2.zip")
        XCTAssertEqual(filenames[1], "Animals_2of2.zip")
    }

    /// Test that Adjectives generates all 8 parts correctly
    func test_adjectives_generates8Parts() {
        // Given: Adjectives is an 8-part category
        guard let adjectives = INCLUDEManifest.category(named: "Adjectives") else {
            XCTFail("Adjectives category should exist")
            return
        }

        // Then: Should generate 8 filenames
        XCTAssertEqual(adjectives.partCount, 8)
        let filenames = adjectives.generateFilenames()
        XCTAssertEqual(filenames.count, 8)

        // Verify each filename
        for i in 1...8 {
            XCTAssertEqual(filenames[i - 1], "Adjectives_\(i)of8.zip")
        }
    }

    /// Test all multi-part categories have correct numbering
    func test_allMultiPartCategories_haveCorrectNumbering() {
        let multiPartCategories = INCLUDEManifest.multiPartCategories

        XCTAssertEqual(multiPartCategories.count, 14, "Should have 14 multi-part categories")

        for category in multiPartCategories {
            let filenames = category.generateFilenames()
            XCTAssertEqual(filenames.count, category.partCount)

            // Verify each filename has correct numbering
            for (index, filename) in filenames.enumerated() {
                let partNumber = index + 1
                let expectedFilename = "\(category.name)_\(partNumber)of\(category.partCount).zip"
                XCTAssertEqual(
                    filename,
                    expectedFilename,
                    "Category '\(category.name)' part \(partNumber) should have correct filename"
                )
            }
        }
    }

    // MARK: - URL Generation Tests

    /// Test that all URLs are valid and use correct base URL
    func test_allURLs_areValidAndUseCorrectBase() {
        let allURLs = INCLUDEManifest.generateAllURLs()

        XCTAssertEqual(allURLs.count, 46, "Should have 46 URLs")

        for (category, partNumber, totalParts, url) in allURLs {
            // Verify URL starts with base URL
            XCTAssertTrue(
                url.absoluteString.hasPrefix(INCLUDEManifest.baseURL.absoluteString),
                "URL should start with base URL"
            )

            // Verify filename matches expected pattern
            let filename = url.lastPathComponent
            if totalParts == 1 {
                XCTAssertEqual(filename, "\(category).zip")
            } else {
                XCTAssertEqual(filename, "\(category)_\(partNumber)of\(totalParts).zip")
            }
        }
    }

    /// Test specific URL generation
    func test_specificURLGeneration_forSeasonsCategory() {
        guard let url = INCLUDEManifest.url(forCategory: "Seasons", part: 1) else {
            XCTFail("Should generate URL for Seasons")
            return
        }

        XCTAssertEqual(
            url.absoluteString,
            "https://zenodo.org/api/records/4010759/files/Seasons.zip"
        )
    }

    /// Test specific URL generation for multi-part category
    func test_specificURLGeneration_forAnimalsCategory() {
        guard let url1 = INCLUDEManifest.url(forCategory: "Animals", part: 1) else {
            XCTFail("Should generate URL for Animals part 1")
            return
        }

        guard let url2 = INCLUDEManifest.url(forCategory: "Animals", part: 2) else {
            XCTFail("Should generate URL for Animals part 2")
            return
        }

        XCTAssertEqual(
            url1.absoluteString,
            "https://zenodo.org/api/records/4010759/files/Animals_1of2.zip"
        )

        XCTAssertEqual(
            url2.absoluteString,
            "https://zenodo.org/api/records/4010759/files/Animals_2of2.zip"
        )
    }

    // MARK: - Category Query Tests

    /// Test that all expected categories exist
    func test_allExpectedCategories_exist() {
        let expectedCategories = [
            "Adjectives", "Animals", "Clothes", "Colours", "Days_and_Time",
            "Electronics", "Greetings", "Home", "Jobs", "Means_of_Transportation",
            "People", "Places", "Pronouns", "Seasons", "Society"
        ]

        for categoryName in expectedCategories {
            XCTAssertTrue(
                INCLUDEManifest.hasCategory(named: categoryName),
                "Category '\(categoryName)' should exist"
            )
            XCTAssertNotNil(
                INCLUDEManifest.category(named: categoryName),
                "Should be able to fetch category '\(categoryName)'"
            )
        }
    }

    /// Test fetching manifest for specific category
    func test_fetchManifestForSpecificCategory_returnsCorrectEntries() {
        // Test single-file category
        let seasonsEntries = INCLUDEManifest.generateEntries(forCategory: "Seasons")
        XCTAssertEqual(seasonsEntries.count, 1)
        XCTAssertEqual(seasonsEntries.first?.category, "Seasons")
        XCTAssertEqual(seasonsEntries.first?.partNumber, 1)
        XCTAssertEqual(seasonsEntries.first?.totalParts, 1)
        XCTAssertEqual(seasonsEntries.first?.filename, "Seasons.zip")

        // Test multi-part category
        let animalsEntries = INCLUDEManifest.generateEntries(forCategory: "Animals")
        XCTAssertEqual(animalsEntries.count, 2)
        XCTAssertEqual(animalsEntries[0].category, "Animals")
        XCTAssertEqual(animalsEntries[0].partNumber, 1)
        XCTAssertEqual(animalsEntries[1].partNumber, 2)
    }

    /// Test fetching manifest for non-existent category
    func test_fetchManifestForNonExistentCategory_returnsEmpty() {
        let entries = INCLUDEManifest.generateEntries(forCategory: "NonExistent")
        XCTAssertTrue(entries.isEmpty)
    }

    // MARK: - Manifest Entry Generation Tests

    /// Test generating all manifest entries
    func test_generateAllEntries_returns46Entries() {
        let allEntries = INCLUDEManifest.generateAllEntries()

        XCTAssertEqual(allEntries.count, 46, "Should generate exactly 46 manifest entries")

        // Verify all entries are unique by ID
        let uniqueIDs = Set(allEntries.map(\.id))
        XCTAssertEqual(uniqueIDs.count, 46, "All entries should have unique IDs")

        // Verify all entries have valid URLs
        for entry in allEntries {
            XCTAssertTrue(entry.url.absoluteString.hasPrefix(INCLUDEManifest.baseURL.absoluteString))
            XCTAssertFalse(entry.filename.isEmpty)
            XCTAssertGreaterThan(entry.partNumber, 0)
            XCTAssertGreaterThan(entry.totalParts, 0)
            XCTAssertLessThanOrEqual(entry.partNumber, entry.totalParts)
        }
    }

    /// Test that sum of category parts equals total file count
    func test_sumOfCategoryParts_equalsTotalFileCount() {
        let sum = INCLUDEManifest.categories.reduce(0) { $0 + $1.partCount }
        XCTAssertEqual(
            sum,
            46,
            "Sum of all category part counts should equal total file count"
        )
    }

    // MARK: - Category Part Count Tests

    /// Test specific category part counts
    func test_specificCategories_haveCorrectPartCounts() {
        let expectedPartCounts: [String: Int] = [
            "Adjectives": 8,
            "Animals": 2,
            "Clothes": 2,
            "Colours": 2,
            "Days_and_Time": 3,
            "Electronics": 2,
            "Greetings": 2,
            "Home": 4,
            "Jobs": 2,
            "Means_of_Transportation": 2,
            "People": 5,
            "Places": 4,
            "Pronouns": 2,
            "Seasons": 1,
            "Society": 3
        ]

        for (categoryName, expectedCount) in expectedPartCounts {
            guard let category = INCLUDEManifest.category(named: categoryName) else {
                XCTFail("Category '\(categoryName)' should exist")
                continue
            }

            XCTAssertEqual(
                category.partCount,
                expectedCount,
                "Category '\(categoryName)' should have \(expectedCount) parts"
            )
        }
    }

    // MARK: - Statistics Tests

    /// Test manifest statistics
    func test_manifestStatistics_containsCorrectValues() {
        let stats = INCLUDEManifest.statistics()

        XCTAssertEqual(stats["totalCategories"] as? Int, 15)
        XCTAssertEqual(stats["totalFiles"] as? Int, 46)
        XCTAssertEqual(stats["singleFileCategories"] as? Int, 1)
        XCTAssertEqual(stats["multiPartCategories"] as? Int, 14)
        XCTAssertEqual(stats["isValid"] as? Bool, true)
        XCTAssertEqual(
            stats["baseURL"] as? String,
            "https://zenodo.org/api/records/4010759/files/"
        )
    }

    // MARK: - Validation Tests

    /// Test that validation catches incorrect total file count
    func test_validation_detectsIncorrectFileCount() {
        // This test verifies our current manifest is correct
        // If totalFileCount != 46, validation should fail
        let errors = INCLUDEManifest.validate()

        if INCLUDEManifest.totalFileCount != 46 {
            XCTAssertTrue(
                errors.contains { $0.contains("Total file count should be 46") },
                "Validation should detect incorrect file count"
            )
        }
    }

    /// Test that validation catches incorrect category count
    func test_validation_detectsIncorrectCategoryCount() {
        let errors = INCLUDEManifest.validate()

        if INCLUDEManifest.categoryCount != 15 {
            XCTAssertTrue(
                errors.contains { $0.contains("Total category count should be 15") },
                "Validation should detect incorrect category count"
            )
        }
    }

    // MARK: - Edge Case Tests

    /// Test fetching URL for invalid part number
    func test_urlGeneration_forInvalidPartNumber_returnsNil() {
        // Try to get part 0 (invalid)
        XCTAssertNil(INCLUDEManifest.url(forCategory: "Seasons", part: 0))

        // Try to get part beyond total parts
        XCTAssertNil(INCLUDEManifest.url(forCategory: "Seasons", part: 2))

        // Try to get part beyond Animals' 2 parts
        XCTAssertNil(INCLUDEManifest.url(forCategory: "Animals", part: 3))
    }

    /// Test category names array
    func test_categoryNames_containsAllCategories() {
        let categoryNames = INCLUDEManifest.categoryNames

        XCTAssertEqual(categoryNames.count, 15)
        XCTAssertTrue(categoryNames.contains("Animals"))
        XCTAssertTrue(categoryNames.contains("Seasons"))
        XCTAssertTrue(categoryNames.contains("Adjectives"))
    }

    // MARK: - Estimated Size Tests

    /// Test that estimated sizes are reasonable
    func test_estimatedSizes_areReasonable() {
        let allEntries = INCLUDEManifest.generateAllEntries()

        for entry in allEntries {
            if let estimatedSize = entry.estimatedSize {
                // Each part should be between 100 MB and 10 GB
                XCTAssertGreaterThan(
                    estimatedSize,
                    100_000_000,
                    "Part size should be at least 100 MB for \(entry.filename)"
                )
                XCTAssertLessThan(
                    estimatedSize,
                    10_000_000_000,
                    "Part size should be less than 10 GB for \(entry.filename)"
                )
            }
        }
    }

    /// Test that total estimated size is approximately 50 GB
    func test_totalEstimatedSize_isApproximately50GB() {
        let estimatedTotal = INCLUDEManifest.estimatedTotalSize

        // Should be close to 50 GB (allow 45-55 GB range)
        XCTAssertGreaterThan(estimatedTotal, 45_000_000_000)
        XCTAssertLessThan(estimatedTotal, 55_000_000_000)
    }
}
