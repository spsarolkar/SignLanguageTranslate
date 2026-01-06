import Foundation
import SwiftData

/// Centralized SwiftData configuration and container management
/// Provides shared container for production and in-memory container for previews/testing
@MainActor
final class PersistenceController {

    // MARK: - Shared Instance

    /// Shared persistence controller for the app
    static let shared = PersistenceController()

    /// Shared container for previews with sample data
    static let preview: PersistenceController = {
        let controller = PersistenceController(inMemory: true)
        controller.populatePreviewData()
        return controller
    }()

    // MARK: - Properties

    /// The SwiftData model container
    let container: ModelContainer

    /// Main context for UI operations
    var mainContext: ModelContext {
        container.mainContext
    }

    /// Whether this controller uses in-memory storage
    let inMemory: Bool

    // MARK: - Schema

    /// All models in the schema
    static let models: [any PersistentModel.Type] = [
        Dataset.self,
        Label.self,
        VideoSample.self
    ]

    /// The complete schema for the app
    static var schema: Schema {
        Schema(models)
    }

    // MARK: - Initialization

    /// Create a new persistence controller
    /// - Parameter inMemory: If true, uses in-memory storage (for previews/testing)
    init(inMemory: Bool = false) {
        self.inMemory = inMemory

        let configuration = ModelConfiguration(
            schema: Self.schema,
            isStoredInMemoryOnly: inMemory,
            allowsSave: true
        )

        do {
            container = try ModelContainer(
                for: Self.schema,
                configurations: [configuration]
            )
        } catch {
            fatalError("Failed to create ModelContainer: \(error.localizedDescription)")
        }
    }

    // MARK: - Preview Data Population

    /// Populate the container with sample data for previews
    private func populatePreviewData() {
        let context = mainContext

        // Create datasets
        let includeDataset = Dataset(
            name: "INCLUDE",
            type: .include,
            status: .completed,
            totalSamples: 250,
            downloadedSamples: 250,
            totalParts: 46,
            downloadedParts: 46,
            totalBytes: 50_000_000_000,
            downloadedBytes: 50_000_000_000
        )

        let islDataset = Dataset(
            name: "ISL-CSLTR",
            type: .islcsltr,
            status: .notStarted,
            totalSamples: 5000,
            totalParts: 1,
            totalBytes: 10_000_000_000
        )

        context.insert(includeDataset)
        context.insert(islDataset)

        // Create category labels
        let categories = ["Animals", "Adjectives", "Greetings", "Colors", "Food"]
        var categoryLabels: [String: Label] = [:]

        for categoryName in categories {
            let label = Label(name: categoryName, type: .category)
            context.insert(label)
            categoryLabels[categoryName] = label
        }

        // Create word labels and video samples
        let wordsByCategory: [String: [String]] = [
            "Animals": ["Dog", "Cat", "Bird", "Fish", "Horse"],
            "Adjectives": ["Happy", "Sad", "Big", "Small", "Fast"],
            "Greetings": ["Hello", "Goodbye", "Thank You", "Please", "Sorry"],
            "Colors": ["Red", "Blue", "Green", "Yellow", "Orange"],
            "Food": ["Apple", "Bread", "Water", "Rice", "Milk"]
        ]

        for (categoryName, words) in wordsByCategory {
            guard let categoryLabel = categoryLabels[categoryName] else { continue }

            for word in words {
                // Create word label
                let wordLabel = Label(name: word, type: .word)
                context.insert(wordLabel)

                // Create 10 video samples per word
                for i in 1...10 {
                    let sample = VideoSample(
                        localPath: "INCLUDE/\(categoryName)/\(word)/video_\(String(format: "%03d", i)).mp4",
                        datasetName: "INCLUDE",
                        originalFilename: "video_\(String(format: "%03d", i)).mp4",
                        fileSize: Int64.random(in: 5_000_000...25_000_000),
                        duration: Double.random(in: 10...60)
                    )

                    // Add labels to sample
                    sample.labels = [categoryLabel, wordLabel]

                    context.insert(sample)
                }
            }
        }

        // Create some sentence-level samples for ISL-CSLTR preview
        let sentences = [
            "How are you today?",
            "Nice to meet you",
            "What is your name?",
            "I am learning sign language",
            "Thank you very much"
        ]

        for (index, sentence) in sentences.enumerated() {
            let sentenceLabel = Label(name: sentence, type: .sentence)
            context.insert(sentenceLabel)

            let sample = VideoSample(
                localPath: "ISL-CSLTR/sentences/video_s\(String(format: "%03d", index + 1)).mp4",
                datasetName: "ISL-CSLTR",
                originalFilename: "video_s\(String(format: "%03d", index + 1)).mp4",
                fileSize: Int64.random(in: 20_000_000...50_000_000),
                duration: Double.random(in: 30...120)
            )

            sample.labels = [sentenceLabel]
            context.insert(sample)
        }

        // Save the context
        do {
            try context.save()
        } catch {
            print("Failed to save preview data: \(error)")
        }
    }

    // MARK: - Convenience Methods

    /// Create a new background context for background operations
    func newBackgroundContext() -> ModelContext {
        ModelContext(container)
    }

    /// Delete all data (useful for testing or reset)
    func deleteAllData() throws {
        let context = mainContext

        // Delete in correct order to handle relationships
        try context.delete(model: VideoSample.self)
        try context.delete(model: Label.self)
        try context.delete(model: Dataset.self)

        try context.save()
    }

    /// Seed initial datasets if none exist
    func seedInitialDatasetsIfNeeded() {
        let context = mainContext

        let descriptor = FetchDescriptor<Dataset>()
        let existingCount = (try? context.fetchCount(descriptor)) ?? 0

        guard existingCount == 0 else { return }

        // Create default datasets
        let includeDataset = Dataset(name: "INCLUDE", type: .include)
        includeDataset.totalParts = 46
        includeDataset.totalBytes = 50_000_000_000

        let islDataset = Dataset(name: "ISL-CSLTR", type: .islcsltr)
        islDataset.totalParts = 1
        islDataset.totalBytes = 10_000_000_000

        context.insert(includeDataset)
        context.insert(islDataset)

        try? context.save()
    }
}

// MARK: - ModelContext Extensions

extension ModelContext {

    /// Fetch a single entity by ID
    func fetch<T: PersistentModel>(id: UUID, type: T.Type) -> T? where T: Identifiable, T.ID == UUID {
        let descriptor = FetchDescriptor<T>(
            predicate: #Predicate { $0.id == id }
        )
        return try? fetch(descriptor).first
    }

    /// Check if any entities exist for the given descriptor
    func exists<T: PersistentModel>(_ descriptor: FetchDescriptor<T>) -> Bool {
        (try? fetchCount(descriptor)) ?? 0 > 0
    }

    /// Save context only if there are changes
    func saveIfNeeded() throws {
        if hasChanges {
            try save()
        }
    }
}
