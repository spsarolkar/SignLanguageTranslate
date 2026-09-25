import XCTest
@testable import SignLanguageTranslate

final class DownloadTaskDeduplicationTests: XCTestCase {

    func test_noDuplicates_dropsNothing() {
        let tasks = [
            createTestDownloadTask(category: "Animals", partNumber: 1, totalParts: 2),
            createTestDownloadTask(category: "Animals", partNumber: 2, totalParts: 2)
        ]

        XCTAssertTrue(DownloadTaskDeduplication.duplicateIDs(in: tasks).isEmpty)
    }

    func test_completedAndPendingCopy_keepsCompleted() {
        // The state found on device after a zip import: every part twice.
        let completed = createTestDownloadTask(status: .completed, bytesDownloaded: 100_000_000)
        let pending = createTestDownloadTask(status: .pending)

        let drop = DownloadTaskDeduplication.duplicateIDs(in: [pending, completed])

        XCTAssertEqual(drop, [pending.id])
    }

    func test_pausedWithBytes_beatsPending() {
        let paused = createTestDownloadTask(status: .paused, bytesDownloaded: 5_000)
        let pending = createTestDownloadTask(status: .pending)

        XCTAssertEqual(DownloadTaskDeduplication.duplicateIDs(in: [paused, pending]), [pending.id])
    }

    func test_sameStatus_keepsMoreBytes() {
        let ahead = createTestDownloadTask(status: .paused, bytesDownloaded: 9_000)
        let behind = createTestDownloadTask(status: .paused, bytesDownloaded: 1_000)

        XCTAssertEqual(DownloadTaskDeduplication.duplicateIDs(in: [behind, ahead]), [behind.id])
    }

    func test_sameFileInDifferentDatasets_isNotADuplicate() {
        let a = createTestDownloadTask(datasetName: "INCLUDE")
        let b = createTestDownloadTask(datasetName: "INCLUDE-copy")

        XCTAssertTrue(DownloadTaskDeduplication.duplicateIDs(in: [a, b]).isEmpty)
    }

    func test_fullManifestDuplicated_dropsExactlyOneCopyPerPart() {
        var tasks: [DownloadTask] = []
        for part in 1...44 {
            tasks.append(createTestDownloadTask(status: .completed, partNumber: part, totalParts: 44, bytesDownloaded: 1))
            tasks.append(createTestDownloadTask(status: .pending, partNumber: part, totalParts: 44))
        }

        let drop = DownloadTaskDeduplication.duplicateIDs(in: tasks)

        XCTAssertEqual(drop.count, 44)
        XCTAssertTrue(tasks.filter { drop.contains($0.id) }.allSatisfy { $0.status == .pending })
    }
}
