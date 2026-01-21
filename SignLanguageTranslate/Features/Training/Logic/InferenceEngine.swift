import Foundation
import Combine
import MLX
import MLXNN
import NaturalLanguage

/// Inference engine for sign language recognition
///
/// Handles real-time prediction from pose sequences to text labels.
/// Uses the trained SignLanguageModel to generate embeddings and matches
/// them against a vocabulary of known signs.
///
/// ## Usage
/// ```swift
/// let engine = InferenceEngine()
/// try await engine.loadModel()
///
/// let prediction = try await engine.predict(frames: poseFrames)
/// print("Predicted sign: \(prediction.label) (\(prediction.confidence)%)")
/// ```
@MainActor
public class InferenceEngine: ObservableObject {

    // MARK: - Types

    public struct Prediction: Sendable {
        public let label: String
        public let confidence: Float
        public let embedding: [Float]
        public let topK: [(label: String, confidence: Float)]
    }

    public enum InferenceError: LocalizedError {
        case modelNotLoaded
        case invalidInput(String)
        case vocabularyEmpty
        case predictionFailed(String)

        public var errorDescription: String? {
            switch self {
            case .modelNotLoaded:
                return "Model not loaded. Call loadModel() first."
            case .invalidInput(let msg):
                return "Invalid input: \(msg)"
            case .vocabularyEmpty:
                return "Vocabulary is empty. Add labels before prediction."
            case .predictionFailed(let msg):
                return "Prediction failed: \(msg)"
            }
        }
    }

    // MARK: - Published State

    @Published public private(set) var isModelLoaded = false
    @Published public private(set) var isProcessing = false
    @Published public private(set) var lastPrediction: Prediction?
    @Published public private(set) var vocabulary: [String] = []

    // MARK: - Properties

    private var model: SignLanguageModel?
    private var config: SignLanguageModelConfig?
    private var labelEmbeddings: [String: [Float]] = [:]
    private let persistence = ModelPersistence()

    // MARK: - Initialization

    public init() {}

    // MARK: - Model Loading

    /// Load the best trained model
    public func loadModel() async throws {
        guard let (model, config, _) = try await persistence.loadBestModel() else {
            // Try loading latest checkpoint
            guard let (latestModel, latestConfig, _) = try await persistence.loadLatestCheckpoint() else {
                throw InferenceError.modelNotLoaded
            }
            self.model = latestModel
            self.config = latestConfig
            self.isModelLoaded = true
            print("[InferenceEngine] Loaded latest checkpoint")
            return
        }

        self.model = model
        self.config = config
        self.isModelLoaded = true
        print("[InferenceEngine] Loaded best model")
    }

    /// Load model from specific checkpoint
    public func loadModel(from url: URL) async throws {
        let (model, config, _) = try await persistence.loadModel(from: url)
        self.model = model
        self.config = config
        self.isModelLoaded = true
    }

    // MARK: - Vocabulary Management

    /// Add a label to the vocabulary with its text embedding
    public func addLabel(_ label: String) async {
        guard labelEmbeddings[label] == nil else { return }

        // Generate text embedding using NaturalLanguage
        if let embedding = generateTextEmbedding(for: label) {
            labelEmbeddings[label] = embedding
            vocabulary = Array(labelEmbeddings.keys).sorted()
            print("[InferenceEngine] Added label: \(label)")
        }
    }

    /// Add multiple labels
    public func addLabels(_ labels: [String]) async {
        for label in labels {
            await addLabel(label)
        }
    }

    /// Load labels from a dataset
    public func loadLabelsFromDataset(_ samples: [VideoSample]) async {
        let uniqueLabels = Set(samples.compactMap { $0.labels.first?.name })
        await addLabels(Array(uniqueLabels))
    }

    /// Clear all labels
    public func clearVocabulary() {
        labelEmbeddings.removeAll()
        vocabulary.removeAll()
    }

    // MARK: - Prediction

