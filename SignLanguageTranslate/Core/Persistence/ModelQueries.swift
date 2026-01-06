import Foundation
import SwiftData

/// Predefined fetch descriptors for common queries
enum ModelQueries {

    // MARK: - Dataset Queries

    /// Fetch all datasets sorted by name
    static var allDatasets: FetchDescriptor<Dataset> {
        var descriptor = FetchDescriptor<Dataset>(
            sortBy: [SortDescriptor(\.name)]
        )
        return descriptor
    }

    /// Fetch datasets by status
    static func datasets(withStatus status: DownloadStatus) -> FetchDescriptor<Dataset> {
        let statusRaw = status.rawValue
        return FetchDescriptor<Dataset>(
            predicate: #Predicate { $0.statusRawValue == statusRaw },
            sortBy: [SortDescriptor(\.name)]
        )
    }

    /// Fetch datasets that are ready to use
    static var readyDatasets: FetchDescriptor<Dataset> {
        let completedRaw = DownloadStatus.completed.rawValue
        return FetchDescriptor<Dataset>(
            predicate: #Predicate { $0.statusRawValue == completedRaw },
            sortBy: [SortDescriptor(\.name)]
        )
    }

    /// Fetch dataset by name
    static func dataset(named name: String) -> FetchDescriptor<Dataset> {
        FetchDescriptor<Dataset>(
            predicate: #Predicate { $0.name == name }
        )
    }

    // MARK: - Label Queries

    /// Fetch all labels sorted by name
    static var allLabels: FetchDescriptor<Label> {
        FetchDescriptor<Label>(
            sortBy: [SortDescriptor(\.name)]
        )
    }

    /// Fetch labels by type
    static func labels(ofType type: LabelType) -> FetchDescriptor<Label> {
        let typeRaw = type.rawValue
        return FetchDescriptor<Label>(
            predicate: #Predicate { $0.typeRawValue == typeRaw },
            sortBy: [SortDescriptor(\.name)]
        )
    }

    /// Fetch category labels only
    static var categoryLabels: FetchDescriptor<Label> {
        labels(ofType: .category)
    }

    /// Fetch word labels only
    static var wordLabels: FetchDescriptor<Label> {
        labels(ofType: .word)
    }

    /// Fetch sentence labels only
    static var sentenceLabels: FetchDescriptor<Label> {
        labels(ofType: .sentence)
    }

    /// Fetch label by name and type
    static func label(named name: String, type: LabelType) -> FetchDescriptor<Label> {
        let typeRaw = type.rawValue
        return FetchDescriptor<Label>(
            predicate: #Predicate { $0.name == name && $0.typeRawValue == typeRaw }
        )
    }

    // MARK: - VideoSample Queries

    /// Fetch all video samples sorted by creation date
    static var allVideoSamples: FetchDescriptor<VideoSample> {
        FetchDescriptor<VideoSample>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
    }

    /// Fetch video samples for a specific dataset
    static func videoSamples(forDataset datasetName: String) -> FetchDescriptor<VideoSample> {
        FetchDescriptor<VideoSample>(
            predicate: #Predicate { $0.datasetName == datasetName },
            sortBy: [SortDescriptor(\.localPath)]
        )
    }

    /// Fetch favorite video samples
    static var favoriteVideoSamples: FetchDescriptor<VideoSample> {
        FetchDescriptor<VideoSample>(
            predicate: #Predicate { $0.isFavorite == true },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
    }

    /// Fetch recently accessed video samples
    static func recentlyAccessedSamples(limit: Int = 20) -> FetchDescriptor<VideoSample> {
        var descriptor = FetchDescriptor<VideoSample>(
            predicate: #Predicate { $0.lastAccessedAt != nil },
            sortBy: [SortDescriptor(\.lastAccessedAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return descriptor
    }

    /// Fetch video samples count for a dataset
    static func videoSampleCount(forDataset datasetName: String) -> FetchDescriptor<VideoSample> {
        FetchDescriptor<VideoSample>(
            predicate: #Predicate { $0.datasetName == datasetName }
        )
    }
}

// MARK: - Query Result Helpers

extension ModelContext {

    /// Fetch all datasets
    func fetchAllDatasets() throws -> [Dataset] {
        try fetch(ModelQueries.allDatasets)
    }

    /// Fetch dataset by name
    func fetchDataset(named name: String) throws -> Dataset? {
        try fetch(ModelQueries.dataset(named: name)).first
    }

    /// Fetch all category labels
    func fetchCategoryLabels() throws -> [Label] {
        try fetch(ModelQueries.categoryLabels)
    }

    /// Fetch all word labels
    func fetchWordLabels() throws -> [Label] {
        try fetch(ModelQueries.wordLabels)
    }

    /// Find or create a label
    func findOrCreateLabel(named name: String, type: LabelType) throws -> Label {
        if let existing = try fetch(ModelQueries.label(named: name, type: type)).first {
            return existing
        }

        let newLabel = Label(name: name, type: type)
        insert(newLabel)
        return newLabel
    }

    /// Fetch video samples for a dataset
    func fetchVideoSamples(forDataset datasetName: String) throws -> [VideoSample] {
        try fetch(ModelQueries.videoSamples(forDataset: datasetName))
    }

    /// Count video samples for a dataset
    func countVideoSamples(forDataset datasetName: String) throws -> Int {
        try fetchCount(ModelQueries.videoSampleCount(forDataset: datasetName))
    }

    /// Fetch favorite video samples
    func fetchFavorites() throws -> [VideoSample] {
        try fetch(ModelQueries.favoriteVideoSamples)
    }
}
