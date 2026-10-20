# Training implementation

Training runs locally with MLX Swift. The current code is a prototype with
known correctness gaps, not a validated sign recognizer. Read the
[review](../reviews/2026-10-20-code-review.md) and
[roadmap](../plans/completion-roadmap.md) before extending it. Source paths
below are relative to `SignLanguageTranslate/Features/Training/`.

## Active path

1. `Views/TrainingDashboardView.swift` configures the session and can persist
   a stratified split through `Logic/StratifiedDatasetSplitter.swift`.
2. `Logic/TrainingSessionManager.swift` fetches samples on the main actor,
   builds class indices and `TrainingDataPipeline.SampleInfo` snapshots,
   creates the model/optimizer, and launches the detached training loop.
3. `Logic/TrainingDataPipeline.swift` loads feature JSON, resamples to 60
   frames, applies optional temporal/geometric augmentation, and creates
   `[batch, 60, 180]` inputs plus class labels/embedding targets.
4. `Logic/SignLanguageModuleWrapper.swift` exposes each plain model's modules
   to MLX parameter traversal and the optimizer.
5. `Callbacks/` implements early stopping, best-weight checkpoint requests,
   cosine scheduling, plateau scheduling, and optional cloud hooks. Presence
   of a callback does not mean it is registered or fully implemented.
6. `Logic/ModelPersistence.swift`, `TrainingStatePersistence.swift`, and the
   checkpoint callback implement overlapping artifact/resume formats.
7. `Logic/InferenceEngine.swift` currently uses embedding similarity;
   `ModelTestingViewModel.swift` drives saved-feature evaluation.

## Models and data

- `Models/SignLanguageModel.swift`: Transformer, with configuration presets
  and classification/embedding output modes.
- `Models/LegacySignLanguageModel.swift`: BiLSTM implementation. It is still
  selectable and is not redundant code.
- `Models/TrainingMetrics.swift`: user configuration and session state;
  `Models/TrainingRun.swift`: persisted run metadata/metrics.
- `Logic/DatasetSplitter.swift`: current random train/validation fallback.
  `StratifiedDatasetSplitter.swift`: persisted word/category splits. Neither
  currently supplies a reproducible signer-independent evaluation contract.

The intended layout is 18 body + 21 left-hand + 21 right-hand landmarks:
60 × 3 = **180 values per frame**. The current serializers write **x, y,
confidence**, despite older comments calling the third value z. Vision 2D
points store `z: nil`. Version and test the feature schema before changing
its meaning. Landmark identity/order and missing-joint handling are not yet
safe enough to treat every 180-value array as equivalent.

## Verification needed before trusting results

- Use one model configuration for construction, saving, loading, and resume;
  preserve model family, class order, preprocessing version, and all weights.
- Share deterministic preprocessing between training and inference.
- Decode classification logits with the persisted class map; keep embedding
  targets/vocabulary separate and choose word labels explicitly.
- Switch model behavior between training and evaluation, and restore it after
  validation. MLX array evaluation is different from model evaluation mode.
- Make checkpoint restore fail on missing/incompatible weights; save optimizer,
  split, random state, and progress needed for honest resume semantics.
- Bound batch prefetch and cancellation, implement configured gradient
  clipping, and test callback behavior and state ownership.
- Evaluate a held-out, reproducible test split. Do not report random samples
  from potentially trained data as held-out accuracy.

The [test guide](../testing/README.md) distinguishes
simulator checks from device tests. First validate a tiny, repeatable training
fixture on the actual M1 iPad, then measure memory, thermal behavior, throughput,
checkpoint reload, and held-out predictions. Storage capacity does not establish
a feasible model size or batch size. No measured training budget exists yet.

`TrainingBackgroundManager` has BGProcessingTask scaffolding, but relaunch and
resume require verification. `SilentAudioPlayer` is still used by feature
extraction and is development-only. Do not extend that workaround.
