import XCTest
@testable import SignLanguageTranslate

final class URLExtensionsTests: XCTestCase {

    var tempDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
    }

    func testIsDirectory() {
        XCTAssertTrue(tempDirectory.isDirectory)

        let file = tempDirectory.appendingPathComponent("test.txt")
        try? "test".write(to: file, atomically: true, encoding: .utf8)
        XCTAssertFalse(file.isDirectory)
    }

    func testSubdirectories() {
        // Create subdirectories
        let sub1 = tempDirectory.appendingPathComponent("folder1")
        let sub2 = tempDirectory.appendingPathComponent("folder2")
        let hidden = tempDirectory.appendingPathComponent(".hidden")

        try? FileManager.default.createDirectory(at: sub1, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: sub2, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: hidden, withIntermediateDirectories: true)

        // Create a file (should not be included)
        let file = tempDirectory.appendingPathComponent("file.txt")
        try? "test".write(to: file, atomically: true, encoding: .utf8)

        let subdirs = tempDirectory.subdirectories()
        XCTAssertEqual(subdirs.count, 2) // Excludes hidden and files
    }

    func testVideoFiles() {
        // Create video and non-video files
        try? "".write(to: tempDirectory.appendingPathComponent("video1.mp4"), atomically: true, encoding: .utf8)
        try? "".write(to: tempDirectory.appendingPathComponent("video2.mov"), atomically: true, encoding: .utf8)
        try? "".write(to: tempDirectory.appendingPathComponent("document.pdf"), atomically: true, encoding: .utf8)
        try? "".write(to: tempDirectory.appendingPathComponent("image.jpg"), atomically: true, encoding: .utf8)

        let videos = tempDirectory.videoFiles()
        XCTAssertEqual(videos.count, 2)
    }

    func testNameWithoutExtension() {
        let url = URL(fileURLWithPath: "/path/to/video.mp4")
        XCTAssertEqual(url.nameWithoutExtension, "video")
    }
}
