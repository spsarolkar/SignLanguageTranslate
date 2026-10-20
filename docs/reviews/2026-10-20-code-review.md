# Code review — 2026-10-20

Reviewed the local tree based on `237e75e`, including startup, downloads,
ingestion, feature extraction, training, model persistence, and inference.
This is a static review plus simulator build/tests, not a physical-device
training audit. Existing user experiments and archives were not executed.

## Verification

Xcode 27.0 (27A266a), Swift 5 language mode, iOS Simulator 26.2,
`iPad Pro (11-inch) (3rd generation)`. The baseline build passed. The baseline
suite ran **607 tests: 605 passed, 0 failed, 2 skipped**. After cleanup,
the final full serial run completed with **604 passed, 1 failed, 2 skipped**;
the sole failure is the pre-existing network-dependent pause test. The earlier
parallel run also encountered the known queue-advance failure and then ran out
of system-disk space while importing diagnostics. Build results, commands,
and exact failure reasons are recorded in [status](../status.md).

The committed package lockfile pins MLX Swift 0.30.6 at
`6ba4827fb82c97d012eec9ab4b2de21f85c3b33d`; the local Xcode checkout matches
that revision. The mode finding below was checked against that checkout's
`Source/MLXNN/Module.swift` and `Dropout.swift`, rather than inferred from
Python MLX or another framework.

The two skipped tests initialize MLX models and require a physical device.
Three complete suites remain behind `#if false`. Passing simulator tests
therefore do not establish training correctness or complete test coverage.

## Findings

### R1 · P1 · Training and inference disagree on input meaning

