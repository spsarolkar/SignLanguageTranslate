import Foundation
import MLX
import SwiftData

/// Analyzes extracted features to provide insights into data quality and distribution.
/// Computes Importance (Variance) and Correlation between feature dimensions.
actor FeatureAnalyzer {
    
    // MARK: - Types
    
    struct AnalysisResult: Sendable {
        /// Variance per feature index [180] (Higher = More "Movement/Importance")
        let featureVariances: [Float]
        
        /// 180x180 Correlation Matrix (Flattened or 2D)
        let correlationMatrix: [Float]
        
        /// Global statistics
        let globalMean: Float
        let globalStd: Float
        
        /// Count of dead features (near-zero variance)
        let deadFeatureCount: Int
        
        /// 2D PCA Projection points (random subset for visualization)
        let pcaPoints: [Point]
    }
    
    // MARK: - Constants
    
    static let featureDim = 180
    
    // MARK: - Public API
    
    /// Analyzes the given list of FeatureSets
    func analyze(featureSets: [FeatureSet]) async throws -> AnalysisResult {
        print("[FeatureAnalyzer] Starting analysis of \(featureSets.count) samples...")
        
        // 1. Load all data into a single massive array [TotalFrames, 180]
        var allFrames: [Float] = []
        // Reserve approx (60 frames per video)
        allFrames.reserveCapacity(featureSets.count * 60 * Self.featureDim)
        
        for (index, set) in featureSets.enumerated() {
            if let frames = await loadFeatures(at: URL(fileURLWithPath: set.filePath)) {
                for frame in frames {
                    allFrames.append(contentsOf: serializeFrame(frame))
                }
            }
            
            if index % 10 == 0 {
                // Yield to allow UI updates if needed
                await Task.yield()
            }
        }
        
        guard !allFrames.isEmpty else {
            throw NSError(domain: "FeatureAnalyzer", code: -1, userInfo: [NSLocalizedDescriptionKey: "No valid feature data found"])
        }
        
        let frameCount = allFrames.count / Self.featureDim
        print("[FeatureAnalyzer] Loaded \(frameCount) frames. Computing stats...")
        
        // 2. Convert to MLX Array [N, 180]
        let data = MLXArray(allFrames, [frameCount, Self.featureDim])
        
        // 3. Compute Stats
        
        // Global
        let mean = data.mean()
        let globalMeanVal = mean.item(Float.self)
        
        let std = MLX.std(data)
        let globalStdVal = std.item(Float.self)
        
        // Per-Feature Variance (Axis 0 = across frames)
        let variances = MLX.variance(data, axis: 0)
        let varianceArray = variances.asArray(Float.self)
        
        // Identify dead features (< 1e-5 variance)
        let deadCount = varianceArray.filter { $0 < 1e-5 }.count
        
        // 4. Compute Correlation Matrix
        
        // Standardize data: Z = (X - mean) / std
        let means = data.mean(axis: 0, keepDims: true)
        let stds = MLX.std(data, axis: 0, keepDims: true)
        
        // Avoid division by zero
        let safeStds = MLX.where(stds .== 0, MLXArray(1.0), stds)
        
        let normalized = (data - means) / safeStds
        
        // Covariance of normalized data is Correlation
        // (Z^T * Z) / (N - 1)
        let n = Float(frameCount)
        let correlation = matmul(normalized.T, normalized) / MLXArray(n - 1)
        
        // Flatten for easy consumption (180*180)
        let correlationArray = correlation.asArray(Float.self)
        
        print("[FeatureAnalyzer] Analysis complete.")
        
        return AnalysisResult(
            featureVariances: varianceArray,
            correlationMatrix: correlationArray,
            globalMean: globalMeanVal,
            globalStd: globalStdVal,
            deadFeatureCount: deadCount,
            pcaPoints: computePCA(normalized: normalized, frameCount: frameCount)
        )
    }
    
    /// 5. Compute PCA (2D Projection)
    private func computePCA(normalized: MLXArray, frameCount: Int) -> [Point] {
        // Use SVD on the covariance matrix (approx) or smaller subset if N is huge
        // For visualization, we only need top 2 components.
        
        // Downsample if too large for SVD speed (e.g. max 5000 samples for projection calculation)
        let maxSamples = 2000
        let effectiveN = min(frameCount, maxSamples)
        
        // Take a random subset or first N for SVD calculation
        // (MLX slicing: [0...effectiveN])
        let subset = normalized[0..<effectiveN]
        
        // Compute Covariance: C = (X^T * X) / (N-1)
        let n = Float(effectiveN)
        let cov = matmul(subset.T, subset) / MLXArray(n - 1)
        
        // SVD of Covariance (180x180) -> U, S, Vt
        // U contains eigenvectors (Principal Components)
        let svdResult = MLX.svd(cov)
        let U = svdResult.0 // [180, 180]
        
        // Project all data (or a display subset) onto top 2 components
        // Top 2 eigenvectors = U[0...180, 0...2] (Wait, MLX columns or rows? Usually cols are vectors in U)
        // Let's assume standard SVD: A = U S V^T. 
        // For Cov matrix (Symmetric): U = V. Columns of U are eigenvectors.
        
        let top2 = U[0...179, 0...1] // [180, 2]
        
        // Projection: Proj = X * U_reduced
        // We project a subset for visualization (e.g., 500 points) to keep UI fast
        let plotCount = min(frameCount, 500)
        let plotSubset = normalized[0..<plotCount]
        let projected = matmul(plotSubset, top2) // [500, 180] * [180, 2] = [500, 2]
        
        // Convert to Structs
        let pointsArray = projected.asArray(Float.self)
        var points: [Point] = []
        for i in 0..<plotCount {
            let x = pointsArray[i * 2]
            let y = pointsArray[i * 2 + 1]
            points.append(Point(x: x, y: y))
        }
        
        return points
    }
    
    struct Point: Codable, Sendable {
        let x: Float
        let y: Float
    }
    
    // MARK: - Helpers
    
    private func loadFeatures(at url: URL) async -> [FrameFeatures]? {
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode([FrameFeatures].self, from: data)
        } catch {
            print("[FeatureAnalyzer] Failed to load \(url.lastPathComponent)")
            return nil
        }
    }
    
    private func serializeFrame(_ frame: FrameFeatures) -> [Float] {
        var params = [Float]()
        params.reserveCapacity(Self.featureDim)
        
        // Normalize Center (Neck)
        var offsetX: Float = 0
        var offsetY: Float = 0
        
        if let neck = frame.body.first(where: { $0.id == "neck" }) ?? frame.body.first(where: { $0.id == "nose" }) {
            offsetX = neck.x
            offsetY = neck.y
        }
        
        func appendPoints(_ points: [UnifiedKeypoint]?, expected: Int) {
            if let pts = points {
                for p in pts {
                    params.append(p.x - offsetX)
                    params.append(p.y - offsetY)
                    params.append(p.confidence)
                }
                if pts.count < expected {
                    params.append(contentsOf: Array(repeating: 0.0, count: (expected - pts.count) * 3))
                }
            } else {
                params.append(contentsOf: Array(repeating: 0.0, count: expected * 3))
            }
        }
        
        appendPoints(frame.body, expected: 18)
        appendPoints(frame.leftHand, expected: 21)
        appendPoints(frame.rightHand, expected: 21)
        
        // Truncate/Pad
        if params.count > Self.featureDim {
            return Array(params.prefix(Self.featureDim))
        } else if params.count < Self.featureDim {
            return params + Array(repeating: 0.0, count: Self.featureDim - params.count)
        }
        
        return params
    }
}
