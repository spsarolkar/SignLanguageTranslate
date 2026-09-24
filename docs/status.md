# Status

## Test baseline — 2026-09-23

Commit `3ff5216` (WIP snapshot + green-build fix). Xcode 27.0 (27A266a),
simulator iPad Pro (11-inch) (3rd generation), iOS 26.2. MLX Swift 0.30.6.

```
xcodebuild test -scheme SignLanguageTranslate \
  -destination 'platform=iOS Simulator,name=iPad Pro (11-inch) (3rd generation),OS=26.2'
```

**562 tests: 530 passed, 32 failed, 0 skipped.** Build has 328 warnings.

Reasons below are the observed symptom from the failure message, not a
diagnosis. None of these were fixed in realign-00.

### Failing tests

**INCLUDE manifest: tests expect 46 files, manifest has 44** (CLAUDE.md says 44 parts)
- `INCLUDEManifestTests.test_totalFileCount_isExactly46` — 44 ≠ 46
- `INCLUDEManifestTests.test_generateAllEntries_returns46Entries` — 44 ≠ 46
- `INCLUDEManifestTests.test_allURLs_areValidAndUseCorrectBase` — 44 ≠ 46 URLs
- `INCLUDEManifestTests.test_sumOfCategoryParts_equalsTotalFileCount` — 44 ≠ 46
- `INCLUDEManifestTests.test_manifestStatistics_containsCorrectValues` — 44 ≠ 46
- `INCLUDEManifestTests.test_manifest_isValid` — validator reports total 44, expects 46
- `ManifestIntegrationTest.test_manifestEntriesGeneration` — 44 ≠ 46

**INCLUDE manifest: filename/URL format**
- `INCLUDEManifestTests.test_singlePartCategory_generatesCorrectFilename` — `Seasons_1of1.zip`, test expects `Seasons.zip`
- `INCLUDEManifestTests.test_allSingleFileCategories_generateCorrectFilenames` — same `_1of1` suffix
- `INCLUDEManifestTests.test_fetchManifestForSpecificCategory_returnsCorrectEntries` — same `_1of1` suffix
- `INCLUDEManifestTests.test_specificURLGeneration_forAnimalsCategory` — URL ends in `/content`, test expects without
- `INCLUDEManifestTests.test_specificURLGeneration_forSeasonsCategory` — `/content` suffix and `_1of1` filename

**Label sanitizing**
- `StringExtensionsTests.testSanitizedLabel_edgeCases` — input `123` sanitizes to `""`, expected `123`
- `ModelEdgeCaseTests.test_sanitizedLabel_edgeCases` — same
- `ModelRelationshipTests.test_sanitizedLabel_worksWithFolderNames` — same

**Size formatting**
- `FileManagerExtensionsTests.testFormattedSize` — `1.07 GB`, expected `1 GB`
- `ModelEdgeCaseTests.test_datasetWithNegativeBytes_handlesGracefully` — `-1 KB`, expected `Zero KB`

**DownloadTask equality/hashing**
- `DownloadTaskTests.test_downloadTask_equatable_sameIDIsEqual` — same-ID tasks compare unequal
- `DownloadTaskTests.test_downloadTask_hashable_sameIDHasSameHash` — same-ID tasks hash differently

**Download status / queue**
- `DownloadTaskStatusTests.test_stateTransitionLogic_terminalStatusesCannotStart` — `Failed` is reported as startable
- `DownloadQueueActorTests.test_exportState_producesValidJSON` — decode fails: `createdAt` type mismatch (expects Double)
- `DownloadQueueActorTests.test_persistenceRoundTrip_preservesAllData` — status comes back `paused`, expected `downloading`
- `DownloadCoordinatorTests.test_handleDownloadFailed_savesResumeData` — resume data not saved (nil)
- `ResumeDataManagerTests.test_fileURL_returnsCorrectPath` — returned path differs from expected
- `ResumeDataManagerTests.test_isValidResumeData_returnsTrueForXMLPlist` — XML plist not accepted as valid

