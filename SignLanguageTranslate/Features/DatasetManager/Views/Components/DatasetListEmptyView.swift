import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Content-column state on first run (`ModelQueries.isFirstRun`): no dataset
/// has started, so the list shows a dashed placeholder instead of rows.
struct DatasetListEmptyView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            DashedEmptyCard(
                title: "Nothing downloaded",
                message: "Datasets appear here once a download starts."
            )
            Spacer(minLength: 0)
        }
        .padding(Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Palette.chrome)
    }
}

/// Empty state view for a specific section
struct DatasetSectionEmptyView: View {
    let section: SectionType
    let compact: Bool

    enum SectionType {
        case available
        case downloading
        case ready
        case failed

        var message: String {
            switch self {
            case .available:
                return "All datasets have been downloaded or are in progress"
            case .downloading:
                return "No downloads in progress"
            case .ready:
                return "No datasets ready yet. Start downloading to get started."
            case .failed:
                return "No failed downloads"
            }
        }

        var icon: String {
            switch self {
            case .available:
                return "checkmark.circle"
            case .downloading:
                return "arrow.down.circle"
            case .ready:
                return "square.stack.3d.up"
            case .failed:
                return "checkmark.seal"
            }
        }
    }

    init(section: SectionType, compact: Bool = true) {
        self.section = section
        self.compact = compact
    }

    var body: some View {
        if compact {
            HStack(spacing: Spacing.sm) {
                Image(systemName: section.icon)
                    .foregroundStyle(Palette.textTertiary)
                    .accessibilityHidden(true)
                Text(section.message)
                    .font(Typo.caption)
                    .foregroundStyle(Palette.textMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, Spacing.md)
        } else {
            VStack(spacing: Spacing.md) {
                Image(systemName: section.icon)
                    .font(Typo.title)
                    .foregroundStyle(Palette.textTertiary)
                    .accessibilityHidden(true)
                Text(section.message)
                    .font(Typo.caption)
                    .foregroundStyle(Palette.textMuted)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.xxl)
        }
    }
}

// MARK: - First Run

/// Detail pane on first run: header, call to action and a preflight card.
/// Download and import reuse `DatasetDownloadActions`, so behavior matches
/// the dataset detail view.
struct FirstRunView: View {
    /// The INCLUDE dataset seeded at launch; nil disables both actions.
    let dataset: Dataset?
    /// Called with the dataset once a download or import starts.
    var onStarted: (Dataset) -> Void = { _ in }

    @Environment(\.modelContext) private var modelContext
    @Environment(DownloadManager.self) private var downloadManager

    @State private var preflight = SystemPreflight()
    @State private var isImporting = false
    @State private var importError: String?
    @State private var showImportError = false

