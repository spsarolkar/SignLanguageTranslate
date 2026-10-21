import Foundation
import MLX
import MLXNN

/// Strict v2-only loading; no legacy model/weight reinterpretation or writes.
enum BiLSTMCheckpointStore {
    struct Metadata: Decodable {
        let epoch: Int
        let value: Float?
        let weightsSHA256: String
        let specification: CheckpointModelSpecification
    }

    static func readMetadata(at url: URL) throws -> Metadata {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let limit = 1024 * 1024
        guard let data = try handle.read(upToCount: limit + 1), data.count <= limit else {
            throw CheckpointCompatibility.Error.incompatible("Invalid BiLSTM checkpoint metadata size.")
        }
        let metadata = try JSONDecoder().decode(Metadata.self, from: data)
        _ = try metadata.specification.validatedBiLSTMConfig()
        guard metadata.epoch >= 0, metadata.weightsSHA256.count == 64,
              metadata.weightsSHA256.allSatisfy({ $0.isHexDigit }), metadata.value?.isFinite != false else {
            throw CheckpointCompatibility.Error.incompatible("Incomplete BiLSTM checkpoint epoch, loss or fingerprint.")
        }
        return metadata
    }

    static func load(metadataURL: URL) throws -> (BiLSTMSignLanguageModel, Metadata) {
        let metadata = try readMetadata(at: metadataURL)
        let basename = metadataURL.deletingPathExtension().lastPathComponent
        guard basename.hasSuffix("_metadata") else {
            throw CheckpointCompatibility.Error.incompatible("Unsupported BiLSTM checkpoint layout.")
        }
        let weights = metadataURL.deletingLastPathComponent().appendingPathComponent(String(basename.dropLast("_metadata".count)) + ".safetensors")
        guard try CheckpointCompatibility.fingerprint(weights) == metadata.weightsSHA256 else {
            throw CheckpointCompatibility.Error.incompatible("BiLSTM checkpoint fingerprint mismatch; weights were not applied.")
        }
        let shapes = try CheckpointCompatibility.readShapes(at: weights)
        let model = try BiLSTMSignLanguageModel(config: metadata.specification.validatedBiLSTMConfig())
        let wrapper = SignLanguageModuleWrapper(model: model)
        let expected = Dictionary(uniqueKeysWithValues: wrapper.parameters().flattened().map { ($0.0, $0.1.shape) })
        try CheckpointCompatibility.validateShapes(expected: expected, actual: shapes)
        let arrays = try loadArrays(url: weights)
        try CheckpointCompatibility.validateShapes(expected: expected, actual: arrays.mapValues { $0.shape })
        try wrapper.update(parameters: ModuleParameters.unflattened(arrays), verify: .all)
        return (model, metadata)
    }
}
