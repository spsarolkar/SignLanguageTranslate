# Design spec

Source of truth for the look of the app. Tokens are in
`SignLanguageTranslate/DesignSystem/DesignTokens.swift`; this file says where
they go and how screens are laid out.

The canvas this came from lives in Claude Design. `artboards/*.dc.html` are
exports of its artboards. They **do not render standalone** (they need the
canvas runtime) — read them as markup: every size, color, radius and gap is in
the inline `style` attributes, and sample data is in the `renderVals()` script
at the bottom of each file. If screenshots exist in `screenshots/`, prefer them
for overall layout and the markup for exact values.

## Precedence when things disagree

1. **Code facts win on data.** Feature layout is 60 landmarks / 180 values. The
   artboards say "61 landmarks", "19 body joints", `[T,61,3]` — use 60, 18,
   `[T,60,3]` in UI copy.
2. **The existing information architecture wins on navigation.** Keep
   `NavigationSection` (datasets, downloads, pipeline, training, settings) and
   the three-column split. The artboards show a simplified sidebar; apply its
   *styling* to the existing sections.
3. **The artboards win on visual treatment**: colors, type, spacing, radii,
   card structure, states, overlay panels.
4. Sample numbers in artboards (clip counts, GB, MB/s, accuracies) are
   placeholders. Bind to real model data; never hardcode them.

## Visual language

- Dark ground `Palette.ground`; sidebar `Palette.chrome`; cards
  `Palette.surface` with 1 pt `Palette.border`; selected card
  `Palette.surfaceRaised` + `Palette.borderSelected`.
- Radii: panels 18, cards 12–14, controls 11, pills fully rounded.
- Accent teal `Palette.accent` = active / complete / healthy. Amber
  `Palette.warning` = queued / resumed / throttled. Red `Palette.danger` =
  failed / quarantined / low confidence. Blue = model/inference; violet = the
  experimental reservoir arm. Use `StateTint` rather than picking per call site.
- Section eyebrows: `Typo.eyebrow`, uppercase, tracking `Tracking.eyebrow`,
  `Palette.textTertiary` ("ACTIVE TRANSFERS", "CATEGORIES").
- All counts, sizes, rates, confidences, IDs and durations: `Typo.mono`.
- Status badge (top right of a screen): pill with a 7 pt dot + label, tinted
  fill and border from `StateTint` — "Processing", "Extracting", "Idle".
- Progress bars: 8 pt (dataset), 6 pt (transfer row), 4–5 pt (compact). Track
  `Palette.track`. Overall dataset bar shows complete (solid) + in-flight
  (accent at ~32% opacity) segments.
- Overlays on video (confidence panel, playback bar): on iOS 26 prefer the
  system glass material (`.glassEffect`) over a custom translucent fill; keep
  the layout from the artboards.
- Empty inline list state: dashed `Palette.border` outline, secondary text.

## Screens

### 1. Data Pipeline — dataset detail, downloading · `Main.dc.html` (1366×1024)
Maps to: detail column for a selected dataset — `DatasetBrowserView` /
`DetailColumnView` + components (`DatasetHeaderSection`, `DatasetStatsSection`,
`DatasetCategoriesSection`, `DatasetProgressIndicator`, `DownloadTaskRowView`).

- Header: large title (`Typo.largeTitle`) + status badge.
- Dataset card (panel radius): name, meta line ("Word-level · Zenodo record
  4010759 · 15 categories · 44 parts"), buttons **Pause All** (secondary) and
  **Download All** (primary, accent fill, dark text). Overall progress bar and a
  mono line: "N complete · N active · N queued" / "X GB of Y GB".
- **Active transfers** section inline in the detail (eyebrow + "n of 3 slots"):
  one row per active part — filename, category, 6 pt bar, "a / b GB · r MB/s",
  44 pt pause button. A resumed part shows amber text "resumed at n%".
- **Categories** grid, 5 columns: name, 4 pt bar, "done / total" parts. Bar is
  accent when complete, amber when partial, track color when none.
- The Downloads sheet (`DownloadListView`) stays for the full queue; restyle it
  with the same row component.

### 2. Sample browser · `Browser.dc.html` (1366×1024) — interactive
Maps to: `DatasetSamplesView`, `FeatureExtraction/Views/DataPipelineView`,
`VideoAnnotationPlayer`, `KeypointVisualizer`, `FilterBarView`.

- Content column (≈260 pt): category **pills** at top (wrapping); below, the
  word list — rows with word name and mono clip count; selected row uses
  `surfaceRaised`.
- Detail: breadcrumb "INCLUDE / Animals", word as title, two label chips
  (Category · Animals in accent, Word · Dog in blue).
- **Video player 16:9**, radius 16, skeleton overlay: joints accent-bright,
  hand points amber, bones accent stroke.
  - Floating panel top-right: "KEYPOINT CONFIDENCE", big mono % , rows Hands
    42/42, Body n/18, Frames n.
  - Playback bar bottom: play button (accent), elapsed / scrubber / duration in
    mono, "Skeleton" toggle.
- **Per-frame confidence** chart card (Swift Charts line): threshold as a
  dashed danger line, dips below it marked amber; header shows min and mean.
- **Samples** grid, 6 columns: clip id + mono confidence; below-threshold clips
  get danger text and a danger-tinted border.

### 3. Portrait · `Portrait.dc.html` (1024×1366)
Same views, compact width. Sidebar collapses behind the toolbar button. Order
top→bottom: status bar row, breadcrumb + large title, dataset card, category
pills, full-width 16:9 player with overlays, word grid (5 columns), samples
grid (8 columns). No separate portrait view types.

### 4. Keypoint export & sync · `Export.dc.html` (1366×1024)
Maps to: the **pipeline** section. Largely new UI over existing services
(`BatchExtractionService`, `BatchFeatureExtractionManager`,
`HuggingFaceSyncService`).

- Stage strip: Ingested → Extract keypoints → Shard → Push to Hub → Models.
  Current stage raised with amber border; done stages accent; pending grey.
- Left: **On-device extraction** card — progress, "n of N clips · ~m min
  remaining", four metric tiles (clips/min, sampled fps, mean confidence,
  quarantined in danger). **Shard schema** card listing fields and types.
- Right: **Hugging Face dataset** card — repo id (placeholder until set),
  train/val/test split bars, Keychain token status, **Dry run** / **Push**
  buttons. **Trained models** card — rows with name, meta, mono accuracy and an
  action (Active / Download / Queued). Copy fix: title "Trained models", not
  "from Colab" — models are trained on device.

### 5. First run · `Empty.dc.html` (1366×1024)
Maps to: `DatasetListEmptyView` + empty detail.
- Sidebar datasets section shows a dashed empty card.
- Centered: icon, "No training data yet", one paragraph, buttons
  **Download INCLUDE · <size>** (primary) and **Import from Files**.
- **Preflight** card: free storage, network, background transfers, Low Power
  Mode (amber when on). Values from the system, not hardcoded.

## Not designed yet

Training dashboard, inference view, settings, database inspector. Apply tokens
and card/section/eyebrow components to them; do not redesign their layout
until an artboard exists.
