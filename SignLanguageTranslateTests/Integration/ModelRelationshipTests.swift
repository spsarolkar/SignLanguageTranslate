import XCTest
import SwiftData
@testable import SignLanguageTranslate

/// Integration tests for model relationships and complex queries
final class ModelRelationshipTests: XCTestCase {

    var container: ModelContainer!
    var context: ModelContext!

    override func setUpWithError() throws {
        (container, context) = try makeTestEnvironment()
    }

    override func tearDownWithError() throws {
        container = nil
        context = nil
    }

    // MARK: - Bidirectional Relationship Tests

    /// Test creating a VideoSample with multiple Labels and verify bidirectional relationships
    func test_videoSampleWithMultipleLabels_createsBidirectionalRelationships() throws {
        // Given: A video sample with category and word labels
        let categoryLabel = TestDataFactory.makeCategoryLabel(name: "Animals")
        let wordLabel = TestDataFactory.makeWordLabel(name: "Dog")
        let sample = TestDataFactory.makeVideoSample(
            localPath: "INCLUDE/Animals/Dog/video_001.mp4",
            datasetName: "INCLUDE"
        )

        // When: We establish the relationship
        sample.labels = [categoryLabel, wordLabel]
        context.insert(categoryLabel)
        context.insert(wordLabel)
        context.insert(sample)
        try context.save()

        // Then: Both directions of the relationship should exist
        XCTAssertEqual(sample.labels.count, 2, "Sample should have 2 labels")

        SwiftDataAssertions.assertBidirectionalRelationship(
            sample: sample,
            label: categoryLabel
        )

        SwiftDataAssertions.assertBidirectionalRelationship(
            sample: sample,
            label: wordLabel
        )
    }

    /// Test querying VideoSamples through their Labels
    func test_queryVideoSamplesThroughLabels_returnsCorrectSamples() throws {
        // Given: Multiple samples with shared labels
        let categoryLabel = TestDataFactory.makeCategoryLabel(name: "Animals")
        let dogLabel = TestDataFactory.makeWordLabel(name: "Dog")
        let catLabel = TestDataFactory.makeWordLabel(name: "Cat")

        context.insert(categoryLabel)
        context.insert(dogLabel)
        context.insert(catLabel)

        // Create dog samples
        let dogSample1 = TestDataFactory.makeVideoSample(localPath: "dog1.mp4")
        dogSample1.labels = [categoryLabel, dogLabel]
        context.insert(dogSample1)

        let dogSample2 = TestDataFactory.makeVideoSample(localPath: "dog2.mp4")
        dogSample2.labels = [categoryLabel, dogLabel]
        context.insert(dogSample2)

        // Create cat sample
        let catSample = TestDataFactory.makeVideoSample(localPath: "cat1.mp4")
        catSample.labels = [categoryLabel, catLabel]
        context.insert(catSample)

        try context.save()

        // When: We query for dog label's videos
        let dogVideos = dogLabel.videoSamples ?? []

        // Then: Should only get dog samples
        XCTAssertEqual(dogVideos.count, 2, "Dog label should have 2 videos")
        XCTAssertTrue(dogVideos.contains(where: { $0.id == dogSample1.id }))
        XCTAssertTrue(dogVideos.contains(where: { $0.id == dogSample2.id }))
        XCTAssertFalse(dogVideos.contains(where: { $0.id == catSample.id }))
    }

    /// Test querying Labels through their VideoSamples
    func test_queryLabelsThroughVideoSamples_returnsCorrectLabels() throws {
        // Given: A sample with multiple labels
        let sample = TestDataFactory.makeVideoSample(localPath: "test.mp4")
        let label1 = TestDataFactory.makeCategoryLabel(name: "Category1")
        let label2 = TestDataFactory.makeWordLabel(name: "Word1")
        let label3 = TestDataFactory.makeSentenceLabel(name: "Sentence1")

        sample.labels = [label1, label2, label3]

        context.insert(sample)
        context.insert(label1)
        context.insert(label2)
        context.insert(label3)
        try context.save()

        // When: We access labels through the sample
        let sampleLabels = sample.labels

        // Then: Should have all 3 labels
        XCTAssertEqual(sampleLabels.count, 3)
        XCTAssertNotNil(sample.categoryLabel)
        XCTAssertNotNil(sample.wordLabel)
        XCTAssertNotNil(sample.sentenceLabel)
    }

    // MARK: - Deletion Tests

