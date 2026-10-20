# Documentation

Start with the [project README](../README.md) and the
[app architecture guide](app/README.md).

| Document | Use |
| --- | --- |
| [Code review, 2026-10-20](reviews/2026-10-20-code-review.md) | Source-backed findings, cleanup evidence, and limits of verification |
| [Status](status.md) | Dated build/test results and unresolved issues; read the latest entry |
| [Review and cleanup plan](plans/review-cleanup.md) | Scope authorized for this review, ahead of remaining screen work |
| [Completion roadmap](plans/completion-roadmap.md) | Proposed implementation sequence and acceptance gates |
| [Decisions](decisions.md) | Existing architectural choices, including keeping the `Label` model name |
| [Design specification](design/README.md) | Visual language, navigation, and screen requirements |
| [Reference artboards](design/artboards/README.md) | HTML reference designs |
| [Reference screenshots](design/screenshots/README.md) | Existing visual references |
| [Test guide](testing/README.md) | Commands, coverage gaps, simulator/device distinction |
| [Training guide](training/README.md) | Current implementation and training contracts |

## Existing work

[Realign 00](plans/realign-00-stabilize.md) and
[Realign 01](plans/realign-01-design-system.md) are recorded as complete.
[Realign 02](plans/realign-02-screens.md) has completed the first-run and dataset
detail screens; sample browsing and the subsequent screen passes remain open.
[Fix tests](plans/fix-tests.md) still records a missing session-injection seam
for network-independent download integration tests.

The original project briefs contain historical statements about a January
build failure and lack of training tests. Later status entries supersede those
statements: the app builds in this review and model configuration tests exist,
but training-loop coverage and physical-device validation remain incomplete.
The briefs' architecture and working rules still apply.

The roadmap proposes future work; it does not authorize all future refactors
or complete the unfinished realignment checklist. Each functional milestone
should receive a focused implementation plan before work starts. Keep historical
results intact and append new measured results rather than rewriting history.
