import SwiftUI
import AVKit

struct LocalFilePreviewView: View {
    let path: String
    let store: LocalFileStore
    var onClose: () -> Void = {}
    @State private var preview: LocalFilePreview?
    @State private var error: String?
    @State private var loading = false
    @State private var frameIndex = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.section) {
                if loading { ProgressView("Reading file…").tint(Palette.accent) }
                if let error {
                    Card { Text(error).font(Typo.body).foregroundStyle(Palette.warning) }
                }
                if let preview {
                    information(preview.entry)
                    previewContent(preview.content)
                }
            }
            .frame(maxWidth: Metrics.workspaceIdealWidth)
            .padding(Spacing.xl)
            .frame(maxWidth: .infinity)
        }
        .background(Palette.ground)
        .navigationTitle((path as NSString).lastPathComponent)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: path) { await refresh() }
        .toolbar {
            LocalFileCloseControl(action: onClose)
            ToolbarItem(placement: .primaryAction) {
                IconButton(systemImage: "arrow.clockwise", accessibilityLabel: "Refresh file preview") {
                    Task { await refresh() }
                }
                .disabled(loading)
            }
        }
    }

    private func information(_ entry: LocalFileEntry) -> some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.md) {
                SwiftUI.Label(entry.name, systemImage: entry.kind.icon)
                    .font(Typo.headline).foregroundStyle(Palette.textPrimary)
                    .lineLimit(2).truncationMode(.middle)
                    .textSelection(.enabled)
                Text("Documents/\(entry.path)")
                    .font(Typo.monoCaption).foregroundStyle(Palette.textSecondary)
                    .textSelection(.enabled)
                Text(ByteCountFormatter.string(fromByteCount: entry.size, countStyle: .file))
                    .font(Typo.monoMetric).foregroundStyle(Palette.textPrimary)
                if let date = entry.modified {
                    Text("Modified \(date.formatted(date: .abbreviated, time: .standard))")
                        .font(Typo.monoCaption).foregroundStyle(Palette.textTertiary)
                }
            }
        }
    }

    @ViewBuilder
    private func previewContent(_ content: LocalFilePreview.Content) -> some View {
        switch content {
        case .features(let frames, let text, let truncated):
            if frames.isEmpty {
                Card {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Text("No frames saved").font(Typo.title2).foregroundStyle(Palette.warning)
                        Text("This feature file is empty. Use Extract all in Pipeline to retry it.")
                            .font(Typo.body).foregroundStyle(Palette.textSecondary)
                    }
                }
            } else {
                featureInspector(frames)
            }
            Card {
                DisclosureGroup("Raw JSON") { LocalRawText(text: text, truncated: truncated) }
                    .font(Typo.control).foregroundStyle(Palette.textSecondary)
            }
        case .text(let text, let truncated, let note):
            Card {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    if let note { Text(note).font(Typo.body).foregroundStyle(Palette.warning) }
                    LocalRawText(text: text, truncated: truncated)
                }
            }
        case .video(let url):
            LocalVideoPreview(url: url)
        case .image(let data):
            if let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFit()
                    .frame(maxHeight: Metrics.filePreviewHeight)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.card))
            }
        case .information(let message):
            Card { Text(message).font(Typo.body).foregroundStyle(Palette.textSecondary) }
        }
    }

    private func featureInspector(_ frames: [FrameFeatures]) -> some View {
        let index = min(frameIndex, frames.count - 1)
        let frame = frames[index]
        return VStack(alignment: .leading, spacing: Spacing.section) {
            Card {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    SectionHeader(eyebrow: "Saved frames", trailing: frames.count.formatted())
                    Text(Set(frames.map(\.sourceModel)).sorted().joined(separator: ", "))
                        .font(Typo.caption).foregroundStyle(Palette.textSecondary)
                    Stepper(value: $frameIndex, in: 0...(frames.count - 1)) {
                        Text("Frame \(index + 1) of \(frames.count)")
                            .font(Typo.monoCaption).foregroundStyle(Palette.textPrimary)
                    }
                    .frame(minHeight: Metrics.touchTarget)
                    if frames.count > 1 {
                        Slider(value: Binding(get: { Double(index) }, set: { frameIndex = Int($0) }),
                               in: 0...Double(frames.count - 1), step: 1)
                            .accessibilityLabel("Feature frame")
                    }
                    Text(String(format: "Timestamp %.3f s", frame.timestamp))
                        .font(Typo.monoCaption).foregroundStyle(Palette.textSecondary)
                    Text("Body \(frame.body.count) · Left hand \(frame.leftHand?.count ?? 0) · Right hand \(frame.rightHand?.count ?? 0)")
                        .font(Typo.monoCaption).foregroundStyle(Palette.textSecondary)
                }
            }
            Card {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    Text("Normalized keypoint plot").font(Typo.headline).foregroundStyle(Palette.textPrimary)
                    Canvas { context, size in
                        draw(frame.body, color: Palette.accent, in: context, size: size)
                        draw(frame.leftHand ?? [], color: Palette.accentBlue, in: context, size: size)
                        draw(frame.rightHand ?? [], color: Palette.warning, in: context, size: size)
                    }
                    .frame(height: Metrics.filePreviewHeight)
                    .background(Palette.control, in: RoundedRectangle(cornerRadius: Radius.card))
                    .clipped()
                    .accessibilityLabel("Saved keypoints for frame \(index + 1). Coordinate values are listed below.")
                    Text("Body: teal · Left hand: blue · Right hand: amber")
                        .font(Typo.caption).foregroundStyle(Palette.textSecondary)
                }
            }
            keypointTable("Body", points: frame.body)
            keypointTable("Left hand", points: frame.leftHand ?? [])
            keypointTable("Right hand", points: frame.rightHand ?? [])
        }
    }

    private func keypointTable(_ title: String, points: [UnifiedKeypoint]) -> some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.md) {
                SectionHeader(eyebrow: title, trailing: points.count.formatted())
                if points.isEmpty {
                    Text("No points detected in this frame.").font(Typo.body).foregroundStyle(Palette.textSecondary)
                } else {
                    ScrollView(.horizontal) {
                        Grid(alignment: .leading, horizontalSpacing: Spacing.lg, verticalSpacing: Spacing.md) {
                            GridRow {
                                Text("Joint"); Text("X"); Text("Y"); Text("Z"); Text("Confidence")
                            }
                            .font(Typo.caption).foregroundStyle(Palette.textTertiary)
                            ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                                GridRow {
                                    Text(point.id)
                                    Text(String(format: "%.3f", point.x))
                                    Text(String(format: "%.3f", point.y))
                                    Text(point.z.map { String(format: "%.3f", $0) } ?? "—")
                                    Text(String(format: "%.3f", point.confidence))
                                }
                                .font(Typo.monoCaption).foregroundStyle(Palette.textPrimary)
                            }
                        }
                        .textSelection(.enabled)
                    }
                }
            }
        }
    }

    private func draw(_ points: [UnifiedKeypoint], color: Color, in context: GraphicsContext, size: CGSize) {
        for point in points where point.confidence > 0 {
            let diameter = Metrics.keypointPreviewDiameter
            let rect = CGRect(x: CGFloat(point.x) * size.width - diameter / 2,
                              y: CGFloat(point.y) * size.height - diameter / 2,
                              width: diameter, height: diameter)
            context.fill(Path(ellipseIn: rect), with: .color(color))
        }
    }

    private func refresh() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        do {
            let snapshot = try await store.preview(path: path)
            try Task.checkCancellation()
            preview = snapshot
            frameIndex = 0
            error = nil
        } catch is CancellationError {
        } catch {
            preview = nil
            self.error = "This file may have changed or moved. \(error.localizedDescription)"
        }
    }
}

private struct LocalRawText: View {
    let text: String
    let truncated: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            if truncated {
                Text("Preview limited to the first 64 KiB.").font(Typo.caption).foregroundStyle(Palette.warning)
            }
            ScrollView([.horizontal, .vertical]) {
                Text(text.isEmpty ? "Empty file" : text)
                    .font(Typo.monoCaption).foregroundStyle(Palette.textSecondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: Metrics.fileTextPreviewHeight)
        }
    }
}

private struct LocalVideoPreview: View {
    let url: URL
    @State private var player: AVPlayer?
    var body: some View {
        VideoPlayer(player: player)
            .frame(height: Metrics.filePreviewHeight)
            .clipShape(RoundedRectangle(cornerRadius: Radius.card))
            .onAppear { player = AVPlayer(url: url) }
            .onDisappear { player?.pause(); player = nil }
    }
}
