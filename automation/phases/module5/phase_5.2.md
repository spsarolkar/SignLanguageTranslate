# Phase 5.2 — Video File Ingestion

Populate SwiftData with `VideoSample` records from extracted files.

## Files to Create

### 1. `Features/DatasetManager/Ingestion/VideoIngestionService.swift`
- **Actor** `VideoIngestionService`
- `func ingestDataset(name: String, type: DatasetType, directory: URL) async throws -> IngestionResult`
- `func ingestCategory(name: String, directory: URL, datasetName: String) async throws -> Int`
- Manages `ModelContext` to create `Label` and `VideoSample` records.

### 2. `Features/DatasetManager/Ingestion/VideoFileScanner.swift`
- Scans directories for `.mp4`, `.mov`, etc.
- `static func scan(directory: URL) throws -> [ScannedFile]`
- `static func scanCategory(directory: URL, categoryName: String) throws -> [ScannedFile]`
- `struct ScannedFile { url, category, wordLabel, fileSize }`

### 3. `Features/DatasetManager/Ingestion/VideoMetadataExtractor.swift`
- Uses `AVAsset` to get metadata.
- `static func extract(from url: URL) async throws -> VideoMetadata { duration, dimensions, frameRate }`
- `static func extractThumbnail(from url: URL) async throws -> CGImage?`

### 4. `Features/DatasetManager/Ingestion/DatasetIngestionStrategy.swift`
- Protocol/Structs for dataset-specific parsing logic (INCLUDE vs ISL-CSLTR).
- `INCLUDE`: `Category/Word/video.mp4`.
- `ISL-CSLTR`: Sentence level parsing.

### 5. `Features/DatasetManager/Ingestion/IngestionProgressTracker.swift`
- `@Observable class`: Tracks files processed vs total.

## Updates
- **VideoSample.swift**: Add factory method `create(from: ScannedFile, metadata: ...)`

## Flow
1. Extraction completes.
2. `Scanner` lists all video files.
3. `IngestionService` iterates files:
   - Gets Metadata.
   - Creates/Links `Label` (Category & Word).
   - Creates `VideoSample`.
4. Saves to SwiftData in batches.
