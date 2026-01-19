#if canImport(XCTest)
import XCTest
@testable import SignLanguageTranslate

/// Tests for DownloadFileManager
final class DownloadFileManagerTests: XCTestCase {

    var fileManager: DownloadFileManager!
    var tempDirectory: URL!
    var cleanup: TestFileCleanup!

    override func setUpWithError() throws {
        try super.setUpWithError()

        fileManager = DownloadFileManager()
        cleanup = TestFileCleanup()

        // Create temp directory for testing
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DownloadFileManagerTests_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        cleanup.track(tempDirectory)
    }

    override func tearDownWithError() throws {
        cleanup.cleanAll()
        fileManager = nil
        tempDirectory = nil
        cleanup = nil
        try super.tearDownWithError()
    }

    // MARK: - Directory Tests

    func test_downloadsDirectory_exists() {
        let url = fileManager.downloadsDirectory

        XCTAssertTrue(FileManager.default.directoryExists(at: url))
    }

    func test_tempDirectory_exists() {
        let url = fileManager.tempDirectory

        XCTAssertTrue(FileManager.default.directoryExists(at: url))
    }

    func test_resumeDataDirectory_exists() {
        let url = fileManager.resumeDataDirectory

        XCTAssertTrue(FileManager.default.directoryExists(at: url))
    }

    func test_completedDownloadsDirectory_exists() {
        let url = fileManager.completedDownloadsDirectory

        XCTAssertTrue(FileManager.default.directoryExists(at: url))
    }

    func test_datasetsDirectory_exists() {
        let url = fileManager.datasetsDirectory

        XCTAssertTrue(FileManager.default.directoryExists(at: url))
    }

    // MARK: - Move Completed Download Tests

    func test_moveCompletedDownload_movesFile() throws {
        let task = createTestDownloadTask()

        // Create source file
        let sourceFile = tempDirectory.appendingPathComponent("source.zip")
        try Data("test content".utf8).write(to: sourceFile)

        let destinationURL = try fileManager.moveCompletedDownload(from: sourceFile, for: task)

        XCTAssertTrue(FileManager.default.fileExists(at: destinationURL))
        XCTAssertFalse(FileManager.default.fileExists(at: sourceFile))

        // Cleanup
        FileManager.default.safeDelete(at: destinationURL)
    }

    func test_moveCompletedDownload_usesCorrectFilename() throws {
        let task = createTestDownloadTask(category: "TestCategory")

        let sourceFile = tempDirectory.appendingPathComponent("original.zip")
        try Data("test content".utf8).write(to: sourceFile)

        let destinationURL = try fileManager.moveCompletedDownload(from: sourceFile, for: task)

        XCTAssertTrue(destinationURL.lastPathComponent.contains(task.id.uuidString))

        // Cleanup
        FileManager.default.safeDelete(at: destinationURL)
    }

    func test_moveCompletedDownload_replacesExistingFile() throws {
        let task = createTestDownloadTask()

        // Create first file
        let sourceFile1 = tempDirectory.appendingPathComponent("source1.zip")
        try Data("first content".utf8).write(to: sourceFile1)
        let dest1 = try fileManager.moveCompletedDownload(from: sourceFile1, for: task)

        // Create second file with same task
        let sourceFile2 = tempDirectory.appendingPathComponent("source2.zip")
        try Data("second content".utf8).write(to: sourceFile2)
        let dest2 = try fileManager.moveCompletedDownload(from: sourceFile2, for: task)

        // Second file should have replaced first
        XCTAssertEqual(dest1.path, dest2.path)
        XCTAssertTrue(FileManager.default.fileExists(at: dest2))

        // Cleanup
        FileManager.default.safeDelete(at: dest2)
    }

    // MARK: - Completed Download URL Tests

    func test_completedDownloadURL_returnsCorrectPath() {
        let task = createTestDownloadTask()

        let url = fileManager.completedDownloadURL(for: task)

        XCTAssertTrue(url.lastPathComponent.contains(task.id.uuidString))
        XCTAssertTrue(url.path.contains("completed"))
    }

    func test_deleteCompletedDownload_removesFile() throws {
        let task = createTestDownloadTask()

        // Create file at expected location
        let url = fileManager.completedDownloadURL(for: task)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("test".utf8).write(to: url)

        XCTAssertTrue(FileManager.default.fileExists(at: url))

        fileManager.deleteCompletedDownload(for: task)

        XCTAssertFalse(FileManager.default.fileExists(at: url))
    }

    // MARK: - Resume Data Tests

    func test_saveResumeData_savesData() throws {
        let taskId = UUID()
        let data = createMockResumeData()

        let url = try fileManager.saveResumeData(data, for: taskId)

        XCTAssertTrue(FileManager.default.fileExists(at: url))
        cleanup.track(url)
    }

