# Phase 4.2 — Download Engine Implementation

Implement the core download engine that processes the queue.

## Context

We have:
- BackgroundSessionManager for URLSession handling
- DownloadCoordinator for orchestration
- DownloadQueueActor for state
- DownloadFileManager for file operations

## Files to Create/Update

### 1. Features/DatasetManager/Downloads/DownloadEngine.swift

Main download engine:

```swift
@Observable
final class DownloadEngine {
    private let coordinator: DownloadCoordinator
    private let queue: DownloadQueueActor
    private let sessionManager: BackgroundSessionManager
    
    // Observable state
    private(set) var isRunning = false
    private(set) var isPaused = false
    
    // Configuration
    let maxConcurrentDownloads: Int
    
    init(maxConcurrentDownloads: Int = 3) {
        // Initialize with queue and coordinator
    }
    
    // Control methods
    func start() async
    func pause() async
    func resume() async
    func stop() async
    
    // Queue processing
    private func processQueue() async
    private func startNextDownload() async -> Bool
    
    // Event handlers
    func handleDownloadProgress(taskId: UUID, bytes: Int64, total: Int64) async
    func handleDownloadComplete(taskId: UUID, fileURL: URL) async
    func handleDownloadFailed(taskId: UUID, error: Error, resumeData: Data?) async
}
```

### 2. Update BackgroundSessionManager

Add callback system:

```swift
extension BackgroundSessionManager {
    // Callback closures
    var onProgress: ((UUID, Int64, Int64) -> Void)?
    var onComplete: ((UUID, URL) -> Void)?
    var onFailed: ((UUID, Error, Data?) -> Void)?
    
    // Task ID tracking
    private var taskIdMap: [Int: UUID] = [:]  // URLSessionTask.taskIdentifier -> our UUID
    
    func startDownload(url: URL, taskId: UUID) -> URLSessionDownloadTask {
        let task = session.downloadTask(with: url)
        taskIdMap[task.taskIdentifier] = taskId
        task.resume()
        return task
    }
}
```

### 3. Features/DatasetManager/Downloads/DownloadEngineDelegate.swift

Protocol for engine events:

```swift
protocol DownloadEngineDelegate: AnyObject, Sendable {
    func downloadEngine(_ engine: DownloadEngine, didUpdateTask task: DownloadTask)
    func downloadEngine(_ engine: DownloadEngine, didCompleteTask task: DownloadTask)
    func downloadEngine(_ engine: DownloadEngine, didFailTask task: DownloadTask, error: Error)
    func downloadEngineDidFinishAllTasks(_ engine: DownloadEngine)
}
```

### 4. Update DownloadManager

Connect to engine:

```swift
@Observable
final class DownloadManager {
    private let engine: DownloadEngine
    private let queue: DownloadQueueActor
    
    // Observed state (from queue)
    var tasks: [DownloadTask] = []
    var isDownloading: Bool { engine.isRunning && !engine.isPaused }
    
    // Control
    func startDownloads() async {
        await engine.start()
    }
    
    func pauseAllDownloads() async {
        await engine.pause()
    }
    
    // Single task control
    func pauseTask(_ id: UUID) async {
        // Pause specific task, save resume data
    }
    
    func resumeTask(_ id: UUID) async {
        // Resume with saved resume data
    }
    
    func cancelTask(_ id: UUID) async {
        // Cancel and remove from queue
    }
}
```

### 5. Error Handling

Create download-specific errors:

```swift
enum DownloadError: LocalizedError {
    case insufficientStorage(required: Int64, available: Int64)
    case networkUnavailable
    case invalidURL(URL)
    case fileMoveFailed(underlying: Error)
    case resumeDataCorrupted
    case serverError(statusCode: Int)
    case timeout
    case cancelled
    
    var errorDescription: String? { ... }
    var recoverySuggestion: String? { ... }
    var isRetryable: Bool { ... }
}
```

### 6. Network Monitoring

Add network status monitoring:

```swift
import Network

class NetworkMonitor {
    static let shared = NetworkMonitor()
    
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitor")
    
    @Published private(set) var isConnected = true
    @Published private(set) var connectionType: ConnectionType = .unknown
    
    enum ConnectionType {
        case wifi, cellular, ethernet, unknown
    }
    
    func start()
    func stop()
}
```

## Download Flow

```
1. User taps "Download INCLUDE"
2. DownloadManager.startDatasetDownload(INCLUDE)
3. Creates 46 DownloadTasks from manifest
4. Enqueues all tasks to DownloadQueueActor
5. Starts DownloadEngine
6. Engine processes queue:
   - Gets next pending task (max 3 concurrent)
   - Starts URLSession download task
   - Updates progress via delegate callbacks
   - On complete: moves file, marks task complete
   - On error: saves resume data, marks failed
   - Repeats until queue empty
7. Updates UI via DownloadManager observation
```

## Requirements

1. Respect max concurrent download limit
2. Handle all error cases gracefully
3. Automatic retry for retryable errors (up to 3 times)
4. Save resume data on pause/failure
5. Clean up on cancel
6. Network monitoring to pause on disconnect