    var body: some View {
        // Fits without scrolling on iPad in both orientations; scrolls when
        // Dynamic Type or a narrow split pushes it past the height.
        ViewThatFits(in: .vertical) {
            content
            ScrollView { content }
        }
        .background(Palette.ground)
        .task { await preflight.monitor() }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [UTType.zip],
            allowsMultipleSelection: false
        ) { result in
            guard let dataset else { return }
            actions(for: dataset).handleImport(result)
            if case .success = result {
                onStarted(dataset)
            }
        }
        .alert("Import Failed", isPresented: $showImportError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(importError ?? "Unknown error")
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: Spacing.section) {
            header
            Spacer(minLength: 0)
            hero
                .frame(maxWidth: .infinity)
            Spacer(minLength: 0)
        }
        .padding(.top, Spacing.paneTop)
        .padding([.horizontal, .bottom], Spacing.pane)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: Spacing.md) {
            Text(NavigationSection.datasets.rawValue)
                .font(Typo.largeTitle)
                .tracking(Tracking.largeTitle)
                .foregroundStyle(Palette.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: Spacing.md)
            StatusBadge(state: .idle, text: "Idle")
        }
    }

    private var hero: some View {
        VStack(spacing: Spacing.xxl) {
            FirstRunGlyph()
                .frame(width: Metrics.heroIcon, height: Metrics.heroIcon)
                .accessibilityHidden(true)

            VStack(spacing: Spacing.sm) {
                Text("No training data yet")
                    .font(Typo.heroTitle)
                    .foregroundStyle(Palette.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text("Fetch the INCLUDE word-level corpus from Zenodo, or import an archive you already have on an external SSD. Downloads run in the background and resume after interruptions.")
                    .font(Typo.body)
                    .lineSpacing(Metrics.paragraphLineSpacing)
                    .foregroundStyle(Palette.textMuted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: Metrics.heroTextWidth)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: Spacing.md) { buttons }
                VStack(spacing: Spacing.md) { buttons }
            }
            .disabled(dataset == nil)

            preflightCard
                .frame(maxWidth: Metrics.preflightWidth)
        }
    }

    @ViewBuilder
    private var buttons: some View {
        PrimaryButton(title: "Download INCLUDE · \(Self.gigabytes(INCLUDEManifest.measuredTotalSize))", size: .large) {
            guard let dataset else { return }
            actions(for: dataset).startDownload()
            onStarted(dataset)
        }
        SecondaryButton(title: "Import from Files", size: .large) {
            isImporting = true
        }
    }

    // MARK: Preflight

    private var preflightCard: some View {
        Card(padding: 0, radius: Radius.cardLarge) {
            VStack(alignment: .leading, spacing: Spacing.md) {
                SectionHeader(eyebrow: "Preflight")
                PreflightRow(label: "Free storage", value: storageValue, state: storageState)
                PreflightRow(label: "Network", value: networkValue, state: networkState)
                PreflightRow(
                    label: "Low Data Mode",
                    value: preflight.isLowDataMode ? "On" : "Off",
                    state: preflight.isLowDataMode ? .queued : .complete
                )
                PreflightRow(
                    label: "Low Power Mode",
                    value: preflight.isLowPowerMode ? "On — will throttle" : "Off",
                    state: preflight.isLowPowerMode ? .queued : .complete
                )
                Text("Keep the app in the app switcher — force-quitting cancels background downloads.")
                    .font(Typo.caption2)
                    .foregroundStyle(Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, Spacing.xl)
            .padding(.horizontal, Spacing.xxl)
        }
    }

    private var storageValue: String {
        guard let free = preflight.freeBytes else { return "Unknown" }
        return free.formatted(.byteCount(style: .file))
    }

    /// Amber when free space is below what download plus extraction needs.
    private var storageState: StateTint {
        guard let free = preflight.freeBytes else { return .idle }
        return free >= INCLUDEManifest.requiredFreeSpace ? .complete : .queued
    }

    private var networkValue: String {
        switch preflight.connection {
        case .checking: return "Checking…"
        case .offline: return "Offline"
        case .wifi: return "Wi-Fi"
        case .wiredEthernet: return "Ethernet"
        case .cellular: return "Cellular"
        case .other: return "Connected"
        }
    }

    private var networkState: StateTint {
        switch preflight.connection {
        case .checking: return .idle
        case .offline: return .failed
        case .cellular: return .queued
        case .wifi, .wiredEthernet, .other: return .complete
        }
    }

    // MARK: Helpers

    private func actions(for dataset: Dataset) -> DatasetDownloadActions {
        DatasetDownloadActions(
            dataset: dataset,
            modelContext: modelContext,
            downloadManager: downloadManager,
            onImportError: { message in
                importError = message
                showImportError = true
            }
        )
    }

    /// Decimal gigabytes to one place: 56,751,819,975 bytes → "56.8 GB".
    static func gigabytes(_ bytes: Int64) -> String {
        Measurement(value: Double(bytes), unit: UnitInformationStorage.bytes)
            .converted(to: .gigabytes)
            .formatted(.measurement(
                width: .abbreviated,
                usage: .asProvided,
                numberFormatStyle: .number.precision(.fractionLength(1))
            ))
    }
}

/// Dashed tray with a down arrow. Geometry from `Empty.dc.html`, drawn in a
/// 132-unit box and scaled to the frame.
private struct FirstRunGlyph: View {
    var body: some View {
        GeometryReader { proxy in
            let unit = min(proxy.size.width, proxy.size.height) / 132
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 12 * unit, style: .continuous)
                    .stroke(
                        Palette.borderMuted,
                        style: StrokeStyle(lineWidth: 2 * unit, dash: [7 * unit, 7 * unit])
                    )
                    .frame(width: 104 * unit, height: 76 * unit)
                    .offset(x: 14 * unit, y: 30 * unit)
                Path { path in
                    path.move(to: CGPoint(x: 66 * unit, y: 52 * unit))
                    path.addLine(to: CGPoint(x: 66 * unit, y: 86 * unit))
                    path.move(to: CGPoint(x: 54 * unit, y: 74 * unit))
                    path.addLine(to: CGPoint(x: 66 * unit, y: 86 * unit))
                    path.addLine(to: CGPoint(x: 78 * unit, y: 74 * unit))
                }
                .stroke(
                    Palette.accent,
                    style: StrokeStyle(lineWidth: 2.6 * unit, lineCap: .round, lineJoin: .round)
                )
            }
        }
    }
}

// MARK: - Previews

#Preview("First run · landscape", traits: .landscapeLeft) {
    FirstRunView(dataset: .previewIncludeNotStarted)
        .modelContainer(PersistenceController.preview.container)
        .environment(DownloadManager())
}

#Preview("First run · portrait", traits: .portrait) {
    FirstRunView(dataset: .previewIncludeNotStarted)
        .modelContainer(PersistenceController.preview.container)
        .environment(DownloadManager())
}

#Preview("Dataset list · first run") {
    DatasetListEmptyView()
        .frame(width: Metrics.sidebarWidth)
}

#Preview("Section Empty States") {
    List {
        Section("Available") {
            DatasetSectionEmptyView(section: .available)
        }
        Section("Downloading") {
            DatasetSectionEmptyView(section: .downloading)
        }
        Section("Ready") {
            DatasetSectionEmptyView(section: .ready, compact: false)
        }
    }
    .listStyle(.insetGrouped)
}
