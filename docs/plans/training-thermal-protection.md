# Automatic thermal pause and resume

Assigned by the user's 2026-10-21 request to add automatic thermal pause/resume.
This is a focused follow-up to the completed live-resume and evaluation plans.

## Behavior and scope

- Observe ProcessInfo thermal state independently of the dashboard's monitor.
  Pause the single existing worker at serious (Hot) or critical; finish the
  current operation and park at its cooperative boundary. Check the initial
  state before any batches, including saved-run continuation.
- Resume automatically only after nominal/fair (Normal/Warm) continuously for
  30 seconds. Recheck the current thermal state before releasing the gate.
  Reheating cancels that cooldown. No temperatures in degrees are inferred.
- Keep user, background-save and thermal pause reasons independent. Manual
  Pause overrides automatic resume, including when already cooling. Manual
  Resume cannot bypass heat protection. Background save cannot be undone by
  cooling; foreground clears only its own reason. Stop/completion cancels
  observers/timers so stale callbacks cannot restart a completed or new run.
- Preserve model/optimizer, metrics, run, data iterator and batch position.
  No new worker, checkpoint reload, model/loss/LR changes or schema changes.
- Show cooling and automatic-resume guidance with existing design tokens;
  provide a Keep paused action during automatic cooling.
- No changes to SilentAudioPlayer, dependencies, project file or extraction.
- Do not test, terminate, replace or launch the iPad app during user training.
  Build/test on Simulator first. The user subsequently confirmed
  "Stopped—install the update"; read-only run metadata also reports Stopped.

## Files

- New `SignLanguageTranslate/Features/Training/Logic/TrainingThermalProtection.swift`:
  injectable thermal source, one observer, cancellable cooldown and lifecycle.
- `TrainingSessionManager.swift`: independent pause reasons and one worker gate,
  start/Stop/completion monitoring and safe background/foreground interactions.
- `TrainingDataPipeline.swift`: optional producer pause boundary before loading
  and tensor creation, plus stream-termination cancellation. It must not mark
  the GPU worker parked. Keep preprocessing and buffer policy unchanged.
- `Views/TrainingDashboardView.swift`: visible cooling status/manual ownership.
- New `SignLanguageTranslateTests/Training/TrainingThermalProtectionTests.swift`:
  simulated thermal notifications, hysteresis, same-worker progress, manual and
  background precedence, Stop/restart, stale timers and observer lifecycle.
- This plan and `docs/status.md`: results, limits and deployment state.

## Checklist

- [x] Implement monitoring/cooldown and independent pause reasons.
- [x] Add clear cooling status and manual-pause action.
- [x] Run focused lifecycle/evaluation regressions, full Simulator suite and build.
      Focused: 55 passed, four GPU-only skipped. Full: 706 passed, two recorded
      pre-existing download failures, 12 skipped (720 total); all 18 new thermal
      regressions passed, including controller release. Generic iOS build passed.
- [x] Record results and save focused commits.
      Implementation/tests: `afcb8c8`.
- [x] Install/launch only after the current training session is safely stopped.
      Backed up the epoch-31 run and all earlier checkpoints before device
      checks. Physical iPad: all 60 thermal/lifecycle/evaluation tests passed,
      including four GPU tests. Final normal device build, in-place install and
      launch succeeded (PID 1731). SHA256 of all 11 original checkpoint files
      matched after testing/install/launch. No user training was started.

Thermal cooldown is an application policy, not a measured hardware temperature.
It cannot interrupt a GPU kernel already in flight or guarantee background
execution when iPadOS suspends the process. Saved checkpoint recovery remains
separate from an in-memory thermal pause.

API reference: [Apple thermal-state notifications](https://developer.apple.com/documentation/foundation/processinfo/thermalstatedidchangenotification).
The monitor reads `thermalState` before registering, as required by Apple.
