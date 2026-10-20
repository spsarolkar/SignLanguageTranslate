import XCTest
@testable import SignLanguageTranslate

@MainActor
final class LocalFileStoreTests: XCTestCase {
    func test_folderListingShowsRealSizesAndFoldersFirst() async throws {
        let (root, store) = try storage()
        defer { try? FileManager.default.removeItem(at: root) }
        try write("abc", to: "z.txt", root: root)
        try write("hidden", to: ".hidden", root: root)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Animals"), withIntermediateDirectories: true)

        let entries = try await store.list(directory: "")

        XCTAssertEqual(entries.map(\.name), ["Animals", "z.txt"])
        XCTAssertTrue(entries[0].isDirectory)
        XCTAssertEqual(entries[1].size, 3)
        XCTAssertNotNil(entries[1].modified)
    }

    func test_allFeaturesIndexesNestedDatasetsWithoutOtherFiles() async throws {
        let (root, store) = try storage()
        defer { try? FileManager.default.removeItem(at: root) }
        try write("[]", to: "Datasets/Features/INCLUDE/Animals/clip_AppleVision_features.json", root: root)
        try write("[]", to: "Datasets/Features/Other/clip_Custom_features.json", root: root)
        try write("{}", to: "Datasets/Features/manifest.json", root: root)
        try write("video", to: "Datasets/INCLUDE/clip.mov", root: root)

        let entries = try await store.allFeatures()

        XCTAssertEqual(entries.count, 2)
        XCTAssertTrue(entries.allSatisfy { $0.kind == .features })
        XCTAssertTrue(entries[0].path.contains("INCLUDE/Animals"))
    }

    func test_refreshFindsFilesCreatedDuringExtraction() async throws {
        let (root, store) = try storage()
        defer { try? FileManager.default.removeItem(at: root) }
        let before = try await store.allFeatures()
        XCTAssertTrue(before.isEmpty)
        try write("[]", to: "Datasets/Features/INCLUDE/new_AppleVision_features.json", root: root)

        let after = try await store.allFeatures()

        XCTAssertEqual(after.count, 1)
    }

    func test_pathTraversalAndAbsolutePathsAreRejected() async throws {
        let (root, store) = try storage()
        defer { try? FileManager.default.removeItem(at: root) }
        for path in ["../", root.path, "Datasets/../../"] {
            do {
                _ = try await store.list(directory: path)
                XCTFail("Must reject \(path)")
            } catch LocalFileStore.BrowserError.outsideDocuments { }
        }
    }

