# Completion roadmap

Proposed on 2026-10-20 for local Indian Sign Language training on the 2021
iPad Pro M1, 2 TB. This is a sequence of reviewable milestones, not a claim
that the features are complete. No accuracy target, resource budget, delivery
date, or full-dataset throughput has been measured yet.

The user authorized review/documentation/verified dead-code cleanup ahead of
the unfinished realignment screens. Functional work below needs a focused plan
per milestone; this roadmap does not authorize unrelated refactors or change
the order within the existing screen plan.

## 0. Establish the starting point

- [x] Review the active pipeline and identify redundant implementations.
- [x] Remove implementations without callers while preserving active paths.
- [x] Add a project entry point and architecture/training/test guides.
- [x] Record the simulator baseline: build passes; 605 passed, 0 failed,
      2 skipped before cleanup.
- [x] Record final cleanup verification: build passes; 604 passed, 1 known
      network-dependent failure, 2 skipped. Save cleanup and review documentation
      in separate local commits.

Evidence: [review](../reviews/2026-10-20-code-review.md),
[cleanup checklist](review-cleanup.md), [status](../status.md).

## 1. Make dataset operations reliable and tests deterministic

Create a download reliability plan based on R10 and the unresolved
[test-fix plan](fix-tests.md).

- [ ] Add a transport seam so tests never depend on example.com or a real
      background session. Repair/re-enable the three compiled-out suites.
- [ ] Route all start/resume operations through actor-owned slot reservation;
      prove concurrency limits under simultaneous pending/resumed transfers.
- [ ] Define dataset-scoped pause/resume/cancel and restore the appropriate
      download activity after import. Move URLSession calls outside the
      existing lock's critical sections without adding new locks.
- [ ] Store authoritative per-part metadata/checksums and validate completed
      downloads/imports. Reconcile stale seed/estimate values with the manifest.
- [ ] Test import → extraction → ingestion with small local archives,
      interruption, duplicate inputs, malformed parts, and insufficient storage.

**Exit:** offline, deterministic download tests; re-enabled suites; no lost or
duplicated task state across restart; integrity failures remain visible and
retryable. Record actual on-device download/import behavior in status.

## 2. Define a canonical feature and split contract

Create a preprocessing/data-contract plan for R1 and R8 before changing
existing feature meaning.

- [ ] Specify a versioned 18-body/21-left/21-right ID order and
      x/y/confidence layout, fixed missing-joint slots, orientation, centering,
      temporal resampling, confidence handling, and exact tensor dimensions.
- [ ] Share a pure transformation between training, evaluation, and inference;
      make augmentation explicit and training-only. Choose a compatibility or
      re-extraction policy for existing JSON and checkpoints.
- [ ] Reject or report corrupt/empty/incompatible feature files instead of
      silently accepting unusable batches. Capture a reproducible extraction
      configuration and source provenance.
- [ ] Persist deterministic per-run train/validation/test sample IDs and
      explicit word-class order. Validate ratios, empty sets, class support,
      and grouping by signer/source where available. Identify missing signer
      metadata before promising signer-independent evaluation.

**Exit:** CPU fixtures prove exact shape/order, missing-joint handling,
train/inference equality, no validation augmentation, and split disjointness
and repeatability. No held-out claim uses a random whole-store fallback.

## 3. Complete a correct small training loop and artifact round trip

Create a focused MLX correctness plan for R2–R7 and R9. Check each API against
the lockfile-matching Swift checkout before implementation.

- [ ] Use a single effective model configuration with model family, output
      mode, class vocabulary, and preprocessing version. Explicitly validate
      legacy/classification and Transformer/embedding combinations.
- [ ] Serialize ownership of model/optimizer/mode/checkpoint state. Keep live
      SwiftData records on their owning executor and send value events to UI.
- [ ] Implement demand-driven batches or bounded backpressure with cancellation;
      validate configuration before allocating tensors or entering the loop.
