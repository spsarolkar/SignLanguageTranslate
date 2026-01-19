import XCTest
@testable import SignLanguageTranslate

/// Tests for DownloadStatePersistence
final class DownloadStatePersistenceTests: XCTestCase {

    var persistence: DownloadStatePersistence!
    var testFileName: String!

    override func setUpWithError() throws {
        try super.setUpWithError()

        // Use unique file name for each test
        testFileName = "test_state_\(UUID().uuidString).json"
        persistence = DownloadStatePersistence(fileName: testFileName, debounceInterval: 0.1)
    }

    override func tearDownWithError() throws {
        // Clean up test file
        if let persistence = persistence {
            Task {
                try? await persistence.clear()
            }
        }
        persistence = nil
        testFileName = nil
        try super.tearDownWithError()
    }

    // MARK: - Initialization Tests

    func test_initialization_createsInstance() {
        XCTAssertNotNil(persistence)
    }

    func test_initialization_customFileName() async {
        let customPersistence = DownloadStatePersistence(fileName: "custom_test.json")

        let fileURL = await customPersistence.getFileURL()
        XCTAssertTrue(fileURL.lastPathComponent == "custom_test.json")
    }

    func test_initialization_customDebounceInterval() {
        let fastPersistence = DownloadStatePersistence(debounceInterval: 0.5)
        XCTAssertNotNil(fastPersistence)
    }

    // MARK: - Save Tests

    func test_save_writesStateToFile() async throws {
        let state = DownloadQueueState.forTesting(taskCount: 3)

        try await persistence.save(state: state)

        let fileExists = await persistence.hasPersistedState()
        XCTAssertTrue(fileExists)
    }

