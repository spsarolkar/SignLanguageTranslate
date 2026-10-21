# Training evaluation and word-target correctness

Assigned by the user's 2026-10-21 stop after the proposed evaluation, target
selection and validation-frequency corrections. The previous resume repair is
complete. This plan supersedes its metrics/evaluation exclusion for this pass.

## Scope and behavior

- Preserve existing runs/checkpoints and data. Read-only device metadata confirms
  the current run is Stopped, with a saved epoch-13 checkpoint. Both runs are
  backed up at `/tmp/slt-evaluation-checkpoints-backup-20261021`.
- Resolve exactly one explicit word label per sample; never use category or
  relationship order for a target. Embedding targets must have 384 finite,
  nonzero values. Classification requires a word index, not a text embedding.
  Snapshot vocabulary/targets before leaving MainActor. Reject ambiguous labels
  or conflicting embeddings rather than selecting arbitrarily.
- Validation disables dropout/training behavior and restores every module's
  prior mode on normal completion, Stop and error. Keep training's smoothing
  objective and use unsmoothed validation loss with explicit display semantics.
- Full validation defaults to once at epoch end (`validationInterval == 0`),
  including newly resumed child runs. Preserve original configs; log migration.
  Keep optional positive intervals safe and avoid a duplicate epoch-end pass.
- Report sample-weighted validation loss and cosine similarity separately from
  full-vocabulary word top-1/top-5 accuracy. Embedding recognition ranks every
  valid word target in the selected dataset, not other clips in the batch.
  Classification ranks its persisted class order. Zero/failed samples cannot
  manufacture a successful validation score.
- Add optional metric fields and data/evaluation contract markers without a
  SwiftData schema migration; old stored metric blobs remain decodable and are
  labelled according to their legacy meaning. Preserve the original checkpoint
  architecture/weights. Continued runs use corrected targets and new metrics;
  comparisons with old evaluation are explicitly limited.
- Show actual epoch, batch/update progress, cosine similarity and validation word
  accuracy without mixing training/validation points. Use existing design tokens.

No architecture, LR/scheduler tuning, embedding regeneration, preprocessing
rewrite, dependency or project-file changes. Do not start user training.

## Files

- New `Features/Training/Logic/TrainingEvaluation.swift`: word-target/vocabulary
  snapshots, recognition aggregation, validation cadence and model-mode scope.
- `TrainingSessionManager.swift`, `Models/TrainingMetrics.swift`,
  `Logic/CheckpointCompatibility.swift`: wire evaluation, optional metrics and
  target/evaluation contract markers. No storage mutation of old runs.
- `Views/TrainingDashboardView.swift`: correct metric names/series, epoch/batch
  and cadence guidance; token styling for changed content.
- `Logic/TrainingDataPipeline.swift` only if needed to expose an internal,
  deterministic validation boundary; keep preprocessing unchanged.
- New `SignLanguageTranslateTests/Training/TrainingEvaluationTests.swift`:
  target/category order, bad/missing targets, classification without embeddings,
  full-vocabulary ranking/ties, weighted aggregates, old metric decoding,
  cadence, and physical-device dropout/mode-restoration checks. An isolated
  real manager GPU smoke test may use temporary fixtures, never user training.
- This plan and `docs/status.md`: results, limits and device deployment.

## Checklist

- [x] Confirm stopped status and back up existing checkpoints.
- [x] Implement explicit word targets and full-vocabulary recognition metrics.
- [x] Implement deterministic evaluation mode, weighted aggregation and cadence.
- [x] Update metric storage/display and continued-run contract markers.
      Versioned metadata also records the candidate words.
- [x] Run meaningful Simulator and isolated device regressions; build green.
      Device: 32 passed, including all 18 evaluation regressions, 13 checkpoint
      checks and one temporary read-only dataset acceptance check. Full Simulator:
      688 passed, 2 recorded pre-existing download failures, 12 skipped (702).
      Final generic-device build passed after removing the acceptance helper.
- [ ] Save focused commits, install/launch and document remaining limits.

Paths above are relative to `SignLanguageTranslate/` unless fully qualified.
