import XCTest
@testable import SignLanguageTranslate

@MainActor
final class ManifestIntegrationTest: XCTestCase {
    func test_manifestEntriesGeneration() {
        let entries = INCLUDEManifest.generateAllEntries()
        print("Generated \(entries.count) entries")
        XCTAssertEqual(entries.count, 46, "Should generate 46 entries")
    }

    func test_downloadManagerWithManifest() async {
        let manager = DownloadManager()
        await manager.loadINCLUDEManifest()

        print("Total count: \(manager.totalCount)")
        print("Tasks count: \(manager.tasks.count)")
        print("Pending count: \(manager.pendingCount)")

        XCTAssertEqual(manager.totalCount, 46)
        XCTAssertEqual(manager.tasks.count, 46)
    }
}