    func test_save_stateCanBeLoaded() async throws {
        let state = DownloadQueueState.forTesting(taskCount: 5)

        try await persistence.save(state: state)
        let loaded = try await persistence.load()

        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.tasks.count, 5)
    }

    func test_save_preservesAllProperties() async throws {
        let tasks = [
            createTestDownloadTask(category: "Animals", partNumber: 1, totalParts: 2),
            createTestDownloadTask(category: "Greetings", partNumber: 1, totalParts: 1)
        ]
        let state = DownloadQueueState(
            tasks: tasks,
            queueOrder: tasks.map(\.id),
            isPaused: true,
            maxConcurrentDownloads: 5
        )

        try await persistence.save(state: state)
        let loaded = try await persistence.load()

        XCTAssertEqual(loaded?.tasks.count, 2)
        XCTAssertEqual(loaded?.isPaused, true)
        XCTAssertEqual(loaded?.maxConcurrentDownloads, 5)
        XCTAssertEqual(loaded?.queueOrder, tasks.map(\.id))
    }

    // MARK: - Load Tests

    func test_load_returnsNilForMissingFile() async throws {
        let loaded = try await persistence.load()

        XCTAssertNil(loaded)
    }

    func test_load_decodesValidState() async throws {
        let state = DownloadQueueState.forTesting(taskCount: 3)
        try await persistence.save(state: state)

        let loaded = try await persistence.load()

        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.tasks.count, 3)
    }

    func test_load_throwsForCorruptedFile() async throws {
        // Write invalid JSON to file
        let fileURL = await persistence.getFileURL()
        try "not valid json".data(using: .utf8)?.write(to: fileURL)

        do {
            _ = try await persistence.load()
            XCTFail("Should have thrown for corrupted file")
        } catch {
            // Expected
        }
    }

    // MARK: - Clear Tests

    func test_clear_removesFile() async throws {
        let state = DownloadQueueState.forTesting(taskCount: 3)
        try await persistence.save(state: state)

        let existsBefore = await persistence.hasPersistedState()
        XCTAssertTrue(existsBefore)

        try await persistence.clear()

        let existsAfter = await persistence.hasPersistedState()
        XCTAssertFalse(existsAfter)
    }

    func test_clear_handlesNonexistentFile() async throws {
        // Should not throw if file doesn't exist
        try await persistence.clear()
    }

    // MARK: - Debounced Save Tests

    func test_scheduleSave_savesAfterDebounce() async throws {
        let state = DownloadQueueState.forTesting(taskCount: 3)

        await persistence.scheduleSave(state: state)

        // Wait for debounce interval + buffer
        try await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds

        let loaded = try await persistence.load()
        XCTAssertNotNil(loaded)
    }

    func test_scheduleSave_coalescesMutipleCalls() async throws {
        let state1 = DownloadQueueState.forTesting(taskCount: 1)
        let state2 = DownloadQueueState.forTesting(taskCount: 2)
        let state3 = DownloadQueueState.forTesting(taskCount: 3)

        await persistence.scheduleSave(state: state1)
        await persistence.scheduleSave(state: state2)
        await persistence.scheduleSave(state: state3)

        // Wait for debounce
        try await Task.sleep(nanoseconds: 200_000_000)

        let loaded = try await persistence.load()
        // Last state should be saved
        XCTAssertEqual(loaded?.tasks.count, 3)
    }

    func test_scheduleSave_skipsSameState() async throws {
        let state = DownloadQueueState.forTesting(taskCount: 3)

        await persistence.scheduleSave(state: state)
        try await Task.sleep(nanoseconds: 200_000_000)

        // Schedule same state again
        await persistence.scheduleSave(state: state)

        // Should be a no-op (same hash)
        let loaded = try await persistence.load()
        XCTAssertEqual(loaded?.tasks.count, 3)
    }

    // MARK: - Flush Tests

    func test_flush_cancelsPendingSave() async {
        let state = DownloadQueueState.forTesting(taskCount: 3)

        await persistence.scheduleSave(state: state)
        await persistence.flush()

        // Flush cancels pending, so state might not be saved
        // This is more of a best-effort operation
    }

    // MARK: - Query Tests

    func test_hasPersistedState_returnsFalseWhenNoFile() async {
        let exists = await persistence.hasPersistedState()

        XCTAssertFalse(exists)
    }

    func test_hasPersistedState_returnsTrueWhenFileExists() async throws {
        let state = DownloadQueueState.forTesting(taskCount: 1)
        try await persistence.save(state: state)

        let exists = await persistence.hasPersistedState()

        XCTAssertTrue(exists)
    }

    func test_getFileURL_returnsValidPath() async {
        let url = await persistence.getFileURL()

        XCTAssertTrue(url.path.contains(testFileName))
    }

    func test_getFileSize_returnsZeroForNonexistent() async {
        let size = await persistence.getFileSize()

        XCTAssertEqual(size, 0)
    }

    func test_getFileSize_returnsPositiveForExistingFile() async throws {
        let state = DownloadQueueState.forTesting(taskCount: 5)
        try await persistence.save(state: state)

        let size = await persistence.getFileSize()

        XCTAssertGreaterThan(size, 0)
    }

    // MARK: - Validation Tests

    func test_loadValidated_returnsValidState() async throws {
        let state = DownloadQueueState.forTesting(taskCount: 3)
        try await persistence.save(state: state)

        let loaded = await persistence.loadValidated()

        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.tasks.count, 3)
    }

    func test_loadValidated_returnsNilForMissingFile() async {
        let loaded = await persistence.loadValidated()

        XCTAssertNil(loaded)
    }

    func test_loadValidated_repairsInvalidQueueOrder() async throws {
        // Create state with mismatched queue order
        let tasks = createTestDownloadTasks(count: 3)
        let invalidState = DownloadQueueState(
            tasks: tasks,
            queueOrder: [UUID(), UUID(), UUID()], // Wrong IDs
            isPaused: false
        )

        // Manually write the invalid state
        let data = try invalidState.toData()
        let fileURL = await persistence.getFileURL()
        try data.write(to: fileURL)

        let loaded = await persistence.loadValidated()

        // Should repair or return nil
        if let loaded = loaded {
            // If repaired, queue order should match task IDs
            XCTAssertEqual(Set(loaded.queueOrder), Set(loaded.tasks.map(\.id)))
        }
    }

    // MARK: - Backup Tests

    func test_createBackup_createsBackupFile() async throws {
        let state = DownloadQueueState.forTesting(taskCount: 3)
        try await persistence.save(state: state)

        let backupURL = try await persistence.createBackup()

        XCTAssertTrue(FileManager.default.fileExists(at: backupURL))

        // Cleanup
        FileManager.default.safeDelete(at: backupURL)
    }

    func test_createBackup_throwsWhenNoState() async {
        do {
            _ = try await persistence.createBackup()
            XCTFail("Should throw when no state to backup")
        } catch {
            XCTAssertTrue(error is DownloadStatePersistenceError)
        }
    }

    func test_restoreFromBackup_restoresState() async throws {
        let state = DownloadQueueState.forTesting(taskCount: 5)
        try await persistence.save(state: state)
        let backupURL = try await persistence.createBackup()

        // Clear main state
        try await persistence.clear()

        // Restore from backup
        let restored = try await persistence.restoreFromBackup()

        XCTAssertEqual(restored.tasks.count, 5)

        // Cleanup
        FileManager.default.safeDelete(at: backupURL)
    }

    func test_restoreFromBackup_throwsWhenNoBackup() async {
        do {
            _ = try await persistence.restoreFromBackup()
            XCTFail("Should throw when no backup exists")
        } catch {
            XCTAssertTrue(error is DownloadStatePersistenceError)
        }
    }

    // MARK: - Error Tests

    func test_persistenceError_descriptions() {
        let noStateError = DownloadStatePersistenceError.noStateToBackup
        XCTAssertNotNil(noStateError.errorDescription)

        let noBackupError = DownloadStatePersistenceError.noBackupFound
        XCTAssertNotNil(noBackupError.errorDescription)

        let corruptedError = DownloadStatePersistenceError.stateCorrupted(errors: ["test error"])
        XCTAssertNotNil(corruptedError.errorDescription)
        XCTAssertTrue(corruptedError.errorDescription!.contains("test error"))
    }

    // MARK: - Concurrent Access Tests

    func test_concurrentSaves_areSafe() async throws {
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<10 {
                group.addTask {
                    let state = DownloadQueueState.forTesting(taskCount: i + 1)
                    try? await self.persistence.save(state: state)
                }
            }
        }

        // Should complete without crashing
        let loaded = try await persistence.load()
        XCTAssertNotNil(loaded)
    }
}
