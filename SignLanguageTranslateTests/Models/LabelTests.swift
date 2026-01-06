import XCTest
import SwiftData
@testable import SignLanguageTranslate

final class LabelTests: XCTestCase {

    var container: ModelContainer!
    var context: ModelContext!

    override func setUpWithError() throws {
        let schema = Schema([Label.self, VideoSample.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: [config])
        context = ModelContext(container)
    }

    override func tearDownWithError() throws {
        container = nil
        context = nil
    }

    // MARK: - Creation Tests

    func testLabelCreation_withCategoryType() {
        let label = Label(name: "Animals", type: .category)

        XCTAssertEqual(label.name, "Animals")
        XCTAssertEqual(label.type, .category)
        XCTAssertNotNil(label.id)
        XCTAssertNotNil(label.createdAt)
    }

    func testLabelCreation_withWordType() {
        let label = Label(name: "Dog", type: .word)

        XCTAssertEqual(label.name, "Dog")
        XCTAssertEqual(label.type, .word)
    }

    func testLabelCreation_withSentenceType() {
        let label = Label(name: "How are you?", type: .sentence)

        XCTAssertEqual(label.name, "How are you?")
        XCTAssertEqual(label.type, .sentence)
    }

    // MARK: - Computed Property Tests

    func testDisplayName_formatsCorrectly() {
        let categoryLabel = Label(name: "Animals", type: .category)
        let wordLabel = Label(name: "Dog", type: .word)
        let sentenceLabel = Label(name: "Hello", type: .sentence)

        XCTAssertEqual(categoryLabel.displayName, "Category: Animals")
        XCTAssertEqual(wordLabel.displayName, "Word: Dog")
        XCTAssertEqual(sentenceLabel.displayName, "Sentence: Hello")
    }

    func testShortDisplayName_returnsNameOnly() {
        let label = Label(name: "Animals", type: .category)
        XCTAssertEqual(label.shortDisplayName, "Animals")
    }

    // MARK: - Type Enum Tests

    func testLabelType_displayNames() {
        XCTAssertEqual(LabelType.category.displayName, "Category")
        XCTAssertEqual(LabelType.word.displayName, "Word")
        XCTAssertEqual(LabelType.sentence.displayName, "Sentence")
    }

    func testLabelType_iconNames() {
        XCTAssertEqual(LabelType.category.iconName, "folder.fill")
        XCTAssertEqual(LabelType.word.iconName, "textformat.abc")
        XCTAssertEqual(LabelType.sentence.iconName, "text.quote")
    }

    func testLabelType_allCases() {
        XCTAssertEqual(LabelType.allCases.count, 3)
        XCTAssertTrue(LabelType.allCases.contains(.category))
        XCTAssertTrue(LabelType.allCases.contains(.word))
        XCTAssertTrue(LabelType.allCases.contains(.sentence))
    }

    // MARK: - SwiftData Persistence Tests

    func testLabel_persistsToDatabase() throws {
        let label = Label(name: "TestLabel", type: .word)
        context.insert(label)
        try context.save()

        let descriptor = FetchDescriptor<Label>(
            predicate: #Predicate { $0.name == "TestLabel" }
        )
        let fetched = try context.fetch(descriptor)

        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.name, "TestLabel")
        XCTAssertEqual(fetched.first?.type, .word)
    }

    func testLabel_fetchByType() throws {
        // Insert labels of different types
        context.insert(Label(name: "Animals", type: .category))
        context.insert(Label(name: "Colors", type: .category))
        context.insert(Label(name: "Dog", type: .word))
        context.insert(Label(name: "Hello", type: .sentence))
        try context.save()

        // Fetch only category labels
        let categoryRaw = LabelType.category.rawValue
        let descriptor = FetchDescriptor<Label>(
            predicate: #Predicate { $0.typeRawValue == categoryRaw }
        )
        let categories = try context.fetch(descriptor)

        XCTAssertEqual(categories.count, 2)
    }

    // MARK: - Hashable Tests

    func testLabel_hashableConformance() {
        let label1 = Label(name: "Dog", type: .word)

        // Same instance should be equal to itself
        XCTAssertEqual(label1, label1)

        // SwiftData's @Model provides Hashable conformance
        // Labels can be used in Set and Dictionary
        var labelSet = Set<Label>()
        labelSet.insert(label1)
        XCTAssertEqual(labelSet.count, 1)

        // Can use as dictionary key
        var labelDict = [Label: String]()
        labelDict[label1] = "test"
        XCTAssertEqual(labelDict[label1], "test")
    }

    // MARK: - Preview Helper Tests

    func testPreviewHelpers_returnValidData() {
        XCTAssertFalse(Label.previewCategories.isEmpty)
        XCTAssertFalse(Label.previewWords.isEmpty)
        XCTAssertFalse(Label.previewSentences.isEmpty)

        // Verify types are correct
        XCTAssertTrue(Label.previewCategories.allSatisfy { $0.type == .category })
        XCTAssertTrue(Label.previewWords.allSatisfy { $0.type == .word })
        XCTAssertTrue(Label.previewSentences.allSatisfy { $0.type == .sentence })
    }
}
