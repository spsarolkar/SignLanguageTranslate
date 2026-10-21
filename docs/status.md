# Status

## Local files rejects Documents on iPad — 2026-10-21

Follow-up scope: [local-files-browser](plans/local-files-browser.md). The user
reported an `outsideDocuments` error on the browser home screen. A new test
using the real app Documents URL reproduced the error on the connected iPad
before the fix (`/tmp/slt-documents-repro-20261021.xcresult`). Earlier tests used
temporary roots and missed the on-device URL representation difference.

`FileManager` can return a filesystem alias such as `/private/var` while the
normalized root uses `/var`. Listings compared unnormalized child paths to
the root with a string prefix. Both sides now use canonical URLs and path
components before containment and relative-path derivation. Absolute paths,
traversal and symlink escapes remain rejected. The Training state shortcut
also now previews the actual `TrainingState.json` file rather than navigating
to a nonexistent `TrainingState` directory. No stored files are migrated.

- **Physical iPad: all 17 browser tests pass**, zero failures/skips. Includes
  real Documents root listing/nested preview, a symlink root, trailing slash
  and Unicode/space names, similarly named sibling rejection, feature indexing,
  bounds and existing traversal/symlink tests. The real-Documents test writes
  and removes only its uniquely named fixture. Report:
  `/tmp/slt-documents-device-fixed-20261021.xcresult` / `.log`.
- **Full Simulator suite: 662 tests, 655 passed, 2 failed, 5 skipped** (exit 65).
  The failures are the previously recorded network-dependent
  `DownloadIntegrationTests.test_pauseSingleTask` and
  `test_queueProcessesNextTaskAfterCompletion`. All 17 browser tests pass;
  no existing test was removed/disabled. Report:
  `/tmp/slt-documents-full-20261021.xcresult` / `.log`.

- **Final generic iOS Debug build passed** (exit 0):
  `/tmp/slt-documents-device-build-20261021.log`. Existing compiler warnings
  remain. No dependency, model schema, deployment target or project-file change.
- **Installed and launched on the physical iPad.** The user confirmed neither
  training nor extraction is running. Updated the app in place without
  uninstalling it; launch succeeded and the corrected executable was observed
  running. No training or checkpoint restoration was started. Reports:
  `/tmp/slt-documents-install-20261021.json`,
  `/tmp/slt-documents-launch-20261021.json` and
  `/tmp/slt-documents-processes-20261021.json`. Service tests establish real
  Documents listing/preview on hardware; manual browser navigation and video
  playback acceptance remain unverified.

## Live training Resume starts another loop — 2026-10-21

Assigned scope: [training-live-resume](plans/training-live-resume.md). The user
reported a stationary dashboard after Resume. Screenshots show step 3160 then
3436; they do not identify the precise GPU/runtime point where work stopped.
User-provided logs establish the lifecycle defect: Pause at 8:36:23 AM was
followed by data refetch, a new split and callback registration, then epoch 11
while the previous worker had reached epoch 10. Three identical foreground
resume messages also demonstrate duplicate notification observers.

Changes:

- One retained `TrainingWorkerLifecycle` owns each live operation. Explicit
  Resume releases its pause gate; it preserves the existing iterator, run,
  dataset, optimizer/model, callbacks and epoch/batch position. A compatibility
  call to Start while paused also uses live Resume; repeated starts cannot
  launch another worker. Preparing/restoring another model rejects a live
  worker rather than replacing its mutable parameters. Configuration stays
  locked while a live worker exists, including pause/cleanup; an ownership
  completion event refreshes the dashboard when that lock can be released.
- Callback registration completes before training starts. Batch metrics are
  published in order through awaited MainActor updates. Validation checks the
  same pause/stop gate per batch and publishes processed-batch counts; stopping
  skips remaining validation/epoch callbacks. The dashboard reports the actual
  training, validation, epoch-callback or checkpoint phase.
- Lifecycle observers register once and are released with the manager.
  Foreground events respect a deliberate user pause. Background saves wait up
  to two seconds for a parked worker, then recheck its pause state synchronously
  before reading weights. If the worker cannot park, the previous checkpoint
  remains untouched. This is not a claim of fully durable background recovery.

