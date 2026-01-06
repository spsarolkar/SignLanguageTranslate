import XCTest
import SwiftData
@testable import SignLanguageTranslate

final class DatasetTests: XCTestCase {

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

    // MARK: - Creation Tests

    func testDatasetCreation_basicProperties() {
        let dataset = Dataset(name: "INCLUDE", type: .include)

        XCTAssertEqual(dataset.name, "INCLUDE")
        XCTAssertEqual(dataset.datasetType, .include)
        XCTAssertEqual(dataset.downloadStatus, .notStarted)
        XCTAssertNotNil(dataset.id)
        XCTAssertNotNil(dataset.createdAt)
        XCTAssertEqual(dataset.totalSamples, 0)
        XCTAssertEqual(dataset.downloadedSamples, 0)
    }

    func testDatasetCreation_islcsltrType() {
        let dataset = Dataset(name: "ISL-CSLTR", type: .islcsltr)

        XCTAssertEqual(dataset.datasetType, .islcsltr)
        XCTAssertEqual(dataset.datasetType.displayName, "ISL-CSLTR")
    }

    // MARK: - Progress Calculation Tests

    func testDownloadProgress_calculatesCorrectly() {
        let dataset = Dataset(
            name: "TEST",
            type: .include,
            totalBytes: 100_000_000,
            downloadedBytes: 25_000_000
        )

        XCTAssertEqual(dataset.downloadProgress, 0.25, accuracy: 0.001)
    }

    func testDownloadProgress_handlesZeroTotal() {
        let dataset = Dataset(name: "TEST", type: .include)
        dataset.totalBytes = 0
        dataset.downloadedBytes = 100

        XCTAssertEqual(dataset.downloadProgress, 0)
    }

    func testPartsProgress_calculatesCorrectly() {
        let dataset = Dataset(
            name: "TEST",
            type: .include,
            totalParts: 46,
            downloadedParts: 23
        )

        XCTAssertEqual(dataset.partsProgress, 0.5, accuracy: 0.001)
    }

    func testSamplesProgress_calculatesCorrectly() {
        let dataset = Dataset(
            name: "TEST",
            type: .include,
            totalSamples: 1000,
            downloadedSamples: 750
        )

        XCTAssertEqual(dataset.samplesProgress, 0.75, accuracy: 0.001)
    }

    // MARK: - Status Tests

    func testIsComplete_returnsTrueWhenCompleted() {
        let dataset = Dataset(name: "TEST", type: .include, status: .completed)
        XCTAssertTrue(dataset.isComplete)

        let dataset2 = Dataset(name: "TEST", type: .include, status: .downloading)
        XCTAssertFalse(dataset2.isComplete)
    }

    func testIsReady_requiresCompletedAndSamples() {
        let dataset = Dataset(
            name: "TEST",
            type: .include,
            status: .completed,
            downloadedSamples: 100
        )
        XCTAssertTrue(dataset.isReady)

        let dataset2 = Dataset(name: "TEST", type: .include, status: .completed)
        XCTAssertFalse(dataset2.isReady) // No samples
    }

    func testCanStartDownload_checksStatus() {
        XCTAssertTrue(Dataset(name: "T", type: .include, status: .notStarted).canStartDownload)
        XCTAssertTrue(Dataset(name: "T", type: .include, status: .paused).canStartDownload)
        XCTAssertTrue(Dataset(name: "T", type: .include, status: .failed).canStartDownload)
        XCTAssertFalse(Dataset(name: "T", type: .include, status: .downloading).canStartDownload)
        XCTAssertFalse(Dataset(name: "T", type: .include, status: .completed).canStartDownload)
    }

    func testCanPauseDownload_checksStatus() {
        XCTAssertTrue(Dataset(name: "T", type: .include, status: .downloading).canPauseDownload)
        XCTAssertFalse(Dataset(name: "T", type: .include, status: .paused).canPauseDownload)
        XCTAssertFalse(Dataset(name: "T", type: .include, status: .notStarted).canPauseDownload)
    }

    // MARK: - Formatted Output Tests

