import XCTest
@testable import SignLanguageTranslate

final class StringExtensionsTests: XCTestCase {

    func testSanitizedLabel_withNumberDotPrefix() {
        XCTAssertEqual("12. Dog".sanitizedLabel(), "Dog")
        XCTAssertEqual("1. Cat".sanitizedLabel(), "Cat")
        XCTAssertEqual("999. Elephant".sanitizedLabel(), "Elephant")
    }

    func testSanitizedLabel_withSpacesAndDots() {
        XCTAssertEqual("  5.  Bird  ".sanitizedLabel(), "Bird")
        XCTAssertEqual("  12.   Multiple Words  ".sanitizedLabel(), "Multiple Words")
    }

    func testSanitizedLabel_withoutNumberPrefix() {
        XCTAssertEqual("Hello World".sanitizedLabel(), "Hello World")
        XCTAssertEqual("Dog".sanitizedLabel(), "Dog")
    }

    func testSanitizedLabel_edgeCases() {
        XCTAssertEqual("".sanitizedLabel(), "")
        XCTAssertEqual("   ".sanitizedLabel(), "")
        XCTAssertEqual("123".sanitizedLabel(), "123") // Just numbers, keep as-is
        XCTAssertEqual("1.".sanitizedLabel(), "") // Number and dot only
        XCTAssertEqual(".Dog".sanitizedLabel(), ".Dog") // Dot without number, keep
    }

    func testIsValidFilename() {
        XCTAssertTrue("valid_file.mp4".isValidFilename)
        XCTAssertTrue("my video 2024.mov".isValidFilename)
        XCTAssertFalse("invalid/file.mp4".isValidFilename)
        XCTAssertFalse("invalid:file.mp4".isValidFilename)
        XCTAssertFalse("".isValidFilename)
        XCTAssertFalse("   ".isValidFilename)
    }

    func testToSafeFilename() {
        XCTAssertEqual("hello/world".toSafeFilename(), "hello_world")
        XCTAssertEqual("file:name".toSafeFilename(), "file_name")
        XCTAssertEqual("already_safe".toSafeFilename(), "already_safe")
    }
}
