import Foundation
import SwiftData
import XCTest
@testable import SignLanguageTranslate

// MARK: - Test Container Factory

/// Factory for creating in-memory ModelContainers for testing
enum TestContainerFactory {

    /// Create a fresh in-memory container with all models
    static func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            Dataset.self,
            Label.self,
            VideoSample.self
        ])

        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true
        )

        return try ModelContainer(
            for: schema,
            configurations: [configuration]
        )
    }

    /// Create a container and return both container and context
    static func makeContainerWithContext() throws -> (ModelContainer, ModelContext) {
        let container = try makeContainer()
        let context = ModelContext(container)
        return (container, context)
    }
}

// MARK: - Test Data Factory

/// Factory for creating test model instances
enum TestDataFactory {

    // MARK: - Dataset Factories

    /// Create a test Dataset with default values
    static func makeDataset(
        name: String = "TEST_DATASET",
        type: DatasetType = .include,
        status: DownloadStatus = .notStarted
    ) -> Dataset {
        Dataset(name: name, type: type, status: status)
    }

    /// Create a test Dataset with download progress
    static func makeDownloadingDataset(
        name: String = "DOWNLOADING_DATASET",
        totalBytes: Int64 = 1_000_000_000,
        downloadedBytes: Int64 = 250_000_000
    ) -> Dataset {
        Dataset(
            name: name,
            type: .include,
            status: .downloading,
            totalParts: 10,
            downloadedParts: 3,
            totalBytes: totalBytes,
            downloadedBytes: downloadedBytes
        )
    }

    /// Create a completed Dataset
    static func makeCompletedDataset(
        name: String = "COMPLETED_DATASET"
    ) -> Dataset {
        Dataset(
            name: name,
            type: .include,
            status: .completed,
            totalSamples: 100,
            downloadedSamples: 100,
            totalParts: 5,
            downloadedParts: 5,
            totalBytes: 500_000_000,
            downloadedBytes: 500_000_000
        )
    }

    // MARK: - Label Factories

    /// Create a test Label
    static func makeLabel(
        name: String,
        type: LabelType
    ) -> Label {
        Label(name: name, type: type)
    }

    /// Create a category label
    static func makeCategoryLabel(name: String = "Animals") -> Label {
        Label(name: name, type: .category)
    }

    /// Create a word label
    static func makeWordLabel(name: String = "Dog") -> Label {
        Label(name: name, type: .word)
    }

    /// Create a sentence label
    static func makeSentenceLabel(name: String = "Hello World") -> Label {
        Label(name: name, type: .sentence)
    }

    // MARK: - VideoSample Factories

    /// Create a test VideoSample
    static func makeVideoSample(
        localPath: String = "test/video.mp4",
        datasetName: String = "TEST",
        fileSize: Int64 = 10_000_000,
        duration: Double = 30.0
    ) -> VideoSample {
        VideoSample(
            localPath: localPath,
            datasetName: datasetName,
            fileSize: fileSize,
            duration: duration
        )
    }

    /// Create a VideoSample with labels
    static func makeVideoSampleWithLabels(
        localPath: String = "test/Animals/Dog/video_001.mp4",
        datasetName: String = "INCLUDE",
        categoryName: String = "Animals",
        wordName: String = "Dog"
    ) -> (VideoSample, Label, Label) {
        let categoryLabel = makeCategoryLabel(name: categoryName)
        let wordLabel = makeWordLabel(name: wordName)
        let sample = makeVideoSample(localPath: localPath, datasetName: datasetName)
        sample.labels = [categoryLabel, wordLabel]
        return (sample, categoryLabel, wordLabel)
    }

    // MARK: - Bulk Data Factories

    /// Create multiple VideoSamples for a word
    static func makeVideoSamplesForWord(
        word: String,
        category: String,
        count: Int,
        datasetName: String = "INCLUDE"
    ) -> (samples: [VideoSample], categoryLabel: Label, wordLabel: Label) {
        let categoryLabel = makeCategoryLabel(name: category)
        let wordLabel = makeWordLabel(name: word)

        var samples: [VideoSample] = []
        for i in 1...count {
            let sample = makeVideoSample(
                localPath: "\(datasetName)/\(category)/\(word)/video_\(String(format: "%03d", i)).mp4",
                datasetName: datasetName
            )
            sample.labels = [categoryLabel, wordLabel]
            samples.append(sample)
        }

        return (samples, categoryLabel, wordLabel)
    }
}

// MARK: - Test Data Populator

/// Utilities for populating test data into a context
enum TestDataPopulator {

