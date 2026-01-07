# Phase 5.1 — Zip Extraction System

Implement zip file extraction for downloaded dataset files.

## Context

We have:
- Downloaded zip files in the downloads directory
- INCLUDE dataset has 46 zip files (some multi-part)
- Need to extract and organize video files
- Some categories have multiple parts that need merging

## Files to Create

### 1. Features/DatasetManager/Extraction/ZipExtractor.swift

Core extraction functionality:

```swift
import Foundation
import ZIPFoundation  // or use built-in compression

actor ZipExtractor {
    enum ExtractionError: LocalizedError {
        case fileNotFound(URL)
        case invalidZipFile(URL)
        case extractionFailed(underlying: Error)
        case insufficientSpace(required: Int64, available: Int64)
        case cancelled
        
        var errorDescription: String? { ... }
    }
    
    struct ExtractionProgress {
        let currentFile: String
        let filesExtracted: Int
        let totalFiles: Int
        let bytesExtracted: Int64
        let totalBytes: Int64
        
        var progress: Double {
            guard totalFiles > 0 else { return 0 }
            return Double(filesExtracted) / Double(totalFiles)
        }
    }
    
    // Progress callback
    var onProgress: ((ExtractionProgress) -> Void)?
    
    // Extract single zip file
    func extract(
        zipURL: URL,
        to destinationURL: URL,
        overwrite: Bool = false
    ) async throws -> [URL]
    
    // Extract and merge multi-part zips
    func extractMultiPart(
        zipURLs: [URL],
        to destinationURL: URL
    ) async throws -> [URL]
    
    // List contents without extracting
    func listContents(of zipURL: URL) throws -> [String]
    
    // Cancel current extraction
    func cancel()
}
```

### 2. Features/DatasetManager/Extraction/ExtractionCoordinator.swift

Coordinate extraction for entire dataset:

```swift
actor ExtractionCoordinator {
    private let extractor = ZipExtractor()
    private let fileManager = FileManager.default
    
    struct CategoryExtraction {
        let category: String
        let zipFiles: [URL]  // May be multiple parts
        let destinationURL: URL
        var status: ExtractionStatus
    }
    
    enum ExtractionStatus {
        case pending
        case extracting(progress: Double)
        case completed(fileCount: Int)
        case failed(Error)
    }
    
    // Extract all zip files for a dataset
    func extractDataset(
        datasetName: String,
        downloadedFiles: [URL]
    ) async throws -> ExtractionResult
    
    // Group zip files by category
    func groupByCategory(_ files: [URL]) -> [String: [URL]]
    
    // Handle multi-part files (Animals_1of2.zip, Animals_2of2.zip)
    func mergeMultiPartCategory(
        category: String,
        parts: [URL],
        destination: URL
    ) async throws -> URL
}
```

### 3. Features/DatasetManager/Extraction/MultiPartMerger.swift

Handle multi-part zip files:

```swift
struct MultiPartMerger {
    // Pattern to detect multi-part files
    static let multiPartPattern = /(.+)_(\d+)of(\d+)\.zip$/
    
    struct PartInfo {
        let category: String
        let partNumber: Int
        let totalParts: Int
        let fileURL: URL
    }
    
    // Parse filename for part info
    static func parsePartInfo(from url: URL) -> PartInfo?
    
    // Group files by category
    static func groupParts(_ files: [URL]) -> [String: [PartInfo]]
    
    // Validate all parts present
    static func validateParts(_ parts: [PartInfo]) -> Bool
    
    // Sort parts in order
    static func sortParts(_ parts: [PartInfo]) -> [PartInfo]
}
```

### 4. Features/DatasetManager/Extraction/ExtractionProgress.swift

Progress tracking:

```swift
@Observable
class ExtractionProgressTracker {
    // Overall progress
    private(set) var overallProgress: Double = 0
    private(set) var currentCategory: String?
    private(set) var categoriesCompleted: Int = 0
    private(set) var totalCategories: Int = 0
    
    // Current file progress
    private(set) var currentFileProgress: Double = 0
    private(set) var currentFileName: String?
    
    // Statistics
    private(set) var filesExtracted: Int = 0
    private(set) var bytesExtracted: Int64 = 0
    
    // Status
    private(set) var status: ExtractionStatus = .idle
    
    enum ExtractionStatus {
        case idle
        case preparing
        case extracting
        case merging
        case completed
        case failed(Error)
    }
    
    func update(category: String, progress: Double)
    func categoryCompleted(_ category: String)
    func setFailed(_ error: Error)
    func reset()
}
```

### 5. Update DownloadTask for Extraction

Add extraction state:

```swift
extension DownloadTaskStatus {
    // Add extracting case if not present
    case extracting
}

extension DownloadTask {
    // Track extraction progress separately
    var extractionProgress: Double
    var isExtracting: Bool { status == .extracting }
}
```

### 6. Features/DatasetManager/Extraction/ZipValidation.swift

Validate zip files before extraction:

```swift
struct ZipValidator {
    // Validate zip file integrity
    static func validate(_ url: URL) throws -> Bool
    
    // Get uncompressed size
    static func uncompressedSize(of url: URL) throws -> Int64
    
    // Check for zip bomb (excessive compression ratio)
    static func isSafe(_ url: URL, maxRatio: Double = 100) throws -> Bool
    
    // Validate contents match expected structure
    static func validateStructure(
        _ url: URL,
        expectedPattern: String
    ) throws -> Bool
}
```

## Extraction Flow

```
1. Download completes (e.g., Animals_1of2.zip)
2. Mark task as "extracting"
3. Wait for all parts (if multi-part)
4. Validate zip files
5. Extract to temp directory
6. Merge multi-part extractions
7. Move to final dataset directory
8. Clean up zip files
9. Mark task as "completed"
```

## Directory Structure After Extraction

```
datasets/
└── INCLUDE/
    ├── Animals/
    │   ├── video1.mp4
    │   ├── video2.mp4
    │   └── ...
    ├── Adjectives/
    │   └── ...
    └── ... (15 categories total)
```

## Requirements

1. Handle multi-part zip files correctly
2. Show extraction progress
3. Clean up temp files on failure
4. Validate before extraction
5. Respect storage constraints
6. Support cancellation
