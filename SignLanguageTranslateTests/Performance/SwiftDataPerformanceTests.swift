import XCTest
import SwiftData
@testable import SignLanguageTranslate

/// Performance tests for SwiftData operations
final class SwiftDataPerformanceTests: XCTestCase {

    var container: ModelContainer!
    var context: ModelContext!

    override func setUpWithError() throws {
        (container, context) = try makeTestEnvironment()
    }

    override func tearDownWithError() throws {
        container = nil
        context = nil
    }

    // MARK: - Bulk Insertion Tests

    /// Test bulk insertion of 1000 VideoSamples with Labels
    func test_bulkInsert_1000VideoSamplesWithLabels_completesInReasonableTime() throws {
        // This test measures the time to insert 1000 samples with labels
        measure {
            // Given: Fresh context for each iteration
            let testContext = ModelContext(container)

            // Create shared labels
            let categoryLabel = TestDataFactory.makeCategoryLabel(name: "PerfTest")
            let wordLabel = TestDataFactory.makeWordLabel(name: "Word")

            testContext.insert(categoryLabel)
            testContext.insert(wordLabel)

            // When: We insert 1000 samples
            for i in 1...1000 {
                let sample = TestDataFactory.makeVideoSample(
                    localPath: "perf/video_\(i).mp4",
                    datasetName: "PERF_TEST"
                )
                sample.labels = [categoryLabel, wordLabel]
                testContext.insert(sample)
            }

            // Then: Save should complete
            try? testContext.save()
        }
    }

    /// Test inserting samples in batches
    func test_batchInsert_500SamplesInBatchesOf100_performsWell() throws {
        measure {
            let testContext = ModelContext(container)

            let categoryLabel = TestDataFactory.makeCategoryLabel(name: "BatchTest")
            let wordLabel = TestDataFactory.makeWordLabel(name: "Word")

            testContext.insert(categoryLabel)
            testContext.insert(wordLabel)

            // Insert in batches of 100
            for batch in 0..<5 {
                for i in 1...100 {
                    let index = (batch * 100) + i
                    let sample = TestDataFactory.makeVideoSample(
                        localPath: "batch/video_\(index).mp4",
                        datasetName: "BATCH_TEST"
                    )
                    sample.labels = [categoryLabel, wordLabel]
                    testContext.insert(sample)
                }
                // Save after each batch
                try? testContext.save()
            }
        }
    }

    // MARK: - Query Performance Tests

    /// Test fetching samples by dataset name with 1000 samples
    func test_fetchByDatasetName_with1000Samples_performsWell() throws {
        // Setup: Insert 1000 samples
        try TestDataPopulator.populateLargeDataset(in: context, sampleCount: 1000)

        // Measure query performance
        measure {
            _ = try? context.fetchVideoSamples(forDataset: "LARGE_TEST")
        }
    }

    /// Test fetching samples by label with 1000 samples
    func test_fetchByLabel_with1000Samples_performsWell() throws {
        // Setup: Insert 1000 samples with shared label
        let label = TestDataFactory.makeWordLabel(name: "PerfLabel")
        context.insert(label)

        for i in 1...1000 {
            let sample = TestDataFactory.makeVideoSample(
                localPath: "label/video_\(i).mp4",
                datasetName: "LABEL_TEST"
            )
            sample.labels = [label]
            context.insert(sample)
        }

        try context.save()

        // Measure query performance
        measure {
            let samples = label.videoSamples ?? []
            _ = samples.count
        }
    }

    /// Test counting samples without fetching all data
    func test_countSamples_with1000Samples_performsWell() throws {
        // Setup: Insert 1000 samples
        try TestDataPopulator.populateLargeDataset(in: context, sampleCount: 1000)

        // Measure count performance (should be faster than fetch)
        measure {
            _ = try? context.countVideoSamples(forDataset: "LARGE_TEST")
        }
    }

    // MARK: - Complex Query Performance Tests

    /// Test filtering samples with multiple predicates
    func test_complexFilter_with1000Samples_performsWell() throws {
        // Setup: Create samples with various properties
        let dataset = TestDataFactory.makeDataset(name: "COMPLEX_TEST")
        context.insert(dataset)

        let categoryLabel = TestDataFactory.makeCategoryLabel(name: "Category")
        context.insert(categoryLabel)

        for i in 1...1000 {
            let sample = TestDataFactory.makeVideoSample(
                localPath: "complex/video_\(i).mp4",
                datasetName: "COMPLEX_TEST"
            )
            sample.labels = [categoryLabel]
            sample.isFavorite = (i % 10 == 0) // Every 10th is favorite
            context.insert(sample)
        }

        try context.save()

        // Measure complex query
        measure {
            let favorites = try? context.fetchFavorites()
            let complexFiltered = favorites?.filter { $0.datasetName == "COMPLEX_TEST" } ?? []
            _ = complexFiltered.count
        }
    }

