# Phase 4.3 — Progress Tracking and Persistence

Implement robust progress tracking that survives app restarts.

## Context

We have:
- DownloadEngine processing downloads
- DownloadQueueActor managing state
- BackgroundSessionManager for URLSession

Need to persist download state so we can:
- Resume after app termination
- Show accurate progress after relaunch
- Recover from crashes

## Files to Create

### 1. Features/DatasetManager/Downloads/DownloadStatePersistence.swift

Persist download queue state:

```swift
actor DownloadStatePersistence {
    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    
    init() {
        fileURL = FileManager.default.documentsDirectory
            .appendingPathComponent("download_state.json")
    }
    
    // Save current state
    func save(state: DownloadQueueState) async throws
    
    // Load saved state
    func load() async throws -> DownloadQueueState?
    
    // Clear saved state
    func clear() async throws
    
    // Auto-save with debouncing
    private var saveTask: Task<Void, Never>?
    func scheduleSave(state: DownloadQueueState)
}
```

### 2. Features/DatasetManager/Downloads/DownloadProgressTracker.swift

Track and aggregate progress:

```swift
@Observable
class DownloadProgressTracker {
    // Per-task progress
    private var taskProgress: [UUID: TaskProgress] = [:]
    
    struct TaskProgress {
        var bytesDownloaded: Int64
        var totalBytes: Int64
        var lastUpdate: Date
        var downloadRate: Double  // bytes per second
    }
    
    // Aggregated progress
    var overallProgress: Double
    var totalBytesDownloaded: Int64
    var totalBytesExpected: Int64
    var estimatedTimeRemaining: TimeInterval?
    var currentDownloadRate: Double  // bytes per second
    
    // Update methods
    func updateProgress(taskId: UUID, bytes: Int64, total: Int64)
    func taskCompleted(_ taskId: UUID)
    func taskFailed(_ taskId: UUID)
    func reset()
    
    // Calculate estimates
    private func calculateDownloadRate() -> Double
    private func calculateETA() -> TimeInterval?
}
```

### 3. Features/DatasetManager/Downloads/ResumeDataManager.swift

Manage resume data files:

```swift
struct ResumeDataManager {
    private let resumeDataDirectory: URL
    
    init() {
        resumeDataDirectory = FileManager.default.documentsDirectory
            .appendingPathComponent("resume_data")
        try? FileManager.default.createDirectory(at: resumeDataDirectory, 
                                                  withIntermediateDirectories: true)
    }
    
    // Save resume data for a task
    func save(_ data: Data, for taskId: UUID) throws
    
    // Load resume data
    func load(for taskId: UUID) throws -> Data?
    
    // Check if resume data exists
    func hasResumeData(for taskId: UUID) -> Bool
    
    // Delete resume data
    func delete(for taskId: UUID)
    
    // Clean up old/orphaned resume data
    func cleanupOrphaned(validTaskIds: Set<UUID>)
    
    // Get total size of resume data
    func totalSize() -> Int64
}
```

### 4. Update DownloadQueueActor

Add persistence integration:

```swift
extension DownloadQueueActor {
    // Called on significant state changes
    func persistState() async {
        let state = DownloadQueueState(
            tasks: Array(tasks.values),
            queueOrder: queue,
            isPaused: isPaused,
            exportedAt: Date()
        )
        try? await persistence.save(state: state)
    }
    
    // Called on app launch
    func restoreState() async {
        guard let state = try? await persistence.load() else { return }
        await importState(state)
        
        // Restore resume data paths
        for task in tasks.values where task.status == .paused {
            if resumeDataManager.hasResumeData(for: task.id) {
                // Task can be resumed
            }
        }
    }
}
```

### 5. Update DownloadManager

Add recovery on init:

```swift
extension DownloadManager {
    func recoverDownloads() async {
        // 1. Load persisted state
        await queue.restoreState()
        
        // 2. Check for background session tasks
        let backgroundTasks = await sessionManager.getPendingTasks()
        
        // 3. Reconcile background tasks with queue
        await reconcileBackgroundTasks(backgroundTasks)
        
        // 4. Update UI
        await refresh()
    }
    
    private func reconcileBackgroundTasks(_ tasks: [URLSessionDownloadTask]) async {
        // Match background tasks with our queue
        // Update progress for any that completed while suspended
    }
}
```

### 6. Features/DatasetManager/Downloads/DownloadHistory.swift

Track download history for analytics:

```swift
struct DownloadHistoryEntry: Codable {
    let taskId: UUID
    let url: URL
    let category: String
    let startedAt: Date
    let completedAt: Date?
    let bytesDownloaded: Int64
    let success: Bool
    let errorMessage: String?
}

actor DownloadHistory {
    private var entries: [DownloadHistoryEntry] = []
    private let maxEntries = 1000
    
    func record(_ entry: DownloadHistoryEntry)
    func getHistory(limit: Int) -> [DownloadHistoryEntry]
    func clearHistory()
    func exportToJSON() -> Data
}
```

## State Recovery Flow

```
App Launch:
1. DownloadManager.init()
2. recoverDownloads()
3. Load persisted queue state
4. Check URLSession for pending/completed tasks
5. Reconcile states
6. Resume any interrupted downloads
7. Update UI

App Background:
1. Save current state
2. URLSession continues in background
3. System may terminate app

App Terminated by System:
1. URLSession completes downloads
2. System relaunches app (handleEventsForBackgroundURLSession)
3. recoverDownloads() called
4. Process completed downloads
5. Update database
```

## Requirements

1. State persists across app launches
2. No data loss on crash
3. Background downloads reconciled correctly
4. Resume data properly managed
5. Progress estimation is reasonably accurate
6. History kept for debugging/analytics