    func test_saveResumeData_writesAtomically() throws {
        let taskId = UUID()
        let data = createMockResumeData()

        let url = try fileManager.saveResumeData(data, for: taskId)

        // File should exist and have correct content
        let loadedData = try Data(contentsOf: url)
        XCTAssertEqual(loadedData, data)
        cleanup.track(url)
    }

    func test_loadResumeData_loadsExistingData() throws {
        let taskId = UUID()
        let originalData = createMockResumeData()

        let url = try fileManager.saveResumeData(originalData, for: taskId)
        cleanup.track(url)

        let loadedData = try fileManager.loadResumeData(for: taskId)

        XCTAssertEqual(loadedData, originalData)
    }

    func test_loadResumeData_returnsNilForNonexistent() throws {
        let unknownId = UUID()

        let data = try fileManager.loadResumeData(for: unknownId)

        XCTAssertNil(data)
    }

    func test_deleteResumeData_removesFile() throws {
        let taskId = UUID()
        let data = createMockResumeData()

        let url = try fileManager.saveResumeData(data, for: taskId)
        XCTAssertTrue(FileManager.default.fileExists(at: url))

        fileManager.deleteResumeData(for: taskId)

        XCTAssertFalse(FileManager.default.fileExists(at: url))
    }

    func test_resumeDataURL_returnsCorrectPath() {
        let taskId = UUID()

        let url = fileManager.resumeDataURL(for: taskId)

        XCTAssertTrue(url.lastPathComponent.contains(taskId.uuidString))
        XCTAssertTrue(url.pathExtension == "resume")
    }

    func test_hasResumeData_returnsTrueWhenExists() throws {
        let taskId = UUID()
        let data = createMockResumeData()

        let url = try fileManager.saveResumeData(data, for: taskId)
        cleanup.track(url)

        XCTAssertTrue(fileManager.hasResumeData(for: taskId))
    }

    func test_hasResumeData_returnsFalseWhenNotExists() {
        let unknownId = UUID()

        XCTAssertFalse(fileManager.hasResumeData(for: unknownId))
    }

    // MARK: - Storage Space Tests

    func test_availableStorageSpace_returnsPositiveValue() {
        let available = fileManager.availableStorageSpace()

        XCTAssertGreaterThan(available, 0)
    }

    func test_hasStorageSpace_returnsTrueForSmallAmount() {
        // 1 KB should always be available
        let hasSpace = fileManager.hasStorageSpace(for: 1024)

        XCTAssertTrue(hasSpace)
    }

    func test_hasStorageSpace_includes10PercentBuffer() {
        // Testing the buffer calculation
        let available = fileManager.availableStorageSpace()

        // Should have space for less than available with buffer
        let reasonableAmount = available / 2
        XCTAssertTrue(fileManager.hasStorageSpace(for: reasonableAmount))
    }

    // MARK: - File Size Tests

    func test_downloadedFileSize_returnsCorrectSize() throws {
        let task = createTestDownloadTask()
        let content = Data(count: 1000)

        // Create file at expected location
        let url = fileManager.completedDownloadURL(for: task)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try content.write(to: url)

        let size = fileManager.downloadedFileSize(for: task)

        XCTAssertEqual(size, 1000)

        // Cleanup
        FileManager.default.safeDelete(at: url)
    }

    func test_downloadedFileSize_returnsNilForNonexistent() {
        let task = createTestDownloadTask()

        let size = fileManager.downloadedFileSize(for: task)

        XCTAssertNil(size)
    }

    func test_totalDownloadsSize_returnsValue() {
        let size = fileManager.totalDownloadsSize()

        // Size should be >= 0
        XCTAssertGreaterThanOrEqual(size, 0)
    }

    func test_totalDatasetsSize_returnsValue() {
        let size = fileManager.totalDatasetsSize()

        // Size should be >= 0
        XCTAssertGreaterThanOrEqual(size, 0)
    }

    // MARK: - Cleanup Tests

    func test_cleanupTempDirectory_removesFiles() throws {
        // Create files in temp directory
        let file1 = fileManager.tempDirectory.appendingPathComponent("temp1.tmp")
        let file2 = fileManager.tempDirectory.appendingPathComponent("temp2.tmp")
        try Data("test".utf8).write(to: file1)
        try Data("test".utf8).write(to: file2)

        fileManager.cleanupTempDirectory()

        XCTAssertFalse(FileManager.default.fileExists(at: file1))
        XCTAssertFalse(FileManager.default.fileExists(at: file2))
    }

    func test_cleanupOrphanedResumeData_removesOrphanedFiles() throws {
        let validTaskId = UUID()
        let orphanedTaskId = UUID()

        // Create resume data files
        try fileManager.saveResumeData(createMockResumeData(), for: validTaskId)
        try fileManager.saveResumeData(createMockResumeData(), for: orphanedTaskId)

        // Cleanup with only validTaskId
        fileManager.cleanupOrphanedResumeData(validTaskIds: [validTaskId])

        XCTAssertTrue(fileManager.hasResumeData(for: validTaskId))
        XCTAssertFalse(fileManager.hasResumeData(for: orphanedTaskId))

        // Cleanup
        fileManager.deleteResumeData(for: validTaskId)
    }

