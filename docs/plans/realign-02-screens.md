# Realign 02 — Screens

**One screen per session, in this order.** Each screen: read its section in
`docs/design/README.md` and its artboard, list the existing files you'll
change, get confirmation, then implement using `DesignSystem` components only.
Verify landscape and portrait in previews or the simulator.

- [x] 1. First run (`Empty.dc.html`) — `DatasetListEmptyView`, empty detail, preflight card
  - First run = no dataset has left `notStarted` (`ModelQueries.isFirstRun`, tested).
  - Refactor (approved): `startDownload` / `handleImport` / `performExtractionAndIngestion`
    moved unchanged from `DatasetDetailView` to
    `Features/DatasetManager/DatasetDownloadActions.swift` so `FirstRunView` reuses them.
    Separate commit, no behavior change, tests unchanged.
  - `DetailColumnView` now takes `selectedDataset` as a binding so starting a
    download or import selects INCLUDE.
  - New: `DashedEmptyCard`, `PreflightRow` (DesignSystem), `SystemPreflight` (Core).
  - Portrait checked in the simulator; landscape checked by rendering at
    landscape detail widths (no Simulator GUI to rotate in this environment).
- [ ] 2. Dataset detail (`Main.dc.html`) — header, dataset card, inline active transfers, categories grid; restyle `DownloadListView` rows
  - Also: sidebar storage footer from the artboards (free space + bar at the
    bottom of the sidebar), deferred from screen 1.
- [ ] 3. Sample browser (`Browser.dc.html`) — pills, word list, player overlays, confidence chart, samples grid
- [ ] 4. Portrait pass (`Portrait.dc.html`) — adapt screens 1–3; no duplicate views
- [ ] 5. Keypoint export & sync (`Export.dc.html`) — pipeline section
- [ ] 6. Token pass only (no relayout): training dashboard, inference, settings, database inspector

Rules: no business-logic changes; if a view needs data that doesn't exist yet,
use a clearly marked placeholder and note it in `docs/status.md`.