Checkpoint preservation and authorized deployment:

- Before deployment approval, only read-only `devicectl` inventory/copy calls
  were made against the iPad; the stalled session was left untouched.
- Saved checkpoint files were copied to
  `/tmp/slt-stalled-checkpoint-backup-20261021`. The weights file is 13,746,535
  bytes; its safetensors header parses with 70 entries. SHA256:
  `cbd5eb34c9ed3a81f0cc66a9d63c322d078183ef9b6bf93655417544efeebf3d`.
  The copied metadata records epoch 8, valLoss 1.6671373, timestamp
  `2026-10-21T02:44:21Z` (8:14 AM IST). Config and metadata were copied too.
  Header parsing does not establish architecture/config compatibility, tensor
  integrity, restored predictions or recoverability of later unsaved steps.
- Stop remained unresponsive. After a second inventory confirmed no newer
  checkpoint, the user explicitly selected **Force-close and install**, having
  acknowledged loss of unsaved training progress. The old app process (1232)
  was terminated and the prepared Debug build was installed in place, without
  uninstalling the app. Launch succeeded and the updated executable was
  observed running as process 1575. Dataset videos, feature JSON files and
  the epoch-8 checkpoint/config/metadata remain in the data container; checkpoint
  sizes/modification dates match the pre-update inventory. No new training or
  checkpoint restoration was started. The local-file browser is included.
  Device reports: `/tmp/slt-training-fix-install-20261021.json`,
  `/tmp/slt-training-fix-launch-20261021.json`,
  `/tmp/slt-training-fix-processes-20261021.json`,
  `/tmp/slt-training-fix-checkpoints-20261021.json` and
  `/tmp/slt-training-fix-datasets-20261021.json`.

Verification:

- **15 deterministic lifecycle tests passed on Simulator**, with no MLX model
  initialization. They cover same-worker continuation, position preservation,
  repeated actions, stop while paused, checkpoint-boundary acknowledgement and
  timeout, worker release/notification, manager prepare/start guards, background
  pause/foreground resume, manual pause retention and observer behavior with
  notification delivery from a background thread.
- **Final full Simulator suite: 658 tests, 652 passed, 1 failed, 5 skipped**
  (exit 65). The sole failure is the already recorded network-dependent
  `DownloadIntegrationTests.test_pauseSingleTask` (`Failed` vs `Paused`). The
  previously flaky queue-advance test passed in the final run. The five existing
  hardware-only skips are unchanged. No test was removed/disabled.
  Final report: `/tmp/slt-training-resume-release-20261021.xcresult` / `.log`.
  Initial focused report: `/tmp/slt-training-resume-targeted2-20261021.xcresult`.
- **Final generic iOS Debug build passed** (exit 0), without deployment:
  `/tmp/slt-training-resume-ready-device-20261021.log`. Xcode 27.1, target iOS
  26.2 and Swift 5 are unchanged. Resolved MLX 0.30.6 and the local checkout
  both remain at `6ba4827fb82c97d012eec9ab4b2de21f85c3b33d`. Existing compiler
  actor-isolation/deprecation warnings remain; this is not a warning-free build.

Limits: these tests do not run a real GPU optimizer or establish the exact
runtime cause of the already-stalled session. Saved-configuration fidelity,
force-cast checkpoint restoration, optimizer/random/split recovery, evaluation
mode and callback SwiftData ownership remain open review findings. No new
claim of model accuracy, exact restart or numerically identical recovery is
made. Data-loader prefetch/cancellation is unchanged (R6); the new owner controls
the training operation, not every producer task. Real-device pause/resume/stop
acceptance remains pending.

## Local datasets and pipeline file browser — 2026-10-21

Assigned scope: [local-files-browser](plans/local-files-browser.md). Added a
read-only full-screen browser from Pipeline and Settings, preserving the five
sidebar sections, root split view and app-owned extraction service.

- Quick access to all generated feature files, local dataset/feature folders,
  downloads, models, checkpoints and training state. Home also lists visible
  Documents contents. The feature index searches names/relative paths across
  datasets; folder search filters the current folder snapshot. Refresh updates
  listings without adding a recursive watcher during extraction.