    func testProgressText_formatsCorrectly() {
        let dataset = Dataset(
            name: "TEST",
            type: .include,
            totalBytes: 1_000_000_000,
            downloadedBytes: 500_000_000
        )

        // Should contain both sizes
        XCTAssertTrue(dataset.progressText.contains("/"))
    }

    func testPartsProgressText_formatsCorrectly() {
        let dataset = Dataset(
            name: "TEST",
            type: .include,
            totalParts: 46,
            downloadedParts: 12
        )

        XCTAssertEqual(dataset.partsProgressText, "12 / 46 files")
    }

    // MARK: - State Change Method Tests

    func testStartDownload_updatesState() {
        let dataset = Dataset(name: "TEST", type: .include)
        XCTAssertNil(dataset.downloadStartedAt)

        dataset.startDownload()

        XCTAssertEqual(dataset.downloadStatus, .downloading)
        XCTAssertNotNil(dataset.downloadStartedAt)
        XCTAssertNil(dataset.lastError)
    }

    func testPauseDownload_updatesState() {
        let dataset = Dataset(name: "TEST", type: .include, status: .downloading)

        dataset.pauseDownload()

        XCTAssertEqual(dataset.downloadStatus, .paused)
    }

    func testCompleteDownload_updatesState() {
        let dataset = Dataset(name: "TEST", type: .include, status: .downloading)
        XCTAssertNil(dataset.downloadCompletedAt)

        dataset.completeDownload()

        XCTAssertEqual(dataset.downloadStatus, .completed)
        XCTAssertNotNil(dataset.downloadCompletedAt)
    }

    func testFailDownload_updatesState() {
        let dataset = Dataset(name: "TEST", type: .include, status: .downloading)

        dataset.failDownload(error: "Network error")

        XCTAssertEqual(dataset.downloadStatus, .failed)
        XCTAssertEqual(dataset.lastError, "Network error")
    }

    func testUpdateProgress_updatesBytes() {
        let dataset = Dataset(name: "TEST", type: .include)

        dataset.updateProgress(downloadedBytes: 500, totalBytes: 1000)

        XCTAssertEqual(dataset.downloadedBytes, 500)
        XCTAssertEqual(dataset.totalBytes, 1000)
    }

    func testIncrementDownloadedParts_incrementsAndTransitionsToProcessing() {
        let dataset = Dataset(
            name: "TEST",
            type: .include,
            status: .downloading,
            totalParts: 3,
            downloadedParts: 2
        )

        dataset.incrementDownloadedParts()

        XCTAssertEqual(dataset.downloadedParts, 3)
        XCTAssertEqual(dataset.downloadStatus, .processing)
    }

    func testResetDownload_clearsState() {
        let dataset = Dataset(
            name: "TEST",
            type: .include,
            status: .failed,
            downloadedParts: 10,
            downloadedBytes: 1000,
            downloadStartedAt: Date.now,
            lastError: "Some error"
        )

        dataset.resetDownload()

        XCTAssertEqual(dataset.downloadStatus, .notStarted)
        XCTAssertEqual(dataset.downloadedBytes, 0)
        XCTAssertEqual(dataset.downloadedParts, 0)
        XCTAssertNil(dataset.downloadStartedAt)
        XCTAssertNil(dataset.lastError)
    }

    // MARK: - Storage Directory Tests

    func testStorageDirectory_constructsCorrectly() {
        let dataset = Dataset(name: "INCLUDE", type: .include)

        let expected = FileManager.default.datasetsDirectory.appendingPathComponent("INCLUDE")
        XCTAssertEqual(dataset.storageDirectory, expected)
    }

    // MARK: - SwiftData Persistence Tests