- [ ] Verify nonempty trainable parameters, finite loss/gradients, actual weight
      updates, real gradient clipping, train/eval switching, and scheduler
      behavior. Await callback setup and implement best-weight restoration.
- [ ] Unify checkpoint storage/discovery. Save all required model state and
      fail on missing/corrupt/incompatible weights. Save optimizer/random/split
      state and a precise cursor for continuation, or explicitly document
      restart-at-epoch behavior. Remove the unsafe restoration cast.
- [ ] On the physical iPad, overfit a tiny deterministic labeled fixture,
      reload its checkpoint, and verify equivalent evaluation predictions.

**Exit:** repeated tiny-device runs learn, checkpoints reproduce predictions,
invalid artifacts fail visibly, and cancellation/slow consumption keep prefetch
bounded. No simulator pass is counted as a GPU training test.

## 4. Make evaluation and inference describe the same model

- [ ] Decode classification output with its saved class order; explicitly
      support embedding vocabulary matching as a separate mode.
- [ ] Select word labels by type, validate vocabulary dimensions/coverage, and
      associate evaluation with the chosen run's dataset and held-out split.
- [ ] Report sample counts, top-1/top-k and per-class results for the fixed
      test split. Label embedding similarity as similarity; do not silently
      present it as a calibrated probability or classification accuracy.
- [ ] Verify offline saved-feature inference before completing camera capture,
      live-window buffering, orientation, and cancellation.

**Exit:** held-out results can be reproduced from a saved run; class decoding
and preprocessing match training; unsupported/no-model/no-sign conditions are
visible. Record measured results without asserting a target in advance.

## 5. Validate the actual M1 iPad resource and lifecycle budget

- [ ] Record OS/device configuration, free space, source/feature sizes, peak
      memory, model parameter count, batch time, epoch duration, thermal state,
      and energy behavior for a small known configuration.
- [ ] Increase workload only after measurements establish headroom. The
      device's 2 TB storage is not available GPU training memory.
- [ ] Verify extraction pause/resume, training pause/stop, termination recovery,
      checkpoint consistency, and background-task expiration. The existing
      BGProcessingTask scaffold must handle relaunch, not just a live singleton.
- [ ] Replace the development-only silent-audio workaround with supported
      processing/checkpoint recovery before release; never promise continuous
      training while iPadOS suspends the app.

**Exit:** a documented supported configuration and interruption matrix on the
target device, with no unbounded queues or corrupted artifacts. Performance
claims cite the measured fixture and configuration.

## 6. Finish the planned UI and optional sync

- [ ] Resume [realign-02](realign-02-screens.md) in its own order: sample browser,
      sidebar/list cards, portrait pass, export/sync screen, then token pass.
      Keep its per-screen file list, confirmation, and visual verification.
- [ ] Replace misleading placeholders with measured values or clear empty
      states; verify touch targets, accessibility, landscape, and portrait.
- [ ] Validate optional Hugging Face/R2 upload/download round trips, artifact
      integrity, Keychain credentials, retries, cancellation, and error states.

**Exit:** the existing screen checklist is complete and the local workflow
works without a cloud account. Sync restores a compatible tested artifact.

## 7. Establish a release gate

- [ ] Automate a reproducible simulator build/test job without changing the
      historical Python orchestrator. Add a separate physical-device MLX
      verification procedure; state which checks are manual.
- [ ] Run the complete suite, publish accurate coverage gaps, finish device
      end-to-end acceptance, and resolve or explicitly defer every review ID.
- [ ] Document dataset provenance/terms, application licensing, privacy/storage
      behavior, supported configurations, setup, recovery, and known limits.

**Exit:** a tagged candidate with a reproducible setup, green supported checks,
recorded device evidence, and no unsupported model-quality claims.

Additional architectures (spiking model or fly-connectome reservoir) remain
deferred until this pipeline is reproducible and a separate plan exists. Any
connectome experiment requires its shuffled-graph control.
