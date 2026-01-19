# Phase 5.3 — Extraction UI & Integration

Integrate Extraction/Ingestion into the main UI loop.

## Files to Create

### 1. Progress Components
Create reusable progress views in `Features/DatasetManager/Views/Components/`:
- **`ExtractionProgressView.swift`**: Shows unzip progress (files/bytes) + current category.
- **`IngestionProgressView.swift`**: Shows DB import progress (samples created) + errors.
- **`DatasetProcessingView.swift`**: High-level stepper view showing the 3 phases: Download -> Extract -> Ingest.

### 2. `Features/DatasetManager/Processing/DatasetProcessor.swift`
- **Orchestrator Class** (`@Observable`)
- Manages the full pipeline state.
- `func processDataset(_ dataset: Dataset) async`
  1. **Download**: `DownloadManager.startDownloads()` -> wait for completion.
  2. **Extract**: `ExtractionCoordinator.extractDataset()`.
  3. **Ingest**: `VideoIngestionService.ingestDataset()`.
  4. **Complete**: Update `Dataset` status to `.ready`.

### 3. Updates
- **`DatasetDetailView.swift`**: Show `DatasetProcessingView` when `dataset.processingState` is active.
- **`Dataset.swift`**: Add `processingState` enum (Download/Extract/Ingest/Ready).

## Integration Flow
1. User clicks "Download".
2. `DatasetProcessor` starts.
3. UI switches to `DatasetProcessingView`.
4. Processor runs phases sequentially.
5. On success, UI shows "Ready" and enables "Browse Samples".