    func test_symlinkEscapeCannotBeBrowsedOrPreviewed() async throws {
        let (root, store) = try storage()
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent("outside-\(UUID())")
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outside)
        }
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try write("private", to: "file.txt", root: outside)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("escape"), withDestinationURL: outside)
        let listing = try await store.list(directory: "")
        XCTAssertTrue(listing.isEmpty)
        do {
            _ = try await store.preview(path: "escape/file.txt")
            XCTFail("Symlink escape must not expose files")
        } catch LocalFileStore.BrowserError.outsideDocuments { }
    }

    func test_recursiveIndexDoesNotFollowSymlinks() async throws {
        let (root, store) = try storage()
        defer { try? FileManager.default.removeItem(at: root) }
        try write("[]", to: "Datasets/Features/real_AppleVision_features.json", root: root)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("Datasets/Features/loop"),
                                                  withDestinationURL: root)
        let entries = try await store.allFeatures()
        XCTAssertEqual(entries.count, 1)
    }

    func test_featurePreviewLoadsFramesAndCoordinatesWithoutChangingFile() async throws {
        let (root, store) = try storage()
        defer { try? FileManager.default.removeItem(at: root) }
        let path = "Datasets/Features/clip_AppleVision_features.json"
        let frames = [FrameFeatures(timestamp: 0.25,
                                   body: [UnifiedKeypoint(id: "nose", x: 0.2, y: 0.3, z: nil, confidence: 0.8)],
                                   leftHand: nil, rightHand: nil, sourceModel: "AppleVision")]
        let data = try JSONEncoder().encode(frames)
        try write(data, to: path, root: root)
        let url = root.appendingPathComponent(path)
        let modified = try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate

        let preview = try await store.preview(path: path)

        guard case .features(let loaded, _, let truncated) = preview.content else { return XCTFail("Expected feature inspector") }
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].timestamp, 0.25)
        XCTAssertEqual(loaded[0].body[0].x, 0.2)
        XCTAssertFalse(truncated)
        XCTAssertEqual(try Data(contentsOf: url), data)
        XCTAssertEqual(try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate, modified)
    }

    func test_emptyFeaturesRemainVisibleAsZeroFrames() async throws {
        let (root, store) = try storage()
        defer { try? FileManager.default.removeItem(at: root) }
        try write("[]", to: "clip_AppleVision_features.json", root: root)
        let preview = try await store.preview(path: "clip_AppleVision_features.json")
        guard case .features(let frames, _, _) = preview.content else { return XCTFail("Expected empty frame inspector") }
        XCTAssertTrue(frames.isEmpty)
    }

    func test_partialFeatureJSONFallsBackToTextWithExplanation() async throws {
        let (root, store) = try storage()
        defer { try? FileManager.default.removeItem(at: root) }
        try write("[{", to: "clip_AppleVision_features.json", root: root)
        let preview = try await store.preview(path: "clip_AppleVision_features.json")
        guard case .text(let text, _, let note) = preview.content else { return XCTFail("Expected raw fallback") }
        XCTAssertEqual(text, "[{")
        XCTAssertNotNil(note)
    }

    func test_textPreviewIsBounded() async throws {
        let (root, store) = try storage()
        defer { try? FileManager.default.removeItem(at: root) }
        try write(Data(repeating: 65, count: LocalFileStore.textLimit * 2), to: "large.log", root: root)
        let preview = try await store.preview(path: "large.log")
        guard case .text(let text, let truncated, _) = preview.content else { return XCTFail("Expected text") }
        XCTAssertEqual(text.utf8.count, LocalFileStore.textLimit)
        XCTAssertTrue(truncated)
    }

    func test_largeFeatureFileDoesNotDecodeUnboundedFrames() async throws {
        let (root, store) = try storage()
        defer { try? FileManager.default.removeItem(at: root) }
        try write(Data(repeating: 32, count: LocalFileStore.featureLimit + 2), to: "large_AppleVision_features.json", root: root)
        let preview = try await store.preview(path: "large_AppleVision_features.json")
        guard case .text(let text, let truncated, let note) = preview.content else { return XCTFail("Expected bounded fallback") }
        XCTAssertEqual(text.utf8.count, LocalFileStore.textLimit)
        XCTAssertTrue(truncated)
        XCTAssertTrue(note?.contains("8 MiB") == true)
    }

    func test_archivePreviewOnlyReadsMetadata() async throws {
        let (root, store) = try storage()
        defer { try? FileManager.default.removeItem(at: root) }
        try write("archive", to: "part.zip", root: root)
        let preview = try await store.preview(path: "part.zip")
        guard case .information = preview.content else { return XCTFail("Do not expand archives") }
        XCTAssertEqual(preview.entry.size, 7)
    }

    func test_deletedFilesAndMissingFoldersReportErrors() async throws {
        let (root, store) = try storage()
        defer { try? FileManager.default.removeItem(at: root) }
        do {
            _ = try await store.preview(path: "deleted.json")
            XCTFail("Must report missing file")
        } catch { }
        do {
            _ = try await store.list(directory: "Models")
            XCTFail("Must report missing folder")
        } catch LocalFileStore.BrowserError.unavailableFolder { }
    }

    private func storage() throws -> (URL, LocalFileStore) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("local-browser-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return (root, LocalFileStore(root: root))
    }

    private func write(_ text: String, to path: String, root: URL) throws {
        try write(Data(text.utf8), to: path, root: root)
    }

    private func write(_ data: Data, to path: String, root: URL) throws {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}