    /// Test deleting a Label removes it from VideoSample.labels
    func test_deletingLabel_removesFromVideoSampleLabels() throws {
        // Given: A sample with labels
        let sample = TestDataFactory.makeVideoSample(localPath: "test.mp4")
        let categoryLabel = TestDataFactory.makeCategoryLabel(name: "Animals")
        let wordLabel = TestDataFactory.makeWordLabel(name: "Dog")

        sample.labels = [categoryLabel, wordLabel]
        context.insert(sample)
        context.insert(categoryLabel)
        context.insert(wordLabel)
        try context.save()

        XCTAssertEqual(sample.labels.count, 2)

        // When: We delete the category label
        context.delete(categoryLabel)
        try context.save()

        // Then: Sample should only have word label
        XCTAssertEqual(sample.labels.count, 1)
        XCTAssertEqual(sample.labels.first?.name, "Dog")
        XCTAssertNil(sample.categoryLabel)
        XCTAssertNotNil(sample.wordLabel)
    }

    /// Test deleting a VideoSample removes it from Label.videoSamples
    func test_deletingVideoSample_removesFromLabelVideoSamples() throws {
        // Given: A label with multiple video samples
        let label = TestDataFactory.makeWordLabel(name: "Dog")
        let sample1 = TestDataFactory.makeVideoSample(localPath: "video1.mp4")
        let sample2 = TestDataFactory.makeVideoSample(localPath: "video2.mp4")

        sample1.labels = [label]
        sample2.labels = [label]

        context.insert(label)
        context.insert(sample1)
        context.insert(sample2)
        try context.save()

        XCTAssertEqual(label.videoSamples?.count, 2)

        // When: We delete one sample
        context.delete(sample1)
        try context.save()

        // Then: Label should still exist with only one video
        let fetchedLabel = try context.fetch(
            ModelQueries.label(named: "Dog", type: .word)
        ).first
        XCTAssertNotNil(fetchedLabel)
        XCTAssertEqual(fetchedLabel?.videoSamples?.count, 1)
        XCTAssertTrue(fetchedLabel?.videoSamples?.contains(where: { $0.id == sample2.id }) ?? false)
    }

    // MARK: - Complex Query Tests

    /// Test finding all videos in a category, then all words in that category
    func test_complexQuery_findAllVideosAndWordsInCategory() throws {
        // Given: A category with multiple words and videos
        let animalsCategory = TestDataFactory.makeCategoryLabel(name: "Animals")
        context.insert(animalsCategory)

        let words = ["Dog", "Cat", "Bird"]
        var allSamples: [VideoSample] = []

        for word in words {
            let wordLabel = TestDataFactory.makeWordLabel(name: word)
            context.insert(wordLabel)

            // Create 3 videos per word
            for i in 1...3 {
                let sample = TestDataFactory.makeVideoSample(
                    localPath: "Animals/\(word)/video_\(i).mp4"
                )
                sample.labels = [animalsCategory, wordLabel]
                context.insert(sample)
                allSamples.append(sample)
            }
        }

        try context.save()

        // When: We query for all videos in Animals category
        let categoryVideos = animalsCategory.videoSamples ?? []

        // Then: Should have 9 videos (3 words × 3 videos)
        XCTAssertEqual(categoryVideos.count, 9)

        // When: We find all unique words in this category
        let uniqueWords = Set(categoryVideos.compactMap { $0.wordLabel?.name })

        // Then: Should have 3 unique words
        XCTAssertEqual(uniqueWords.count, 3)
        XCTAssertTrue(uniqueWords.contains("Dog"))
        XCTAssertTrue(uniqueWords.contains("Cat"))
        XCTAssertTrue(uniqueWords.contains("Bird"))
    }

    // MARK: - Sanitized Label Tests

    /// Test sanitizedLabel extension works correctly when creating Labels from folder names
    func test_sanitizedLabel_worksWithFolderNames() throws {
        // Given: Folder names with number prefixes
        let folderNames = [
            "12. Dog",
            "1. Cat",
            "  5.  Bird  ",
            "Hello World",
            "123"
        ]

        let expectedNames = ["Dog", "Cat", "Bird", "Hello World", "123"]

        // When: We create labels using sanitized names
        var labels: [Label] = []
        for folderName in folderNames {
            let sanitizedName = folderName.sanitizedLabel()
            let label = TestDataFactory.makeWordLabel(name: sanitizedName)
            context.insert(label)
            labels.append(label)
        }

        try context.save()

        // Then: Labels should have sanitized names
        for (index, label) in labels.enumerated() {
            XCTAssertEqual(label.name, expectedNames[index])
        }
    }