    func testDataset_persistsToDatabase() throws {
        let dataset = Dataset(name: "INCLUDE", type: .include)
        dataset.totalSamples = 15000
        dataset.totalParts = 46

        context.insert(dataset)
        try context.save()

        let descriptor = FetchDescriptor<Dataset>(
            predicate: #Predicate { $0.name == "INCLUDE" }
        )
        let fetched = try context.fetch(descriptor)

        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.totalSamples, 15000)
        XCTAssertEqual(fetched.first?.totalParts, 46)
    }

    func testDataset_fetchByType() throws {
        context.insert(Dataset(name: "INCLUDE", type: .include))
        context.insert(Dataset(name: "ISL-CSLTR", type: .islcsltr))
        try context.save()

        let includeRaw = DatasetType.include.rawValue
        let descriptor = FetchDescriptor<Dataset>(
            predicate: #Predicate { $0.typeRawValue == includeRaw }
        )
        let fetched = try context.fetch(descriptor)

        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.name, "INCLUDE")
    }

    func testDataset_fetchByStatus() throws {
        let d1 = Dataset(name: "D1", type: .include, status: .completed)
        let d2 = Dataset(name: "D2", type: .include, status: .downloading)
        let d3 = Dataset(name: "D3", type: .include, status: .completed)

        context.insert(d1)
        context.insert(d2)
        context.insert(d3)
        try context.save()

        let completedRaw = DownloadStatus.completed.rawValue
        let descriptor = FetchDescriptor<Dataset>(
            predicate: #Predicate { $0.statusRawValue == completedRaw }
        )
        let fetched = try context.fetch(descriptor)

        XCTAssertEqual(fetched.count, 2)
    }

    // MARK: - DatasetType Tests

    func testDatasetType_allCases() {
        XCTAssertEqual(DatasetType.allCases.count, 2)
    }

    func testDatasetType_properties() {
        XCTAssertEqual(DatasetType.include.displayName, "INCLUDE")
        XCTAssertTrue(DatasetType.include.usesCategories)
        XCTAssertEqual(DatasetType.include.primaryLabelType, .word)

        XCTAssertEqual(DatasetType.islcsltr.displayName, "ISL-CSLTR")
        XCTAssertFalse(DatasetType.islcsltr.usesCategories)
        XCTAssertEqual(DatasetType.islcsltr.primaryLabelType, .sentence)
    }

    // MARK: - DownloadStatus Tests

    func testDownloadStatus_allCases() {
        XCTAssertEqual(DownloadStatus.allCases.count, 6)
    }

    func testDownloadStatus_isActive() {
        XCTAssertTrue(DownloadStatus.downloading.isActive)
        XCTAssertTrue(DownloadStatus.processing.isActive)
        XCTAssertFalse(DownloadStatus.paused.isActive)
        XCTAssertFalse(DownloadStatus.completed.isActive)
    }

    func testDownloadStatus_isAvailable() {
        XCTAssertTrue(DownloadStatus.completed.isAvailable)
        XCTAssertFalse(DownloadStatus.downloading.isAvailable)
        XCTAssertFalse(DownloadStatus.notStarted.isAvailable)
    }

    // MARK: - Preview Helper Tests

    func testPreviewHelpers_returnValidData() {
        XCTAssertEqual(Dataset.previewIncludeNotStarted.downloadStatus, .notStarted)
        XCTAssertEqual(Dataset.previewIncludeDownloading.downloadStatus, .downloading)
        XCTAssertEqual(Dataset.previewIncludeCompleted.downloadStatus, .completed)
        XCTAssertEqual(Dataset.previewPaused.downloadStatus, .paused)
        XCTAssertEqual(Dataset.previewFailed.downloadStatus, .failed)
        XCTAssertNotNil(Dataset.previewFailed.lastError)

        XCTAssertFalse(Dataset.previewList.isEmpty)
    }

    // MARK: - Hashable Tests

    func testDataset_hashableConformance() {
        let d1 = Dataset(name: "D1", type: .include)

        // Same instance should be equal to itself
        XCTAssertEqual(d1, d1)

        // SwiftData's @Model provides Hashable conformance
        // Datasets can be used in Set and Dictionary
        var datasetSet = Set<Dataset>()
        datasetSet.insert(d1)
        XCTAssertEqual(datasetSet.count, 1)

        // Can use as dictionary key
        var datasetDict = [Dataset: String]()
        datasetDict[d1] = "test"
        XCTAssertEqual(datasetDict[d1], "test")
    }
}
