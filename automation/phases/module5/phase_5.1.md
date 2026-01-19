# Phase 5.1 — Zip Extraction System

Implement zip extraction for `DownloadTask`s. Uses `ZIPFoundation`.

## Files to Create

### 1. `Features/DatasetManager/Extraction/ZipExtractor.swift`
- **Actor** `ZipExtractor`
- `func extract(zipURL: URL, to destinationURL: URL, overwrite: Bool = false) async throws -> [URL]`
- `func extractMultiPart(zipURLs: [URL], to destinationURL: URL) async throws -> [URL]`
- `func listContents(of zipURL: URL) throws -> [String]`
- `func cancel()`
- Support progress tracking via closure `((ExtractionProgress) -> Void)?`.

### 2. `Features/DatasetManager/Extraction/ExtractionCoordinator.swift`
- **Actor** `ExtractionCoordinator`
- Coordinates single/multi-part extraction logic.
- `func extractDataset(datasetName: String, downloadedFiles: [URL]) async throws -> ExtractionResult`
- `func groupByCategory(_ files: [URL]) -> [String: [URL]]`
- `func mergeMultiPartCategory(category: String, parts: [URL], destination: URL) async throws -> URL`

### 3. `Features/DatasetManager/Extraction/MultiPartMerger.swift`
- Helper struct for detecting and sorting multi-part zips (e.g. `Animals_1of2.zip`).
- `static let multiPartPattern = /(.+)_(\d+)of(\d+)\.zip$/`
- `static func groupParts(_ files: [URL]) -> [String: [PartInfo]]`
- `static func validateParts(_ parts: [PartInfo]) -> Bool`

### 4. `Features/DatasetManager/Extraction/ExtractionProgressTracker.swift`
- `@Observable class ExtractionProgressTracker`: Tracks overall dataset extraction progress.
- Properties: `overallProgress`, `currentCategory`, `filesExtracted`, `status`.

## Updates
- **DownloadTask.swift**: Add `status = .extracting` case.

## Flow
1. Download completes.
2. `DownloadManager` hands off file list to `ExtractionCoordinator`.
3. `Coordinator` groups files (hanlding multi-part logic).
4. `ZipExtractor` extracts each group to `datasets/DatasetName/CategoryName`.
5. Update progress UI throughout.
