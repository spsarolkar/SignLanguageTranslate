# App source guide

The app source lives in `SignLanguageTranslate/`. Xcode synchronizes that
source directory and picks up its Swift files automatically; do not add file
references to `project.pbxproj`. Source paths below are relative to that directory.

## Runtime path and ownership

| Stage | Entry points and owners |
| --- | --- |
| Startup | `App/SignLanguageTranslateApp.swift` creates the SwiftData container integration, download manager, extraction tracker, and shared batch extraction service; `AppDelegate` handles background URLSession wakeups |
| Navigation | `Features/DatasetManager/Views/MainNavigationView.swift` and `Views/Navigation/` implement sidebar → content → detail |
| Dataset actions | `Features/DatasetManager/DatasetDownloadActions.swift` shares download/import/extract/ingest actions across first-run and dataset detail |
| Download queue | `DownloadManager` is the UI facade; `DownloadEngine` schedules work; `DownloadCoordinator` executes lifecycle actions; `DownloadQueueActor` owns queue state; `BackgroundSessionManager` bridges URLSession callbacks |
| Archive extraction | `Features/DatasetManager/Extraction/` contains `ExtractionCoordinator`, `ZipExtractor`, and `MultiPartMerger` |
| Video ingestion | `Features/DatasetManager/Ingestion/` scans clips, extracts metadata, and shares category/word labels through `INCLUDEIngestionStrategy` |
| Feature extraction | `BatchExtractionService` coordinates the active batch UI; `VideoFeatureExtractionService`, `VisionPoseExtractor`, and `VisionHandExtractor` produce `FrameFeatures`; `FeatureFileManager` stores JSON |
| Feature inspection | `Features/Analysis/` contains analysis logic/charts; `Features/FeatureExtraction/Views/` contains pipeline, player, and keypoint views |
| Training and evaluation | `Features/Training/` implements the models, data pipeline, session manager, callbacks, persistence, and testing UI; see its [guide](../training/README.md) |
| Optional sync | `Features/Sync/` contains Hugging Face integration; `Training/Cloud/` contains R2 integration and run records |

`Core/` contains shared extensions, persistence queries/container setup,
Keychain, and system preflight utilities. Features may depend on Core.
`DesignSystem/` owns visual tokens and shared components. Preserve the
datasets/downloads/pipeline/training/settings navigation and use shared tokens
for view changes.

## Storage contracts

- `Documents/Datasets/` is the base for video relative paths and
  `Features/...` JSON paths. `VideoSample` and `FeatureSet` expose resolved URLs.
- SwiftData stores datasets, shared labels, video metadata, feature metadata,
  and training runs. A clip can have both category and word labels; never infer
  word identity from the first element of that relationship.
- Download state/resume data have their own persistence helpers under
  `DatasetManager/Downloads/`.
- Training currently uses both `Documents/Checkpoints/<run>/` and
  `Documents/Models/`. They are not yet one interchangeable artifact contract;
  see the review before changing or consuming checkpoints.
- `Core/Utilities/KeychainStore.swift` and existing sync Keychain helpers own
  secrets. UserDefaults may hold non-secret preferences, not tokens or keys.

Only main-actor code should use the view `ModelContext`. Background work needs
its own context or immutable value snapshots. Download queue mutations belong
to `DownloadQueueActor`. Existing concurrency violations and lock risks are
review findings, not patterns to copy.

## Cleanup policy

The feature folders already provide useful boundaries; this review preserves
them. Remove an alternate implementation only after checking declarations,
callers, tests, previews, and project configuration. Similar names alone do
not establish redundancy: the random fallback splitter and persisted
stratified splitter currently serve different paths.

Keep documentation outside the synchronized app/test trees. Xcode copies
Markdown there as resources; multiple module READMEs can produce duplicate
output filenames. The guides live under `docs/` to avoid that problem.

Root-level untracked Swift experiments, package experiments, archives, and logs
were present before this review. They are not part of the app target and were
left in place for their owner to assess. Keep new Swift work in the app or test
tree and new logs in `/tmp`.
