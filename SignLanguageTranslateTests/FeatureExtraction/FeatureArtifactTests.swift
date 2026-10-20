import XCTest
@testable import SignLanguageTranslate

@MainActor
final class FeatureArtifactTests: XCTestCase {
    func test_savedRelativePathRoundTripsAndCanBeReused() async throws {
        let (root, manager) = try storage()
        defer { try? FileManager.default.removeItem(at: root) }
        let path = try manager.saveFeatures(frames(), forVideoPath: "INCLUDE/Jobs/Actor/clip.mov", modelName: "AppleVision")

        XCTAssertFalse(path.hasPrefix("/"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent(path).path))
        let loaded = try manager.loadFeatures(at: path)
        XCTAssertEqual(loaded.count, 2)
        XCTAssertEqual(loaded[1].timestamp, 0.1)
        XCTAssertEqual(loaded[0].body.first?.confidence, 0.9)
        XCTAssertTrue(manager.canReuseFeatures(at: path, frameCount: 2))
    }

    func test_emptyWriteCannotOverwriteValidFeatures() async throws {
        let (root, manager) = try storage()
        defer { try? FileManager.default.removeItem(at: root) }
        let path = try manager.saveFeatures(frames(), forVideoPath: "clip.mov", modelName: "AppleVision")
        let original = try Data(contentsOf: root.appendingPathComponent(path))

        XCTAssertThrowsError(try manager.saveFeatures([], forVideoPath: "clip.mov", modelName: "AppleVision"))

        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(path)), original)
    }

    func test_legacyEmptyFileIsRejectedEvenWithPositiveMetadata() async throws {
        let (root, manager) = try storage()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("[]".utf8).write(to: root.appendingPathComponent("empty.json"))

        XCTAssertThrowsError(try manager.loadFeatures(at: "empty.json"))
        XCTAssertFalse(manager.canReuseFeatures(at: "empty.json", frameCount: 0))
        XCTAssertFalse(manager.canReuseFeatures(at: "empty.json", frameCount: 20))
    }

    func test_corruptMissingAndMismatchedArtifactsAreNotReused() async throws {
        let (root, manager) = try storage()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("not-json".utf8).write(to: root.appendingPathComponent("bad.json"))
        let path = try manager.saveFeatures(frames(), forVideoPath: "clip.mov", modelName: "AppleVision")

        XCTAssertFalse(manager.canReuseFeatures(at: "bad.json", frameCount: 2))
        XCTAssertFalse(manager.canReuseFeatures(at: "missing.json", frameCount: 2))
        XCTAssertFalse(manager.canReuseFeatures(at: path, frameCount: 3))
        XCTAssertFalse(manager.canReuseFeatures(at: path, frameCount: 0))
    }

    func test_reExtractionReplacesLegacyEmptyArtifactAtSameRelativePath() async throws {
        let (root, manager) = try storage()
        defer { try? FileManager.default.removeItem(at: root) }
        let path = try manager.saveFeatures(frames(), forVideoPath: "clip.mov", modelName: "AppleVision")
        try Data("[]".utf8).write(to: root.appendingPathComponent(path))
        XCTAssertFalse(manager.canReuseFeatures(at: path, frameCount: 0))

        let recoveredPath = try manager.saveFeatures(frames(), forVideoPath: "clip.mov", modelName: "AppleVision")

        XCTAssertEqual(path, recoveredPath)
        XCTAssertTrue(manager.canReuseFeatures(at: recoveredPath, frameCount: 2))
    }

    func test_analysisResolvesRelativeFeaturePathsUnderStorageRoot() async throws {
        let (root, manager) = try storage()
        defer { try? FileManager.default.removeItem(at: root) }
        let path = try manager.saveFeatures(frames(), forVideoPath: "INCLUDE/clip.mov", modelName: "AppleVision")

        let values = try await FeatureAnalyzer(fileManager: manager).loadFrameValues(featurePaths: [path])

        XCTAssertEqual(values.count, 2 * 180)
        XCTAssertEqual(values[2], 0.9, accuracy: 0.001)
        XCTAssertEqual(values[182], 0.9, accuracy: 0.001)
    }

    func test_analysisOfOnlyEmptyOrUnreadableFilesReportsRecovery() async throws {
        let (root, manager) = try storage()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("[]".utf8).write(to: root.appendingPathComponent("empty.json"))
        let analyzer = FeatureAnalyzer(fileManager: manager)

        do {
            _ = try await analyzer.loadFrameValues(featurePaths: ["empty.json", "missing.json"])
            XCTFail("Unusable artifacts must not produce a successful analysis")
        } catch FeatureAnalyzer.AnalysisError.noUsableFrames {
            // Expected; no MLX computation should be attempted.
        }
    }

    func test_analysisCanUseValidClipsAlongsideUnusableOnes() async throws {
        let (root, manager) = try storage()
        defer { try? FileManager.default.removeItem(at: root) }
        let path = try manager.saveFeatures(frames(), forVideoPath: "clip.mov", modelName: "AppleVision")
        try Data("[]".utf8).write(to: root.appendingPathComponent("empty.json"))

        let values = try await FeatureAnalyzer(fileManager: manager)
            .loadFrameValues(featurePaths: ["missing.json", path, "empty.json"])

        XCTAssertEqual(values.count, 360)
    }

    func test_analysisRejectsSingleFrameBeforeStatistics() async throws {
        let (root, manager) = try storage()
        defer { try? FileManager.default.removeItem(at: root) }
        let path = try manager.saveFeatures(Array(frames().prefix(1)), forVideoPath: "clip.mov", modelName: "AppleVision")

        do {
            _ = try await FeatureAnalyzer(fileManager: manager).analyze(featurePaths: [path])
            XCTFail("Correlation needs at least two frames")
        } catch FeatureAnalyzer.AnalysisError.insufficientFrames {
            // Expected, without needing an MLX device on Simulator.
        }
    }

    func test_analysisComputesFiniteStatisticsOnDevice() async throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("MLX numerical analysis is verified on the physical iPad.")
        #else
        let (root, manager) = try storage()
        defer { try? FileManager.default.removeItem(at: root) }
        let path = try manager.saveFeatures(frames(), forVideoPath: "clip.mov", modelName: "AppleVision")
        let result = try await FeatureAnalyzer(fileManager: manager).analyze(featurePaths: [path])
        XCTAssertEqual(result.featureVariances.count, 180)
        XCTAssertEqual(result.correlationMatrix.count, 180 * 180)
        XCTAssertTrue(result.correlationMatrix.allSatisfy(\.isFinite))
        XCTAssertTrue(result.globalMean.isFinite)
        XCTAssertTrue(result.globalStd.isFinite)
        XCTAssertEqual(result.pcaPoints.count, 2)
        XCTAssertTrue(result.pcaPoints.allSatisfy { $0.x.isFinite && $0.y.isFinite })
        #endif
    }

    private func storage() throws -> (URL, FeatureFileManager) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("feature-tests-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return (root, FeatureFileManager(storageRoot: root))
    }

    private func frames() -> [FrameFeatures] {
        (0..<2).map { index in
            FrameFeatures(timestamp: Double(index) * 0.1,
                          body: [UnifiedKeypoint(id: "neck", x: Float(index) * 0.1,
                                                 y: 0.2, z: nil, confidence: 0.9)],
                          leftHand: nil, rightHand: nil, sourceModel: "AppleVision")
        }
    }
}
