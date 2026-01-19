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

### 1. `SignLanguageTranslateTests/Downloads/BackgroundSessionManagerTests.swift`

Test URLSession management:
*   **Session Config**: Verify identifier and background settings.
*   **Tasks**: Test `startDownload`, `cancelDownload`, and concurrent tasks.
*   **State**: Verify `activeDownloadCount` and `isDownloading` tracking.
*   **Callbacks**: Ensure progress and completion delegates are called.

### 2. `SignLanguageTranslateTests/Downloads/DownloadEngineTests.swift`

Test engine behavior:
*   **Control**: `start`, `pause`, `stop`, `resume`.
*   **Concurrency**: Ensure it respects `maxConcurrentDownloads`.
*   **Retry**: Verify retry logic for retryable vs non-retryable errors.
*   **State**: Test state transitions (e.g. paused -> running).

### 3. `SignLanguageTranslateTests/Downloads/DownloadCoordinatorTests.swift`

Test coordination between engine and file manager:
*   **Flow**: Start -> Progress -> Complete -> File Move.
*   **Failure**: Handling failures and resume data.
*   **Cleanup**: Removing temp files on completion.

### 4. `SignLanguageTranslateTests/Downloads/DownloadFileManagerTests.swift`

Test file operations:
*   **Move**: Moving files from temp to permanent locations.
*   **Resume Data**: saving, loading, and deleting resume blobs.
*   **Storage**: Space calculation and handling disk full scenarios.

### 5. `SignLanguageTranslateTests/Downloads/DownloadStatePersistenceTests.swift`

Test state persistence:
*   **CRUD**: Save and load full queue state.
*   **Edge Cases**: Missing file, corrupted data.
*   **Debounce**: Verify saves are not triggered too frequently.

### 6. `SignLanguageTranslateTests/Downloads/DownloadIntegrationTests.swift`

Integration tests covering the full flow (mocking only the network):
1.  **Full Flow**: Load manifest -> Start -> Simulate Progress -> Simulate Completion -> Verify File Exists.
2.  **Pause/Resume**: Start -> Pause -> Verify State -> Resume -> Complete.
3.  **Failure/Retry**: Start -> Simulate Error -> Verify Retry Scheduled -> Retry -> Complete.
4.  **Recovery**: Save state -> Re-instantiate Manager -> assert state restored.

### 7. `SignLanguageTranslateTests/Mocks/MockURLSession.swift` (and helpers)

Create necessary mocks:
*   `MockURLSession` & `MockDownloadTask`: Intercept network calls to simulate progress, completion, and errors without real network.
*   `TestHelpers.swift`: Factory methods for creating test tasks and manifest entries.

## Performance Tests (Optional)

*   Measure queue processing speed.
*   Measure state save/load times with large queues.

## Requirements

1.  All tests must pass.
2.  **No real network calls** in unit tests (use mocks).
3.  Test error scenarios thoroughly (404, 500, disk full).
4.  Integration tests must verify the end-to-end file persistence.
