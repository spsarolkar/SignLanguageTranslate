import XCTest
import SwiftData
@testable import SignLanguageTranslate

final class ModelQueriesTests: XCTestCase {

    var container: ModelContainer!
    var context: ModelContext!

    override func setUpWithError() throws {
        let schema = Schema([Dataset.self, Label.self, VideoSample.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: [config])
        context = ModelContext(container)
    }

    override func tearDownWithError() throws {
        container = nil
        context = nil
    }

    // MARK: - Dataset Query Tests

    func testFetchAllDatasets_returnsSortedByName() throws {
        context.insert(Dataset(name: "Zebra", type: .include))
        context.insert(Dataset(name: "Alpha", type: .include))
        context.insert(Dataset(name: "Middle", type: .islcsltr))
        try context.save()

        let datasets = try context.fetch(ModelQueries.allDatasets)

        XCTAssertEqual(datasets.count, 3)
        XCTAssertEqual(datasets[0].name, "Alpha")
        XCTAssertEqual(datasets[1].name, "Middle")
        XCTAssertEqual(datasets[2].name, "Zebra")
    }

    func testFetchDatasetsByStatus_filtersCorrectly() throws {
        context.insert(Dataset(name: "D1", type: .include, status: .completed))
        context.insert(Dataset(name: "D2", type: .include, status: .downloading))
        context.insert(Dataset(name: "D3", type: .include, status: .completed))
        try context.save()

        let completed = try context.fetch(ModelQueries.datasets(withStatus: .completed))

        XCTAssertEqual(completed.count, 2)
    }

    func testFetchDatasetByName_findsCorrect() throws {
        context.insert(Dataset(name: "INCLUDE", type: .include))
        context.insert(Dataset(name: "ISL-CSLTR", type: .islcsltr))
        try context.save()

        let dataset = try context.fetchDataset(named: "INCLUDE")

        XCTAssertNotNil(dataset)
        XCTAssertEqual(dataset?.name, "INCLUDE")
    }

    // MARK: - Label Query Tests

    func testFetchLabelsByType_filtersCorrectly() throws {
        context.insert(Label(name: "Animals", type: .category))
        context.insert(Label(name: "Colors", type: .category))
        context.insert(Label(name: "Dog", type: .word))
        context.insert(Label(name: "Hello", type: .sentence))
        try context.save()

        let categories = try context.fetchCategoryLabels()
        let words = try context.fetchWordLabels()

        XCTAssertEqual(categories.count, 2)
        XCTAssertEqual(words.count, 1)
    }

    func testFindOrCreateLabel_findsExisting() throws {
        let existing = Label(name: "Animals", type: .category)
        context.insert(existing)
        try context.save()

        let found = try context.findOrCreateLabel(named: "Animals", type: .category)

        XCTAssertEqual(found.id, existing.id)
    }

    func testFindOrCreateLabel_createsNew() throws {
        let label = try context.findOrCreateLabel(named: "NewLabel", type: .word)
        try context.save()

        XCTAssertEqual(label.name, "NewLabel")
        XCTAssertEqual(label.type, .word)

        // Verify it was inserted
        let all = try context.fetchWordLabels()
        XCTAssertEqual(all.count, 1)
    }

    // MARK: - VideoSample Query Tests

    func testFetchVideoSamplesForDataset_filtersCorrectly() throws {
        context.insert(VideoSample(localPath: "a.mp4", datasetName: "INCLUDE"))
        context.insert(VideoSample(localPath: "b.mp4", datasetName: "INCLUDE"))
        context.insert(VideoSample(localPath: "c.mp4", datasetName: "ISL-CSLTR"))
        try context.save()

        let includeSamples = try context.fetchVideoSamples(forDataset: "INCLUDE")

        XCTAssertEqual(includeSamples.count, 2)
    }

    func testCountVideoSamplesForDataset_countsCorrectly() throws {
        context.insert(VideoSample(localPath: "a.mp4", datasetName: "INCLUDE"))
        context.insert(VideoSample(localPath: "b.mp4", datasetName: "INCLUDE"))
        context.insert(VideoSample(localPath: "c.mp4", datasetName: "ISL-CSLTR"))
        try context.save()

        let count = try context.countVideoSamples(forDataset: "INCLUDE")

        XCTAssertEqual(count, 2)
    }

    func testFetchFavorites_filtersCorrectly() throws {
        let fav1 = VideoSample(localPath: "a.mp4", datasetName: "TEST")
        fav1.isFavorite = true

        let fav2 = VideoSample(localPath: "b.mp4", datasetName: "TEST")
        fav2.isFavorite = true

        let notFav = VideoSample(localPath: "c.mp4", datasetName: "TEST")

        context.insert(fav1)
        context.insert(fav2)
        context.insert(notFav)
        try context.save()

        let favorites = try context.fetchFavorites()

        XCTAssertEqual(favorites.count, 2)
    }

    // MARK: - ModelContext Extension Tests

    func testSaveIfNeeded_savesOnlyWhenChanges() throws {
        // No changes - should not throw
        try context.saveIfNeeded()

        // With changes
        context.insert(Label(name: "Test", type: .word))
        try context.saveIfNeeded()

        // Verify saved
        let labels = try context.fetch(ModelQueries.allLabels)
        XCTAssertEqual(labels.count, 1)
    }

    func testExists_checksCorrectly() throws {
        XCTAssertFalse(context.exists(ModelQueries.allDatasets))

        context.insert(Dataset(name: "Test", type: .include))
        try context.save()

        XCTAssertTrue(context.exists(ModelQueries.allDatasets))
    }
}
