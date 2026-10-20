import Foundation
import Observation

/// Selections belong to a sidebar section; pushed detail screens never carry
/// over into another section. All model references stay on the main actor.
@MainActor
@Observable
final class NavigationState {
    private(set) var selectedSection: NavigationSection?
    private(set) var stackGeneration = 0

    var selectedDataset: Dataset?
    var trainingDataset: Dataset?
    private(set) var pipelineDataset: Dataset?
    private(set) var pipelineCategory: String?
    private(set) var pipelineSearch = ""
    var pipelineVideo: VideoSample?
    var pipelineAnalysisPresented = false

    init(section: NavigationSection? = .datasets) {
        selectedSection = section
    }

    // No actor-bound cleanup; matches the existing UI state owners and avoids
    // isolated-deinit runtime crashes on the supported iOS 26.2 runtime.
    nonisolated deinit {}

    func selectSection(_ section: NavigationSection?) {
        guard selectedSection != section else { return }
        selectedSection = section
        pipelineVideo = nil
        pipelineAnalysisPresented = false
        // Recreate the split's implicit navigation stacks as well as its views.
        // Changing only the detail view's identity leaves pushed destinations.
        stackGeneration += 1
    }

    func selectPipelineDataset(_ dataset: Dataset?) {
        guard pipelineDataset?.id != dataset?.id else { return }
        pipelineDataset = dataset
        pipelineCategory = nil
        pipelineSearch = ""
        clearPipelineDestination()
    }

    func selectPipelineCategory(_ category: String?) {
        guard pipelineCategory != category else { return }
        pipelineCategory = category
        clearPipelineDestination()
    }

    func searchPipeline(_ text: String) {
        guard pipelineSearch != text else { return }
        pipelineSearch = text
        clearPipelineDestination()
    }

    private func clearPipelineDestination() {
        pipelineVideo = nil
        pipelineAnalysisPresented = false
    }
}
