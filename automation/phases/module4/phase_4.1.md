# Phase 4.1 — Background URLSession Configuration

Set up background download capabilities using URLSession background configuration.

## Context

We have:
- DownloadManager and DownloadQueueActor for state management
- DownloadTask model for tracking downloads
- UI components for displaying progress

Now we need actual networking with background download support so downloads continue when app is suspended.

## Files to Create

### 1. Features/DatasetManager/Downloads/BackgroundSessionManager.swift

Singleton manager for background URLSession:

```swift
final class BackgroundSessionManager: NSObject {
    static let shared = BackgroundSessionManager()
    
    private let sessionIdentifier = "com.signlanguage.translate.background-downloads"
    
    private(set) lazy var session: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: sessionIdentifier)
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        config.allowsConstrainedNetworkAccess = true
        config.allowsExpensiveNetworkAccess = true
        
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()
    
    // Completion handler for background events
    var backgroundCompletionHandler: (() -> Void)?
    
    // Active download tasks mapped by URL
    private var activeDownloads: [URL: URLSessionDownloadTask] = [:]
    
    // Methods
    func startDownload(url: URL, taskId: UUID) -> URLSessionDownloadTask
    func pauseDownload(taskId: UUID) async -> Data?  // Returns resume data
    func resumeDownload(resumeData: Data, taskId: UUID) -> URLSessionDownloadTask
    func cancelDownload(taskId: UUID)
    func cancelAllDownloads()
}
```

### 2. BackgroundSessionManager+URLSessionDelegate

Implement delegate methods:

```swift
extension BackgroundSessionManager: URLSessionDelegate {
    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        DispatchQueue.main.async {
            self.backgroundCompletionHandler?()
            self.backgroundCompletionHandler = nil
        }
    }
}
```

### 3. BackgroundSessionManager+DownloadDelegate

Implement download delegate:

```swift
extension BackgroundSessionManager: URLSessionDownloadDelegate {
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, 
                    didFinishDownloadingTo location: URL) {
        // Move file to permanent location
        // Notify DownloadManager
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        // Update progress
        // Notify DownloadManager
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, 
                    didCompleteWithError error: Error?) {
        // Handle completion or error
        // Save resume data if available
    }
}
```

### 4. Features/DatasetManager/Downloads/DownloadCoordinator.swift

Coordinator between BackgroundSessionManager and DownloadManager:

```swift
actor DownloadCoordinator {
    private let sessionManager = BackgroundSessionManager.shared
    private let queue: DownloadQueueActor
    private let fileManager: DownloadFileManager
    
    // Start next pending download if under limit
    func processQueue() async
    
    // Handle download completion
    func handleDownloadComplete(taskId: UUID, fileURL: URL) async
    
    // Handle download failure
    func handleDownloadFailed(taskId: UUID, error: Error, resumeData: Data?) async
    
    // Handle progress update
    func handleProgressUpdate(taskId: UUID, bytesWritten: Int64, totalBytes: Int64) async
}
```

### 5. Features/DatasetManager/Downloads/DownloadFileManager.swift

File operations for downloads:

```swift
struct DownloadFileManager {
    let downloadsDirectory: URL
    let datasetsDirectory: URL
    
    // Move completed download to appropriate location
    func moveCompletedDownload(from tempURL: URL, for task: DownloadTask) throws -> URL
    
    // Get/set resume data path
    func saveResumeData(_ data: Data, for taskId: UUID) throws -> URL
    func loadResumeData(for taskId: UUID) throws -> Data?
    func deleteResumeData(for taskId: UUID)
    
    // Storage queries
    func availableStorageSpace() -> Int64
    func downloadedFileSize(for task: DownloadTask) -> Int64?
}
```

### 6. Update App/AppDelegate.swift

Handle background session events:

```swift
class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     handleEventsForBackgroundURLSession identifier: String,
                     completionHandler: @escaping () -> Void) {
        BackgroundSessionManager.shared.backgroundCompletionHandler = completionHandler
    }
}
```

### 7. Update App/SignLanguageTranslateApp.swift

Configure app delegate:

```swift
@main
struct SignLanguageTranslateApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    // ...
}
```

## Requirements

1. Downloads must continue when app is backgrounded
2. Downloads must resume after app termination
3. Proper handling of resume data for paused downloads
4. Progress updates even from background
5. Storage space validation before starting downloads
6. Proper cleanup of temporary files
