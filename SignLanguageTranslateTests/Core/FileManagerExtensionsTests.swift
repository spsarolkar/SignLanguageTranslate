import XCTest
@testable import SignLanguageTranslate

final class FileManagerExtensionsTests: XCTestCase {

    func testDocumentsDirectoryExists() {
        let docs = FileManager.default.documentsDirectory
        XCTAssertTrue(FileManager.default.fileExists(atPath: docs.path))
    }

    func testDatasetsDirectoryCreated() {
        let datasets = FileManager.default.datasetsDirectory
        XCTAssertTrue(FileManager.default.directoryExists(at: datasets))
    }

    func testFormattedSize() {
        XCTAssertEqual(FileManager.formattedSize(0), "Zero KB")
        XCTAssertEqual(FileManager.formattedSize(1024), "1 KB")
        XCTAssertEqual(FileManager.formattedSize(1024 * 1024), "1 MB")
        XCTAssertEqual(FileManager.formattedSize(1024 * 1024 * 1024), "1 GB")
    }

    func testDirectorySize() {
        // Test with temp directory that we create and populate
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        // Create a small test file
        let testFile = tempDir.appendingPathComponent("test.txt")
        try? "Hello".data(using: .utf8)?.write(to: testFile)

        let size = FileManager.default.directorySize(at: tempDir)
        XCTAssertGreaterThan(size, 0)

        // Cleanup
        try? FileManager.default.removeItem(at: tempDir)
    }
}
