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
  app relaunch until the user reports completion. Prepare and verify on Mac
  and Simulator; leave deployment explicitly pending.

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
- [ ] Install/verify on iPad only after extraction has finished (pending user).
