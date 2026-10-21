import Foundation
import MLXNN

nonisolated struct TrainingWordTarget: Sendable {
    let name: String
    let embedding: [Float]

    @MainActor
    static func resolve(_ sample: VideoSample, requiresEmbedding: Bool) throws -> Self {
        let words = sample.labels.filter { $0.typeRawValue == LabelType.word.rawValue }
        guard words.count == 1 else { throw TrainingEvaluationError.invalid("A clip must have exactly one word label.") }
        let name = words[0].name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw TrainingEvaluationError.invalid("The word label is empty.") }
        guard requiresEmbedding else { return Self(name: name, embedding: []) }
        guard let vector = words[0].embedding, vector.count == 384, vector.allSatisfy(\.isFinite) else {
            throw TrainingEvaluationError.invalid("Word '\(name)' needs a finite 384-value embedding.")
        }
        let norm = vector.reduce(Float(0)) { $0 + $1 * $1 }
        guard norm.isFinite, norm > 0 else { throw TrainingEvaluationError.invalid("Word '\(name)' has an empty embedding direction.") }
        return Self(name: name, embedding: vector)
    }
}

nonisolated enum TrainingEvaluationError: LocalizedError {
    case invalid(String)
    var errorDescription: String? { switch self { case .invalid(let message): return message } }
}

nonisolated struct TrainingVocabulary: Sendable {
    let words: [String]
    let embeddings: [[Float]]
    var indices: [String: Int] { Dictionary(uniqueKeysWithValues: words.enumerated().map { ($0.element, $0.offset) }) }

    init(targets: [TrainingWordTarget]) throws {
        var byWord: [String: [Float]] = [:]
        for target in targets {
            if let previous = byWord[target.name], previous != target.embedding {
                throw TrainingEvaluationError.invalid("Conflicting embeddings for word '\(target.name)'.")
            }
            byWord[target.name] = target.embedding
        }
        words = byWord.keys.sorted()
        embeddings = words.map { byWord[$0]! }
    }

    /// Rank the entire vocabulary, with deterministic class-index tie breaking.
    /// Targets identify words, not positions of matching clips in a batch.
    func recognition(scores: [Float], targets: [Int]) throws -> (top1: Int, top5: Int) {
        guard !words.isEmpty, !targets.isEmpty, scores.count == targets.count * words.count,
              scores.allSatisfy(\.isFinite), targets.allSatisfy({ words.indices.contains($0) }) else {
            throw TrainingEvaluationError.invalid("Invalid recognition scores or word indices.")
        }
        var top1 = 0
        var top5 = 0
        for (row, target) in targets.enumerated() {
            let offset = row * words.count
            let ranked = words.indices.sorted {
                scores[offset + $0] == scores[offset + $1] ? $0 < $1 : scores[offset + $0] > scores[offset + $1]
            }
            if ranked.first == target { top1 += 1 }
            if ranked.prefix(5).contains(target) { top5 += 1 }
        }
        return (top1, top5)
    }
}

nonisolated struct ValidationResult: Sendable {
    let loss: Float
    let cosineSimilarity: Float?
    let top1: Float
    let top5: Float
    let sampleCount: Int
}

nonisolated struct ValidationTotals {
    private var weightedLoss: Double = 0
    private var weightedSimilarity: Double = 0
    private var similarityCount = 0
    private var sampleCount = 0
    private var top1Count = 0
    private var top5Count = 0

    mutating func add(loss: Float, similarity: Float?, samples: Int, top1: Int, top5: Int) throws {
        guard samples > 0, loss.isFinite, similarity?.isFinite != false,
              top1 >= 0, top5 >= top1, top5 <= samples else {
            throw TrainingEvaluationError.invalid("Validation produced non-finite values or invalid sample counts.")
        }
        weightedLoss += Double(loss) * Double(samples)
        sampleCount += samples
        top1Count += top1
        top5Count += top5
        if let similarity {
            weightedSimilarity += Double(similarity) * Double(samples)
            similarityCount += samples
        }
    }

    func result() throws -> ValidationResult {
        guard sampleCount > 0 else { throw TrainingEvaluationError.invalid("No validation samples could be evaluated; no score was recorded.") }
        return ValidationResult(loss: Float(weightedLoss / Double(sampleCount)),
                                cosineSimilarity: similarityCount > 0 ? Float(weightedSimilarity / Double(similarityCount)) : nil,
                                top1: Float(top1Count) / Float(sampleCount), top5: Float(top5Count) / Float(sampleCount), sampleCount: sampleCount)
    }
}

nonisolated enum TrainingEvaluationPolicy {
    static let version = 2
    static let targetContract = "explicit-word-target-v1"
    static let evaluationContract = "evaluation-mode-full-word-vocabulary-v1"

    static func validatesAfterBatch(step: Int, interval: Int) -> Bool {
        step > 0 && interval > 0 && step.isMultiple(of: interval)
    }
}

nonisolated enum ModelEvaluationMode {
    static func withEvaluation<Value>(_ wrapper: SignLanguageModuleWrapper,
                                      operation: () async throws -> Value) async rethrows -> Value {
        // Restore parents before children so mixed prior modes are preserved.
        let previous = wrapper.namedModules().sorted {
            $0.0.split(separator: ".").count < $1.0.split(separator: ".").count
        }.map { ($0.1, $0.1.training) }
        wrapper.train(false)
        defer { for (module, training) in previous { module.train(training) } }
        return try await operation()
    }
}
