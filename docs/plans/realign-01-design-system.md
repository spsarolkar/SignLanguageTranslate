# Realign 01 — Design system

**Goal:** tokens and shared components exist and are used by nothing
screen-specific yet. The app looks the same except for dark mode.

- [x] `DesignSystem/DesignTokens.swift` compiles (already added). Resolve any
      name clash with existing code rather than renaming tokens.
      *Clash: Training's `StatusBadge(status:)` renamed `TrainingRunStatusBadge`.*
- [x] `.preferredColorScheme(.dark)` and `Palette.ground` background at the app root.
- [x] Components in `DesignSystem/Components/`, each with a `#Preview`:
  - `Card` (surface + border + radius; `raised` and `selected` variants)
  - `StatusBadge(state: StateTint, text:)`
  - `ProgressBar(value:, inFlight:, height:, tint:)`
  - `SectionHeader(eyebrow:, trailing:)`
  - `PillButton(title:, isSelected:, action:)`
  - `MetricTile(value:, caption:, tint:)`
  - `PrimaryButton` / `SecondaryButton` (min height 44)
- [x] Values match `docs/design/README.md` § Visual language.
      *Tokens added from the artboards: `Palette.textControl`, `textMuted`,
      `borderSubtle`, `borderMuted`; `Opacity`; `Typo.control`, `controlStrong`,
      `pill`, `tileCaption`, `monoSmall`; `Tracking.badge`; `Metrics.borderWidth`,
      `statusDot`, `pillHeight`; `StateTint.border`, `.label`. Padding snapped
      to the `Spacing` scale where the artboards use off-scale values (14, 18,
      13 → 12/16). Pills are 36 pt visible with a 44 pt hit area.*
- [x] Build green, tests unchanged from `docs/status.md`.
      *Baseline failures unchanged; one extra failure is pre-existing (fails at
      `0fbc10e` too), recorded in status.md.*
