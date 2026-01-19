import XCTest
@testable import SignLanguageTranslate

/// Tests for INCLUDEIngestionStrategy
final class INCLUDEIngestionStrategyTests: XCTestCase {
    
    func testParseWordLabel_WithNumberPrefix() {
        XCTAssertEqual(
            INCLUDEIngestionStrategy.parseWordLabel(from: "12. Dog"),
            "Dog"
        )
        XCTAssertEqual(
            INCLUDEIngestionStrategy.parseWordLabel(from: "03. Cat"),
            "Cat"
        )
        XCTAssertEqual(
            INCLUDEIngestionStrategy.parseWordLabel(from: "100. Test"),
            "Test"
        )
    }
    
    func testParseWordLabel_WithoutPrefix() {
        XCTAssertEqual(
            INCLUDEIngestionStrategy.parseWordLabel(from: "Dog"),
            "Dog"
        )
        XCTAssertEqual(
            INCLUDEIngestionStrategy.parseWordLabel(from: "  Cat  "),
            "Cat"
        )
    }
    
    func testParseWordLabel_FromURL() {
        let url = URL(fileURLWithPath: "/datasets/INCLUDE/Animals/12. Dog/video1.mp4")
        let label = INCLUDEIngestionStrategy.parseWordLabel(from: url)
        
        XCTAssertEqual(label, "Dog")
    }
    
    func testParseCategory_FromURL() {
        let baseURL = URL(fileURLWithPath: "/datasets/INCLUDE")
        let fileURL = URL(fileURLWithPath: "/datasets/INCLUDE/Animals/Dog/video1.mp4")
        
        let category = INCLUDEIngestionStrategy.parseCategory(from: fileURL, baseURL: baseURL)
        
        XCTAssertEqual(category, "Animals")
    }
    
    func testParseCategory_InvalidPath() {
        let baseURL = URL(fileURLWithPath: "/datasets/INCLUDE")
        let fileURL = URL(fileURLWithPath: "/other/path/video.mp4")
        
        let category = INCLUDEIngestionStrategy.parseCategory(from: fileURL, baseURL: baseURL)
        
        XCTAssertNil(category)
    }
    
    func testDisplayName() {
        XCTAssertEqual(
            INCLUDEIngestionStrategy.displayName(for: "Days_and_Time"),
            "Days and Time"
        )
        XCTAssertEqual(
            INCLUDEIngestionStrategy.displayName(for: "Animals"),
            "Animals"
        )
    }
    
    func testNormalizeCategory() {
        XCTAssertEqual(
            INCLUDEIngestionStrategy.normalizeCategory("  Animals  "),
            "Animals"
        )
        XCTAssertEqual(
            INCLUDEIngestionStrategy.normalizeCategory("Days_and_Time"),
            "Days_and_Time"
        )
    }
    
    func testExpectedCategories() {
        XCTAssertEqual(INCLUDEIngestionStrategy.expectedCategoryCount, 15)
        XCTAssertEqual(INCLUDEIngestionStrategy.expectedCategories.count, 15)
        
        // Verify some known categories
        XCTAssertTrue(INCLUDEIngestionStrategy.expectedCategories.contains("Animals"))
        XCTAssertTrue(INCLUDEIngestionStrategy.expectedCategories.contains("Greetings"))
        XCTAssertTrue(INCLUDEIngestionStrategy.expectedCategories.contains("Colours"))
    }
    
    func testExpectedStatistics() {
        let stats = INCLUDEIngestionStrategy.expectedStatistics
        
        XCTAssertEqual(stats.categoryCount, 15)
        XCTAssertGreaterThan(stats.wordCount, 0)
        XCTAssertGreaterThan(stats.sampleCount, 0)
    }
}
