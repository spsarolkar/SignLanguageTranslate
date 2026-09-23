# SignLanguageTranslate — project brief

iPad app for Indian Sign Language: download and ingest the INCLUDE dataset,
extract body and hand keypoints on device with Vision, and **train sign
classifiers on device with MLX Swift**. Secondary goal: show that a
production-grade app can be built with an agentic workflow, with the evidence
in the repo (plans, tests, small commits).

Target: iPad Pro M1, 2 TB. Read this whole file before starting any task.

---

## Status (read first)

- Development paused 25 Jan 2026. **HEAD does not build.** The last log
  (`buildlog.txt`) fails in `Features/Training/Models/LegacySignLanguageModel.swift`.
- Modules reached: downloads → extraction → ingestion → feature extraction →
  training (MLX) → sync (Hugging Face, R2). Downloads and ingestion are well
  tested; training has no tests.
- Current work is **realignment**, in this order: `docs/plans/realign-00-stabilize.md`,
  then `realign-01-design-system.md`, then `realign-02-screens.md`.
  Do not start a later plan while an earlier one has open items.

---

## Toolchain facts (do not "fix" these)

- **Xcode synchronized folders.** Any file created under `SignLanguageTranslate/`
  or `SignLanguageTranslateTests/` is added to the target automatically.
  **Never edit `project.pbxproj` to add or remove files.**
- Deployment target **iOS 26.2**. Swift **5** language mode. Do not switch to
  Swift 6 mode as part of any other task.
- **MLX Swift is pinned at 0.30.2.** Its API differs from PyTorch, Keras and
  Python MLX. Before using any MLX/MLXNN type or initializer, confirm it exists
  in the pinned source (`~/Library/Developer/Xcode/DerivedData/*/SourcePackages/checkouts/mlx-swift/Source/`).
  Example of what went wrong: `ELU` is not a layer type in 0.30.2; only the
  function `elu(_:alpha:)` exists.
- Other dependency: ZIPFoundation. **Do not add dependencies** without asking.

## Build and test

```bash
# Find an available iPad simulator name first:
xcrun simctl list devices available | grep -i ipad

xcodebuild build -scheme SignLanguageTranslate \
  -destination 'platform=iOS Simulator,name=<IPAD NAME>' -quiet \
  > /tmp/slt-build.log 2>&1; tail -40 /tmp/slt-build.log

xcodebuild test -scheme SignLanguageTranslate \
  -destination 'platform=iOS Simulator,name=<IPAD NAME>' -quiet \
  > /tmp/slt-test.log 2>&1; tail -60 /tmp/slt-test.log
```

**Build and test logs go to `/tmp`, never into the repo.** A task is not done
until the build is green and tests pass (or failures are pre-existing and
recorded in `docs/status.md`).

---

## Repo map

```
SignLanguageTranslate/
  App/                         app entry, AppDelegate (background session wakeups)
  Core/                        Extensions, Persistence (PersistenceController, ModelQueries), Utilities
  DesignSystem/                DesignTokens.swift (+ shared components, added in realign-01)
  Features/
    DatasetManager/
      Downloads/               BackgroundSessionManager, DownloadEngine, DownloadQueueActor,
                               DownloadCoordinator, ResumeDataManager, persistence
      Extraction/              ZipExtractor, MultiPartMerger
      Ingestion/               INCLUDEIngestionStrategy, VideoFileScanner, VideoIngestionService
      Manifest/                INCLUDEManifest (Zenodo 4010759, 15 categories, 44 parts)
      Models/                  Dataset, VideoSample, Label, LabelType, FeatureSet, DownloadStatus
      Views/                   MainNavigationView, Navigation/, Components/, list/browser views
    FeatureExtraction/         Vision pose + hand extractors, batch extraction, DataPipelineView,
                               VideoAnnotationPlayer, KeypointVisualizer
    Training/                  MLX models, TrainingSessionManager, callbacks, augmentation,
                               splitters, InferenceEngine, dashboard views
    Sync/                      HuggingFaceSyncService
SignLanguageTranslateTests/    unit + integration tests (see TEST_PLAN.md)
automation/                    Python orchestrator (Claude API) + dashboard — see below
docs/                          design spec, plans, decisions, status
```