**Download integration**
- `DownloadIntegrationTests.test_pauseSingleTask` — status `Failed`, expected `Paused`
- `DownloadIntegrationTests.test_progressUpdatesFlow` — bytes 100000000, expected 1000
- `DownloadIntegrationTests.test_queueProcessesNextTaskAfterCompletion` — no next task started (0 active)

**Crashes (SIGABRT)**
- `DownloadPerformanceTests.test_progressCalculation_performance_46Tasks` — test process crashed
- `DownloadPerformanceTests.test_progressCalculation_performance_frequentUpdates` — test process crashed
- `SignLanguageModelTests.testModelInitializationT5Small` — test process crashed
- `SignLanguageModelTests.testModelInitializationT5Base` — test process crashed

After a crash the simulator clone sometimes failed to relaunch the test host
("Simulator device failed to launch"); xcodebuild recovered and finished the run.

## Re-run — 2026-09-24 (realign-01)

After realign-00 §0.5 and realign-01. Same simulator and destination.

**568 tests: 535 passed, 33 failed.** The +6 tests are the new `KeychainStoreTests`
(all pass). The 32 failures above are unchanged. One more failure:

- `BackgroundSessionManagerTests.test_resumeDownload_createsNewTask`: fails
  every time now (3/3 in isolation), and **also fails at baseline commit
  `0fbc10e`**, so realign-01 did not cause it. It passed in the 2026-09-23 run.
  The test passes mock resume data to a real background `URLSession`; the task
  seems to be dropped before `isDownloading` is checked. It depends on timing or
  environment and has not been investigated.

## Re-run — 2026-09-24 (docs/plans/fix-tests.md)

**569 tests: 564 passed, 3 failed, 2 skipped** in the last full run. One of the 3
(`BackgroundSessionManagerTests.test_resumeDownload_replacesExistingTask`, a
racy check added in this pass) was fixed afterwards and its class passes (58/58);
the full suite was not re-run after that change. Expected now: 566 passed,
2 failed, 2 skipped.

Everything in the lists above is fixed except:

- `DownloadIntegrationTests.test_pauseSingleTask`: engine uses the real
  background session against example.com; the task can fail before the pause.
- `DownloadIntegrationTests.test_queueProcessesNextTaskAfterCompletion`: same
  cause; tasks have already failed, so 0 are active.

Skipped on Simulator (MLX needs Metal features the Simulator lacks):
`SignLanguageModelTests.testModelInitializationT5Small`, `...T5Base`.

`DownloadProgressTrackerTests` is still compiled out (`#if false`) because of
the deinit crash; that crash is now fixed, so the tests can be re-enabled.

## realign-02 screen 1 (first run) — 2026-09-24

Follow-ups, not done in this screen:

- **Manifest sizes and checksums.** The Zenodo API (records/4010759/files)
  reports per-file size and MD5 for all 44 zips. Store both in
  `INCLUDEManifest` and verify downloads against the MD5. For now only the
  total is hardcoded: `INCLUDEManifest.measuredTotalSize` = 56,751,819,975 bytes.
- **Stale estimates.** `INCLUDEManifest.estimatedTotalSize` (50 GB, has a test)
  and the launch seed in `PersistenceController.seedInitialDatasetsIfNeeded`
  (`totalBytes` 50 GB, `totalParts` 46; INCLUDE has 44) are still estimates.
  Left unchanged: this plan does not allow business-logic changes.
- **`requiredFreeSpace` (~115 GB)** is an estimate (zips plus extracted
  videos), not a measurement.
- **Import progress from first run.** Importing from the first-run screen ends
  first run as soon as the dataset starts, so the detail switches to INCLUDE.
  The import overlay (`downloadManager.isImporting`) still shows there, but the
  later extraction/ingestion progress line was reported to the first-run view
  and is not shown.

