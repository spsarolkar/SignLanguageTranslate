# Accurate Transformer model diagram

Assigned by the user's request to correct the Transformer diagram under Model.
This authorizes replacing that diagram, without a general dashboard redesign.

## Scope

- Replace the generic dense-neuron drawing for Transformer with the actual
  forward sequence: pose frames, input projection/LayerNorm, sinusoidal position
  and dropout, repeated pre-norm attention/MLP residual blocks, final LayerNorm,
  configured pooling, output projection and L2 normalization.
- Show effective dimensions/heads, encoder count, dropout and MLP expansion.
  Expand encoder branches to explain attention, GELU MLP, LayerScale and skip
  additions. No invented activations, weights, parameter counts or class counts.
- Use the instantiated model's config for live sessions. Idle configuration is
  explicitly a preview, with symbolic C for an unresolved classifier size.
  Saved-run Model uses its recorded specification, or an explicitly labelled
  reconstruction from complete legacy settings. Invalid/missing data fails
  visibly instead of silently showing defaults. Never allocate/read GPU weights.
- Reflect implementation rather than aspirational config comments: sinusoidal
  position is used; relative position bias is not wired; stochastic depth is
  disabled; first-timestep pooling does not add a CLS token; L2 normalization
  currently applies in both embedding and classification modes. No model edits.
- Retain the existing Model tab and BiLSTM view. Use one responsive hierarchy,
  existing tokens (add diagram dimensions if needed), accessible disclosure
  controls and readable shapes. Architecture only; no fake live weight data.
- Preserve current iPad training. Install/test/launch on device only after the
  session is stopped. Build outputs may use a disposable external-drive cache
  because internal space is low; all logs/results remain in /tmp.

## Files

- New `Features/Training/Logic/TransformerArchitectureDiagram.swift`: pure
  diagram snapshot, effective preview and bounded saved-spec reading.
- New `Features/Training/Views/Components/TransformerArchitectureView.swift`:
  flow, expandable residual block and metadata wrappers.
- `NeuralNetVisualizer.swift`: route Transformer uses to the new preview;
  retain the existing BiLSTM drawing without unrelated changes.
- `TrainingDashboardView.swift`, `RunDetailView.swift`: use live/preview versus
  recorded configuration; remove fixed Transformer canvas height.
- `TrainingSessionManager.swift`: expose a read-only config value snapshot.
- `DesignSystem/DesignTokens.swift`: diagram-specific layout dimensions.
- New `SignLanguageTranslateTests/Training/TransformerArchitectureDiagramTests.swift`:
  real head correction, shapes/output modes, pooling variants and unavailable
  or legacy saved metadata. Optional temporary render fixture is removed before
  commit; its screenshots/helper remain in /tmp.
- This plan and `docs/status.md` for evidence and deployment limits.

App paths are relative to `SignLanguageTranslate/`. No dependencies, project
file, training math, checkpoint writes or unrelated view changes.

## Checklist

- [x] Implement truthful configuration snapshots and diagram structure.
- [x] Wire responsive diagram to live, preview and historical Model tabs.
- [x] Test configuration regressions, inspect rendered narrow/wide layouts,
      build green and record existing test failures.
      All 11 new tests pass. Full Simulator: 718 passed, two recorded download
      failures, 12 skips (732 total, including a temporary render check).
      Inspected collapsed/expanded renders at 360/760 pt and removed the helper
      before delivery. Generic iOS build and signature verification passed.
- [ ] Commit and document; install/launch when session status permits.
