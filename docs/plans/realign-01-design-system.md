# Realign 01 — Design system

**Goal:** tokens and shared components exist and are used by nothing
screen-specific yet. The app looks the same except for dark mode.

- [ ] `DesignSystem/DesignTokens.swift` compiles (already added). Resolve any
      name clash with existing code rather than renaming tokens.
- [ ] `.preferredColorScheme(.dark)` and `Palette.ground` background at the app root.
- [ ] Components in `DesignSystem/Components/`, each with a `#Preview`:
  - `Card` (surface + border + radius; `raised` and `selected` variants)
  - `StatusBadge(state: StateTint, text:)`
  - `ProgressBar(value:, inFlight:, height:, tint:)`
  - `SectionHeader(eyebrow:, trailing:)`
  - `PillButton(title:, isSelected:, action:)`
  - `MetricTile(value:, caption:, tint:)`
  - `PrimaryButton` / `SecondaryButton` (min height 44)
- [ ] Values match `docs/design/README.md` § Visual language.
- [ ] Build green, tests unchanged from `docs/status.md`.
