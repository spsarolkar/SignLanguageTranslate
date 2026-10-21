import SwiftUI

struct TransformerArchitectureView: View {
    let diagram: TransformerArchitectureDiagram
    @State private var showEncoder = false

    init(diagram: TransformerArchitectureDiagram, initiallyExpanded: Bool = false) {
        self.diagram = diagram
        _showEncoder = State(initialValue: initiallyExpanded)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Transformer encoder").font(Typo.title2)
                Text(diagram.source.rawValue).font(Typo.caption).foregroundStyle(Palette.accent)
                Text("Architecture and tensor shapes. No live activations or weight values are displayed.")
                    .font(Typo.caption).foregroundStyle(Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                if diagram.source == .legacy {
                    Text("Legacy settings reconstruction; checkpoint weights are not inspected by this diagram.")
                        .font(Typo.caption).foregroundStyle(Palette.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: Metrics.architectureTileMinWidth), alignment: .leading)], alignment: .leading, spacing: Spacing.md) {
                summary("Model width", "\(diagram.config.modelDim)")
                summary("Encoder blocks", "\(diagram.config.numLayers)")
                summary("Attention heads", "\(diagram.config.numHeads)")
                summary("MLP width", "\(diagram.mlpWidth)")
            }
            VStack(spacing: Spacing.sm) {
                ForEach(diagram.stages) { stage in
                    if stage.id != .input {
                        Image(systemName: "arrow.down").font(Typo.caption).foregroundStyle(Palette.textTertiary)
                            .accessibilityHidden(true)
                    }
                    stageCard(stage)
                }
            }
            Text("Implementation notes: positional encoding is sinusoidal; the relative-position-bias setting is not wired into attention. Stochastic depth is currently disabled. Dropout is active during training and disabled during evaluation.")
                .font(Typo.caption).foregroundStyle(Palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(Palette.textPrimary)
        .padding(Spacing.lg)
        .background(Palette.ground, in: RoundedRectangle(cornerRadius: Radius.panel))
    }

    private func summary(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(title).font(Typo.caption).foregroundStyle(Palette.textTertiary)
            Text(value).font(Typo.monoMetric)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.md)
        .background(Palette.well, in: RoundedRectangle(cornerRadius: Radius.card))
    }

    private func stageCard(_ stage: TransformerArchitectureDiagram.Stage) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.md) {
                    stageTitle(stage).fixedSize()
                    Spacer(minLength: Spacing.sm)
                    Text(stage.shape).font(Typo.monoCaption).fixedSize()
                }
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    stageTitle(stage)
                    Text(stage.shape).font(Typo.monoCaption)
                }
            }
            Text(stage.detail).font(Typo.monoCaption).foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if stage.id == .encoder {
                DisclosureGroup(isExpanded: $showEncoder) {
                    VStack(alignment: .leading, spacing: Spacing.lg) {
                        branch("Attention branch", steps: diagram.attentionBranch, residual: "x₁ = x + attention branch")
                        branch("Feed-forward branch", steps: diagram.mlpBranch, residual: "x₂ = x₁ + feed-forward branch")
                        Text("Repeat this block \(diagram.config.numLayers) times with separate parameters.")
                            .font(Typo.monoCaption).foregroundStyle(Palette.textTertiary)
                    }.padding(.top, Spacing.md)
                } label: {
                    Text("Inside each encoder block").font(Typo.control)
                        .frame(minHeight: Metrics.touchTarget, alignment: .leading)
                }
                .tint(Palette.accentViolet)
            }
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.card))
        .overlay(RoundedRectangle(cornerRadius: Radius.card).stroke(Palette.border, lineWidth: Metrics.borderWidth))
    }

    private func stageTitle(_ stage: TransformerArchitectureDiagram.Stage) -> some View {
        Text(stage.title).font(stage.id == .encoder ? Typo.monoMetric : Typo.headline)
            .foregroundStyle(stage.id == .encoder ? Palette.accentViolet : Palette.accentBlue)
    }

    private func branch(_ title: String, steps: [String], residual: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(title).font(Typo.control).foregroundStyle(Palette.accentViolet)
            ForEach(Array(steps.enumerated()), id: \.offset) { _, step in
                HStack(alignment: .top, spacing: Spacing.sm) {
                    Image(systemName: "arrow.down").accessibilityHidden(true)
                    Text(step)
                }.font(Typo.monoCaption).foregroundStyle(Palette.textSecondary)
            }
            SwiftUI.Label(residual, systemImage: "arrow.triangle.branch")
                .font(Typo.monoCaption).foregroundStyle(Palette.accent)
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.well, in: RoundedRectangle(cornerRadius: Radius.card))
    }
}

struct TransformerConfigurationDiagramView: View {
    let training: TrainingConfig
    var instantiatedConfig: SignLanguageModelConfig? = nil

    var body: some View {
        if let diagram = try? makeDiagram() {
            TransformerArchitectureView(diagram: diagram)
        } else {
            ContentUnavailableView("Architecture unavailable", systemImage: "cpu", description: Text("The selected Transformer settings are invalid. Check model width, head count and encoder count."))
        }
    }

    private func makeDiagram() throws -> TransformerArchitectureDiagram {
        if let instantiatedConfig { return try TransformerArchitectureDiagram(config: instantiatedConfig, source: .live) }
        return try TransformerArchitectureDiagram.preview(training: training)
    }
}

struct SavedTransformerDiagramView: View {
    let run: TrainingRun
    @State private var diagram: TransformerArchitectureDiagram?
    @State private var error: String?

    var body: some View {
        Group {
            if let diagram {
                TransformerArchitectureView(diagram: diagram)
            } else if let error {
                ContentUnavailableView("Architecture unavailable", systemImage: "cpu", description: Text(error))
            } else { ProgressView("Reading saved architecture…") }
        }
        .task(id: run.id) {
            diagram = nil
            error = nil
            do {
                let directory = TrainingSessionManager.shared.getRunCheckpointDirectory(runName: run.name)
                diagram = try TransformerArchitectureDiagram.readSaved(recordedTraining: run.configData, specificationURL: directory.appendingPathComponent("model-specification.json"))
                error = nil
            } catch { self.error = error.localizedDescription }
        }
    }
}
