import XCTest
@testable import SignLanguageTranslate

/// Tests for MultiPartMerger utility
final class MultiPartMergerTests: XCTestCase {
    
    func testParsePartInfo_ValidMultiPart() {
        let filename = "Animals_1of3.zip"
        let url = URL(fileURLWithPath: "/test/\(filename)")
        
        let partInfo = MultiPartMerger.parsePartInfo(from: filename, url: url)
        
        XCTAssertNotNil(partInfo)
        XCTAssertEqual(partInfo?.baseName, "Animals")
        XCTAssertEqual(partInfo?.partNumber, 1)
        XCTAssertEqual(partInfo?.totalParts, 3)
    }
    
    func testParsePartInfo_DifferentFormats() {
        let testCases: [(String, String, Int, Int)] = [
            ("Category_2of5.zip", "Category", 2, 5),
            ("Test_10of20.zip", "Test", 10, 20),
            ("Name_With_Spaces_3of4.zip", "Name_With_Spaces", 3, 4)
        ]
        
        for (filename, expectedBase, expectedPart, expectedTotal) in testCases {
            let url = URL(fileURLWithPath: "/test/\(filename)")
            let partInfo = MultiPartMerger.parsePartInfo(from: filename, url: url)
            
            XCTAssertNotNil(partInfo, "Failed to parse: \(filename)")
            XCTAssertEqual(partInfo?.baseName, expectedBase)
            XCTAssertEqual(partInfo?.partNumber, expectedPart)
            XCTAssertEqual(partInfo?.totalParts, expectedTotal)
        }
    }
    
    func testParsePartInfo_InvalidFormats() {
        let invalidFilenames = [
            "NotMultiPart.zip",
            "Invalid_1-3.zip",
            "Test.zip",
            "NoExtension_1of2"
        ]
        
        for filename in invalidFilenames {
            let url = URL(fileURLWithPath: "/test/\(filename)")
            let partInfo = MultiPartMerger.parsePartInfo(from: filename, url: url)
            XCTAssertNil(partInfo, "Should not parse: \(filename)")
        }
    }
    
    func testGroupParts() {
        let files = [
            URL(fileURLWithPath: "/test/Animals_1of2.zip"),
            URL(fileURLWithPath: "/test/Animals_2of2.zip"),
            URL(fileURLWithPath: "/test/Colors_1of3.zip"),
            URL(fileURLWithPath: "/test/Colors_2of3.zip"),
            URL(fileURLWithPath: "/test/Colors_3of3.zip"),
            URL(fileURLWithPath: "/test/SingleFile.zip")
        ]
        
        let grouped = MultiPartMerger.groupParts(files)
        
        XCTAssertEqual(grouped.count, 3)
        XCTAssertEqual(grouped["Animals"]?.count, 2)
        XCTAssertEqual(grouped["Colors"]?.count, 3)
        XCTAssertEqual(grouped["SingleFile"]?.count, 1)
    }
    
    func testValidateParts_Complete() {
        let parts = [
            PartInfo(
                baseName: "Test",
                partNumber: 1,
                totalParts: 3,
                url: URL(fileURLWithPath: "/test/Test_1of3.zip")
            ),
            PartInfo(
                baseName: "Test",
                partNumber: 2,
                totalParts: 3,
                url: URL(fileURLWithPath: "/test/Test_2of3.zip")
            ),
            PartInfo(
                baseName: "Test",
                partNumber: 3,
                totalParts: 3,
                url: URL(fileURLWithPath: "/test/Test_3of3.zip")
            )
        ]
        
        XCTAssertTrue(MultiPartMerger.validateParts(parts))
    }
    
    func testValidateParts_Incomplete() {
        // Missing part 2
        let parts = [
            PartInfo(
                baseName: "Test",
                partNumber: 1,
                totalParts: 3,
                url: URL(fileURLWithPath: "/test/Test_1of3.zip")
            ),
            PartInfo(
                baseName: "Test",
                partNumber: 3,
                totalParts: 3,
                url: URL(fileURLWithPath: "/test/Test_3of3.zip")
            )
        ]
        
        XCTAssertFalse(MultiPartMerger.validateParts(parts))
    }
    
    func testIsMultiPartArchive() {
        XCTAssertTrue(MultiPartMerger.isMultiPart("Test_1of2.zip"))
        XCTAssertTrue(MultiPartMerger.isMultiPart("Category_10of15.zip"))
        XCTAssertFalse(MultiPartMerger.isMultiPart("SingleFile.zip"))
        XCTAssertFalse(MultiPartMerger.isMultiPart("Not_Archive.txt"))
    }
}