    // MARK: - Relationship Query Performance

    /// Test querying through relationships with many-to-many
    func test_relationshipQuery_withManyToMany_performsWell() throws {
        // Setup: Create a label shared by many samples
        let popularLabel = TestDataFactory.makeWordLabel(name: "PopularWord")
        context.insert(popularLabel)

        for i in 1...500 {
            let sample = TestDataFactory.makeVideoSample(
                localPath: "popular/video_\(i).mp4",
                datasetName: "POPULAR_TEST"
            )
            sample.labels = [popularLabel]
            context.insert(sample)
        }

        try context.save()

        // Measure accessing samples through label
        measure {
            let samples = popularLabel.videoSamples ?? []
            for sample in samples {
                _ = sample.displayTitle // Access computed property
            }
        }
    }

    // MARK: - Update Performance Tests

    /// Test updating many samples
    func test_updateManySamples_performsWell() throws {
        // Setup: Create 500 samples
        var samples: [VideoSample] = []
        for i in 1...500 {
            let sample = TestDataFactory.makeVideoSample(
                localPath: "update/video_\(i).mp4",
                datasetName: "UPDATE_TEST"
            )
            context.insert(sample)
            samples.append(sample)
        }

        try context.save()

        // Measure bulk update
        measure {
            for sample in samples {
                sample.isFavorite = true
                sample.markAsAccessed()
            }
            try? context.save()
        }
    }

    // MARK: - Delete Performance Tests

    /// Test deleting many samples
    func test_deleteManySamples_performsWell() throws {
        measure {
            let testContext = ModelContext(container)

            // Create 500 samples
            for i in 1...500 {
                let sample = TestDataFactory.makeVideoSample(
                    localPath: "delete/video_\(i).mp4",
                    datasetName: "DELETE_TEST"
                )
                testContext.insert(sample)
            }

            try? testContext.save()

            // Delete all
            try? testContext.delete(model: VideoSample.self)
            try? testContext.save()
        }
    }

    // MARK: - Computed Property Performance

    /// Test accessing computed properties on many samples
    func test_computedProperties_onManySamples_performsWell() throws {
        // Setup: Create 1000 samples
        try TestDataPopulator.populateLargeDataset(in: context, sampleCount: 1000)

        let samples = try context.fetchVideoSamples(forDataset: "LARGE_TEST")

        // Measure computed property access
        measure {
            var totalDuration: Double = 0
            for sample in samples {
                _ = sample.displayTitle
                _ = sample.formattedFileSize
                _ = sample.formattedDuration
                totalDuration += sample.duration
            }
            _ = totalDuration
        }
    }

    // MARK: - Memory Performance Tests

    /// Test memory usage with large result sets
    func test_largeResultSet_doesNotCauseMemoryIssues() throws {
        // Setup: Create 2000 samples
        for i in 1...2000 {
            let sample = TestDataFactory.makeVideoSample(
                localPath: "memory/video_\(i).mp4",
                datasetName: "MEMORY_TEST"
            )
            context.insert(sample)

            // Save periodically to avoid memory buildup during insertion
            if i % 200 == 0 {
                try context.save()
            }
        }

        try context.save()

        // Measure fetching large result set
        measureMetrics([.wallClockTime], automaticallyStartMeasuring: false) {
            startMeasuring()
            let samples = try? context.fetchVideoSamples(forDataset: "MEMORY_TEST")
            stopMeasuring()

            // Verify we got all samples
            XCTAssertEqual(samples?.count, 2000)
        }
    }

    // MARK: - Fetch Descriptor Performance

    /// Test different fetch descriptor configurations
    func test_fetchDescriptorWithSorting_performsWell() throws {
        // Setup: Create samples with various timestamps
        for i in 1...500 {
            let sample = TestDataFactory.makeVideoSample(
                localPath: "sort/video_\(i).mp4",
                datasetName: "SORT_TEST"
            )
            context.insert(sample)
        }

        try context.save()

        // Measure sorted fetch
        measure {
            let descriptor = FetchDescriptor<VideoSample>(
                predicate: #Predicate { $0.datasetName == "SORT_TEST" },
                sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
            )
            _ = try? context.fetch(descriptor)
        }
    }

    /// Test fetch with limit
    func test_fetchWithLimit_performsBetterThanFullFetch() throws {
        // Setup: Create 1000 samples
        try TestDataPopulator.populateLargeDataset(in: context, sampleCount: 1000)

        // Measure limited fetch (should be faster)
        measure {
            var descriptor = FetchDescriptor<VideoSample>(
                predicate: #Predicate { $0.datasetName == "LARGE_TEST" }
            )
            descriptor.fetchLimit = 50
            _ = try? context.fetch(descriptor)
        }
    }
}
