# BiLSTM learning and training-step repair

Assigned by the user's slow-learning report at epoch 18 and request to change
the LSTM model. The active v1 run remains untouched until safely stopped.

## Evidence and scope

- Current run: two BiLSTM layers, hidden width 64, batch 8, InfoNCE, dropout
  0.2 and BatchNorm. Read-only logs show validation top-1 6.25% at epoch 17,
  6.94% at epoch 18, with loss 1.8702 at epoch 18. Thermal pauses now also add
  wall time. No claim that one architectural choice is a proven cause.
- Add a separate version-2 model, preserving LegacySignLanguageModel and all
  existing weights. New default: frame projection to 96 + LayerNorm + GELU,
  one bidirectional LSTM with 96 units per direction, learned scalar temporal
  attention over all 60 states, LayerNorm, dropout 0.1, direct output head.
  Embeddings remain 384 values and are L2 normalized; classification returns
  raw word logits. No batch-dependent normalization or 64-value dense bottleneck.
- Expose v1/v2, recurrent width, one/two layers and dropout for fresh BiLSTM
  experiments. Keep current batch size, split, LR and objective unchanged by
  default so improvements are measured rather than attributed to LR tuning.
  Label v2 as an experiment; do not promise higher recognition accuracy.
- Version training config and checkpoint specifications with additive optional
  JSON fields, not a SwiftData schema change. Old configs decode as v1. New
  v2 checkpoints require exact architecture, parameter keys/shapes, fingerprint
  and classifier class order. Support v2 saved-run continuation into a new child
  run with a fresh optimizer. Reject v1 restore explicitly; never reinterpret
  old recurrent weights as v2 or overwrite a source checkpoint.
  Disable the Transformer-only Fine-tune path for v2; verified Resume is the
  supported continuation path in this pass.
- For recurrent training only, use the resolved MLX auxiliary-output gradient
  API to obtain loss and predictions from one forward pass. Differentiate only
  the loss. Compute metric from the same pre-update predictions and combine
  gradient-norm reduction before one host read. Keep Transformer math/step
  unchanged. Add timing counters for recurrent forward/update work as needed
  for isolated benchmarks; no unmeasured speedup claim.
- Add a truthful v2 Model diagram and model/version labels; keep existing
  navigation and token styling. Saved v2 diagrams use recorded metadata.
- Keep extraction/preprocessing, splits, text embeddings and loss formula
  unchanged. No new dependencies, project-file or silent-audio changes.

## Files

- New `Models/BiLSTMSignLanguageModel.swift`: typed v2 config/model/attention.
- `Models/LegacySignLanguageModel.swift`: mark the shared immutable BiLSTM
  helper nonisolated for background MLX calls; keep its v1 architecture/math.
- `Models/TrainingMetrics.swift`: optional-compatible recurrent version marker.
- `Logic/CheckpointCompatibility.swift`: optional v2 specification validation.
- New `Logic/BiLSTMCheckpointStore.swift`: strict v2-only read/restore boundary.
- New `Logic/RecurrentTrainingStep.swift`: one-forward auxiliary-output step.
- `Logic/TrainingSessionManager.swift`, `Logic/SignLanguageModuleWrapper.swift`:
  model selection, module conformance, metadata, strict saved-run continuation
  and recurrent-only step integration. Preserve Transformer restore behavior.
- `Views/TrainingDashboardView.swift`, `Views/RunDetailView.swift`, new
  `Views/Components/BiLSTMArchitectureView.swift`: explicit version/config and
  actual flow, without placeholder accuracy/weights. Existing design tokens.
- New `SignLanguageTranslateTests/Training/BiLSTMModelTests.swift`: pure version/
  metadata checks plus physical-only finite outputs/gradients, batch invariance,
  one-forward loss gradient equivalence, toy overfit and checkpoint round-trip.
  Isolated timing fixture may compare old/new models on identical inputs.
- This plan and `docs/status.md` for evidence and remaining limitations.

App paths are relative to `SignLanguageTranslate/`. Temporary acceptance/render
helpers are removed before commit. Logs/results remain in /tmp; build products
use the existing disposable external-drive cache.

## Checklist

- [x] Confirm resolved MLX APIs and implement versioned model/config/metadata.
- [x] Implement recurrent-only single-forward step and strict v2 checkpoint load.
- [x] Wire selection, accurate diagram and preserved-source continuation.
- [x] Run Simulator regressions/full suite and device build; document limitations.
- [x] When the active run is safely stopped, back up checkpoints and run isolated
      device learnability/gradient/restore checks without starting user training.
- [ ] Commit, install/launch and report measured results plus a new-run protocol.

The legacy run cannot continue with the v2 architecture; it is retained as the
baseline. Synthetic learnability tests establish functionality, not INCLUDE
accuracy. Evaluation remains limited by the existing split/preprocessing audit.

Reference: [Layer Normalization](https://arxiv.org/abs/1607.06450), supporting
the rationale for batch-independent normalization in recurrent models.