- Feature inspection shows saved frames/model names, selected-frame timestamp,
  body/hand counts, normalized keypoint plot, and x/y/optional-z/confidence
  tables. Empty files show a recovery message; corrupt/incomplete JSON falls
  back to raw text. Videos use the system player; images are thumbnailed.
- Actor-backed filesystem reads return immutable snapshots, without SwiftData
  contexts. Paths are confined to Documents, listings skip symlinks and escape
  attempts are rejected. Text previews are limited to 64 KiB; feature/image
  reads to 8 MiB; image thumbnails to 1024 px. Large feature files show a text
  excerpt. No delete/move/rename/upload/extraction action was introduced.

Verification:

- **13 focused Simulator tests passed, zero failures/skips.** Coverage includes
  real listing metadata, recursive indexing, newly created files after refresh,
  path traversal/symlink rejection, frame/coordinate loading, read-only byte and
  timestamp preservation, zero-frame/corrupt files, preview caps and missing
  files/folders. Report: `/tmp/slt-local-files-targeted2-20261021.xcresult`.
- Native hosted captures were inspected at 390 pt narrow, 1194×834 landscape,
  and 834×1194 portrait. Synthetic fixtures cover home, indexed features,
  frame inspector and empty-feature inspection. Initial captures exposed a
  missing Done control; it was fixed on every browser destination and verified
  in a second run. Images: `/tmp/slt-local-*.png`; result:
  `/tmp/slt-local-files-render2-20261021.xcresult`. The temporary render helper
  was removed; source retained at `/tmp/slt-local-visual-fixture.swift`.
- **Final full Simulator suite: 643 tests, 636 passed, 2 failed, 5 skipped**
  (exit 65). The failures are the same previously recorded network-dependent
  `DownloadIntegrationTests.test_pauseSingleTask` and
  `test_queueProcessesNextTaskAfterCompletion`. All 13 new tests pass. The five
  hardware-only skips are unchanged; no existing tests were removed/disabled.
  Report: `/tmp/slt-local-files-full-20261021.xcresult` / `.log`.
- **Generic iOS Debug build passed** (exit 0), with no deployment operation:
  `/tmp/slt-local-files-device-build-20261021.log`. Simulator renders/tests
  and the device build use Xcode 27.1; target iOS 26.2 and Swift 5 are unchanged.

**Deployed 2026-10-21:** installation was initially held while extraction and
training were active. After Stop remained unresponsive, the user authorized
force-closing the stalled app and installing the prepared update. Installation
and launch succeeded with the training fix; saved dataset/feature files remain.
Open **Local files** from Pipeline or Settings. Physical video playback and
browsing the user's completed artifacts remain device acceptance checks. See the feature's
[README](../SignLanguageTranslate/Features/LocalFiles/README.md) for usage/limits.

## Empty feature extraction and analysis recovery — 2026-10-20

Assigned scope: [feature-extraction-recovery](plans/feature-extraction-recovery.md),
following the report that `Vision ready` clips show zero frames and analysis
cannot find features. Implementation: `ca25637`. Source videos and existing
valid artifacts are preserved.

Root causes and fixes:

- The video reader requested original compressed samples (`outputSettings:
  nil`), then skipped every sample without an image buffer. It now explicitly
  requests decoded YUV pixels and rejects empty/incomplete reads.
- Empty arrays could be saved and the batch runner skipped them merely because
  a file existed. Empty writes/loads now fail, writes are atomic, and reuse
  requires readable nonempty JSON with a matching positive frame count.
  Extract all retries zero/missing/corrupt/mismatched results; successful
  extraction replaces stale metadata. Persistence errors propagate.
- Analysis incorrectly opened stored relative paths as absolute file URLs.
  It now uses the feature file manager and receives path snapshots rather than
  SwiftData models across its actor boundary. Empty and one-frame analyses
  report actionable errors before numerical computation.