**Nothing goes at the repo root** except config files. No Swift files at root.

### Navigation

`MainNavigationView` is a three-column `NavigationSplitView`
(sidebar → content → detail) with sections in `NavigationSection`:
datasets, downloads, pipeline, training, settings. **Keep this information
architecture.** The designs restyle it; they do not replace it.

---

## Architecture rules

- **Concurrency.** Download queue state is owned by `DownloadQueueActor`;
  nothing else mutates it. URLSession delegate callbacks hop into it with
  `Task { await ... }`. No `DispatchQueue`, no locks in new code.
- **SwiftData.** `ModelContext` is not Sendable. Background work uses its own
  context; only `@MainActor` code touches the view context.
- **Storage.** Video bytes live under the app's Documents directory; SwiftData
  holds metadata and **relative** paths only.
- **Secrets.** Tokens and keys (Hugging Face, R2) live in **Keychain**, never in
  `UserDefaults`, source, or config files.
- Features depend on Core, never the reverse.

## Data model facts

- `VideoSample` ↔ `Label` is many-to-many. A clip at `Animals/12. Dog/x.mp4`
  gets `Label(Animals, .category)` and `Label(Dog, .word)`. Labels are shared,
  not duplicated per clip.
- Folder names like `12. Dog` are cleaned by stripping leading digits, dots and
  whitespace (`12. Dog` → `Dog`).
- ⚠️ The SwiftData model `Label` **shadows SwiftUI's `Label`** in every file of
  this module. Until it is resolved (see realign-00), write `SwiftUI.Label(...)`
  in views.
- **Features: 60 landmarks × 3 = 180 values per frame** — body 18 + left hand 21
  + right hand 21 (`TrainingDataPipeline.featureDim`). This is authoritative;
  if a design or doc says 61, the design is wrong.

## ML facts

- Training runs **on device** with MLX Swift. Models: `SignLanguageModel`
  (Transformer; `small` / `default` / `large` configs) and
  `LegacySignLanguageModel` (BiLSTM ported from an earlier Keras model).
- Planned later, not now: a small spiking network trained on device, and a
  frozen fly-connectome reservoir with a **mandatory** shuffled-graph control.
  Do not start these without a plan file.
- `SilentAudioPlayer` keeps the app alive in the background by playing silent
  audio. Acceptable for development builds only; it will be replaced with
  `BGProcessingTask` + checkpoint resume. Do not extend it.

---

## Design

The visual spec is **`docs/design/README.md`**, with reference markup in
`docs/design/artboards/`. Rules:

- Use `DesignTokens.swift` (`Palette`, `Typo`, `Spacing`, `Radius`, `Metrics`,
  `StateTint`). **No new hardcoded colors, font sizes or magic spacing in views.**
  Missing token → add it to the token file.
- The app is dark (`.preferredColorScheme(.dark)` at the root).
- Numbers the user reads or compares use `Typo.mono(...)`.
- One view hierarchy for landscape and portrait; adapt with size classes and
  `ViewThatFits`, not duplicated screens.
- Touch targets ≥ 44 pt. Icon-only buttons get an accessibility label.

---

## Working rules

1. Work only from the plan file you were given. Tick items as you finish them.
2. Ambiguity or a conflict between this file, a plan, the design and the code:
   **stop and ask.** Do not guess.
3. Small commits, one logical change each, real messages. Never commit logs,
   screenshots, venvs, `__pycache__` or DerivedData.
4. Do not refactor code the current plan does not mention.
5. Do not delete tests to make a build pass. A failing test is either fixed or
   recorded in `docs/status.md` with the reason.
6. Don't invent numbers (accuracy, sizes, counts) in UI or docs; measured or
   clearly placeholder.

## automation/

A Python orchestrator that drove earlier phases via the Claude API
(`automation/phases/`, `automation/scripts/orchestrator.py`, dashboard). Phase
specs there stop at module 5. It is **not** used for the realignment work;
don't modify it unless asked.
