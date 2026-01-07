# Phase 4.4 — Download System Tests

Create comprehensive tests for the download system.

## Context

We have:
- BackgroundSessionManager
- DownloadEngine
- DownloadCoordinator
- DownloadFileManager
- DownloadStatePersistence
- DownloadProgressTracker
- ResumeDataManager

## Test Files to Create

### 1. SignLanguageTranslateTests/Downloads/BackgroundSessionManagerTests.swift

Test URLSession management:
- Session configuration is correct
- Task creation and tracking
- Pause with resume data
- Resume from data
- Cancel task
- Multiple concurrent tasks
- Background completion handler

### 2. SignLanguageTranslateTests/Downloads/DownloadEngineTests.swift

Test engine behavior:
- Start processing queue
- Respects max concurrent limit
- Pause all downloads
- Resume all downloads
- Stop engine
- Handles task completion
- Handles task failure
- Retries on retryable errors
- Doesn't retry non-retryable errors
- Engine state transitions

### 3. SignLanguageTranslateTests/Downloads/DownloadCoordinatorTests.swift

Test coordination:
- Starts downloads from queue
- Updates queue on progress
- Handles completion correctly
- Handles failure with resume data
- Moves files to correct location
- Cleans up temp files

### 4. SignLanguageTranslateTests/Downloads/DownloadFileManagerTests.swift

Test file operations:
- Move file to correct location
- Handle name conflicts
- Save resume data
- Load resume data
- Delete resume data
- Calculate available space
- Handle disk full scenario

### 5. SignLanguageTranslateTests/Downloads/DownloadStatePersistenceTests.swift

Test state persistence:
- Save state to file
- Load state from file
- Handle missing file
- Handle corrupted file
- Debounced saves
- Clear state

### 6. SignLanguageTranslateTests/Downloads/DownloadProgressTrackerTests.swift

Test progress tracking:
- Update single task progress
- Calculate overall progress
- Calculate download rate
- Estimate time remaining
- Handle completion
- Handle failure
- Reset tracking

### 7. SignLanguageTranslateTests/Downloads/ResumeDataManagerTests.swift

Test resume data:
- Save resume data
- Load resume data
- Check existence
- Delete resume data
- Cleanup orphaned data
- Calculate total size

### 8. SignLanguageTranslateTests/Downloads/DownloadIntegrationTests.swift

Integration tests:

```swift
class DownloadIntegrationTests: XCTestCase {
    var downloadManager: DownloadManager!
    var mockSession: MockURLSession!
    
    func test_fullDownloadFlow() async {
        // 1. Load manifest
        await downloadManager.loadINCLUDEManifest()
        
        // 2. Start downloads
        await downloadManager.startDownloads()
        
        // 3. Simulate progress
        mockSession.simulateProgress(0.5)
        
        // 4. Verify state
        XCTAssertEqual(downloadManager.activeCount, 3)
        
        // 5. Simulate completion
        mockSession.simulateComplete(taskIndex: 0)
        
        // 6. Verify file moved
        // 7. Verify next task started
    }
    
    func test_pauseAndResume() async { ... }
    func test_failureAndRetry() async { ... }
    func test_stateRecoveryAfterRelaunch() async { ... }
    func test_backgroundCompletion() async { ... }
}
```

### 9. SignLanguageTranslateTests/Mocks/MockURLSession.swift

Mock for testing without network:

```swift
class MockURLSession: URLSessionProtocol {
    var downloadTasks: [MockDownloadTask] = []
    var onTaskCreated: ((MockDownloadTask) -> Void)?
    
    func downloadTask(with url: URL) -> URLSessionDownloadTask {
        let task = MockDownloadTask(url: url)
        downloadTasks.append(task)
        onTaskCreated?(task)
        return task
    }
    
    // Simulation methods
    func simulateProgress(_ progress: Double, forTaskAt index: Int)
    func simulateComplete(forTaskAt index: Int, fileURL: URL)
    func simulateFailure(forTaskAt index: Int, error: Error)
}

class MockDownloadTask: URLSessionDownloadTask {
    var mockState: URLSessionTask.State = .suspended
    var resumeDataToReturn: Data?
    
    override func resume() { mockState = .running }
    override func suspend() { mockState = .suspended }
    override func cancel(byProducingResumeData: @escaping (Data?) -> Void) {
        byProducingResumeData(resumeDataToReturn)
    }
}
```

### 10. SignLanguageTranslateTests/Downloads/NetworkMonitorTests.swift

Test network monitoring:
- Detects connection type
- Notifies on disconnect
- Notifies on reconnect
- Handles WiFi to cellular switch

## Test Helpers

### TestDownloadHelpers.swift

```swift
extension XCTestCase {
    func createTestDownloadTask(
        status: DownloadTaskStatus = .pending,
        progress: Double = 0
    ) -> DownloadTask
    
    func createTestManifestEntry(
        category: String = "Animals",
        partNumber: Int = 1
    ) -> ManifestEntry
    
    func createTempFile(size: Int) -> URL
}
```

## Performance Tests

```swift
class DownloadPerformanceTests: XCTestCase {
    func test_queueProcessingPerformance() {
        measure {
            // Process queue with 100 tasks
        }
    }
    
    func test_statePersistencePerformance() {
        measure {
            // Save/load state with 100 tasks
        }
    }
    
    func test_progressCalculationPerformance() {
        measure {
            // Calculate progress for 46 tasks
        }
    }
}
```

## Requirements

1. All tests pass
2. No real network calls in unit tests
3. Use mocks/stubs appropriately
4. Test error cases thoroughly
5. Test edge cases (empty queue, all failed, etc.)
6. Integration tests cover main user flows
