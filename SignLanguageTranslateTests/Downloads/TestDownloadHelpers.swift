#if canImport(XCTest)
import Foundation
import XCTest
@testable import SignLanguageTranslate

// MARK: - Test Helper Extensions

extension XCTestCase {

    /// Create a test download task with customizable properties
    /// - Parameters:
    ///   - id: Task UUID (defaults to new UUID)
    ///   - status: Task status (defaults to .pending)
    ///   - progress: Download progress 0.0-1.0 (defaults to 0)
    ///   - category: Category name (defaults to "Animals")
    ///   - partNumber: Part number (defaults to 1)
    ///   - totalParts: Total parts (defaults to 1)
    ///   - bytesDownloaded: Bytes downloaded (defaults to 0)
    ///   - totalBytes: Total bytes (defaults to 100_000_000)
    /// - Returns: A configured DownloadTask
    func createTestDownloadTask(
        id: UUID = UUID(),
        status: DownloadTaskStatus = .pending,
        progress: Double = 0,
        category: String = "Animals",
        partNumber: Int = 1,
        totalParts: Int = 1,
        bytesDownloaded: Int64 = 0,
        totalBytes: Int64 = 100_000_000,
        datasetName: String = "INCLUDE",
        errorMessage: String? = nil,
        resumeDataPath: String? = nil
    ) -> DownloadTask {
        DownloadTask(
            id: id,
            url: URL(string: "https://example.com/\(category)_\(partNumber)of\(totalParts).zip")!,
            category: category,
            partNumber: partNumber,
            totalParts: totalParts,
            datasetName: datasetName,
            status: status,
            progress: progress,
            bytesDownloaded: bytesDownloaded,
            totalBytes: totalBytes,
            errorMessage: errorMessage,
            resumeDataPath: resumeDataPath
        )
    }

    /// Create multiple test download tasks
    /// - Parameters:
    ///   - count: Number of tasks to create
    ///   - status: Status for all tasks (defaults to .pending)
    /// - Returns: Array of DownloadTask
    func createTestDownloadTasks(count: Int, status: DownloadTaskStatus = .pending) -> [DownloadTask] {
        (1...count).map { index in
            createTestDownloadTask(
                status: status,
                category: "Category\(index)",
                partNumber: 1,
                totalParts: 1
            )
        }
    }

    /// Create a temporary file with specified size
    /// - Parameter size: File size in bytes
    /// - Returns: URL of the temporary file
    func createTempFile(size: Int) -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent(UUID().uuidString + ".tmp")

        let data = Data(count: size)
        try? data.write(to: fileURL)

        return fileURL
    }

    /// Create a temporary directory for testing
    /// - Returns: URL of the temporary directory
    func createTempDirectory() -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("TestDir_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        return tempDir
    }

    /// Clean up a temporary file or directory
    /// - Parameter url: URL to clean up
    func cleanupTemp(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    /// Create valid resume data (mock plist format)
    /// - Returns: Data that looks like valid resume data
    func createMockResumeData() -> Data {
        // Binary plist header "bplist"
        var data = Data([0x62, 0x70, 0x6C, 0x69, 0x73, 0x74])
        // Add some random bytes
        data.append(contentsOf: (0..<100).map { _ in UInt8.random(in: 0...255) })
        return data
    }

    /// Create invalid resume data
    /// - Returns: Data that is not valid resume data
    func createInvalidResumeData() -> Data {
        return Data("not valid resume data".utf8)
    }

    /// Wait for a condition to become true
    /// - Parameters:
    ///   - timeout: Maximum time to wait
    ///   - condition: Condition to check
    /// - Returns: True if condition became true before timeout
    @MainActor
    func waitFor(timeout: TimeInterval = 5.0, condition: @escaping () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if condition() {
                return true
            }
            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
        }

        return false
    }

    /// Wait for a condition to become true with async check
    /// - Parameters:
    ///   - timeout: Maximum time to wait
    ///   - condition: Async condition to check
    /// - Returns: True if condition became true before timeout
    @MainActor
    func waitForAsync(timeout: TimeInterval = 5.0, condition: @escaping () async -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if await condition() {
                return true
            }
            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
        }

        return false
    }
}

// MARK: - Test Download Queue State

extension DownloadQueueState {

    /// Create a test state with specified number of tasks
    /// - Parameters:
    ///   - taskCount: Number of tasks
    ///   - status: Status for all tasks
    /// - Returns: DownloadQueueState for testing
    static func forTesting(
        taskCount: Int,
        status: DownloadTaskStatus = .pending,
        isPaused: Bool = false
    ) -> DownloadQueueState {
        let tasks = (0..<taskCount).map { index in
            DownloadTask(
                url: URL(string: "https://example.com/file\(index).zip")!,
                category: "Category\(index)",
                partNumber: 1,
                totalParts: 1,
                datasetName: "INCLUDE",
                status: status
            )
        }

        return DownloadQueueState(
            tasks: tasks,
            queueOrder: tasks.map(\.id),
            isPaused: isPaused,
            maxConcurrentDownloads: 3
        )
    }
}

// MARK: - Async Test Helpers

/// A simple expectation for async tests
actor AsyncExpectation {
    private var isFulfilled = false
    private var fulfillCount = 0
    private let expectedCount: Int

    init(count: Int = 1) {
        self.expectedCount = count
    }

    func fulfill() {
        fulfillCount += 1
        if fulfillCount >= expectedCount {
            isFulfilled = true
        }
    }

    func wait(timeout: TimeInterval = 5.0) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if isFulfilled {
                return true
            }
            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
        }

        return isFulfilled
    }

    var fulfilled: Bool {
        isFulfilled
    }
}

// MARK: - Mock Network Monitor

/// A mock network monitor for testing
final class MockNetworkMonitor: @unchecked Sendable {
    private var _isConnected: Bool
    private let lock = NSLock()

    var isConnected: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _isConnected
        }
        set {
            lock.lock()
            _isConnected = newValue
            lock.unlock()
        }
    }

    init(isConnected: Bool = true) {
        self._isConnected = isConnected
    }

    func simulateConnectionLost() {
        isConnected = false
    }

    func simulateConnectionRestored() {
        isConnected = true
    }
}

// MARK: - Test File Cleanup

/// Helper class to manage test file cleanup
final class TestFileCleanup {
    private var filesToClean: [URL] = []

    func track(_ url: URL) {
        filesToClean.append(url)
    }

    func cleanAll() {
        for url in filesToClean {
            try? FileManager.default.removeItem(at: url)
        }
        filesToClean.removeAll()
    }

    deinit {
        cleanAll()
    }
}
#endif