- The pinned MLX 0.30.6 checkout matches `Package.resolved` revision
  `6ba4827fb82c97d012eec9ab4b2de21f85c3b33d`. Its Metal backend throws
  `Metal SVD NYI`; the existing PCA SVD now explicitly uses the CPU backend.
- Pipeline cards mark zero-frame/missing-file metadata `Needs re-extraction`
  instead of `Vision ready`, with recovery guidance. Inspector file-loading
  failures now produce an error instead of silently showing no features.

Verification:

- Before the fix, a generated three-frame H.264 movie returned zero records
  (`/tmp/slt-feature-red-20261020.xcresult`). The regression now verifies all
  three decoded image buffers and their timestamps.
- Initial default-Vision execution on Simulator returned Vision Code 9 during
  body-pose request initialization. Decoding is therefore tested independently
  using an injected frame processor. Three separately identified device-only
  tests cover actual Vision, batch recovery, and MLX statistics; none of the
  decoder/file-loading regressions is disabled.
- **Physical M1 iPad, iPadOS 27.0.1: 14 focused tests passed, zero failures,
  zero skips**, including actual Vision processing of the generated movie,
  stale zero-frame replacement, valid-artifact reuse, source-byte preservation,
  relative-path loading, finite correlation/statistics and CPU PCA output.
  The fixture is a synthetic blank clip, so this verifies frame processing,
  not landmark detection quality on the user's signs. Temporary test folders
  are unique and removed after each test; the dataset is not cleared.
- **Final Simulator suite: 630 tests, 623 passed, 2 failed, 5 skipped** (exit
  65). Both failures are already recorded network-dependent download races:
  `DownloadIntegrationTests.test_pauseSingleTask` (`Failed` vs `Paused`) and
  `test_queueProcessesNextTaskAfterCompletion` (zero queued progress). The five
  skips comprise the two existing MLX initialization skips and the three new
  hardware-only checks, all three of which passed on the iPad. All eleven
  simulator-compatible new regressions passed. No existing test was removed
  or disabled.
- The fixed Debug app was installed by the successful physical-device test
  run, and normal app launch succeeded afterward. Launch report:
  `/tmp/slt-feature-ipad-launch-20261020.json`.
- Builds retain existing Swift 5 actor-isolation/deprecation warnings. The
  device batch test also reports warnings from the existing silent-audio
  session calls; this work does not extend that development-only mechanism.

Reports: `/tmp/slt-feature-device-20261020.xcresult`,
`/tmp/slt-feature-device-20261020.log`,
`/tmp/slt-feature-targeted-20261020.xcresult`, and
`/tmp/slt-feature-full-20261020.xcresult` / `.log`.

Recovery on the installed update: choose Pipeline → dataset → Extract all.
Valid results are skipped and unusable results are re-extracted. Open a ready
clip for keypoint playback, or run Analyze after usable frames are available.
Re-extracting the user's complete dataset and checking landmark alignment are
manual acceptance steps, not claimed by the generated-fixture tests.

## Navigation consistency and pipeline layout — 2026-10-20

Approved scope: `docs/plans/navigation-pipeline-consistency.md`, ahead of the
remaining screen order. Xcode was restored after software updates: **27.1
(27A9275)**, macOS 27.0.1. The connected M1 iPad now reports iPadOS 27.0.1.

Changes:

- `NavigationState` owns independent dataset, pipeline, and training
  selections. Sidebar switches recreate the split's navigation identity and
  clear pipeline clip/analysis destinations, preventing old detail routes
  from appearing under another section. Dataset browsing and training keep
  their own selected datasets.
- Pipeline selectors occupy the middle column; extraction, clip inspection,
  and analysis are hosted in an explicit detail navigation stack. Training
  dataset selection drives its detail dashboard rather than pushing a second
  dashboard from the middle column.
- Pipeline header/actions/clip cards now use shared design components and
  tokens. Actions stack at narrow widths rather than stretching vertically.
  Progress uses a bottom safe-area inset. Below 1000 pt the sidebar is behind
  the system reveal button; the three-column information architecture stays.
