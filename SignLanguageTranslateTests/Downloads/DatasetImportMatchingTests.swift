import XCTest
@testable import SignLanguageTranslate

final class DatasetImportMatchingTests: XCTestCase {

    // MARK: - Manifest re-load adds nothing already queued

    func test_entriesToEnqueue_allNewForEmptyQueue() {
        let entries = INCLUDEManifest.generateAllEntries()

        let toAdd = DownloadManager.entriesToEnqueue(entries, existing: [], datasetName: "INCLUDE")

        XCTAssertEqual(toAdd.count, entries.count)
    }

    func test_entriesToEnqueue_noneWhenManifestAlreadyQueued() {
        // A zip import used to re-enqueue all 44 parts, doubling the queue.
        let entries = INCLUDEManifest.generateAllEntries()
        let queued = entries.map { DownloadTask(from: $0, datasetName: "INCLUDE") }

        let toAdd = DownloadManager.entriesToEnqueue(entries, existing: queued, datasetName: "INCLUDE")

        XCTAssertTrue(toAdd.isEmpty)
    }

    func test_entriesToEnqueue_addsOnlyMissingParts() {
        let entries = INCLUDEManifest.generateAllEntries()
        let queued = entries.dropFirst(3).map { DownloadTask(from: $0, datasetName: "INCLUDE") }

        let toAdd = DownloadManager.entriesToEnqueue(entries, existing: Array(queued), datasetName: "INCLUDE")

        XCTAssertEqual(toAdd.map(\.url), entries.prefix(3).map(\.url))
    }

    func test_entriesToEnqueue_otherDatasetDoesNotCount() {
        let entries = INCLUDEManifest.generateAllEntries()
        let queued = entries.map { DownloadTask(from: $0, datasetName: "OTHER") }

        let toAdd = DownloadManager.entriesToEnqueue(entries, existing: queued, datasetName: "INCLUDE")

        XCTAssertEqual(toAdd.count, entries.count)
    }

    // MARK: - Extraction finds the dataset's part zips

    func test_partFileMapping_matchesStoredPartsWithUUIDPrefix() {
        let dir = URL(fileURLWithPath: "/tmp/completed")
        let id = UUID().uuidString
        let files = [
            dir.appendingPathComponent("\(id)_Adjectives_1of8.zip"),
            dir.appendingPathComponent("\(UUID().uuidString)_Seasons_1of1.zip")
        ]

        let mapping = DatasetDownloadActions.partFileMapping(
            files: files,
            partNames: ["Adjectives_1of8.zip", "Seasons_1of1.zip"]
        )

        // The old check required "INCLUDE" in the filename and matched neither.
        XCTAssertEqual(Set(mapping.keys), ["Adjectives_1of8.zip", "Seasons_1of1.zip"])
        XCTAssertEqual(mapping["Adjectives_1of8.zip"], files[0])
    }

    func test_partFileMapping_ignoresFilesFromOtherDatasets() {
        let file = URL(fileURLWithPath: "/tmp/completed/\(UUID().uuidString)_Unrelated_1of1.zip")

        let mapping = DatasetDownloadActions.partFileMapping(files: [file], partNames: ["Adjectives_1of8.zip"])

        XCTAssertTrue(mapping.isEmpty)
    }

    func test_originalFilename_keepsNamesWithoutPrefix() {
        XCTAssertEqual(DatasetDownloadActions.originalFilename("Adjectives_1of8.zip"), "Adjectives_1of8.zip")
    }
}
