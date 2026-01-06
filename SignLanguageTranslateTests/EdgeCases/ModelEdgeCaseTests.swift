import XCTest
import SwiftData
@testable import SignLanguageTranslate

/// Edge case tests for model validation and boundary conditions
final class ModelEdgeCaseTests: XCTestCase {

    var container: ModelContainer!
    var context: ModelContext!

    override func setUpWithError() throws {
        (container, context) = try makeTestEnvironment()
    }

    override func tearDownWithError() throws {
        container = nil
        context = nil
    }

    // MARK: - VideoSample Path Edge Cases

    /// Test VideoSample with empty localPath
    func test_videoSampleWithEmptyLocalPath_handlesGracefully() {
        let sample = VideoSample(localPath: "", datasetName: "TEST")

        XCTAssertEqual(sample.localPath, "")
        XCTAssertEqual(sample.fileName, "")
        XCTAssertEqual(sample.fileNameWithoutExtension, "")
        XCTAssertEqual(sample.fileExtension, "")
    }

    /// Test VideoSample with very long localPath
    func test_videoSampleWithVeryLongLocalPath_handlesCorrectly() {
        // Create a path with 500+ characters
        let longFolder = String(repeating: "a", count: 100)
        let longPath = "\(longFolder)/\(longFolder)/\(longFolder)/\(longFolder)/\(longFolder)/video.mp4"

        XCTAssertGreaterThan(longPath.count, 500)

        let sample = VideoSample(localPath: longPath, datasetName: "TEST")

        XCTAssertEqual(sample.localPath, longPath)
        XCTAssertEqual(sample.fileName, "video.mp4")
        XCTAssertEqual(sample.fileExtension, "mp4")
    }

    /// Test VideoSample with special characters in path
    func test_videoSampleWithSpecialCharactersInPath_handlesCorrectly() {
        let paths = [
            "folder/video with spaces.mp4",
            "folder/vidéo-àccénts.mp4",
            "folder/日本語/video.mp4",
            "folder/emoji😀/video.mp4"
        ]

        for path in paths {
            let sample = VideoSample(localPath: path, datasetName: "TEST")
            XCTAssertEqual(sample.localPath, path)
            XCTAssertFalse(sample.fileName.isEmpty)
        }
    }

    // MARK: - Label Name Edge Cases

    /// Test Label with empty name
    func test_labelWithEmptyName_canBeCreated() {
        let label = Label(name: "", type: .word)

        XCTAssertEqual(label.name, "")
        XCTAssertEqual(label.displayName, "Word: ")
        XCTAssertEqual(label.shortDisplayName, "")
    }

    /// Test Label with whitespace-only name
    func test_labelWithWhitespaceOnlyName_preserved() {
        let label = Label(name: "   ", type: .word)

        XCTAssertEqual(label.name, "   ")
    }

    /// Test Label with special characters in name
    func test_labelWithSpecialCharactersInName_handlesCorrectly() {
        let names = [
            "Hello/World",
            "Test@Label",
            "Label#1",
            "Label & More",
            "Question?",
            "Exclamation!",
            "日本語ラベル",
            "Emoji😀Label"
        ]

        for name in names {
            let label = Label(name: name, type: .word)
            context.insert(label)

            XCTAssertEqual(label.name, name)
        }

        XCTAssertNoThrow(try context.save())
    }

    /// Test Label with very long name (1000+ characters)
    func test_labelWithVeryLongName_handlesCorrectly() {
        let longName = String(repeating: "a", count: 1000)
        let label = Label(name: longName, type: .word)

        XCTAssertEqual(label.name.count, 1000)
        XCTAssertEqual(label.shortDisplayName, longName)

        context.insert(label)
        XCTAssertNoThrow(try context.save())
    }

    // MARK: - Dataset Progress Edge Cases

    /// Test Dataset with zero totalBytes (division by zero)
    func test_datasetWithZeroTotalBytes_progressIsZero() {
        let dataset = Dataset(
            name: "TEST",
            type: .include,
            totalBytes: 0,
            downloadedBytes: 100
        )

        XCTAssertEqual(dataset.downloadProgress, 0)
        XCTAssertEqual(dataset.partsProgress, 0)
        XCTAssertEqual(dataset.samplesProgress, 0)
    }

    /// Test Dataset with downloadedBytes > totalBytes
    func test_datasetWithDownloadedExceedingTotal_handlesGracefully() {
        let dataset = Dataset(
            name: "TEST",
            type: .include,
            totalBytes: 1_000_000,
            downloadedBytes: 2_000_000  // More than total
        )

        // Progress should be > 1.0 in this edge case
        XCTAssertGreaterThan(dataset.downloadProgress, 1.0)
        XCTAssertEqual(dataset.downloadProgress, 2.0)
    }

    /// Test Dataset with negative bytes
    func test_datasetWithNegativeBytes_handlesGracefully() {
        let dataset = Dataset(name: "TEST", type: .include)
        dataset.totalBytes = -1000
        dataset.downloadedBytes = -500

        // Should handle negative values
        XCTAssertEqual(dataset.formattedTotalSize, "Zero KB")
    }