- Releasing the sidebar's `SystemPreflight` state on iOS 26.2 exposed an
  isolated-deinit crash in Swift TaskLocal cleanup after the compiler update.
  An explicit `nonisolated deinit {}` matches the existing UI state pattern.
  A synchronous release regression covers that failure path. Navigation state
  uses the same teardown pattern.

Verification:

- The unchanged baseline built under Xcode 27.1 before implementation.
- **Full final suite: 616 tests, 613 passed, 1 failed, 2 skipped** (exit 65).
  The only failure is the known real-session race in
  `DownloadIntegrationTests.test_pauseSingleTask` (`Failed` vs `Paused`).
  The other previously flaky queue-advance test passed. The two skips are the
  existing MLX initialization tests on Simulator. No existing test was removed
  or disabled. The nine new navigation/lifecycle regressions all pass.
- Workspace rendering was inspected at 390, 520, 700, and 834 pt widths.
  Native hosted navigation captures were inspected at 1194×834 landscape and
  834×1194 portrait. These use a clearly synthetic three-clip, in-memory
  fixture, not the user's dataset. Portrait hides the sidebar and leaves the
  workspace readable. Images are in `/tmp/slt-pipeline-*.png` and
  `/tmp/slt-navigation-{1194,834}.png`, not the repository.
- The temporary visual fixture was removed after its final successful run;
  its source remains at `/tmp/slt-ui-visual-fixture.swift`. Initial image-only
  rendering omitted scroll content; native scene-attached hosting was used
  for the actual visual checks. Earlier temporary-host teardown failures are
  not counted as passing verification.
- The exact on-device dataset → category → word → sidebar tap sequence still
  needs a manual acceptance check. Route invalidation and independent
  selections are covered by automated tests; the fixture captures check layout.

Logs/results: `/tmp/slt-xcode271-baseline-build.log`,
`/tmp/slt-navigation-final-20261020.xcresult`,
`/tmp/slt-pipeline-scenes-20261020.xcresult`,
`/tmp/slt-ui-full-tests.log` / `/tmp/slt-ui-full-20261020.xcresult`, and
`/tmp/slt-ui-ipad-build.log`.

**Physical iPad:** the Debug build passed, its signature verified, and the
update installed over the existing app on the connected M1 iPad. After the user
unlocked the iPad, launch succeeded and the app process was confirmed running
(PID 1200). The initial locked-device launch was denied with
`FBSOpenApplicationErrorDomain`, code 7. No app data was erased.
Install/launch reports: `/tmp/slt-ui-ipad-install.json` and
`/tmp/slt-ui-ipad-launch-verified.json`; running-process confirmation:
`/tmp/slt-ui-ipad-process-verified.json`. The physical touch-sequence acceptance
above remains manual.

This does not complete the remaining browser/sidebar/export designs in
`realign-02-screens.md`, change training/extraction/sync internals, or validate
model accuracy. Existing user experiments and archives remain untouched.

## Code review and cleanup — 2026-10-20

Baseline source: `237e75e`. Cleanup source: `e5c86f2`, on
`codex/review-cleanup`. Xcode 27.0 (27A266a), iPad Pro (11-inch)
(3rd generation) Simulator, iOS 26.2. The committed MLX Swift 0.30.6
revision matches the local checkout.

- **Baseline build passed.** Full baseline: **607 tests, 605 passed,
  0 failed, 2 skipped**, from the result-bundle summary.
- **Cleanup build passed.** Removed four unused implementation files and
  unused pipeline helpers (748 lines); no tests were deleted or disabled.
  Existing compiler warnings remain; this is not a warning-free build.
- The first post-cleanup full run reported the two known flaky failures below.
  Xcode then failed while importing simulator diagnostics with `No space left
  on device` (exit 133), so its bundle is not treated as a reliable final
  summary. Simulator clone launch failures were also reported. Only the
  review-created incomplete diagnostic dump was removed to restore space;
  project files and existing user artifacts were not deleted.
- **Final full serial run: 607 tests, 604 passed, 1 failed, 2 skipped**
  (exit 65). The only failure is the pre-existing
  `DownloadIntegrationTests.test_pauseSingleTask`: actual `Failed`, expected
  `Paused`. Queue advancement passed in this run. The result bundle completed
  normally; no new test failure was observed. This run uses the already-built
  app and tests from the cleanup sources, with no intervening Swift changes.

