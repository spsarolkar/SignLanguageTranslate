# Code review, cleanup, and completion planning

Requested and authorized on 2026-10-20. This review takes priority over the
remaining screen restyling in `realign-02-screens.md`; it does not mark those
screens complete or authorize a redesign.

## Scope

- [x] Read the project instructions, decisions, existing plans, and status.
- [x] Review the active download → ingestion → extraction → training → inference
      paths; record actionable findings with source references.
- [x] Record a fresh build and full test baseline, distinguishing simulator
      verification from Metal training on the target iPad.
- [x] Remove redundant implementations only after checking every declared type
      and helper for callers in app code, tests, and Xcode configuration.
      Candidates: `DownloadActionButton`, `ValidationSplitter`,
      `BatchFeatureExtractionManager`, and the unused `LearningRateScheduler`
      family. Preserve the active services and all tests.
- [x] Remove the unused private file manager/loader and empty compatibility overload
      from `TrainingDataPipeline` if searches confirm no callers. Preserve its
      active initializer and preprocessing behavior.
- [x] Add a project README, documentation index, app architecture guide, training
      guide, and test README with reproducible commands and limitations.
- [x] Write an ordered completion roadmap with acceptance criteria, including
      training correctness and on-device verification before model expansion.
- [x] Verify the cleanup with build, tests, reference searches, and diff review;
      update `docs/status.md` with observed results.
      Final build passed; full serial suite: 604 passed, 1 pre-existing flaky
      failure, 2 simulator skips. The failure and interrupted earlier diagnostic
      collection are recorded in status; no test was removed or disabled.

## Boundaries

No dependency, Swift language mode, deployment target, persistence schema,
navigation, UI layout, training algorithm, or automation changes. Do not edit
`project.pbxproj` for synchronized files. Do not delete untracked experiments,
archives, or logs; their ownership is unknown. Existing plans and historical
status entries remain available. Functional fixes identified in the review
need their own implementation plan and regression tests.

## Deliverables

- `docs/reviews/2026-10-20-code-review.md`
- `README.md`, `docs/README.md`, `docs/app/README.md`,
  `docs/training/README.md`, `docs/testing/README.md`. Guides stay outside the
  synchronized targets because Xcode copies Markdown as resources and module
  READMEs produced a duplicate-output build error during verification.
- `docs/plans/completion-roadmap.md`
- Build/test results in `docs/status.md`; raw logs and result bundles in `/tmp`.