    /// Populate a context with standard test data
    /// - Parameter context: The context to populate
    /// - Returns: Tuple of created datasets, labels, and samples
    @discardableResult
    static func populateStandardData(
        in context: ModelContext
    ) throws -> (datasets: [Dataset], labels: [Label], samples: [VideoSample]) {
        // Create datasets
        let includeDataset = TestDataFactory.makeCompletedDataset(name: "INCLUDE")
        let islDataset = TestDataFactory.makeDataset(name: "ISL-CSLTR", type: .islcsltr)

        context.insert(includeDataset)
        context.insert(islDataset)

        // Create labels and samples
        var allLabels: [Label] = []
        var allSamples: [VideoSample] = []

        let testData = [
            ("Animals", ["Dog", "Cat", "Bird"]),
            ("Colors", ["Red", "Blue", "Green"])
        ]

        for (category, words) in testData {
            let categoryLabel = TestDataFactory.makeCategoryLabel(name: category)
            context.insert(categoryLabel)
            allLabels.append(categoryLabel)

            for word in words {
                let wordLabel = TestDataFactory.makeWordLabel(name: word)
                context.insert(wordLabel)
                allLabels.append(wordLabel)

                // Create 3 samples per word
                for i in 1...3 {
                    let sample = TestDataFactory.makeVideoSample(
                        localPath: "INCLUDE/\(category)/\(word)/video_\(i).mp4",
                        datasetName: "INCLUDE"
                    )
                    sample.labels = [categoryLabel, wordLabel]
                    context.insert(sample)
                    allSamples.append(sample)
                }
            }
        }

        try context.save()

        return ([includeDataset, islDataset], allLabels, allSamples)
    }

    /// Create a large batch of test samples for performance testing
    static func populateLargeDataset(
        in context: ModelContext,
        sampleCount: Int
    ) throws -> [VideoSample] {
        let categoryLabel = TestDataFactory.makeCategoryLabel(name: "TestCategory")
        let wordLabel = TestDataFactory.makeWordLabel(name: "TestWord")

        context.insert(categoryLabel)
        context.insert(wordLabel)

        var samples: [VideoSample] = []

        for i in 1...sampleCount {
            let sample = TestDataFactory.makeVideoSample(
                localPath: "TEST/video_\(i).mp4",
                datasetName: "LARGE_TEST"
            )
            sample.labels = [categoryLabel, wordLabel]
            context.insert(sample)
            samples.append(sample)
        }

        try context.save()

        return samples
    }
}

// MARK: - XCTestCase Extensions

extension XCTestCase {

    /// Create a fresh test container and context
    func makeTestEnvironment() throws -> (ModelContainer, ModelContext) {
        try TestContainerFactory.makeContainerWithContext()
    }

    /// Assert that two arrays contain the same elements (order-independent)
    func assertArraysEqual<T: Equatable>(
        _ array1: [T],
        _ array2: [T],
        _ message: String = "Arrays should contain the same elements",
        file: StaticString = #file,
        line: UInt = #line
    ) {
        XCTAssertEqual(
            Set(array1),
            Set(array2),
            message,
            file: file,
            line: line
        )
    }

    /// Assert that a relationship exists between two models
    func assertRelationshipExists<T: Identifiable>(
        _ item: T,
        in collection: [T]?,
        _ message: String = "Relationship should exist",
        file: StaticString = #file,
        line: UInt = #line
    ) where T.ID: Equatable {
        XCTAssertTrue(
            collection?.contains(where: { $0.id == item.id }) ?? false,
            message,
            file: file,
            line: line
        )
    }
}

// MARK: - Assertion Helpers

/// Custom assertions for SwiftData testing
enum SwiftDataAssertions {

    /// Assert that a fetch returns the expected count
    static func assertFetchCount<T: PersistentModel>(
        _ context: ModelContext,
        _ descriptor: FetchDescriptor<T>,
        equals expectedCount: Int,
        _ message: String = "",
        file: StaticString = #file,
        line: UInt = #line
    ) {
        let actualCount = (try? context.fetchCount(descriptor)) ?? 0
        XCTAssertEqual(
            actualCount,
            expectedCount,
            message.isEmpty ? "Expected \(expectedCount) items but found \(actualCount)" : message,
            file: file,
            line: line
        )
    }

    /// Assert that a relationship is bidirectional
    static func assertBidirectionalRelationship(
        sample: VideoSample,
        label: Label,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        // Check forward relationship
        XCTAssertTrue(
            sample.labels.contains(where: { $0.id == label.id }),
            "Sample should contain label",
            file: file,
            line: line
        )

        // Check inverse relationship
        XCTAssertTrue(
            label.videoSamples?.contains(where: { $0.id == sample.id }) ?? false,
            "Label should contain sample",
            file: file,
            line: line
        )
    }
}