    func test_cleanupOrphanedDownloads_removesOrphanedFiles() throws {
        let validTask = createTestDownloadTask(category: "Valid")
        let orphanedTask = createTestDownloadTask(category: "Orphaned")

        // Create completed download files
        let validFile = tempDirectory.appendingPathComponent("valid.zip")
        let orphanedFile = tempDirectory.appendingPathComponent("orphaned.zip")
        try Data("valid".utf8).write(to: validFile)
        try Data("orphaned".utf8).write(to: orphanedFile)

        try fileManager.moveCompletedDownload(from: validFile, for: validTask)
        try fileManager.moveCompletedDownload(from: orphanedFile, for: orphanedTask)

        // Cleanup with only validTask
        fileManager.cleanupOrphanedDownloads(validTaskIds: [validTask.id])

        // Valid should still exist, orphaned should be removed
        XCTAssertTrue(FileManager.default.fileExists(at: fileManager.completedDownloadURL(for: validTask)))
        XCTAssertFalse(FileManager.default.fileExists(at: fileManager.completedDownloadURL(for: orphanedTask)))

        // Cleanup
        fileManager.deleteCompletedDownload(for: validTask)
    }

    func test_cleanupOrphanedFiles_callsAllCleanups() throws {
        let validTaskId = UUID()

        // Create orphaned files in various locations
        let orphanedResumeId = UUID()
        try fileManager.saveResumeData(createMockResumeData(), for: orphanedResumeId)

        fileManager.cleanupOrphanedFiles(validTaskIds: [validTaskId])

        // Orphaned resume data should be removed
        XCTAssertFalse(fileManager.hasResumeData(for: orphanedResumeId))
    }

    // MARK: - Dataset Directory Tests

    func test_datasetDirectory_createsDirectory() {
        let url = fileManager.datasetDirectory(for: "TestDataset")

        XCTAssertTrue(FileManager.default.directoryExists(at: url))
        XCTAssertTrue(url.lastPathComponent == "TestDataset")

        // Cleanup
        try? FileManager.default.removeItem(at: url)
    }

    func test_categoryDirectory_createsNestedDirectory() {
        let url = fileManager.categoryDirectory(for: "Animals", in: "TestDataset")

        XCTAssertTrue(FileManager.default.directoryExists(at: url))
        XCTAssertTrue(url.lastPathComponent == "Animals")
        XCTAssertTrue(url.deletingLastPathComponent().lastPathComponent == "TestDataset")

        // Cleanup
        try? FileManager.default.removeItem(at: fileManager.datasetDirectory(for: "TestDataset"))
    }

    func test_isCategoryDownloaded_returnsFalseForEmptyDirectory() {
        let _ = fileManager.categoryDirectory(for: "EmptyCategory", in: "TestDataset")

        let isDownloaded = fileManager.isCategoryDownloaded("EmptyCategory", in: "TestDataset")

        XCTAssertFalse(isDownloaded)

        // Cleanup
        try? FileManager.default.removeItem(at: fileManager.datasetDirectory(for: "TestDataset"))
    }

    func test_isCategoryDownloaded_returnsTrueWithContent() throws {
        let categoryURL = fileManager.categoryDirectory(for: "FilledCategory", in: "TestDataset")

        // Add a file to the category
        let fileURL = categoryURL.appendingPathComponent("test.txt")
        try Data("test".utf8).write(to: fileURL)

        let isDownloaded = fileManager.isCategoryDownloaded("FilledCategory", in: "TestDataset")

        XCTAssertTrue(isDownloaded)

        // Cleanup
        try? FileManager.default.removeItem(at: fileManager.datasetDirectory(for: "TestDataset"))
    }

    // MARK: - Error Tests

    func test_downloadFileError_descriptions() {
        let insufficientStorage = DownloadFileError.insufficientStorage(required: 1000, available: 500)
        XCTAssertNotNil(insufficientStorage.errorDescription)
        XCTAssertTrue(insufficientStorage.errorDescription!.contains("Insufficient"))

        let fileNotFound = DownloadFileError.fileNotFound(URL(string: "file://test")!)
        XCTAssertNotNil(fileNotFound.errorDescription)
        XCTAssertTrue(fileNotFound.errorDescription!.contains("not found"))

        let moveFailed = DownloadFileError.moveFailed(
            from: URL(string: "file://from")!,
            to: URL(string: "file://to")!,
            underlying: NSError(domain: "test", code: 1)
        )
        XCTAssertNotNil(moveFailed.errorDescription)

        let corrupted = DownloadFileError.resumeDataCorrupted
        XCTAssertNotNil(corrupted.errorDescription)
        XCTAssertTrue(corrupted.errorDescription!.contains("corrupted"))
    }
}
#endif