Final verification command:

```bash
xcodebuild test-without-building -scheme SignLanguageTranslate \
  -destination 'platform=iOS Simulator,name=iPad Pro (11-inch) (3rd generation),OS=26.2' \
  -parallel-testing-enabled NO -collect-test-diagnostics never \
  -quiet -resultBundlePath /tmp/slt-review-final-20261020.xcresult \
  > /tmp/slt-review-final-test.log 2>&1
```

The observed assertions were in:

- `DownloadIntegrationTests.test_pauseSingleTask` — task was already `Failed`
  when `Paused` was expected; also failed in the final serial run.
- `DownloadIntegrationTests.test_queueProcessesNextTaskAfterCompletion` —
  zero active tasks when more than zero was expected; passed in the final run.

These are the existing real-session/network-timing failures described in the
September entries and `docs/plans/fix-tests.md`. Both passed in the baseline
run today. No transport injection or test expectation changes are part of this
cleanup.

Logs/results are in `/tmp/slt-review-build.log`,
`/tmp/slt-review-baseline-20261020.xcresult`,
`/tmp/slt-review-cleanup-build.log`, `/tmp/slt-review-cleanup-test.log`, and
`/tmp/slt-review-final-test.log` / `/tmp/slt-review-final-20261020.xcresult`.
These are local verification artifacts, not repository content.

Two model initialization tests still skip on Simulator; no physical iPad
training/inference validation was performed. `DownloadManagerTests`,
`DownloadProgressTrackerTests`, and `PersistenceControllerTests` remain
compiled out with `#if false` and are not included in the totals.

See the [review](reviews/2026-10-20-code-review.md) for ten actionable findings
and the [completion roadmap](plans/completion-roadmap.md) for proposed work.
The highest-impact gaps concern preprocessing consistency, model/configuration
and output-mode contracts, train/eval mode, checkpoint safety, bounded batch
streaming, and held-out evaluation. No accuracy claim is supported yet.

New guides live under `docs/` because putting multiple `README.md` files in
the synchronized app tree produced duplicate resource outputs during the
initial cleanup build. The guides were moved and the build passed without
editing `project.pbxproj`. Pre-existing untracked instructions, experiments,
archives, and logs remain untouched and uncommitted.

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


## realign-02 screen 2 (dataset detail) — 2026-09-24

- **Pause All / Resume All (fixed, `fix:` commit).** Pause only set
  `dataset.downloadStatus`; the transfers kept running and the next 1 s sync
  tick set the status back to downloading. It now calls
  `DownloadManager.pauseAll()`. Resume calls `resumeAll()` and then
  `resumeTask` for each of the dataset's paused tasks, because `resumeAll()`
  only lifts the queue pause and never restarts `.paused` tasks.
  Needs on-device verification.
  - **Needs scoping per dataset.** The engine has no per-dataset pause, so
    Pause All pauses every dataset's transfers and Resume lifts the global
    queue pause.
  - **Resume can exceed 3 slots.** `resumeTask` goes through
    `DownloadCoordinator.startTask`, which does not check the concurrency
    limit, while `resumeAll()` lets the engine start pending tasks too.
- **"resumed at n%" / "resumed" (not shown).** The artboard's amber note on a
  resumed transfer has no data behind it: `DownloadCoordinator.startTask`
  clears `resumeDataPath` as the part restarts and nothing records the resume
  point. Needs new state in the downloads internals; `TransferRow` supports
  the amber note but nothing sets it yet.
- **Test run after screen 2:** 581 tests, 577 passed, 2 failed, 2 skipped.
  The failures and skips are the known ones above
  (`DownloadIntegrationTests.test_pauseSingleTask`,
  `...test_queueProcessesNextTaskAfterCompletion`; T5 init skipped on Simulator).
- **Dead code left:** `DownloadActionButton` has no callers now that
  `DownloadTaskRowView` uses `IconButton`; not removed in this screen.

## Download UI freeze on device — 2026-09-25

