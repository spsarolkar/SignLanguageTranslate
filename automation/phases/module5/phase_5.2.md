# Phase 5.2 — Video File Ingestion

Create VideoSample records from extracted video files.

## Context

We have:
- Extracted video files organized by category
- VideoSample SwiftData model
- Label model for categories and words
- String extension for sanitizing label names (e.g., "12. Dog" → "Dog")

## Files to Create

### 1. Features/DatasetManager/Ingestion/VideoIngestionService.swift

Main ingestion service:

```swift
actor VideoIngestionService {
    private let modelContext: ModelContext
    
    struct IngestionResult {
        let samplesCreated: Int
        let labelsCreated: Int
        let categoriesCreated: Int
        let errors: [IngestionError]
        let duration: TimeInterval
    }
    
    struct IngestionError {
        let filePath: String
        let error: Error
    }
    
    // Progress callback
    var onProgress: ((IngestionProgress) -> Void)?
    
    struct IngestionProgress {
        let currentFile: String
        let filesProcessed: Int
        let totalFiles: Int
        let progress: Double
    }
    
    // Ingest all videos from dataset directory
    func ingestDataset(
        name: String,
        type: DatasetType,
        directory: URL
    ) async throws -> IngestionResult
    
    // Ingest single category
    func ingestCategory(
        name: String,
        directory: URL,
        datasetName: String
    ) async throws -> Int  // Returns sample count
    
    // Create or find label
    private func findOrCreateLabel(
        name: String,
        type: LabelType
    ) -> Label
}
```

### 2. Features/DatasetManager/Ingestion/VideoFileScanner.swift

Scan directories for video files:

```swift
struct VideoFileScanner {
    // Supported extensions
    static let supportedExtensions = ["mp4", "mov", "m4v", "avi"]
    
    struct ScannedFile {
        let url: URL
        let category: String
        let wordLabel: String  // Parsed from filename/folder
        let fileSize: Int64
    }
    
    // Scan dataset directory
    static func scan(directory: URL) throws -> [ScannedFile]
    
    // Scan single category directory
    static func scanCategory(
        directory: URL,
        categoryName: String
    ) throws -> [ScannedFile]
    
    // Parse word label from file path
    // e.g., "Animals/12. Dog/video1.mp4" → "Dog"
    static func parseWordLabel(from url: URL, category: String) -> String
}
```

### 3. Features/DatasetManager/Ingestion/VideoMetadataExtractor.swift

Extract video metadata:

```swift
import AVFoundation

struct VideoMetadataExtractor {
    struct VideoMetadata {
        let duration: TimeInterval
        let dimensions: CGSize
        let frameRate: Float
        let codec: String?
        let fileSize: Int64
    }
    
    // Extract metadata from video file
    static func extract(from url: URL) async throws -> VideoMetadata
    
    // Extract thumbnail
    static func extractThumbnail(
        from url: URL,
        at time: TimeInterval = 0
    ) async throws -> CGImage?
}
```

### 4. Features/DatasetManager/Ingestion/INCLUDEIngestionStrategy.swift

Specific strategy for INCLUDE dataset:

```swift
struct INCLUDEIngestionStrategy {
    // INCLUDE structure:
    // Category/
    //   Word (numbered)/
    //     video files
    
    // Parse category from path
    static func parseCategory(from url: URL, baseURL: URL) -> String?
    
    // Parse word label from path
    // "12. Dog" → "Dog"
    static func parseWordLabel(from url: URL) -> String?
    
    // Validate INCLUDE directory structure
    static func validateStructure(_ directory: URL) -> Bool
    
    // Get expected categories
    static let expectedCategories = [
        "Adjectives", "Animals", "Clothes", "Colours",
        "Days_and_Time", "Electronics", "Greetings", "Home",
        "Jobs", "Means_of_Transportation", "People", "Places",
        "Pronouns", "Seasons", "Society"
    ]
}
```

### 5. Features/DatasetManager/Ingestion/ISLCSLTRIngestionStrategy.swift

Strategy for ISL-CSLTR dataset:

```swift
struct ISLCSLTRIngestionStrategy {
    // ISL-CSLTR structure:
    // Sentence videos at root or organized differently
    
    // Parse sentence from filename or metadata
    static func parseSentence(from url: URL) -> String?
    
    // This dataset has sentences, not word-level labels
    static func createSentenceLabel(
        text: String,
        context: ModelContext
    ) -> Label
}
```

### 6. Update VideoSample Model

Add ingestion-related methods:

```swift
extension VideoSample {
    // Create from scanned file
    static func create(
        from file: VideoFileScanner.ScannedFile,
        metadata: VideoMetadataExtractor.VideoMetadata?,
        in context: ModelContext
    ) -> VideoSample
    
    // Update metadata
    func updateMetadata(_ metadata: VideoMetadataExtractor.VideoMetadata)
}
```

### 7. Features/DatasetManager/Ingestion/IngestionProgressTracker.swift

Track ingestion progress:

```swift
@Observable
class IngestionProgressTracker {
    private(set) var status: Status = .idle
    private(set) var currentCategory: String?
    private(set) var filesProcessed: Int = 0
    private(set) var totalFiles: Int = 0
    private(set) var samplesCreated: Int = 0
    private(set) var errors: [String] = []
    
    enum Status {
        case idle
        case scanning
        case ingesting
        case completed
        case failed
    }
    
    var progress: Double {
        guard totalFiles > 0 else { return 0 }
        return Double(filesProcessed) / Double(totalFiles)
    }
}
```

## Ingestion Flow

```
1. Extraction completes
2. Scan dataset directory for video files
3. For each category:
   a. Find/create category Label
   b. Scan word subdirectories
   c. For each word:
      - Parse word name (sanitize "12. Dog" → "Dog")
      - Find/create word Label
      - For each video file:
        * Extract metadata (duration, size)
        * Create VideoSample record
        * Link to category and word Labels
4. Update Dataset with counts
5. Report completion
```

## Label Hierarchy for INCLUDE

```
Category Label (type: .category)
  └── Word Label (type: .word)
       └── VideoSample (links to both)

Example:
- Animals (category)
  - Dog (word)
    - video1.mp4, video2.mp4, ...
  - Cat (word)
    - video1.mp4, video2.mp4, ...
```

## Requirements

1. Use String.sanitizedLabel() for label names
2. Create labels idempotently (find or create)
3. Handle duplicate filenames
4. Extract video duration for UI
5. Track progress for UI updates
6. Handle errors gracefully (skip bad files)
7. Batch database saves for performance
