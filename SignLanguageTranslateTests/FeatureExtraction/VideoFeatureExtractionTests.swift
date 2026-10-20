import XCTest
import AVFoundation
import SwiftData
@testable import SignLanguageTranslate

final class VideoFeatureExtractionTests: XCTestCase {
    /// A compressed movie must be decoded before asking Vision for landmarks.
    /// A blank frame intentionally has no person: detection absence is distinct
    /// from failing to decode any frames at all.
    @MainActor
    func test_compressedMovieProducesFrameRecords() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("extraction-\(UUID()).mov")
        defer { try? FileManager.default.removeItem(at: url) }
        try await writeMovie(to: url)

        let frames = try await VideoFeatureExtractionService().readFrames(from: url) { sample, timestamp in
            XCTAssertNotNil(CMSampleBufferGetImageBuffer(sample))
            return FrameFeatures(timestamp: timestamp, body: [], leftHand: nil,
                                 rightHand: nil, sourceModel: "AppleVision")
        }

        XCTAssertEqual(frames.count, 3)
        XCTAssertEqual(frames.map(\.sourceModel), Array(repeating: "AppleVision", count: 3))
        XCTAssertEqual(frames.first?.timestamp ?? -1, 0, accuracy: 0.001)
        XCTAssertEqual(frames.last?.timestamp ?? -1, 2.0 / 30, accuracy: 0.001)
    }

    @MainActor
    func test_compressedMovieRunsVisionOnDevice() async throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Vision pose request initialization is unavailable on this Simulator; decoding is tested separately.")
        #else
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("vision-\(UUID()).mov")
        defer { try? FileManager.default.removeItem(at: url) }
        try await writeMovie(to: url)
        let frames = try await VideoFeatureExtractionService().extractFeatures(from: url)
        XCTAssertEqual(frames.count, 3)
        #endif
    }

    @MainActor
    func test_frameProcessorFailureIsNotReportedAsSuccessfulExtraction() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("failed-vision-\(UUID()).mov")
        defer { try? FileManager.default.removeItem(at: url) }
        try await writeMovie(to: url)
        do {
            _ = try await VideoFeatureExtractionService().readFrames(from: url) { _, _ in
                throw NSError(domain: "FrameProcessor", code: 9)
            }
            XCTFail("Frame-processing errors must propagate")
        } catch {
            XCTAssertEqual((error as NSError).domain, "FrameProcessor")
        }
    }

    @MainActor
    func test_batchRepairsEmptyClipAndSkipsValidClipOnDevice() async throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("The batch's Vision processor requires the physical iPad.")
        #else
        let folder = "FeatureRecoveryTests-\(UUID())"
        let root = FileManager.default.datasetsDirectory
        let videoDirectory = root.appendingPathComponent(folder)
        let featuresDirectory = root.appendingPathComponent("Features/\(folder)")
        try FileManager.default.createDirectory(at: videoDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: featuresDirectory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: videoDirectory)
            try? FileManager.default.removeItem(at: featuresDirectory)
        }
        let source = videoDirectory.appendingPathComponent("empty.mov")
        try await writeMovie(to: source)
        let originalMovie = try Data(contentsOf: source)
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: VideoSample.self, FeatureSet.self, Label.self,
                                           configurations: configuration)
        let context = container.mainContext
        let empty = VideoSample(localPath: "\(folder)/empty.mov", datasetName: folder)
        let valid = VideoSample(localPath: "\(folder)/valid.mov", datasetName: folder)
        context.insert(empty)
        context.insert(valid)
        let emptyPath = "Features/\(folder)/empty_AppleVision_features.json"
        try Data("[]".utf8).write(to: root.appendingPathComponent(emptyPath))
        let stale = FeatureSet(modelName: "AppleVision", filePath: emptyPath, frameCount: 0)
        stale.videoSample = empty
        context.insert(stale)
        let manager = FeatureFileManager()
        let validFrames = [FrameFeatures(timestamp: 0, body: [], leftHand: nil,
                                         rightHand: nil, sourceModel: "AppleVision")]
        let validPath = try manager.saveFeatures(validFrames, forVideoPath: valid.localPath, modelName: "AppleVision")
        let preserved = FeatureSet(modelName: "AppleVision", filePath: validPath, frameCount: 1)
        preserved.videoSample = valid
        context.insert(preserved)
        try context.save()
        let staleID = stale.id
        let preservedID = preserved.id
        let preservedData = try Data(contentsOf: root.appendingPathComponent(validPath))
        let service = BatchExtractionService()
        service.extractAll(videos: [empty, valid], model: .appleVision, modelContext: context)
        let deadline = Date().addingTimeInterval(60)
        while service.isExtracting, Date() < deadline {
            try await Task.sleep(for: .milliseconds(100))
        }
        if service.isExtracting { service.cancel(); XCTFail("Batch did not finish"); return }

        XCTAssertTrue(service.failedVideos.isEmpty, "\(service.failedVideos.map(\.error))")
        XCTAssertEqual(empty.featureSets.count, 1)
        XCTAssertEqual(empty.featureSets.first?.frameCount, 3)
        XCTAssertNotEqual(empty.featureSets.first?.id, staleID)
        XCTAssertEqual(try manager.loadFeatures(at: emptyPath).count, 3)
        XCTAssertEqual(valid.featureSets.first?.id, preservedID)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(validPath)), preservedData)
        XCTAssertEqual(try Data(contentsOf: source), originalMovie)
        // valid.mov deliberately does not exist: a valid artifact must be reused.
        #endif
    }

    private func writeMovie(to url: URL) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 160,
            AVVideoHeightKey: 160
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: 160,
                kCVPixelBufferHeightKey as String: 160
            ]
        )
        writer.add(input)
        XCTAssertTrue(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        let pool = try XCTUnwrap(adaptor.pixelBufferPool)

        for index in 0..<3 {
            let deadline = Date().addingTimeInterval(5)
            while !input.isReadyForMoreMediaData {
                guard writer.status == .writing, Date() < deadline else {
                    throw writer.error ?? NSError(domain: "MovieFixture", code: 1)
                }
                try await Task.sleep(for: .milliseconds(10))
            }
            var buffer: CVPixelBuffer?
            XCTAssertEqual(CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer), kCVReturnSuccess)
            let pixels = try XCTUnwrap(buffer)
            CVPixelBufferLockBaseAddress(pixels, [])
            memset(CVPixelBufferGetBaseAddress(pixels), 128,
                   CVPixelBufferGetBytesPerRow(pixels) * CVPixelBufferGetHeight(pixels))
            CVPixelBufferUnlockBaseAddress(pixels, [])
            XCTAssertTrue(adaptor.append(pixels, withPresentationTime: CMTime(value: Int64(index), timescale: 30)))
        }
        input.markAsFinished()
        await writer.finishWriting()
        XCTAssertEqual(writer.status, .completed, "\(String(describing: writer.error))")
    }
}