Seen on the iPad Pro M1 while INCLUDE downloaded: the UI and the Xcode
console stopped updating for minutes, then recovered. The app sat at ~52% CPU
while only showing progress. No crash, hang or jetsam report was written, and
no backtrace was captured while it was frozen, so the cause below comes from
the code and the log, not a stack.

- **Cause: progress flood.** URLSession reports progress every ~16 KB. Each
  callback printed a line, hopped to the main actor twice (the engine's
  `onProgress` and a duplicate `coordinator.handleProgressUpdate` that updated
  the queue a second time), re-sorted and regrouped all 44 tasks, and redrew
  every view watching `tasks`. The detail view also wrote to SwiftData on
  every change. **Fixed:** `ProgressThrottle` forwards at most one update per
  transfer every 0.5 s (first and final always pass), through one path, with
  no per-chunk print; the detail syncs on its 1 s timer only.
  **Needs on-device check:** CPU during a download should now be a few percent.
- **Time remaining was for the active parts only (fixed).**
  `DownloadProgressTracker` totals only parts that have reported progress, so
  with 3 of 44 active, "2h 3m remaining" was the time for those 3 parts. It
  also hid any estimate over 24 h. `DownloadManager.estimatedTimeRemaining`
  now uses every task's remaining bytes at the current rate, uncapped.
- **Throughput is server-bound for now.** The iPad got ~416 KB/s total across
  3 transfers; a single connection from a Mac to the same Zenodo file measured
  ~650 KB/s on 2026-09-25. Not an app limit; more parallel transfers are not
  proven to help.
- **Xcode gauges show Network/Disk at zero** for the app during downloads:
  background transfers run in `nsurlsessiond`, not the app process. Expected.
- **Lock held across URLSession calls (not fixed).**
  `BackgroundSessionManager.startDownload`, `resumeDownload` and
  `cancelDownload` call `cancel()`, `downloadTask(...)` and `resume()` while
  holding its `NSLock`, which the delegate callback also takes. Not shown to
  cause the freeze, but it is a lock-order risk; move those calls outside the
  lock when the downloads internals are next touched.
- **More tests compiled out (`#if false`), since before realign:**
  `DownloadManagerTests` (API changed, Jan 2026) and
  `PersistenceControllerTests`, in addition to `DownloadProgressTrackerTests`.
- **Test run after these fixes:** 594 tests, 592 passed, 0 failed, 2 skipped
  (T5 init on Simulator). The two network-dependent
  `DownloadIntegrationTests` passed this run; they are still flaky, not fixed.

## Zip import on device — 2026-09-25

Imported Zenodo's "Download all" zip on the iPad. Checked from the saved
queue (`Documents/download_state.json`) and the app container:

- **The import itself worked.** All 44 parts were marked completed, and every
  part's size matches the Zenodo API exactly (56,751,819,975 bytes in total).
  Sizes only; there is still no MD5 check.
- **Duplicate parts (fixed).** Import checked
  `getTasksForCategory(dataset.name)` — "INCLUDE" is never a category — so it
  always re-enqueued the manifest, and enqueue only de-duplicates by task ID.
  Result: 88 tasks, 44 of them pending copies, and the dataset could never
  reach completed (it offered Resume, which would re-download 56 GB).
  `loadINCLUDEManifest` now skips URLs already queued for the dataset; a
  one-time clean-up on queue restore (`DownloadTaskDeduplication`) keeps the
  most advanced task per (dataset, URL) and drops the rest.
- **Extraction after import did nothing (fixed).** It only extracted zips
  whose name contained the dataset name; no INCLUDE part does. It now matches
  the dataset's part filenames. On the iPad: 44 zips, 0 videos, no `Datasets`
  folder at the time of checking.
- **Cancel did nothing (fixed, and made safe).** Same wrong lookup. Cancel
  now cancels the dataset's unfinished parts only: `DownloadCoordinator.cancelTask`
  deletes a completed part's zip, so completed parts are left alone.
- **Import still pauses all downloads** and does not resume them afterwards,
  and it unzips the whole bundle to a temporary folder before importing
  anything. Not changed.
