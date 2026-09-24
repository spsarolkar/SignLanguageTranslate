# Fix failing tests

**Goal:** clear the failures recorded in `docs/status.md`. For each one,
decide whether the test or the code is wrong, and fix only that side.

Decisions (2026-09-24, user):
- Label cleaning strips a leading number only when a dot follows it (`12. Dog` → `Dog`,
  `123` → `123`).
- Sizes use decimal units (`ByteCountFormatter` `.file`, as in the Files app).
- `DownloadTask` keeps value equality (all fields), not ID-only.
- ~~Resume data saved on failure is kept, so a retry resumes.~~ Revised: retry is
  designed to restart from zero (`retryTask` deletes resume data and resets), so
  failure now discards resume data and the coordinator test expects that.

## Tests wrong
- [x] Manifest (12): Zenodo record 4010759 has 44 zips + README.md + download_data.sh = 46
      files. Tests expect 44 zips, `Seasons_1of1.zip`, and `/content` URLs.
- [x] `DownloadTaskStatusTests.test_stateTransitionLogic_terminalStatusesCannotStart`:
      `.failed` is terminal but can be retried (other tests assert this).
- [x] `DownloadQueueActorTests.test_exportState_producesValidJSON`: decode with
      `DownloadQueueState.fromData` (ISO 8601 dates).
- [x] `DownloadQueueActorTests.test_persistenceRoundTrip_preservesAllData`: expect the
      status after `pauseAll()`.
- [x] `ResumeDataManagerTests.test_fileURL_returnsCorrectPath`: trailing-slash URL compare.
- [x] `BackgroundSessionManagerTests.test_resumeDownload_*` (2): real background session
      with fake resume data fails at once; don't assert `isDownloading`.
- [x] `DownloadTaskTests` equality/hash (2): value equality is intended.
- [x] `FileManagerExtensionsTests.testFormattedSize`: decimal units.

## Code wrong
- [x] `sanitizedLabel`: require the dot (3 tests).
- [x] `FileManager.formattedSize`: negative → "Zero KB".
- [x] `ResumeDataManager.isValidResumeData`: 50-byte prefix misses "plist" in an XML header.
- [x] `DownloadTask.updateProgress`: server-reported size must replace the estimate.
- [x] Resume data on failure: `handleDownloadFailed` discards it (see decisions).

## Investigate
- [x] `DownloadPerformanceTests` (2): SIGABRT in `DownloadProgressTracker` deinit.
      *Fixed with `nonisolated deinit {}`.*
- [x] `SignLanguageModelTests.testModelInitializationT5*` (2): SIGABRT; MLX on Simulator?
      *Yes (mlx-swift docs). Skipped on Simulator; weight-shape assertion fixed.
      Not yet run on device.*
- [ ] `DownloadIntegrationTests.test_pauseSingleTask`, `test_queueProcessesNextTaskAfterCompletion`:
      intermittent. *Still open: the engine always uses `BackgroundSessionManager.shared`
      and real URLs (the test's `MockURLSession` is never injected), so results
      depend on network timing. Fixing needs a session-injection seam in
      DownloadEngine/Coordinator — a download refactor, needs its own go-ahead.*

Done when: full suite run, `docs/status.md` updated with what remains and why.