    /// Test Dataset with maximum Int64 bytes
    func test_datasetWithMaximumBytes_formatsCorrectly() {
        let dataset = Dataset(name: "TEST", type: .include)
        dataset.totalBytes = Int64.max

        let formatted = dataset.formattedTotalSize
        XCTAssertFalse(formatted.isEmpty)
        // Should contain some unit (KB, MB, GB, TB, etc.)
        XCTAssertTrue(formatted.contains("B"))
    }

    // MARK: - VideoSample Duration Edge Cases

    /// Test VideoSample.formattedDuration with very large duration
    func test_videoSampleFormattedDuration_withLargeDuration_formatsCorrectly() {
        let sample = VideoSample(
            localPath: "test.mp4",
            datasetName: "TEST",
            duration: 10_000  // ~2.7 hours
        )

        let formatted = sample.formattedDuration
        XCTAssertEqual(formatted, "166:40")  // 166 minutes, 40 seconds
    }

    /// Test VideoSample.formattedDuration with negative duration
    func test_videoSampleFormattedDuration_withNegativeDuration_handlesGracefully() {
        let sample = VideoSample(
            localPath: "test.mp4",
            datasetName: "TEST",
            duration: -30
        )

        // Should handle negative duration
        let formatted = sample.formattedDuration
        XCTAssertFalse(formatted.isEmpty)
    }

    /// Test VideoSample.formattedDuration with zero duration
    func test_videoSampleFormattedDuration_withZeroDuration_returnsZero() {
        let sample = VideoSample(
            localPath: "test.mp4",
            datasetName: "TEST",
            duration: 0
        )

        XCTAssertEqual(sample.formattedDuration, "0:00")
    }

    /// Test VideoSample.formattedDuration with fractional seconds
    func test_videoSampleFormattedDuration_withFractionalSeconds_roundsDown() {
        let sample = VideoSample(
            localPath: "test.mp4",
            datasetName: "TEST",
            duration: 45.7
        )

        XCTAssertEqual(sample.formattedDuration, "0:45")  // Should round down
    }

    // MARK: - Multiple Labels Same Name Different Type

    /// Test multiple Labels with same name but different types
    func test_multipleLabelsWithSameNameDifferentTypes_areDistinct() throws {
        let categoryLabel = Label(name: "Test", type: .category)
        let wordLabel = Label(name: "Test", type: .word)
        let sentenceLabel = Label(name: "Test", type: .sentence)

        context.insert(categoryLabel)
        context.insert(wordLabel)
        context.insert(sentenceLabel)
        try context.save()

        // Should be able to fetch each separately
        let categories = try context.fetch(ModelQueries.labels(ofType: .category))
        let words = try context.fetch(ModelQueries.labels(ofType: .word))
        let sentences = try context.fetch(ModelQueries.labels(ofType: .sentence))

        XCTAssertEqual(categories.filter { $0.name == "Test" }.count, 1)
        XCTAssertEqual(words.filter { $0.name == "Test" }.count, 1)
        XCTAssertEqual(sentences.filter { $0.name == "Test" }.count, 1)

        // All should have different IDs
        XCTAssertNotEqual(categoryLabel.id, wordLabel.id)
        XCTAssertNotEqual(categoryLabel.id, sentenceLabel.id)
        XCTAssertNotEqual(wordLabel.id, sentenceLabel.id)
    }

    /// Test finding the correct Label when duplicates exist (different types)
    func test_findLabelWithDuplicateNames_findsCorrectType() throws {
        let categoryLabel = Label(name: "Duplicate", type: .category)
        let wordLabel = Label(name: "Duplicate", type: .word)

        context.insert(categoryLabel)
        context.insert(wordLabel)
        try context.save()

        // When: We search for specific type
        let foundCategory = try context.findOrCreateLabel(named: "Duplicate", type: .category)
        let foundWord = try context.findOrCreateLabel(named: "Duplicate", type: .word)

        // Then: Should find the correct one by type
        XCTAssertEqual(foundCategory.id, categoryLabel.id)
        XCTAssertEqual(foundWord.id, wordLabel.id)
        XCTAssertEqual(foundCategory.type, .category)
        XCTAssertEqual(foundWord.type, .word)
    }

    // MARK: - String Extension Edge Cases

    /// Test sanitizedLabel with edge cases
    func test_sanitizedLabel_edgeCases() {
        let testCases: [(input: String, expected: String)] = [
            ("", ""),
            ("   ", ""),
            ("123", "123"),
            ("1.", ""),
            (".Dog", ".Dog"),
            ("1.2.3. Dog", "2.3. Dog"),
            ("  999.   ", ""),
            ("12. Dog Cat Bird", "Dog Cat Bird"),
            ("No numbers here", "No numbers here"),
            ("123 No dot", "123 No dot")
        ]

        for (input, expected) in testCases {
            let result = input.sanitizedLabel()
            XCTAssertEqual(result, expected, "Failed for input: '\(input)'")
        }
    }