[TrainingDataPipeline](../../SignLanguageTranslate/Features/Training/Logic/TrainingDataPipeline.swift)
resamples every clip to 60 frames and centers each frame on its own neck/nose.
[InferenceEngine.processFrames](../../SignLanguageTranslate/Features/Training/Logic/InferenceEngine.swift#L228)
instead takes the first 60 frames, pads short clips, and centers all frames
using the first frame. The same clip produces different input tensors.

Both serializers append landmarks in received array order and pad missing
points at the end of each group, rather than assigning slots by landmark ID.
[VisionPoseExtractor.processObservation](../../SignLanguageTranslate/Features/FeatureExtraction/Logic/VisionPoseExtractor.swift#L53)
skips zero-confidence joints. A missing joint shifts the meanings of later
slots; extra body points can displace hand slots. Inference also lacks the
training serializer's final dimension guard. Older comments call the third
value z, but both serializers write confidence.

**Required:** one versioned, pure preprocessing contract: fixed IDs/order for
18 + 21 + 21 joints, explicit missing values, x/y/confidence semantics,
identical temporal normalization and centering, and exact shape checks.
Test a clip through both consumers, plus missing/shuffled/extra joint inputs.

### R2 · P1 · Saved model configuration does not describe the trained model

[TrainingSessionManager.initializeModel](../../SignLanguageTranslate/Features/Training/Logic/TrainingSessionManager.swift#L105)
creates an attention-pooling Transformer and sets its relative-position-bias
configuration flag to true. The same file's `startTraining` writes configurations
with mean pooling and that flag false (around lines 338 and 422). Head-count
correction is also duplicated. The pooling difference changes the reloaded
architecture, so a saved run cannot reliably reproduce its trained forward pass.
The bias flag itself is not consumed by the encoder construction; setting it
currently does not implement relative position bias.

The legacy branch passes the fixed embedding width, 384, as `numClasses`
even when cross entropy uses the dataset's word-class indices. Selecting a
classification loss does not produce the requested legacy class head.
The Transformer's forward pass also L2-normalizes output in both modes;
classification inherits an embedding-specific constraint on its logits.

**Required:** construct one effective model specification after label mapping,
persist that same specification with model family and class order, and use it
for load/resume. Verify output shape and prediction equality after reload for
each supported family/mode. Reject unsupported combinations explicitly.

### R3 · P1 · Inference interprets classification logits as embeddings

[InferenceEngine.predict](../../SignLanguageTranslate/Features/Training/Logic/InferenceEngine.swift#L139)
always finds cosine-similarity matches against 384-value text embeddings.
It does not branch on the saved output mode or read the training run's
`classes.json`. A classification model returns class logits, which have a
different meaning and usually a different width. The similarity helper returns
zero for different lengths, allowing an unrelated label to be selected.

`loadLabelsFromDataset` also uses `labels.first`; a video's first relationship
entry can be its category. The training sample embedding selection similarly
uses `sample.labels.first`, so embedding training can select category targets.

**Required:** decode classification logits with their persisted class order;
use explicitly selected word embeddings for embedding mode. Test both paths
and reject missing/incompatible label maps rather than producing predictions.

### R4 · P1 · Validation and inference leave modules in training mode

[TrainingSessionManager.runValidation](../../SignLanguageTranslate/Features/Training/Logic/TrainingSessionManager.swift#L863)
and [InferenceEngine](../../SignLanguageTranslate/Features/Training/Logic/InferenceEngine.swift)
do not change module training mode. The resolved MLX `Module` defaults to
`training = true`; `train(false)` recursively changes it. Dropout uses that
flag. `MLX.eval(...)` evaluates arrays/graphs and does not set evaluation mode.

Consequently dropout stays active in validation and inference; legacy batch
normalization can also update running statistics during validation.
Checkpoint ranking and repeated predictions are not reliable evaluation.

**Required:** deliberately enter evaluation mode for validation/inference and
restore training mode afterwards. Test repeated prediction equality and that
validation does not mutate running statistics.

### R5 · P1 · Checkpoint loading can succeed without weights; restoration can crash

[ModelPersistence.loadModel](../../SignLanguageTranslate/Features/Training/Logic/ModelPersistence.swift#L212)
prints a warning if the weights file is absent, then returns a newly
initialized model as successfully loaded. Inference sets `isModelLoaded` on
that result. A metadata-only or damaged checkpoint can silently give random
predictions.

[TrainingSessionManager.loadResumeCheckpoint](../../SignLanguageTranslate/Features/Training/Logic/TrainingSessionManager.swift#L1252)
force-casts a dictionary of `MLXArray` values to a dictionary of `NestedItem`
values before constructing parameters. The cast does not wrap the values and
can trap outside error handling. `restoreAndResume` also calls `prepare()`,
which uses a placeholder class count of 100, rather than the saved effective
class head. Optimizer/random/split state is not restored; `globalStep` is
persisted as the current batch, and the loop resumes at the next epoch.

**Required:** one checkpoint schema, atomic complete writes, validated required
weights and shapes, safe unflattening, explicit resume semantics, and failure
propagation. Cover missing/corrupt/incompatible artifacts and interrupted
resume on device. Do not promise exact continuation from the current format.

### R6 · P1 · Batch streaming has no backpressure or cancellation connection

[TrainingDataPipeline.batchStream](../../SignLanguageTranslate/Features/Training/Logic/TrainingDataPipeline.swift#L60)
creates a default unbounded `AsyncStream`. Its producer keeps loading files
and yielding tensors without waiting for the optimizer or a paused consumer.
No termination handler cancels that producer, and it does not check task
cancellation. Pausing/stopping can leave queued batches and ongoing reads.

**Required:** demand-driven batching or bounded prefetch with true producer
backpressure and propagated cancellation. Do not simply drop batches with a
buffering policy. Validate positive batch size and assert memory/prefetch stay
bounded while consuming slowly, pausing, and cancelling. A 2 TB disk does not
bound this memory use.

### R7 · P2 · Advertised training safeguards are incomplete

[TrainingSessionManager.clipGradients](../../SignLanguageTranslate/Features/Training/Logic/TrainingSessionManager.swift#L671)
computes a norm but returns the gradients unchanged. The configured clipping
threshold provides no clipping.
[EarlyStoppingCallback.onTrainEnd](../../SignLanguageTranslate/Features/Training/Callbacks/EarlyStoppingCallback.swift#L122)
does not implement `restoreBestWeights`, despite it being enabled by session
setup. Callback setup is launched in a separate unawaited task before the
training task starts, rather than being a prerequisite to the loop.

**Required:** real, tested clipping that preserves parameter structure;
best-state restoration; and awaited callback setup/reset. Test effects on
parameters and callback events, not just configuration fields.

### R8 · P1 · Evaluation can include training data

[ModelTestingViewModel.startEvaluation](../../SignLanguageTranslate/Features/Training/Logic/ModelTestingViewModel.swift#L115)
falls back to random samples from the entire store when no test split exists.
Those samples may already have been trained on. The test query is also global,
not tied to the selected run's dataset/split artifact.
[DatasetSplitter](../../SignLanguageTranslate/Features/Training/Logic/DatasetSplitter.swift)
uses unseeded shuffling, while the persisted
[StratifiedDatasetSplitter](../../SignLanguageTranslate/Features/Training/Logic/StratifiedDatasetSplitter.swift)
does not validate ratios, use `testRatio` to determine assignment, or guarantee
useful small-class allocation. These paths do not define reproducible,
signer-independent held-out results.

**Required:** persist sample IDs and split policy per run, validate ratios and
class support, use signer/source grouping where metadata supports it, and
refuse held-out evaluation without the associated test split. Never label the
random fallback as held-out accuracy. Test disjointness and reproducibility.

### R9 · P2 · Training and checkpoint callbacks share mutable state across executors

[TrainingSessionManager.runTrainingLoop](../../SignLanguageTranslate/Features/Training/Logic/TrainingSessionManager.swift#L632)
mutates the wrapper/optimizer in a detached task. Main-actor callbacks mutate
the same optimizer's learning rate and save its parameters; background-entry
handling can also save the wrapper while an update is active. Callbacks carry
the live SwiftData `TrainingRun` across the callback actor boundary. Swift 5
compilation does not establish safe ownership of these mutable objects.

**Required:** one serialized training owner for model, optimizer, mode changes,
and checkpoint snapshots; pass value events to the UI/callback layer and keep
view-context SwiftData access on the main actor. Prove pause/checkpoint/update
ordering with tests and device runs before expanding background work.

### R10 · P2 · Download reliability still depends on bypasses and real sessions

[DownloadCoordinator.startTask](../../SignLanguageTranslate/Features/DatasetManager/Downloads/DownloadCoordinator.swift#L225)
can start transfers without reserving a concurrency slot in the queue, while
the engine also schedules work. Resume All can exceed the intended limit.
[BackgroundSessionManager](../../SignLanguageTranslate/Features/DatasetManager/Downloads/BackgroundSessionManager.swift#L121)
calls URLSession while holding its existing lock. This is a lock-order risk,
not a demonstrated deadlock in this review.

[DownloadEngine](../../SignLanguageTranslate/Features/DatasetManager/Downloads/DownloadEngine.swift#L77)
uses `BackgroundSessionManager.shared`, so the mock in integration tests is
not injected. Known timing-sensitive tests passed this baseline but remain
network-dependent. Import still pauses all downloads without restoring their
prior activity, and per-part checksum validation remains absent, as recorded
in [status](../status.md).

**Required:** inject the transport, reserve all start/resume slots through the
queue, define per-dataset actions, and repair the disabled tests. Add integrity
verification and import lifecycle tests in a focused download plan.

## Cleanup completed in this review

Checked app/test references, declaration scope, previews, string/selector use,
and Xcode configuration before removing:

| Removed implementation | Evidence / retained active path |
| --- | --- |
| `DatasetManager/Views/Components/DownloadActionButton.swift` | Only self-contained previews referenced it; active rows use `TransferRow` and `IconButton` |
| `FeatureExtraction/Logic/BatchFeatureExtractionManager.swift` and its error type | No callers; startup and pipeline use `BatchExtractionService`. Its same-named nested types are separate from the active service types |
| `Training/Logic/ValidationSplitter.swift` and its top-level `SplitResult` | No callers; `DatasetSplitter.SplitResult` is a separate nested type used by the active random fallback. The persisted stratified splitter stays |
| `Training/Logic/LearningRateScheduler.swift` family | No callers of its scheduler/history/warmup types or Adam helper extension; registered `CosineLRScheduler` and `LRSchedulerCallback` stay |
| Empty `TrainingDataPipeline.batchStream(videoSamples:...)` overload, private unused feature-loader wrapper and file manager | Active callers use `SampleInfo`; the removed overload immediately finished without data. The active initializer and processing behavior stay |

Also removed a duplicated documentation comment. No tests were deleted or
disabled, no active feature was consolidated speculatively, and no source
registration was added to the project file. Documentation lives under `docs/`
because duplicate module README resources broke the first verification build;
moving the new guides resolves that without project-file changes.

## Organization and next action

The existing feature-oriented hierarchy is useful; a broad file shuffle would
add review cost without resolving these defects. The active legacy model,
two active splitters, download layers, and legacy feature repair utility have
callers and remain. Historical automation is outside scope. Untracked root
experiments, archives, and logs belong to the user and remain untouched.

The [completion roadmap](../plans/completion-roadmap.md) orders separate
implementation plans around data correctness, artifact reproducibility,
device execution, and then the remaining UI/release work. Fix R1–R6 and R8
before treating any reported recognition result as evidence of model quality.
