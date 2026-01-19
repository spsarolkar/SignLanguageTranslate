import XCTest
@testable import SignLanguageTranslate

/// Performance tests for the download system
///
/// These tests measure the performance of critical operations to ensure
/// the download system can handle large numbers of tasks efficiently.
final class DownloadPerformanceTests: XCTestCase {

    var tempDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()

        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PerformanceTests_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temp = tempDirectory {
            try? FileManager.default.removeItem(at: temp)
        }
        tempDirectory = nil
        try super.tearDownWithError()
    }

    // MARK: - Queue Processing Performance

    func test_queueProcessing_performance_100Tasks() {
        let queue = DownloadQueueActor(maxConcurrentDownloads: 3)

        measure {
            let tasks = (0..<100).map { index in
                DownloadTask(
                    url: URL(string: "https://example.com/file\(index).zip")!,
                    category: "Category\(index % 10)",
                    partNumber: (index % 5) + 1,
                    totalParts: 5,
                    datasetName: "INCLUDE"
                )
            }

            let expectation = self.expectation(description: "Enqueue complete")

            Task {
                await queue.enqueueAll(tasks)
                let count = await queue.getTotalCount()
                XCTAssertEqual(count, 100)
                expectation.fulfill()
            }

            self.waitForExpectations(timeout: 5.0)

            // Cleanup
            Task {
                await queue.clear()
            }
        }
    }

    func test_queueProcessing_performance_singleEnqueue() {
        let queue = DownloadQueueActor(maxConcurrentDownloads: 3)

        measure {
            let task = DownloadTask(
                url: URL(string: "https://example.com/file.zip")!,
                category: "Animals",
                partNumber: 1,
                totalParts: 1,
                datasetName: "INCLUDE"
            )

            let expectation = self.expectation(description: "Enqueue complete")

            Task {
                for _ in 0..<100 {
                    await queue.enqueue(task)
                    await queue.remove(task.id)
                }
                expectation.fulfill()
            }

            self.waitForExpectations(timeout: 10.0)
        }
    }

    // MARK: - State Persistence Performance

    func test_statePersistence_save_performance() {
        let persistence = DownloadStatePersistence(
            fileName: "perf_test_\(UUID().uuidString).json",
            debounceInterval: 0 // No debounce for testing
        )

        let state = DownloadQueueState.forTesting(taskCount: 100)

        measure {
            let expectation = self.expectation(description: "Save complete")

            Task {
                try await persistence.save(state: state)
                expectation.fulfill()
            }

            self.waitForExpectations(timeout: 5.0)
        }

        // Cleanup
        Task {
            try? await persistence.clear()
        }
    }

    func test_statePersistence_load_performance() {
        let persistence = DownloadStatePersistence(
            fileName: "perf_test_load_\(UUID().uuidString).json",
            debounceInterval: 0
        )

        let state = DownloadQueueState.forTesting(taskCount: 100)

        // Save first
        let saveExpectation = expectation(description: "Save complete")
        Task {
            try await persistence.save(state: state)
            saveExpectation.fulfill()
        }
        waitForExpectations(timeout: 5.0)

        // Measure load
        measure {
            let expectation = self.expectation(description: "Load complete")

            Task {
                let loaded = try await persistence.load()
                XCTAssertNotNil(loaded)
                XCTAssertEqual(loaded?.tasks.count, 100)
                expectation.fulfill()
            }

            self.waitForExpectations(timeout: 5.0)
        }

        // Cleanup
        Task {
            try? await persistence.clear()
        }
    }

    // MARK: - Progress Calculation Performance

    @MainActor
    func test_progressCalculation_performance_46Tasks() {
        let tracker = DownloadProgressTracker()

        // Create 46 tasks (typical for INCLUDE dataset)
        let taskIds = (0..<46).map { _ in UUID() }

        measure {
            // Simulate progress updates for all tasks
            for (index, taskId) in taskIds.enumerated() {
                let progress = Double(index) / 46.0
                let bytes = Int64(Double(100_000_000) * progress)
                tracker.updateProgress(taskId: taskId, bytes: bytes, total: 100_000_000)
            }

            // Get aggregate progress
            _ = tracker.overallProgress
            _ = tracker.totalBytesDownloaded
            _ = tracker.totalBytesExpected
            _ = tracker.currentDownloadRate
        }

        tracker.reset()
    }

    @MainActor
    func test_progressCalculation_performance_frequentUpdates() {
        let tracker = DownloadProgressTracker()
        let taskId = UUID()

        measure {
            // Simulate frequent progress updates (as would happen during download)
            for i in 0..<1000 {
                let bytes = Int64(i * 1000)
                tracker.updateProgress(taskId: taskId, bytes: bytes, total: 1_000_000)
            }

            // Calculate aggregate values
            _ = tracker.overallProgress
            _ = tracker.formattedBytesProgress
            _ = tracker.snapshot()
        }

        tracker.reset()
    }

    // MARK: - Resume Data Manager Performance

    func test_resumeDataManager_save_performance() throws {
        let manager = ResumeDataManager(directory: tempDirectory)
        let resumeData = Data(count: 50_000) // 50KB typical resume data

        measure {
            for _ in 0..<100 {
                let taskId = UUID()
                _ = try? manager.save(resumeData, for: taskId)
            }
        }

        // Cleanup
        _ = manager.deleteAll()
    }

    func test_resumeDataManager_load_performance() throws {
        let manager = ResumeDataManager(directory: tempDirectory)
        let resumeData = Data(count: 50_000)

        // Save some files first
        let taskIds = (0..<50).map { _ -> UUID in
            let id = UUID()
            _ = try? manager.save(resumeData, for: id)
            return id
        }

        measure {
            for taskId in taskIds {
                _ = try? manager.load(for: taskId)
            }
        }

        // Cleanup
        _ = manager.deleteAll()
    }

    func test_resumeDataManager_cleanup_performance() throws {
        let manager = ResumeDataManager(directory: tempDirectory)
        let resumeData = Data(count: 10_000)

        // Create 100 files, mark 50 as valid
        var validIds: Set<UUID> = []
        for i in 0..<100 {
            let id = UUID()
            _ = try? manager.save(resumeData, for: id)
            if i < 50 {
                validIds.insert(id)
            }
        }

        measure {
            _ = manager.cleanupOrphaned(validTaskIds: validIds)
        }
    }

    // MARK: - Download Engine Performance

    @MainActor
    func test_downloadEngine_initialization_performance() {
        measure {
            for _ in 0..<10 {
                let engine = DownloadEngine(
                    maxConcurrentDownloads: 3,
                    maxRetryAttempts: 3,
                    retryDelaySeconds: 2.0
                )
                _ = engine.isRunning
            }
        }
    }

    @MainActor
    func test_downloadEngine_enqueue_performance() {
        let engine = DownloadEngine()

        measure {
            let expectation = self.expectation(description: "Enqueue complete")

            Task { @MainActor in
                let tasks = self.createPerformanceTestTasks(count: 50)
                await engine.enqueueAll(tasks)
                expectation.fulfill()
            }

            self.waitForExpectations(timeout: 10.0)

            // Cleanup
            Task { @MainActor in
                await engine.clearAll()
            }
        }
    }

    // MARK: - Download File Manager Performance

    func test_downloadFileManager_directoryCreation_performance() {
        measure {
            let manager = DownloadFileManager()

            // Directories should be created lazily or cached
            for _ in 0..<100 {
                _ = manager.downloadsDirectory
                _ = manager.tempDirectory
                _ = manager.resumeDataDirectory
            }
        }
    }

    func test_downloadFileManager_storageCheck_performance() {
        let manager = DownloadFileManager()

        measure {
            for _ in 0..<100 {
                _ = manager.availableStorageSpace()
                _ = manager.hasStorageSpace(for: 1_000_000_000)
            }
        }
    }

    // MARK: - Download Queue State Performance

    func test_downloadQueueState_validation_performance() {
        let state = DownloadQueueState.forTesting(taskCount: 100)

        measure {
            for _ in 0..<100 {
                _ = state.validate()
                _ = state.isValid
            }
        }
    }

    func test_downloadQueueState_serialization_performance() throws {
        let state = DownloadQueueState.forTesting(taskCount: 100)

        measure {
            for _ in 0..<10 {
                let data = try? state.toData()
                if let data = data {
                    _ = try? DownloadQueueState.fromData(data)
                }
            }
        }
    }

    // MARK: - Queue Actor Query Performance

    func test_queueActor_filtering_performance() {
        let queue = DownloadQueueActor(maxConcurrentDownloads: 3)

        // Setup: enqueue 100 tasks with mixed statuses
        let setupExpectation = expectation(description: "Setup complete")
        Task {
            let tasks = (0..<100).map { index in
                var task = DownloadTask(
                    url: URL(string: "https://example.com/file\(index).zip")!,
                    category: "Category\(index % 10)",
                    partNumber: 1,
                    totalParts: 1,
                    datasetName: "INCLUDE"
                )
                // Mix of statuses
                if index % 4 == 0 {
                    task.start()
                } else if index % 4 == 1 {
                    task.start()
                    task.complete()
                } else if index % 4 == 2 {
                    task.start()
                    task.fail(with: "Error")
                }
                return task
            }
            await queue.enqueueAll(tasks)
            setupExpectation.fulfill()
        }
        waitForExpectations(timeout: 5.0)

        measure {
            let expectation = self.expectation(description: "Queries complete")

            Task {
                for _ in 0..<10 {
                    _ = await queue.getPendingTasks()
                    _ = await queue.getActiveTasks()
                    _ = await queue.getCompletedTasks()
                    _ = await queue.getFailedTasks()
                    _ = await queue.getOverallProgress()
                    _ = await queue.getTotalBytes()
                }
                expectation.fulfill()
            }

            self.waitForExpectations(timeout: 10.0)
        }
    }

    // MARK: - Concurrent Access Performance

    func test_queueActor_concurrentAccess_performance() {
        let queue = DownloadQueueActor(maxConcurrentDownloads: 3)

        measure {
            let expectation = self.expectation(description: "Concurrent access complete")

            Task {
                await withTaskGroup(of: Void.self) { group in
                    for _ in 0..<50 {
                        group.addTask {
                            let task = DownloadTask(
                                url: URL(string: "https://example.com/file.zip")!,
                                category: "Animals",
                                partNumber: 1,
                                totalParts: 1,
                                datasetName: "INCLUDE"
                            )
                            await queue.enqueue(task)
                            await queue.remove(task.id)
                        }
                    }
                }
                expectation.fulfill()
            }

            self.waitForExpectations(timeout: 10.0)
        }
    }

    // MARK: - Memory Efficiency Tests

    func test_largeTaskCount_memoryEfficiency() {
        // This test verifies that handling many tasks doesn't cause memory issues
        let queue = DownloadQueueActor(maxConcurrentDownloads: 3)

        let expectation = expectation(description: "Large queue handling")

        Task {
            // Create 500 tasks (larger than typical use case)
            let tasks = (0..<500).map { index in
                DownloadTask(
                    url: URL(string: "https://example.com/file\(index).zip")!,
                    category: "Category\(index % 20)",
                    partNumber: (index % 10) + 1,
                    totalParts: 10,
                    datasetName: "INCLUDE"
                )
            }

            await queue.enqueueAll(tasks)

            // Query operations should complete quickly
            _ = await queue.getAllTasks()
            _ = await queue.getOverallProgress()

            // Clear
            await queue.clear()

            let count = await queue.getTotalCount()
            XCTAssertEqual(count, 0)

            expectation.fulfill()
        }

        waitForExpectations(timeout: 30.0)
    }

    // MARK: - Helper Methods

    func createPerformanceTestTasks(count: Int) -> [DownloadTask] {
        (0..<count).map { index in
            DownloadTask(
                url: URL(string: "https://example.com/perf\(index).zip")!,
                category: "Performance\(index % 5)",
                partNumber: (index % 3) + 1,
                totalParts: 3,
                datasetName: "INCLUDE"
            )
        }
    }
}

// MARK: - Baseline Performance Metrics

extension DownloadPerformanceTests {
    /// Documents expected performance baselines
    /// These are not assertions, but documentation of expected performance
    static let expectedBaselines: [String: TimeInterval] = [
        "queueProcessing_100Tasks": 0.5,      // 500ms for 100 tasks
        "statePersistence_save": 0.1,         // 100ms for state save
        "statePersistence_load": 0.1,         // 100ms for state load
        "progressCalculation_46Tasks": 0.01,  // 10ms for 46 tasks
        "resumeDataManager_save": 0.05,       // 50ms per save
        "resumeDataManager_cleanup": 0.1      // 100ms for cleanup
    ]
}