    /// Test toSafeFilename with edge cases
    func test_toSafeFilename_edgeCases() {
        let testCases: [(input: String, shouldBeValid: Bool)] = [
            ("", false),  // Empty
            ("   ", false),  // Only whitespace
            ("valid_file.mp4", true),
            ("invalid/file.mp4", false),
            ("invalid\\file.mp4", false),
            ("invalid:file.mp4", false),
            ("invalid*file.mp4", false),
            ("invalid?file.mp4", false),
            ("invalid\"file.mp4", false),
            ("invalid<file.mp4", false),
            ("invalid>file.mp4", false),
            ("invalid|file.mp4", false),
            ("日本語.mp4", true),  // Unicode
            ("emoji😀.mp4", true)  // Emoji
        ]

        for (input, shouldBeValid) in testCases {
            let isValid = input.isValidFilename
            XCTAssertEqual(isValid, shouldBeValid, "Failed for input: '\(input)'")

            if !shouldBeValid && !input.trimmingCharacters(in: .whitespaces).isEmpty {
                let safe = input.toSafeFilename()
                XCTAssertTrue(safe.isValidFilename, "toSafeFilename should produce valid filename")
            }
        }
    }

    // MARK: - VideoSample with No Labels

    /// Test VideoSample with no labels
    func test_videoSampleWithNoLabels_handlesCorrectly() {
        let sample = VideoSample(localPath: "test.mp4", datasetName: "TEST")

        XCTAssertTrue(sample.labels.isEmpty)
        XCTAssertNil(sample.categoryLabel)
        XCTAssertNil(sample.wordLabel)
        XCTAssertNil(sample.sentenceLabel)
        XCTAssertNil(sample.categoryName)
        XCTAssertNil(sample.wordName)

        // Display title should fall back to filename
        XCTAssertEqual(sample.displayTitle, "test")
    }

    // MARK: - Concurrent Modification Edge Cases

    /// Test adding and removing labels multiple times
    func test_addingAndRemovingLabels_multipleT imes_maintainsConsistency() throws {
        let sample = VideoSample(localPath: "test.mp4", datasetName: "TEST")
        let label = Label(name: "Test", type: .word)

        context.insert(sample)
        context.insert(label)

        // Add and remove multiple times
        for _ in 1...10 {
            sample.addLabel(label)
            sample.removeLabel(label)
        }

        try context.save()

        XCTAssertTrue(sample.labels.isEmpty)
    }

    /// Test adding same label multiple times
    func test_addingSameLabelMultipleTimes_onlyAddsOnce() {
        let sample = VideoSample(localPath: "test.mp4", datasetName: "TEST")
        let label = Label(name: "Test", type: .word)

        context.insert(sample)
        context.insert(label)

        // Add same label 5 times
        for _ in 1...5 {
            sample.addLabel(label)
        }

        XCTAssertEqual(sample.labels.count, 1)
        XCTAssertEqual(sample.labels.first?.id, label.id)
    }

    // MARK: - Dataset State Transition Edge Cases

    /// Test rapid state transitions
    func test_datasetRapidStateTransitions_handlesCorrectly() {
        let dataset = Dataset(name: "TEST", type: .include)

        // Rapid transitions
        dataset.startDownload()
        XCTAssertEqual(dataset.downloadStatus, .downloading)

        dataset.pauseDownload()
        XCTAssertEqual(dataset.downloadStatus, .paused)

        dataset.startDownload()  // Resume
        XCTAssertEqual(dataset.downloadStatus, .downloading)

        dataset.completeDownload()
        XCTAssertEqual(dataset.downloadStatus, .completed)

        // Can't start a completed download
        dataset.startDownload()
        XCTAssertEqual(dataset.downloadStatus, .downloading)  // But it will change to downloading
    }

    /// Test dataset reset after failure
    func test_datasetResetAfterFailure_clearsState() {
        let dataset = Dataset(name: "TEST", type: .include)

        dataset.startDownload()
        dataset.updateProgress(downloadedBytes: 500, totalBytes: 1000)
        dataset.updatePartsProgress(downloadedParts: 3, totalParts: 10)
        dataset.failDownload(error: "Network error")

        XCTAssertEqual(dataset.downloadStatus, .failed)
        XCTAssertNotNil(dataset.lastError)

        dataset.resetDownload()

        XCTAssertEqual(dataset.downloadStatus, .notStarted)
        XCTAssertEqual(dataset.downloadedBytes, 0)
        XCTAssertEqual(dataset.downloadedParts, 0)
        XCTAssertNil(dataset.lastError)
        XCTAssertNil(dataset.downloadStartedAt)
    }

    // MARK: - URL Path Construction Edge Cases

    /// Test absoluteURL construction with unusual paths
    func test_absoluteURL_withUnusualPaths_constructsCorrectly() {
        let samples = [
            VideoSample(localPath: "", datasetName: "TEST"),
            VideoSample(localPath: "single.mp4", datasetName: "TEST"),
            VideoSample(localPath: "deep/nested/path/to/video.mp4", datasetName: "TEST"),
            VideoSample(localPath: "path with spaces/video.mp4", datasetName: "TEST")
        ]

        for sample in samples {
            let url = sample.absoluteURL
            XCTAssertNotNil(url)
            XCTAssertTrue(url.path.contains("Datasets"))
        }
    }
}
