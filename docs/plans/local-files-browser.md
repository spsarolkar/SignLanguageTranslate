# Local datasets and pipeline file browser

Assigned by the user's request while feature extraction is running. Build a
read-only screen to browse saved features, local datasets and other pipeline
artifacts. Preserve the five sidebar sections and the three-column root.
This is a focused addition, not completion of the remaining screen restyles.

## User flow

- Open **Local files** from Pipeline or Settings, in a full-screen browser.
- Shortcuts: All features (recursive index), dataset folders, feature folders,
  downloaded archives, models, checkpoints and training state. Browse all of
  the app's Documents directory, with per-folder search, path, size and date.
- Search the all-features index by filename or relative path; list actual
  generated files even while extraction is writing more. Refresh/pull to
  refresh updates the snapshot; no whole-tree rescans on each search keystroke.
- Inspect feature JSON: frame/model counts, select a frame, view keypoints
  and x/y/z/confidence values, and a bounded raw-text preview. Preview videos,
  images and small text/JSON files; show metadata for archives/weight files.
- Cap preview reads/feature decoding and perform filesystem work off the view
  actor. Confine navigation to Documents, reject symlink escapes, and handle
  changing/missing files. No delete/rename/move/re-extraction actions.
- Keep the running iPad extraction untouched: no install, hardware test or
  app relaunch until the user reports completion or explicitly authorizes
  closing the stalled app. Prepare and verify on Mac and Simulator first.

## File list

New:
- `SignLanguageTranslate/Features/LocalFiles/Logic/LocalFileStore.swift`:
  actor-backed listings, safe path resolution, bounded previews and snapshots.
- `SignLanguageTranslate/Features/LocalFiles/Views/LocalFileBrowserView.swift`:
  folder/search UI and file information, token styling and accessible controls.
- `SignLanguageTranslate/Features/LocalFiles/Views/LocalFilePreviewView.swift`:
  feature/frame/keypoint inspection and media/text preview.
- `SignLanguageTranslateTests/LocalFiles/LocalFileStoreTests.swift`:
  temp-directory fixtures covering listing/indexing, paths, caps, corrupt/empty
  features, read-only preservation and files arriving between refreshes.
- `SignLanguageTranslate/Features/LocalFiles/README.md`: entry points, scope,
  preview limits and live extraction behavior.

Existing:
- `Features/FeatureExtraction/Views/DataPipelineView.swift`: Local files entry.
- `Features/DatasetManager/Views/Navigation/ContentColumnView.swift`:
  Settings Local files entry beside the existing tools.
- `DesignSystem/DesignTokens.swift`: genuinely missing preview layout tokens.
- `docs/status.md` and this plan: test/visual results and pending deployment.

Existing paths above are relative to `SignLanguageTranslate/`. No dependency,
SwiftData schema, extraction/training service or project-file changes.

## Checklist

- [x] Implement bounded read-only filesystem service and regression tests.
      All 13 targeted tests passed on iPad Simulator, with zero failures/skips.
- [x] Implement browser, feature inspector and both entry points.
- [x] Build and run focused/full Simulator tests; record known failures.
      Full suite: 636 passed, 2 known download race failures, 5 existing
      hardware-only skips (643 total). Generic iOS Debug build passed locally.
- [x] Inspect rendered narrow/wide/portrait layouts with synthetic fixtures;
      screenshots and temporary render helpers stay outside commits.
      Captures cover home at 390/1194 pt, feature index and empty file at
      834 pt portrait, and frame inspection at 390 pt. A missing close control
      found in the first capture was fixed and checked in a second run. The
      render helper was removed; its source and captures remain in /tmp.
- [x] Document behavior/limits and save focused local commits.
- [x] Install and verify app launch on iPad after the user explicitly selected
      "Force-close and install" for the stalled training session, acknowledging
      loss of unsaved progress. Installed with the training worker fix on
      2026-10-21; saved dataset and feature files remain in the app container.
      On-device browser interaction/video playback acceptance remains pending.

## Follow-up: Documents rejected on iPad — 2026-10-21

The installed home screen reports that its own Documents folder is outside
Documents. Repair URL normalization/containment in the existing filesystem
service, preserving read-only behavior and rejection of escapes. Exercise the
real app Documents URL in addition to temporary fixture roots. Verify shortcut
destinations against the actual generated paths. The user confirmed neither
training nor feature extraction is running, so the corrected build may be
installed and launched after verification.

- [x] Reproduce the rejection with the real Documents URL; add path regressions.
      The new real-Documents test failed with `outsideDocuments` on the physical
      iPad before the fix. All 17 browser tests pass on that iPad after the fix.
- [x] Fix canonical containment and any verified shortcut destination mismatch.
      Canonicalize listed URLs as well as the root and compare path components;
      retain traversal/symlink escape rejection. Training state previews the
      actual `TrainingState.json` file rather than a nonexistent folder.
- [x] Run regression tests, required build/suite checks and record results.
      Physical browser tests: 17 passed. Full Simulator: 655 passed, 2 known
      download failures, 5 existing skips (662 total). Final generic iOS Debug
      build passed. Reports and limitations are recorded in `docs/status.md`.
- [x] Install/launch the correction and record hardware verification limits.
      Updated the idle iPad app in place on 2026-10-21; launch succeeded and
      the updated executable was observed running. No training/restoration was
      started. Service tests prove real Documents listing/preview on hardware;
      manual browser navigation/video playback acceptance remains unverified.
