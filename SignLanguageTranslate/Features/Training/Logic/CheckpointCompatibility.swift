import Foundation
import CryptoKit

/// Versioned description of the model actually instantiated, not UI defaults.
nonisolated struct CheckpointModelSpecification: Codable, Sendable {
    let version: Int
    let family: String
    let config: SignLanguageModelConfig?
    let classNames: [String]
    var bilstmConfig: BiLSTMModelConfig? = nil
    var targetContract: String? = nil
    var evaluationContract: String? = nil

    init(config: SignLanguageModelConfig?, classNames: [String], family: String = "transformer", bilstmConfig: BiLSTMModelConfig? = nil) {
        self.version = 1
        self.family = family
        self.config = config
        self.classNames = classNames
        self.bilstmConfig = bilstmConfig
    }

    var outputMode: SignLanguageModelConfig.OutputMode? { config?.outputMode ?? bilstmConfig?.outputMode }

    func validatedBiLSTMConfig() throws -> BiLSTMModelConfig {
        guard version == 1, family == "bilstm-v2", case nil = config, let bilstmConfig else {
            throw CheckpointCompatibility.Error.incompatible("Only versioned BiLSTM v2 checkpoints can be restored. Legacy v1 files are preserved but unsupported.")
        }
        try bilstmConfig.validate()
        if bilstmConfig.outputMode == .classification {
            guard classNames.count == bilstmConfig.numClasses, Set(classNames).count == classNames.count,
                  classNames.allSatisfy({ !$0.isEmpty }) else {
                throw CheckpointCompatibility.Error.incompatible("BiLSTM classifier is missing its exact class order.")
            }
        }
        return bilstmConfig
    }

    func validatedConfig() throws -> SignLanguageModelConfig {
        guard version == 1, family == "transformer", let config else {
            throw CheckpointCompatibility.Error.incompatible("Unsupported checkpoint version or model family: \(family).")
        }
        try CheckpointCompatibility.validate(config)
        if config.outputMode == .classification {
            guard classNames.count == config.numClasses, Set(classNames).count == classNames.count,
                  classNames.allSatisfy({ !$0.isEmpty }) else {
                throw CheckpointCompatibility.Error.incompatible("Classification checkpoint is missing its exact class order.")
            }
        }
        return config
    }
}

/// Foundation-only checks run before MLX model allocation; no tensor values
/// are inferred from defaults or silently left at random initialization.
nonisolated enum CheckpointCompatibility {
    enum Error: LocalizedError {
        case incompatible(String)
        var errorDescription: String? {
            switch self { case .incompatible(let message): return message }
        }
    }

    static func validate(_ config: SignLanguageModelConfig) throws {
        guard config.inputDim == 180, config.modelDim > 0, config.modelDim <= 4096,
              config.numHeads > 0, config.modelDim % config.numHeads == 0,
              config.numLayers > 0, config.numLayers <= 64,
              config.outputDim > 0, config.dropout >= 0, config.dropout < 1,
              config.layerScaleInit.isFinite,
              config.outputMode != .classification || config.numClasses > 0 else {
            throw Error.incompatible("Invalid model dimensions, attention heads or output configuration.")
        }
    }

    /// Mirrors the historical training initializer, including head correction.
    /// The same function now constructs every new Transformer training model.
    static func effectiveConfig(training: TrainingConfig, numClasses: Int) throws -> SignLanguageModelConfig {
        guard !training.useLegacyModel, training.hiddenDim > 0 else {
            throw Error.incompatible("BiLSTM checkpoint restoration is unsupported by the Transformer loader.")
        }
        let requestedHeads = training.numHeads ?? 4
        guard requestedHeads > 0 else { throw Error.incompatible("Attention head count must be positive.") }
        let heads = training.hiddenDim % requestedHeads == 0 ? requestedHeads :
            SignLanguageModelConfig.findValidHeads(for: training.hiddenDim)
        let config = SignLanguageModelConfig(
            inputDim: 180, modelDim: training.hiddenDim, outputDim: 384,
            numClasses: numClasses, numLayers: training.numLayers, numHeads: heads,
            dropout: training.dropout, useLayerScale: true, layerScaleInit: 1e-4,
            poolingType: .attention, useRelativePositionBias: true,
            outputMode: training.lossFunction == .crossEntropy ? .classification : .embedding
        )
        try validate(config)
        return config
    }

    static func legacyConfig(recordedTraining data: Data, classNames: [String]) throws -> SignLanguageModelConfig {
        let required: Set<String> = ["useLegacyModel", "hiddenDim", "numLayers", "numHeads", "dropout", "lossFunction"]
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              required.isSubset(of: Set(object.keys)) else {
            throw Error.incompatible("The old run lacks recorded architecture fields; recovery would require guessing.")
        }
        let training = try JSONDecoder().decode(TrainingConfig.self, from: data)
        let config = try effectiveConfig(training: training, numClasses: classNames.count)
        _ = try CheckpointModelSpecification(config: config, classNames: classNames).validatedConfig()
        return config
    }

    static func validateShapes(expected: [String: [Int]], actual: [String: [Int]]) throws {
        let missing = Set(expected.keys).subtracting(actual.keys).sorted()
        let extra = Set(actual.keys).subtracting(expected.keys).sorted()
        let mismatched = expected.keys.filter { actual[$0] != nil && actual[$0] != expected[$0] }.sorted()
        guard missing.isEmpty, extra.isEmpty, mismatched.isEmpty else {
            throw Error.incompatible("Checkpoint parameters do not match the model. Missing: \(missing.prefix(3).joined(separator: ", ")); unexpected: \(extra.prefix(3).joined(separator: ", ")); wrong shape: \(mismatched.prefix(3).joined(separator: ", ")).")
        }
    }

    static func readShapes(at url: URL) throws -> [String: [Int]] {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let length = try handle.seekToEnd()
        try handle.seek(toOffset: 0)
        guard let prefix = try handle.read(upToCount: 8), prefix.count == 8 else {
            throw Error.incompatible("Checkpoint has an incomplete safetensors header.")
        }
        let headerLength = prefix.enumerated().reduce(UInt64(0)) { $0 | UInt64($1.element) << (8 * $1.offset) }
        guard headerLength > 0, headerLength <= 4 * 1024 * 1024, length >= 8 + headerLength,
              let data = try handle.read(upToCount: Int(headerLength)), data.count == Int(headerLength),
              let header = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Error.incompatible("Invalid or oversized safetensors header.")
        }
        var result: [String: [Int]] = [:]
        for (key, value) in header where key != "__metadata__" {
            guard let info = value as? [String: Any], let shape = info["shape"] as? [Int],
                  shape.allSatisfy({ $0 >= 0 }), let offsets = info["data_offsets"] as? [UInt64],
                  offsets.count == 2, offsets[0] <= offsets[1], offsets[1] <= length - 8 - headerLength else {
                throw Error.incompatible("Invalid tensor header or truncated weights: \(key).")
            }
            result[key] = shape
        }
        guard !result.isEmpty else { throw Error.incompatible("Checkpoint contains no tensor parameters.") }
        return result
    }

    static func fingerprint(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256()
        while let bytes = try handle.read(upToCount: 1024 * 1024), !bytes.isEmpty { hash.update(data: bytes) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
