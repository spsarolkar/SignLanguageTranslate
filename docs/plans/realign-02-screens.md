# Realign 02 — Screens

**One screen per session, in this order.** Each screen: read its section in
`docs/design/README.md` and its artboard, list the existing files you'll
change, get confirmation, then implement using `DesignSystem` components only.
Verify landscape and portrait in previews or the simulator.

- [ ] 1. First run (`Empty.dc.html`) — `DatasetListEmptyView`, empty detail, preflight card
- [ ] 2. Dataset detail (`Main.dc.html`) — header, dataset card, inline active transfers, categories grid; restyle `DownloadListView` rows
- [ ] 3. Sample browser (`Browser.dc.html`) — pills, word list, player overlays, confidence chart, samples grid
- [ ] 4. Portrait pass (`Portrait.dc.html`) — adapt screens 1–3; no duplicate views
- [ ] 5. Keypoint export & sync (`Export.dc.html`) — pipeline section
- [ ] 6. Token pass only (no relayout): training dashboard, inference, settings, database inspector

Rules: no business-logic changes; if a view needs data that doesn't exist yet,
use a clearly marked placeholder and note it in `docs/status.md`.
