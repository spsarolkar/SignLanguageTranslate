# Fix failing tests

**Goal:** clear the failures recorded in `docs/status.md`. For each one,
decide whether the test or the code is wrong, and fix only that side.

Decisions (2026-09-24, user):
- Label cleaning strips a leading number only when a dot follows it (`12. Dog` → `Dog`,
  `123` → `123`).
- Sizes use decimal units (`ByteCountFormatter` `.file`, as in the Files app).
- `DownloadTask` keeps value equality (all fields), not ID-only.
- Resume data saved on failure is kept, so a retry resumes.

## Tests wrong
- [ ] Manifest (12): Zenodo record 4010759 has 44 zips + README.md + download_data.sh = 46
      files. Tests expect 44 zips, `Seasons_1of1.zip`, and `/content` URLs.
- [ ] `DownloadTaskStatusTests.test_stateTransitionLogic_terminalStatusesCannotStart`:
      `.failed` is terminal but can be retried (other tests assert this).
- [ ] `DownloadQueueActorTests.test_exportState_producesValidJSON`: decode with
      `DownloadQueueState.fromData` (ISO 8601 dates).
- [ ] `DownloadQueueActorTests.test_persistenceRoundTrip_preservesAllData`: expect the
      status after `pauseAll()`.
- [ ] `ResumeDataManagerTests.test_fileURL_returnsCorrectPath`: trailing-slash URL compare.
- [ ] `BackgroundSessionManagerTests.test_resumeDownload_*` (2): real background session
      with fake resume data fails at once; don't assert `isDownloading`.
- [ ] `DownloadTaskTests` equality/hash (2): value equality is intended.
- [ ] `FileManagerExtensionsTests.testFormattedSize`: decimal units.

## Code wrong
- [ ] `sanitizedLabel`: require the dot (3 tests).
- [ ] `FileManager.formattedSize`: negative → "Zero KB".
- [ ] `ResumeDataManager.isValidResumeData`: 50-byte prefix misses "plist" in an XML header.
- [ ] `DownloadTask.updateProgress`: server-reported size must replace the estimate.
- [ ] `DownloadTask.fail(with:)`: keep `resumeDataPath` (update the unit test that expects nil).

## Investigate
- [ ] `DownloadPerformanceTests` (2): SIGABRT in `DownloadProgressTracker` deinit.
- [ ] `SignLanguageModelTests.testModelInitializationT5*` (2): SIGABRT; MLX on Simulator?
- [ ] `DownloadIntegrationTests.test_pauseSingleTask`, `test_queueProcessesNextTaskAfterCompletion`:
      intermittent.

Done when: full suite run, `docs/status.md` updated with what remains and why.