    /// Test creating labels from sanitized folder structure
    func test_createLabelsFromSanitizedFolderStructure_establishesCorrectRelationships() throws {
        // Given: Simulated folder structure with numbered prefixes
        let categoryFolderName = "12. Animals"
        let wordFolderName = "5. Dog"

        // When: We create labels using sanitized names
        let categoryLabel = Label(name: categoryFolderName.sanitizedLabel(), type: .category)
        let wordLabel = Label(name: wordFolderName.sanitizedLabel(), type: .word)

        context.insert(categoryLabel)
        context.insert(wordLabel)

        let sample = TestDataFactory.makeVideoSample(
            localPath: "INCLUDE/\(categoryFolderName)/\(wordFolderName)/video_001.mp4"
        )
        sample.labels = [categoryLabel, wordLabel]
        context.insert(sample)

        try context.save()

        // Then: Labels should have clean names without numbers
        XCTAssertEqual(categoryLabel.name, "Animals")
        XCTAssertEqual(wordLabel.name, "Dog")

        // And: Relationships should be established
        XCTAssertEqual(sample.categoryLabel?.name, "Animals")
        XCTAssertEqual(sample.wordLabel?.name, "Dog")
    }

    // MARK: - Multiple Samples Same Labels Tests

    /// Test multiple samples can share the same labels
    func test_multipleSamples_canShareSameLabels() throws {
        // Given: Shared labels
        let categoryLabel = TestDataFactory.makeCategoryLabel(name: "Animals")
        let wordLabel = TestDataFactory.makeWordLabel(name: "Dog")

        context.insert(categoryLabel)
        context.insert(wordLabel)

        // When: We create 10 samples with same labels
        var samples: [VideoSample] = []
        for i in 1...10 {
            let sample = TestDataFactory.makeVideoSample(
                localPath: "video_\(i).mp4"
            )
            sample.labels = [categoryLabel, wordLabel]
            context.insert(sample)
            samples.append(sample)
        }

        try context.save()

        // Then: All samples should reference the same label instances
        XCTAssertEqual(categoryLabel.videoSamples?.count, 10)
        XCTAssertEqual(wordLabel.videoSamples?.count, 10)

        // Verify all samples have the same label IDs
        for sample in samples {
            XCTAssertEqual(sample.categoryLabel?.id, categoryLabel.id)
            XCTAssertEqual(sample.wordLabel?.id, wordLabel.id)
        }
    }

    // MARK: - Label Reuse Tests

    /// Test finding or creating labels doesn't create duplicates
    func test_findOrCreateLabel_doesNotCreateDuplicates() throws {
        // Given: An existing label
        let existing = TestDataFactory.makeWordLabel(name: "Dog")
        context.insert(existing)
        try context.save()

        // When: We try to find or create the same label multiple times
        let found1 = try context.findOrCreateLabel(named: "Dog", type: .word)
        let found2 = try context.findOrCreateLabel(named: "Dog", type: .word)
        let found3 = try context.findOrCreateLabel(named: "Dog", type: .word)

        try context.save()

        // Then: Should all be the same instance
        XCTAssertEqual(found1.id, existing.id)
        XCTAssertEqual(found2.id, existing.id)
        XCTAssertEqual(found3.id, existing.id)

        // And: Should only have one Dog word label in database
        let allDogWords = try context.fetch(
            ModelQueries.label(named: "Dog", type: .word)
        )
        XCTAssertEqual(allDogWords.count, 1)
    }

    // MARK: - Cross-Dataset Query Tests

    /// Test querying samples across multiple datasets
    func test_querySamplesAcrossMultipleDatasets_returnsCorrect() throws {
        // Given: Samples from different datasets
        let includeDataset = TestDataFactory.makeDataset(name: "INCLUDE")
        let islDataset = TestDataFactory.makeDataset(name: "ISL-CSLTR")

        context.insert(includeDataset)
        context.insert(islDataset)

        let sample1 = TestDataFactory.makeVideoSample(
            localPath: "video1.mp4",
            datasetName: "INCLUDE"
        )
        let sample2 = TestDataFactory.makeVideoSample(
            localPath: "video2.mp4",
            datasetName: "ISL-CSLTR"
        )

        context.insert(sample1)
        context.insert(sample2)
        try context.save()

        // When: We query by dataset
        let includeSamples = try context.fetchVideoSamples(forDataset: "INCLUDE")
        let islSamples = try context.fetchVideoSamples(forDataset: "ISL-CSLTR")

        // Then: Should get correct samples
        XCTAssertEqual(includeSamples.count, 1)
        XCTAssertEqual(islSamples.count, 1)
        XCTAssertEqual(includeSamples.first?.id, sample1.id)
        XCTAssertEqual(islSamples.first?.id, sample2.id)
    }
}
