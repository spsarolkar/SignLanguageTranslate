# Recover empty feature extraction and analysis loading

Assigned by the user's 2026-10-20 report: extracted clips show `Vision ready`
with zero frames and Analyze reports no feature data. This focused bug fix
follows completion-roadmap milestone 2's requirement to reject empty feature
artifacts. It does not broaden the unfinished screen redesign or change the
training feature contract.

## Diagnosis

- `VideoFeatureExtractionService` requests `outputSettings: nil`, which yields
  compressed samples for compressed movies. It silently skips samples without
  image buffers and returns an empty success.
- `FeatureFileManager` saves empty arrays; the batch runner skips any existing
  feature file even when its metadata or decoded content has zero frames.
- `FeatureAnalyzer` opens a relative stored path as an absolute file URL,
  instead of resolving it under the dataset directory.
- Pipeline readiness depends only on a metadata record existing.

## Scope and files

- `Features/FeatureExtraction/Logic/VideoFeatureExtractionService.swift`:
  request decoded pixels; reject zero decoded frames and incomplete reads.
- `Features/FeatureExtraction/Logic/FeatureFileManager.swift`: reject empty
  writes, validate saved content for reuse, allow an isolated storage root for
  tests without changing the app's Documents layout.
- `Features/FeatureExtraction/Logic/BatchExtractionService.swift`: reuse only
  valid nonempty artifacts; retry empty/missing/corrupt artifacts and replace
  stale metadata only after successful extraction.
- `Features/FeatureExtraction/Views/DataPipelineView.swift`: show unusable
  zero-frame records honestly; explain single-clip load failures.
- `Features/Analysis/Logic/FeatureAnalyzer.swift`: resolve paths through the
  same file manager, report invalid input, guard insufficient analysis frames.
  Inspection of resolved MLX 0.30.6 also found Metal SVD is unimplemented:
  explicitly run the existing PCA decomposition on CPU to avoid a crash once
  file loading succeeds. No analysis algorithm or training-model change.
- `Features/Analysis/Logic/AnalysisViewModel.swift`: present recovery guidance
  when there are no usable features.
- `SignLanguageTranslateTests/FeatureExtraction/`: generated compressed-video
  decoder regression, empty/corrupt/missing artifact and relative-path recovery
  tests. Simulator Vision pose initialization returns Code 9, so inject the
  per-frame processor at the decoding boundary; actual Vision stays a device
  check. Do not disable the decoder regression.
- `docs/status.md` and this plan: accurate results and device limitations.

Paths under `Features/` are relative to `SignLanguageTranslate/`. Synchronized
folders register source/tests; no project-file or dependency edits. Preserve
original videos and valid feature files; no dataset-wide deletion or migration.

## Checklist

- [x] Reproduce compressed-video zero frames with a generated local fixture.
      Before the fix, the three-frame movie returned zero records.
- [x] Fix decoding and reject false successful empty writes.
- [x] Validate reuse and recover stale artifacts on Extract all. Physical-device
      regression replaces an empty record, preserves a valid artifact's ID and
      bytes, and confirms source movie bytes are unchanged.
- [x] Correct analysis loading and readiness/error messages. Physical-device
      analysis produces finite statistics and PCA coordinates.
- [x] Add/run targeted tests and full suite; document known failures. Physical
      iPad: 14 passed, no failures/skips. Simulator: 623 passed, 2 pre-existing
      network-dependent download failures, 5 skips (2 existing MLX + 3 new
      hardware checks). All eleven new simulator-compatible tests pass.
- [x] Build/install on the connected iPad without clearing app data; normal
      app launch succeeded after the hardware tests. Actual landmark detection
      on the user's sign clips remains a manual acceptance step; generated
      blank-video tests verify decoding/Vision execution and artifact recovery.
- [x] Save focused implementation and verification commits.

## User acceptance

On the installed update, choose Pipeline → INCLUDE → Extract all. Empty
results are retried; readable results with matching positive frame counts are
skipped. Then inspect a clip's frame count/keypoint playback and run Analyze.
The original empty artifacts do not contain keypoints to display, so they
require re-extraction. No automatic dataset-wide re-extraction was started.
