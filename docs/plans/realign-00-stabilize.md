# Realign 00 — Stabilize

**Goal:** a clean repo whose HEAD builds, with a recorded test baseline. No
feature work, no UI changes.

## 0.1 Hygiene (one commit)
- [x] Add to `.gitignore`: `automation/venv/`, `__pycache__/`, `*.pyc`,
      `build.log`, `build_log*.txt`, `buildlog.txt`, `automation/dashboard/screenshots/*.png`.
- [x] `git rm -r --cached` those paths (keep files on disk if useful).
- [x] Delete the stray root-level Swift files (`DownloadManager.swift`,
      `DownloadQueueActor.swift`, `DownloadTask.swift`, `DownloadTaskRowView.swift`,
      `SignLanguageTranslateApp.swift`) and root `App/`, `Features/` folders
      **after confirming** each is not part of the target and a real version
      exists under `SignLanguageTranslate/`. List what you delete in the commit.

## 0.2 Green build
- [ ] Fix `Features/Training/Models/LegacySignLanguageModel.swift` against
      **MLX Swift 0.30.2 as pinned** (check the source in SourcePackages):
      replace the non-existent `ELU` layer with the `elu(_:alpha:)` function in
      the forward pass; correct initializer labels (`BatchNorm` etc.); remove the
      stray `indices:` label; resolve the main-actor `init` override mismatch.
- [ ] If any part is unclear, exclude nothing silently — ask.
- [ ] `xcodebuild build` green.

## 0.3 Test baseline
- [ ] Run `xcodebuild test`. Create `docs/status.md` with date, pass/fail
      counts, and each failing test with a one-line reason. Do not fix tests in
      this step.

## 0.4 `Label` shadowing — **stop and ask before doing this**
Present both options with the files affected, then wait:
- A) Rename the SwiftData model to `SampleLabel`. Changes the store's entity
  name, so the dev store must be deleted or a `SchemaMigrationPlan` added.
- B) Keep `Label`; use `SwiftUI.Label` in views (and add a note to CLAUDE.md).

## 0.5 Secrets
- [ ] Move R2 credentials from `UserDefaults` to Keychain (small wrapper in
      `Core/Utilities/`). Same for the Hugging Face token if it is not already.

Done when: build green, `docs/status.md` exists, repo clean, 0.4 decided.
