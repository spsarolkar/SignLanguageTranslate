# Navigation consistency and pipeline layout

Approved in response to the iPad screenshot on 2026-10-20. The user confirmed
the proposed file list and focused exception to the remaining screen order:
"Proceed with the proposed UI pass."

## Observed problem

The screenshot shows Pipeline selected while a previously browsed word's
video list remains in the detail pane. The pipeline workspace is squeezed into
the middle column: its title wraps and a crowded action row stretches the
Analyze control vertically.

The code mounts the complete `DataPipelineView` in `ContentColumnView`, while
the explicit pipeline detail is `EmptyDetailView`. Pipeline and training
register navigation destinations from the content column; dataset browsing
also has its own detail navigation stack and nested destinations. There is no
single explicit owner for the selected workspace and its detail route.
The screenshot is evidence of stale detail; the exact SwiftUI restoration
behavior still needs a runtime regression check.

## Proposed scope exception

- [x] Obtain confirmation for this focused navigation/pipeline pass ahead of
      the remaining screen order. Do not mark unfinished realignment screens
      complete.
- [x] Read the design spec, Browser/Export artboards, screenshot references,
      and the existing navigation/pipeline implementations.

Preserve all five sidebar sections and the existing three-column information
architecture. Keep the active download, extraction, training, and sync services.
This pass does not implement the full export/sharding design, new model metrics,
or a new sidebar design.

## Intended column behavior

| Sidebar selection | Middle column | Detail/workspace |
| --- | --- | --- |
| Datasets | Dataset selection | Selected dataset and its own browsing path |
| Downloads | Transfer list | Current download overview |
| Pipeline | Dataset/category/search selectors | Extraction workspace, clip list and selected clip inspection |
| Training | Dataset selection | Dashboard for that selection |
| Settings | Existing settings choices | Existing settings/debug content |

Selections and detail destinations belong to their section. Switching sections
must dismiss/reset the old section's pushed detail route, so a word, clip, or
training run never appears under an unrelated sidebar selection.

The pipeline workspace gets a normal `Pipeline` title, a compact status badge,
and action controls that wrap/stack with `ViewThatFits`. Use shared cards,
buttons, spacing, colors, and mono numbers. Keep the title readable and every
action at least 44 pt. The same hierarchy must adapt to portrait and a collapsed
sidebar. Do not use the artboards' placeholder metrics.

## Existing files expected to change

- `SignLanguageTranslate/Features/DatasetManager/Views/MainNavigationView.swift`
  — shared section/selection ownership and column sizing.
- `SignLanguageTranslate/Features/DatasetManager/Views/Navigation/ContentColumnView.swift`
  — section selectors rather than embedding the pipeline workspace.
- `SignLanguageTranslate/Features/DatasetManager/Views/Navigation/DetailColumnView.swift`
  — explicit workspace routing and section-scoped navigation stacks.
- `SignLanguageTranslate/Features/FeatureExtraction/Views/DataPipelineView.swift`
  — use parent-owned selection, adaptive header/actions, token styling, and
  explicit clip/analysis routing.
- `SignLanguageTranslate/Features/Training/Views/TrainingContentView.swift`
  — bind dataset selection to the parent instead of independently pushing a
  dashboard into the shared detail destination.
- `SignLanguageTranslate/DesignSystem/DesignTokens.swift`
  — add any genuinely missing layout tokens; retain existing token names.
- `docs/status.md` — record verification and remaining limitations.

Additional necessary fix found during hosted visual verification:
`Core/Utilities/SystemPreflight.swift` needs an explicit nonisolated empty
deinitializer, matching existing UI state owners. On iOS 26.2 with the updated
compiler, releasing the sidebar's storage-status state crashed inside
`swift_task_deinitOnExecutorImpl` / TaskLocal cleanup when the split hierarchy
was destroyed. This is part of safely resetting navigation, not a storage or
download behavior change. Add a release regression to `NavigationStateTests`
and save this fix separately from styling.

Expected new files (Xcode synchronized folders; no project-file registration):

- `Features/DatasetManager/Views/Navigation/NavigationState.swift` under the
  app source tree, for testable section/route ownership.
- `Features/FeatureExtraction/Views/PipelineSelectionView.swift` under the
  app source tree, for the narrow selector pane.
- `SignLanguageTranslateTests/Navigation/NavigationStateTests.swift` for
  regression coverage of section switching and independent selection.

If inspection during implementation reveals that another existing navigation
owner must change, update this plan and explain the reason before broadening
the work. Do not refactor feature internals to accomplish this UI fix.

## Acceptance and verification

- [ ] Navigate into dataset → category → word, then select Pipeline: no word
      detail or Back button from the dataset section remains.
- [x] Cover switching among all five sidebar sections with regression tests:
      old detail identity is invalidated, pipeline clip/analysis destinations
      clear, and dataset selections remain independent. Native hosted captures
      verify pane/title placement; the exact physical touch sequence remains
      a separate manual acceptance check above.
- [x] Pipeline actions stay readable without clipping, tall pills, or forced
      horizontal overflow at narrow detail widths, landscape, and portrait.
- [x] Selected dataset/category/video information stays consistent between
      selector and workspace. Extraction progress survives navigation through
      the existing app-owned batch service, whose lifetime is unchanged.
- [x] Test section/route state transitions and run the full existing suite;
      record any already known flaky failures rather than disabling tests.
      Full run: 613 passed, 1 existing pause-race failure, 2 MLX skips; all
      nine new navigation/lifecycle regressions pass.
- [x] Build, visually verify hosted simulator layouts, and install on the
      connected iPad. Device build/signature/install succeeded; after the user
      unlocked the iPad, launch and running-process checks passed. The exact physical
      reproduction sequence remains the manual acceptance item above.
- [x] Save navigation behavior and pipeline styling as separate small commits.

Verification prerequisite resolved: the user restored Xcode after completing
software updates. Xcode 27.1 (27A9275) is selected at
`/Applications/Xcode.app/Contents/Developer`; first-launch setup is complete.
The iOS 26.2 iPad Pro (11-inch) (3rd generation) Simulator remains available,
and the physical M1 iPad is connected. Verify the baseline under this updated
toolchain before implementation. The baseline build passed under Xcode 27.1.
