# Fix live training pause/resume and worker ownership

Assigned by the 2026-10-21 report: after Resume the dashboard stops updating.
The observed screenshots advanced from step 3160 to 3436, then reportedly
stalled. They do not establish the runtime cause of the final stall. Static
inspection confirms Resume calls Start Training, which launches an additional
loop and recreates callbacks/data while the original loop remains alive.

## Scope

Fix live in-memory resume with one retained worker. Resume must only release
the existing pause gate, preserving run, dataset, model/optimizer, splits,
batch/epoch position and callback state. Repeated start/resume calls cannot
create additional workers. Stop while paused must wake and finish that worker.
Show whether work is training, validating or saving instead of leaving a
stationary step counter unexplained. Await progress publication in order.

Do not redesign model architecture, preprocessing, metrics meaning, numerical
training or checkpoint schema. The existing checkpoint restoration/configuration
and cross-executor callback ownership findings remain separate review items.
Do not promise mid-epoch disk recovery from an in-memory resume fix.

Preserve the running iPad app. Read-only checkpoint inventory/backup is allowed;
no install, test, launch, termination or debugger attachment on the iPad until
the user confirms the active session has ended or explicitly authorizes closing
the stalled app after acknowledging unsaved progress will be lost. Verify new
worker behavior using deterministic fake batches on Simulator, without MLX.

## Files

- New `Features/Training/Logic/TrainingWorkerLifecycle.swift`: one task owner,
  in-memory pause/stop gate, deterministic state transitions, no MLX references.
- `Features/Training/Logic/TrainingSessionManager.swift`: use that owner;
  explicit Resume; guard start/restore/prepare against an active worker;
  register callbacks before launching work; awaited progress and phase logs;
  cancellation/stop checks around validation and epoch completion; register
  lifecycle observers once. Keep model construction/numerical behavior intact.
  Background-save requests must wait for a bounded acknowledgement that the
  existing worker is parked before reading weights; preserve the old checkpoint
  if it cannot reach that boundary. Foreground notifications must not override
  a deliberate user pause. This does not repair the disk-restoration schema.
- `Features/Training/Views/TrainingDashboardView.swift`: call explicit Resume
  and display actual worker phase using existing tokens/components. Keep model
  configuration disabled throughout a live worker, including pause/stop cleanup,
  and reject UI start actions before they can rewrite that configuration.
- New `SignLanguageTranslateTests/Training/TrainingWorkerLifecycleTests.swift`:
  asynchronous fake-batch runs proving pause/resume preserves one worker and
  position, repeated actions are safe, stop works while paused, normal finish
  releases ownership and stale state cannot resume after completion.
- `docs/status.md` and this plan: evidence, exact test results and pending
  deployment; record saved checkpoint backup without asserting restorability.

App paths above are relative to `SignLanguageTranslate/`. Add no dependencies,
project-file changes, runtime-language-mode changes or silent-audio extensions.

## Checklist

- [x] Inventory/back up saved checkpoint files without changing live app state.
      Backup is `/tmp/slt-stalled-checkpoint-backup-20261021`: best weights,
      metadata and config; safetensors header parses (70 entries, 13,746,535
      bytes). Metadata reports epoch 8, valLoss 1.6671373, saved at 8:14 AM IST.
      Header parsing does not validate architecture/restoration or later steps.
- [x] Implement single-worker live pause/resume and wire all live resume entry
      points. Disk restore/fine-tune entry points reject an existing worker;
      their previously reviewed restoration limitations remain open.
- [x] Add clear training/validation/checkpoint phases and ordered progress updates.
      Await callback registration before entering the loop; stop wakes paused
      work and bypasses remaining validation/callbacks. Foreground observation
      is registered once and respects deliberate user pauses.
- [x] Run deterministic lifecycle regressions, full Simulator suite and local
      generic iOS build; record pre-existing failures. Simulator checks are
      complete: 15 lifecycle tests pass; full suite 652 passed, 1 known download
      failure, 5 existing skips (658 total). Final generic iOS Debug build passed.
- [x] Document limits and save small focused local commits.
- [x] Deploy and verify launch on hardware after explicit user authorization.
      Stop remained unresponsive; the user selected "Force-close and install"
      after being informed that unsaved progress would be discarded. Terminated
      the old process, updated the app in place and confirmed the new process
      running. Saved dataset/features and epoch-8 checkpoint files remain.
      No training or checkpoint restoration was started. Real GPU training
      pause/resume/stop acceptance remains a separate pending check.