    /// Predict sign from pose frames
    public func predict(frames: [FrameFeatures], topK: Int = 5) async throws -> Prediction {
        guard let model = model else {
            throw InferenceError.modelNotLoaded
        }

        guard !labelEmbeddings.isEmpty else {
            throw InferenceError.vocabularyEmpty
        }

        guard !frames.isEmpty else {
            throw InferenceError.invalidInput("No frames provided")
        }

        isProcessing = true
        defer { isProcessing = false }

        // Process frames to input tensor
        let inputTensor = try processFrames(frames)

        // Run inference
        let embedding = model(inputTensor)

        // Convert to array
        let embeddingArray = embedding.asArray(Float.self)
        guard !embeddingArray.isEmpty else {
            throw InferenceError.predictionFailed("Empty embedding output")
        }

        // Find closest labels
        let matches = findClosestLabels(embedding: embeddingArray, topK: topK)

        guard let best = matches.first else {
            throw InferenceError.predictionFailed("No matches found")
        }

        let prediction = Prediction(
            label: best.0,
            confidence: best.1,
            embedding: embeddingArray,
            topK: matches
        )

        lastPrediction = prediction
        return prediction
    }

    /// Predict from raw input tensor (for batch processing)
    public func predictBatch(inputs: MLXArray) async throws -> [Prediction] {
        guard let model = model else {
            throw InferenceError.modelNotLoaded
        }

        guard !labelEmbeddings.isEmpty else {
            throw InferenceError.vocabularyEmpty
        }

        isProcessing = true
        defer { isProcessing = false }

        // Run batch inference
        let embeddings = model(inputs)

        // Process each sample
        var predictions: [Prediction] = []
        let batchSize = embeddings.dim(0)

        for i in 0..<batchSize {
            let embedding = embeddings[i, 0...]
            let embeddingArray = embedding.asArray(Float.self)
            let matches = findClosestLabels(embedding: embeddingArray, topK: 5)

            if let best = matches.first {
                predictions.append(Prediction(
                    label: best.0,
                    confidence: best.1,
                    embedding: embeddingArray,
                    topK: matches
                ))
            }
        }

        return predictions
    }

    // MARK: - Private Helpers

    private func processFrames(_ frames: [FrameFeatures]) throws -> MLXArray {
        let maxFrames = 60
        let featureDim = 180

        var flatData: [Float] = []
        flatData.reserveCapacity(maxFrames * featureDim)

        let frameCount = min(frames.count, maxFrames)

        // Find center point for normalization
        var offsetX: Float = 0
        var offsetY: Float = 0
        if let firstFrame = frames.first,
           let neck = firstFrame.body.first(where: { $0.id == "neck" }) ?? firstFrame.body.first(where: { $0.id == "nose" }) {
            offsetX = neck.x
            offsetY = neck.y
        }

        for i in 0..<frameCount {
            let frame = frames[i]
            flatData.append(contentsOf: serializeFrame(frame, offsetX: offsetX, offsetY: offsetY))
        }

        // Zero padding
        if frameCount < maxFrames {
            let paddingCount = (maxFrames - frameCount) * featureDim
            flatData.append(contentsOf: Array(repeating: 0.0, count: paddingCount))
        }

        return MLXArray(flatData, [1, maxFrames, featureDim])
    }

    private func serializeFrame(_ frame: FrameFeatures, offsetX: Float, offsetY: Float) -> [Float] {
        var params: [Float] = []
        params.reserveCapacity(180)

        func appendPoints(_ points: [UnifiedKeypoint]?, expected: Int) {
            if let pts = points {
                for p in pts {
                    params.append(p.x - offsetX)
                    params.append(p.y - offsetY)
                    params.append(p.confidence)
                }
                if pts.count < expected {
                    let missing = expected - pts.count
                    params.append(contentsOf: Array(repeating: 0.0, count: missing * 3))
                }
            } else {
                params.append(contentsOf: Array(repeating: 0.0, count: expected * 3))
            }
        }

        appendPoints(frame.body, expected: 18)
        appendPoints(frame.leftHand, expected: 21)
        appendPoints(frame.rightHand, expected: 21)

        return params
    }

