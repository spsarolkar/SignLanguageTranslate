import XCTest
import SwiftData
@testable import SignLanguageTranslate

final class VideoSampleTests: XCTestCase {

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

    func testVideoSampleCreation_basicProperties() {
        let sample = VideoSample(
            localPath: "INCLUDE/Animals/Dog/video_001.mp4",
            datasetName: "INCLUDE"
        )

        XCTAssertEqual(sample.localPath, "INCLUDE/Animals/Dog/video_001.mp4")
        XCTAssertEqual(sample.datasetName, "INCLUDE")
        XCTAssertNotNil(sample.id)
        XCTAssertNotNil(sample.createdAt)
        XCTAssertFalse(sample.isFavorite)
        XCTAssertNil(sample.lastAccessedAt)
        XCTAssertNil(sample.notes)
    }

    func testVideoSampleCreation_withAllProperties() {
        let sample = VideoSample(
            localPath: "INCLUDE/Animals/Dog/video_001.mp4",
            datasetName: "INCLUDE",
            originalFilename: "original_video.mp4",
            fileSize: 15_000_000,
            duration: 45.5
        )

        XCTAssertEqual(sample.originalFilename, "original_video.mp4")
        XCTAssertEqual(sample.fileSize, 15_000_000)
        XCTAssertEqual(sample.duration, 45.5)
    }

    // MARK: - Computed Property Tests

    func testFileName_extractsCorrectly() {
        let sample = VideoSample(
            localPath: "INCLUDE/Animals/Dog/video_001.mp4",
            datasetName: "INCLUDE"
        )

        XCTAssertEqual(sample.fileName, "video_001.mp4")
    }

    func testFileNameWithoutExtension_extractsCorrectly() {
        let sample = VideoSample(
            localPath: "INCLUDE/Animals/Dog/video_001.mp4",
            datasetName: "INCLUDE"
        )

        XCTAssertEqual(sample.fileNameWithoutExtension, "video_001")
    }

    func testFileExtension_extractsCorrectly() {
        let sample = VideoSample(
            localPath: "INCLUDE/Animals/Dog/video_001.MP4",
            datasetName: "INCLUDE"
        )

        XCTAssertEqual(sample.fileExtension, "mp4") // Should be lowercase
    }

    func testFormattedFileSize_formatsCorrectly() {
        let sample = VideoSample(
            localPath: "test.mp4",
            datasetName: "TEST",
            fileSize: 15_000_000
        )

        // Should be around "15 MB" or "14.3 MB" depending on formatter
        XCTAssertTrue(sample.formattedFileSize.contains("MB"))
    }

    func testFormattedDuration_formatsCorrectly() {
        let sample1 = VideoSample(localPath: "test.mp4", datasetName: "TEST", duration: 45)
        XCTAssertEqual(sample1.formattedDuration, "0:45")

        let sample2 = VideoSample(localPath: "test.mp4", datasetName: "TEST", duration: 125)
        XCTAssertEqual(sample2.formattedDuration, "2:05")

        let sample3 = VideoSample(localPath: "test.mp4", datasetName: "TEST", duration: 0)
        XCTAssertEqual(sample3.formattedDuration, "0:00")
    }

    func testAbsoluteURL_constructsCorrectly() {
        let sample = VideoSample(
            localPath: "INCLUDE/Animals/Dog/video.mp4",
            datasetName: "INCLUDE"
        )

        let expectedPath = FileManager.default.datasetsDirectory
            .appendingPathComponent("INCLUDE/Animals/Dog/video.mp4")

        XCTAssertEqual(sample.absoluteURL, expectedPath)
    }

    // MARK: - Label Accessor Tests

    func testCategoryLabel_returnsCorrectLabel() throws {
        let sample = VideoSample(localPath: "test.mp4", datasetName: "TEST")
        let categoryLabel = Label(name: "Animals", type: .category)
        let wordLabel = Label(name: "Dog", type: .word)

        context.insert(sample)
        context.insert(categoryLabel)
        context.insert(wordLabel)

        sample.labels = [categoryLabel, wordLabel]
        try context.save()

        XCTAssertEqual(sample.categoryLabel?.name, "Animals")
        XCTAssertEqual(sample.categoryName, "Animals")
    }

    func testWordLabel_returnsCorrectLabel() throws {
        let sample = VideoSample(localPath: "test.mp4", datasetName: "TEST")
        let categoryLabel = Label(name: "Animals", type: .category)
        let wordLabel = Label(name: "Dog", type: .word)

        context.insert(sample)
        context.insert(categoryLabel)
        context.insert(wordLabel)

        sample.labels = [categoryLabel, wordLabel]
        try context.save()

        XCTAssertEqual(sample.wordLabel?.name, "Dog")
        XCTAssertEqual(sample.wordName, "Dog")
    }

    func testSentenceLabel_returnsCorrectLabel() throws {
        let sample = VideoSample(localPath: "test.mp4", datasetName: "ISL-CSLTR")
        let sentenceLabel = Label(name: "How are you?", type: .sentence)

        context.insert(sample)
        context.insert(sentenceLabel)

        sample.labels = [sentenceLabel]
        try context.save()

        XCTAssertEqual(sample.sentenceLabel?.name, "How are you?")
        XCTAssertEqual(sample.sentenceText, "How are you?")
    }

    func testDisplayTitle_prefersWordOverFilename() throws {
        let sample = VideoSample(localPath: "video_001.mp4", datasetName: "TEST")

        // Without labels, should show filename
        XCTAssertEqual(sample.displayTitle, "video_001")

        // With word label, should show word
        let wordLabel = Label(name: "Dog", type: .word)
        context.insert(sample)
        context.insert(wordLabel)
        sample.labels = [wordLabel]

        XCTAssertEqual(sample.displayTitle, "Dog")
    }

