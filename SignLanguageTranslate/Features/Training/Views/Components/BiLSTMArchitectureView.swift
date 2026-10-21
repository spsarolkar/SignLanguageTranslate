import SwiftUI

struct BiLSTMArchitectureView: View {
    let config: BiLSTMModelConfig
    var source = "Configuration preview · fresh v2 experiment"
    private var outputWidth: String { config.outputMode == .embedding ? "\(config.outputDim)" : (config.numClasses > 0 ? "\(config.numClasses)" : "C") }
    private var stages: [(String, String)] { [
        ("Pose frames", "[B, 60, \(config.inputDim)]"),
        ("Frame projection → LayerNorm → GELU", "[B, 60, \(config.hiddenDim)]"),
        ("BiLSTM × \(config.numLayers) · \(config.hiddenDim) units per direction", "[B, 60, \(config.hiddenDim * 2)]"),
        ("Temporal attention over all frames", "[B, \(config.hiddenDim * 2)]"),
        ("LayerNorm → Dropout (\(config.dropout))", "[B, \(config.hiddenDim * 2)]"),
        (config.outputMode == .embedding ? "Direct projection → L2 normalization" : "Direct projection → raw class logits", "[B, \(outputWidth)]")
    ] }
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("BiLSTM v2").font(Typo.title2)
            Text(source).font(Typo.caption).foregroundStyle(Palette.accent)
            Text("Batch-independent normalization and an attention-weighted sequence summary. Dropout between recurrent layers applies only when two layers are selected. B is the actual batch size; C is the dataset word count.")
                .font(Typo.caption).foregroundStyle(Palette.textSecondary).fixedSize(horizontal: false, vertical: true)
            ForEach(Array(stages.enumerated()), id: \.offset) { index, stage in
                if index > 0 { Image(systemName: "arrow.down").foregroundStyle(Palette.textTertiary).accessibilityHidden(true) }
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(stage.0).font(Typo.monoCaption).foregroundStyle(Palette.accentBlue)
                    Text(stage.1).font(Typo.monoCaption)
                }
                .padding(Spacing.md).frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.card))
            }
            Text("This is a new architecture and requires a new run; legacy v1 weights are kept separately. Accuracy gains must be measured on the same validation split.")
                .font(Typo.caption).foregroundStyle(Palette.textTertiary).fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(Palette.textPrimary).padding(Spacing.lg)
        .background(Palette.ground, in: RoundedRectangle(cornerRadius: Radius.panel))
    }
}

struct BiLSTMConfigurationDiagramView: View {
    let training: TrainingConfig
    var instantiatedConfig: BiLSTMModelConfig? = nil
    var body: some View {
        if let config = instantiatedConfig { BiLSTMArchitectureView(config: config, source: "Instantiated model") }
        else if let config = try? preview() { BiLSTMArchitectureView(config: config) }
        else { ContentUnavailableView("Architecture unavailable", systemImage: "cpu", description: Text("Check the v2 recurrent width, layer count and dropout.")) }
    }
    private func preview() throws -> BiLSTMModelConfig {
        var structural = training
        structural.lossFunction = .contrastive
        var config = try BiLSTMModelConfig.effective(training: structural, numClasses: 0)
        config.outputMode = training.lossFunction == .crossEntropy ? .classification : .embedding
        return config
    }
}

struct SavedBiLSTMDiagramView: View {
    let run: TrainingRun
    @State private var config: BiLSTMModelConfig?
    @State private var error: String?
    var body: some View {
        Group {
            if let config { BiLSTMArchitectureView(config: config, source: "Saved model specification") }
            else if let error { ContentUnavailableView("Architecture unavailable", systemImage: "cpu", description: Text(error)) }
            else { ProgressView("Reading saved architecture…") }
        }.task(id: run.id) {
            config = nil
            error = nil
            do {
                let directory = TrainingSessionManager.shared.getRunCheckpointDirectory(runName: run.name)
                let metadata = try BiLSTMCheckpointStore.readMetadata(at: directory.appendingPathComponent("best_metadata.json"))
                config = try metadata.specification.validatedBiLSTMConfig()
            } catch { self.error = error.localizedDescription }
        }
    }
}