    private func generateTextEmbedding(for text: String) -> [Float]? {
        guard let embedding = NLEmbedding.wordEmbedding(for: .english) else {
            return nil
        }

        // Try to get embedding for the text
        if let vector = embedding.vector(for: text.lowercased()) {
            // Pad or truncate to 384 dimensions to match model output
            var result = vector.map { Float($0) }
            if result.count < 384 {
                result.append(contentsOf: Array(repeating: 0.0, count: 384 - result.count))
            } else if result.count > 384 {
                result = Array(result.prefix(384))
            }

            // Normalize
            let norm = sqrt(result.reduce(0) { $0 + $1 * $1 })
            if norm > 0 {
                result = result.map { $0 / norm }
            }

            return result
        }

        // Fallback: try splitting compound words
        let words = text.lowercased().split(separator: " ")
        var combined: [Float] = Array(repeating: 0, count: 384)
        var count = 0

        for word in words {
            if let vector = embedding.vector(for: String(word)) {
                for (i, v) in vector.prefix(384).enumerated() {
                    combined[i] += Float(v)
                }
                count += 1
            }
        }

        if count > 0 {
            combined = combined.map { $0 / Float(count) }
            let norm = sqrt(combined.reduce(0) { $0 + $1 * $1 })
            if norm > 0 {
                combined = combined.map { $0 / norm }
            }
            return combined
        }

        return nil
    }

    private func findClosestLabels(embedding: [Float], topK: Int) -> [(String, Float)] {
        var similarities: [(String, Float)] = []

        for (label, labelEmb) in labelEmbeddings {
            let similarity = cosineSimilarity(embedding, labelEmb)
            similarities.append((label, similarity))
        }

        // Sort by similarity descending
        similarities.sort { $0.1 > $1.1 }

        // Convert to confidence percentage (0-100)
        return similarities.prefix(topK).map { ($0.0, max(0, $0.1) * 100) }
    }

    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }

        var dot: Float = 0
        var normA: Float = 0
        var normB: Float = 0

        for i in 0..<a.count {
            dot += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }

        let denom = sqrt(normA) * sqrt(normB)
        return denom > 0 ? dot / denom : 0
    }
}

// MARK: - Real-Time Inference

extension InferenceEngine {

    /// Stream predictions from a sequence of frames (for real-time use)
    public func streamPredictions(
        frameStream: AsyncStream<FrameFeatures>,
        windowSize: Int = 30,
        stride: Int = 10
    ) -> AsyncStream<Prediction> {
        AsyncStream { continuation in
            Task {
                var buffer: [FrameFeatures] = []

                for await frame in frameStream {
                    buffer.append(frame)

                    // Process when we have enough frames
                    if buffer.count >= windowSize {
                        do {
                            let prediction = try await predict(frames: buffer, topK: 3)
                            continuation.yield(prediction)
                        } catch {
                            print("[InferenceEngine] Prediction error: \(error)")
                        }

                        // Slide window
                        buffer = Array(buffer.suffix(windowSize - stride))
                    }
                }

                // Process remaining frames
                if !buffer.isEmpty {
                    do {
                        let prediction = try await predict(frames: buffer, topK: 3)
                        continuation.yield(prediction)
                    } catch {
                        print("[InferenceEngine] Final prediction error: \(error)")
                    }
                }

                continuation.finish()
            }
        }
    }
}

// MARK: - Model Info

extension InferenceEngine {

    /// Get information about the loaded model
    public var modelInfo: String {
        guard let config = config else {
            return "No model loaded"
        }

        return """
        Model Configuration:
        - Input Dim: \(config.inputDim)
        - Model Dim: \(config.modelDim)
        - Output Dim: \(config.outputDim)
        - Layers: \(config.numLayers)
        - Heads: \(config.numHeads)
        - Pooling: \(config.poolingType.rawValue)
        - Vocabulary Size: \(vocabulary.count)
        """
    }
}