    // MARK: - Method Tests

    func testMarkAsAccessed_updatesTimestamp() {
        let sample = VideoSample(localPath: "test.mp4", datasetName: "TEST")
        XCTAssertNil(sample.lastAccessedAt)

        sample.markAsAccessed()

        XCTAssertNotNil(sample.lastAccessedAt)
    }

    func testToggleFavorite_togglesCorrectly() {
        let sample = VideoSample(localPath: "test.mp4", datasetName: "TEST")
        XCTAssertFalse(sample.isFavorite)

        sample.toggleFavorite()
        XCTAssertTrue(sample.isFavorite)

        sample.toggleFavorite()
        XCTAssertFalse(sample.isFavorite)
    }

    func testAddLabel_addsNewLabel() throws {
        let sample = VideoSample(localPath: "test.mp4", datasetName: "TEST")
        let label = Label(name: "Dog", type: .word)

        context.insert(sample)
        context.insert(label)

        sample.addLabel(label)

        XCTAssertEqual(sample.labels.count, 1)
        XCTAssertTrue(sample.hasLabel(label))
    }

    func testAddLabel_doesNotAddDuplicate() throws {
        let sample = VideoSample(localPath: "test.mp4", datasetName: "TEST")
        let label = Label(name: "Dog", type: .word)

        context.insert(sample)
        context.insert(label)

        sample.addLabel(label)
        sample.addLabel(label) // Add same label again

        XCTAssertEqual(sample.labels.count, 1)
    }

    func testRemoveLabel_removesCorrectly() throws {
        let sample = VideoSample(localPath: "test.mp4", datasetName: "TEST")
        let label1 = Label(name: "Animals", type: .category)
        let label2 = Label(name: "Dog", type: .word)

        context.insert(sample)
        context.insert(label1)
        context.insert(label2)

        sample.labels = [label1, label2]
        XCTAssertEqual(sample.labels.count, 2)

        sample.removeLabel(label1)

        XCTAssertEqual(sample.labels.count, 1)
        XCTAssertFalse(sample.hasLabel(label1))
        XCTAssertTrue(sample.hasLabel(label2))
    }

    func testHasLabelNamed_checksCorrectly() throws {
        let sample = VideoSample(localPath: "test.mp4", datasetName: "TEST")
        let label = Label(name: "Dog", type: .word)

        context.insert(sample)
        context.insert(label)
        sample.labels = [label]

        XCTAssertTrue(sample.hasLabel(named: "Dog", type: .word))
        XCTAssertFalse(sample.hasLabel(named: "Dog", type: .category))
        XCTAssertFalse(sample.hasLabel(named: "Cat", type: .word))
    }

    // MARK: - SwiftData Persistence Tests

    func testVideoSample_persistsToDatabase() throws {
        let sample = VideoSample(
            localPath: "INCLUDE/Animals/Dog/video.mp4",
            datasetName: "INCLUDE",
            fileSize: 15_000_000,
            duration: 45.0
        )

        context.insert(sample)
        try context.save()

        let descriptor = FetchDescriptor<VideoSample>(
            predicate: #Predicate { $0.datasetName == "INCLUDE" }
        )
        let fetched = try context.fetch(descriptor)

        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.localPath, "INCLUDE/Animals/Dog/video.mp4")
        XCTAssertEqual(fetched.first?.fileSize, 15_000_000)
    }

    func testVideoSample_relationshipWithLabels() throws {
        // Create sample and labels
        let sample = VideoSample(localPath: "test.mp4", datasetName: "TEST")
        let categoryLabel = Label(name: "Animals", type: .category)
        let wordLabel = Label(name: "Dog", type: .word)

        // Insert into context
        context.insert(sample)
        context.insert(categoryLabel)
        context.insert(wordLabel)

        // Set up relationship
        sample.labels = [categoryLabel, wordLabel]
        try context.save()

        // Fetch and verify
        let descriptor = FetchDescriptor<VideoSample>()
        let fetched = try context.fetch(descriptor)

        XCTAssertEqual(fetched.first?.labels.count, 2)

        // Verify inverse relationship
        XCTAssertTrue(categoryLabel.videoSamples?.contains(where: { $0.id == sample.id }) ?? false)
    }

    // MARK: - Hashable Tests

    func testVideoSample_hashableConformance() {
        let sample1 = VideoSample(localPath: "test1.mp4", datasetName: "TEST")

        // Same instance should be equal to itself
        XCTAssertEqual(sample1, sample1)

        // SwiftData's @Model provides Hashable conformance
        // Samples can be used in Set and Dictionary
        var sampleSet = Set<VideoSample>()
        sampleSet.insert(sample1)
        XCTAssertEqual(sampleSet.count, 1)

        // Can use as dictionary key
        var sampleDict = [VideoSample: String]()
        sampleDict[sample1] = "test"
        XCTAssertEqual(sampleDict[sample1], "test")
    }

    // MARK: - Preview Helper Tests

    func testPreviewHelpers_returnValidData() {
        let preview = VideoSample.preview
        XCTAssertFalse(preview.localPath.isEmpty)
        XCTAssertFalse(preview.datasetName.isEmpty)

        let previewWithLabels = VideoSample.previewWithLabels()
        XCTAssertEqual(previewWithLabels.labels.count, 2)

        let previewList = VideoSample.previewList
        XCTAssertEqual(previewList.count, 5)

        let previewSentence = VideoSample.previewSentence
        XCTAssertEqual(previewSentence.datasetName, "ISL-CSLTR")
    }
}
