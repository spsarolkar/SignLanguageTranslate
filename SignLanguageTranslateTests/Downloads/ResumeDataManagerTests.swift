import XCTest
@testable import SignLanguageTranslate

/// Tests for ResumeDataManager
final class ResumeDataManagerTests: XCTestCase {

    var manager: ResumeDataManager!
    var testDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()

        // Create unique test directory
        testDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ResumeDataManagerTests_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: testDirectory, withIntermediateDirectories: true)

        manager = ResumeDataManager(directory: testDirectory)
    }

    override func tearDownWithError() throws {
        // Clean up test directory
        if let dir = testDirectory {
            try? FileManager.default.removeItem(at: dir)
        }
        manager = nil
        testDirectory = nil
        try super.tearDownWithError()
    }

    // MARK: - Initialization Tests

    func test_initialization_createsDirectory() {
        XCTAssertTrue(FileManager.default.directoryExists(at: testDirectory))
    }

    func test_initialization_usesDefaultDirectoryWhenNil() {
        let defaultManager = ResumeDataManager()

        XCTAssertTrue(defaultManager.directoryURL.path.contains("resume"))
    }

    func test_initialization_usesCustomDirectory() {
        XCTAssertEqual(manager.directoryURL.path, testDirectory.path)
    }

    // MARK: - Save Tests

    func test_save_writesDataToFile() throws {
        let taskId = UUID()
        let data = createMockResumeData()

        let url = try manager.save(data, for: taskId)

        XCTAssertTrue(FileManager.default.fileExists(at: url))
    }

    func test_save_returnsCorrectURL() throws {
        let taskId = UUID()
        let data = createMockResumeData()

        let url = try manager.save(data, for: taskId)

        XCTAssertEqual(url.lastPathComponent, "\(taskId.uuidString).resume")
    }

    func test_save_writesCorrectContent() throws {
        let taskId = UUID()
        let data = createMockResumeData()

        let url = try manager.save(data, for: taskId)
        let savedData = try Data(contentsOf: url)

        XCTAssertEqual(savedData, data)
    }

    func test_save_overwritesExistingFile() throws {
        let taskId = UUID()
        let data1 = Data("first".utf8)
        let data2 = Data("second".utf8)

        _ = try manager.save(data1, for: taskId)
        _ = try manager.save(data2, for: taskId)

        let loadedData = try manager.load(for: taskId)

        XCTAssertEqual(loadedData, data2)
    }

    // MARK: - Load Tests

    func test_load_returnsNilForNonexistent() throws {
        let unknownId = UUID()

        let data = try manager.load(for: unknownId)

        XCTAssertNil(data)
    }

    func test_load_returnsExistingData() throws {
        let taskId = UUID()
        let originalData = createMockResumeData()

        _ = try manager.save(originalData, for: taskId)
        let loadedData = try manager.load(for: taskId)

        XCTAssertEqual(loadedData, originalData)
    }

    // MARK: - Has Resume Data Tests

    func test_hasResumeData_returnsTrueWhenExists() throws {
        let taskId = UUID()

        _ = try manager.save(createMockResumeData(), for: taskId)

        XCTAssertTrue(manager.hasResumeData(for: taskId))
    }

    func test_hasResumeData_returnsFalseWhenNotExists() {
        let unknownId = UUID()

        XCTAssertFalse(manager.hasResumeData(for: unknownId))
    }

    // MARK: - Delete Tests

    func test_delete_removesFile() throws {
        let taskId = UUID()

        _ = try manager.save(createMockResumeData(), for: taskId)
        XCTAssertTrue(manager.hasResumeData(for: taskId))

        manager.delete(for: taskId)

        XCTAssertFalse(manager.hasResumeData(for: taskId))
    }

    func test_delete_handlesNonexistentFile() {
        let unknownId = UUID()

        // Should not crash
        manager.delete(for: unknownId)
    }

    func test_deleteMultiple_removesAllFiles() throws {
        let taskId1 = UUID()
        let taskId2 = UUID()
        let taskId3 = UUID()

        _ = try manager.save(createMockResumeData(), for: taskId1)
        _ = try manager.save(createMockResumeData(), for: taskId2)
        _ = try manager.save(createMockResumeData(), for: taskId3)

        manager.delete(for: [taskId1, taskId2, taskId3])

        XCTAssertFalse(manager.hasResumeData(for: taskId1))
        XCTAssertFalse(manager.hasResumeData(for: taskId2))
        XCTAssertFalse(manager.hasResumeData(for: taskId3))
    }

    // MARK: - File URL Tests

    func test_fileURL_returnsCorrectPath() {
        let taskId = UUID()

        let url = manager.fileURL(for: taskId)

        XCTAssertEqual(url.lastPathComponent, "\(taskId.uuidString).resume")
        XCTAssertEqual(url.deletingLastPathComponent(), testDirectory)
    }

    func test_filePath_returnsPathString() {
        let taskId = UUID()

        let path = manager.filePath(for: taskId)

        XCTAssertTrue(path.contains(taskId.uuidString))
        XCTAssertTrue(path.hasSuffix(".resume"))
    }

    // MARK: - Cleanup Orphaned Tests

    func test_cleanupOrphaned_removesOrphanedFiles() throws {
        let validId = UUID()
        let orphanedId = UUID()

        _ = try manager.save(createMockResumeData(), for: validId)
        _ = try manager.save(createMockResumeData(), for: orphanedId)

        let deleted = manager.cleanupOrphaned(validTaskIds: [validId])

        XCTAssertEqual(deleted, 1)
        XCTAssertTrue(manager.hasResumeData(for: validId))
        XCTAssertFalse(manager.hasResumeData(for: orphanedId))
    }

    func test_cleanupOrphaned_keepsValidFiles() throws {
        let validId1 = UUID()
        let validId2 = UUID()

        _ = try manager.save(createMockResumeData(), for: validId1)
        _ = try manager.save(createMockResumeData(), for: validId2)

        let deleted = manager.cleanupOrphaned(validTaskIds: [validId1, validId2])

        XCTAssertEqual(deleted, 0)
        XCTAssertTrue(manager.hasResumeData(for: validId1))
        XCTAssertTrue(manager.hasResumeData(for: validId2))
    }

    func test_cleanupOrphaned_removesInvalidFilenames() throws {
        // Create file with invalid filename (not a UUID)
        let invalidFile = testDirectory.appendingPathComponent("invalid_name.resume")
        try Data("test".utf8).write(to: invalidFile)

        _ = manager.cleanupOrphaned(validTaskIds: [])

        XCTAssertFalse(FileManager.default.fileExists(at: invalidFile))
    }

    // MARK: - Cleanup Old Tests

    func test_cleanupOld_removesOldFiles() throws {
        // This test is tricky because we'd need to set file creation dates
        // Instead, test with very short max age
        let taskId = UUID()
        _ = try manager.save(createMockResumeData(), for: taskId)

        // Wait a tiny bit
        Thread.sleep(forTimeInterval: 0.1)

        // Cleanup files older than 0.05 seconds
        let deleted = manager.cleanupOld(maxAge: 0.05)

        XCTAssertEqual(deleted, 1)
    }

    func test_cleanupOld_keepsNewFiles() throws {
        let taskId = UUID()
        _ = try manager.save(createMockResumeData(), for: taskId)

        // Cleanup files older than 1 hour
        let deleted = manager.cleanupOld(maxAge: 3600)

        XCTAssertEqual(deleted, 0)
        XCTAssertTrue(manager.hasResumeData(for: taskId))
    }

    // MARK: - Delete All Tests

    func test_deleteAll_removesAllFiles() throws {
        _ = try manager.save(createMockResumeData(), for: UUID())
        _ = try manager.save(createMockResumeData(), for: UUID())
        _ = try manager.save(createMockResumeData(), for: UUID())

        let deleted = manager.deleteAll()

        XCTAssertEqual(deleted, 3)
        XCTAssertEqual(manager.count(), 0)
    }

    func test_deleteAll_returnsZeroWhenEmpty() {
        let deleted = manager.deleteAll()

        XCTAssertEqual(deleted, 0)
    }

    // MARK: - Total Size Tests

    func test_totalSize_returnsZeroWhenEmpty() {
        XCTAssertEqual(manager.totalSize(), 0)
    }

    func test_totalSize_returnsCorrectSize() throws {
        let data1 = Data(count: 100)
        let data2 = Data(count: 200)

        _ = try manager.save(data1, for: UUID())
        _ = try manager.save(data2, for: UUID())

        let totalSize = manager.totalSize()

        XCTAssertEqual(totalSize, 300)
    }

    func test_formattedTotalSize_returnsString() throws {
        _ = try manager.save(Data(count: 1024), for: UUID())

        let formatted = manager.formattedTotalSize

        XCTAssertTrue(formatted.contains("KB") || formatted.contains("B"))
    }

    // MARK: - Count Tests

    func test_count_returnsZeroWhenEmpty() {
        XCTAssertEqual(manager.count(), 0)
    }

    func test_count_returnsCorrectCount() throws {
        _ = try manager.save(createMockResumeData(), for: UUID())
        _ = try manager.save(createMockResumeData(), for: UUID())
        _ = try manager.save(createMockResumeData(), for: UUID())

        XCTAssertEqual(manager.count(), 3)
    }

    // MARK: - All Task IDs Tests

    func test_allTaskIds_returnsEmptyWhenNoFiles() {
        let ids = manager.allTaskIds()

        XCTAssertEqual(ids.count, 0)
    }

    func test_allTaskIds_returnsAllIds() throws {
        let taskId1 = UUID()
        let taskId2 = UUID()
        let taskId3 = UUID()

        _ = try manager.save(createMockResumeData(), for: taskId1)
        _ = try manager.save(createMockResumeData(), for: taskId2)
        _ = try manager.save(createMockResumeData(), for: taskId3)

        let ids = manager.allTaskIds()

        XCTAssertEqual(Set(ids), Set([taskId1, taskId2, taskId3]))
    }

    // MARK: - Validation Tests

    func test_isValidResumeData_returnsTrueForBinaryPlist() {
        let data = createMockResumeData()

        XCTAssertTrue(manager.isValidResumeData(data))
    }

    func test_isValidResumeData_returnsFalseForInvalidData() {
        let invalidData = Data("not valid".utf8)

        XCTAssertFalse(manager.isValidResumeData(invalidData))
    }

    func test_isValidResumeData_returnsFalseForTooShort() {
        let shortData = Data([0x62, 0x70])

        XCTAssertFalse(manager.isValidResumeData(shortData))
    }

    func test_loadValidated_returnsValidData() throws {
        let taskId = UUID()
        let data = createMockResumeData()

        _ = try manager.save(data, for: taskId)

        let loaded = manager.loadValidated(for: taskId)

        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded, data)
    }

    func test_loadValidated_returnsNilForInvalidData() throws {
        let taskId = UUID()
        let invalidData = Data("not valid".utf8)

        _ = try manager.save(invalidData, for: taskId)

        let loaded = manager.loadValidated(for: taskId)

        XCTAssertNil(loaded)
        // Invalid data should be deleted
        XCTAssertFalse(manager.hasResumeData(for: taskId))
    }

    func test_loadValidated_returnsNilForNonexistent() {
        let unknownId = UUID()

        let loaded = manager.loadValidated(for: unknownId)

        XCTAssertNil(loaded)
    }

    // MARK: - Diagnostic Info Tests

    func test_diagnosticInfo_containsAllFields() throws {
        _ = try manager.save(createMockResumeData(), for: UUID())
        _ = try manager.save(createMockResumeData(), for: UUID())

        let info = manager.diagnosticInfo

        XCTAssertEqual(info.directoryPath, testDirectory.path)
        XCTAssertEqual(info.fileCount, 2)
        XCTAssertGreaterThan(info.totalSize, 0)
        XCTAssertEqual(info.taskIds.count, 2)
        XCTAssertNotNil(info.formattedSize)
    }

    // MARK: - Directory URL Tests

    func test_directoryURL_returnsConfiguredDirectory() {
        XCTAssertEqual(manager.directoryURL, testDirectory)
    }

    // MARK: - XML Plist Validation Tests

    func test_isValidResumeData_returnsTrueForXMLPlist() {
        let xmlPlist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict></dict>
        </plist>
        """.data(using: .utf8)!

        XCTAssertTrue(manager.isValidResumeData(xmlPlist))
    }

    // MARK: - Edge Cases

    func test_concurrentOperations_areSafe() throws {
        let taskIds = (0..<10).map { _ in UUID() }

        DispatchQueue.concurrentPerform(iterations: 10) { i in
            do {
                _ = try self.manager.save(self.createMockResumeData(), for: taskIds[i])
            } catch {
                XCTFail("Concurrent save failed: \(error)")
            }
        }

        XCTAssertEqual(manager.count(), 10)
    }

    func test_largeData_canBeSavedAndLoaded() throws {
        let taskId = UUID()
        // Create 1MB of data
        let largeData = Data(count: 1024 * 1024)

        _ = try manager.save(largeData, for: taskId)
        let loaded = try manager.load(for: taskId)

        XCTAssertEqual(loaded?.count, largeData.count)
    }
}
