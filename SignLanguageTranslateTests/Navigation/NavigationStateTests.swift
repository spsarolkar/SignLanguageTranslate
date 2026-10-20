import XCTest
@testable import SignLanguageTranslate

final class NavigationStateTests: XCTestCase {
    @MainActor
    func test_sidebarSwitch_invalidatesDetailAndKeepsIndependentDatasetSelections() async {
        let state = NavigationState(section: .pipeline)
        let browsing = Dataset(name: "Browse", type: .include)
        let training = Dataset(name: "Train", type: .include)
        let pipeline = Dataset(name: "Extract", type: .include)
        state.selectedDataset = browsing
        state.trainingDataset = training
        state.selectPipelineDataset(pipeline)

        for section in NavigationSection.allCases where section != .pipeline {
            state.selectSection(.pipeline)
            state.pipelineVideo = video(dataset: pipeline)
            state.pipelineAnalysisPresented = true
            let oldStack = state.stackGeneration

            state.selectSection(section)

            XCTAssertEqual(state.selectedSection, section)
            XCTAssertNotEqual(state.stackGeneration, oldStack, "Old word/clip/run destinations must be discarded")
            XCTAssertNil(state.pipelineVideo)
            XCTAssertFalse(state.pipelineAnalysisPresented)
            XCTAssertEqual(state.selectedDataset?.id, browsing.id)
            XCTAssertEqual(state.trainingDataset?.id, training.id)
            XCTAssertEqual(state.pipelineDataset?.id, pipeline.id)
        }
    }

    @MainActor
    func test_reselectingSameSection_doesNotDismissCurrentClip() async {
        let state = NavigationState(section: .pipeline)
        let dataset = Dataset(name: "INCLUDE", type: .include)
        let clip = video(dataset: dataset)
        state.selectPipelineDataset(dataset)
        state.pipelineVideo = clip
        let oldStack = state.stackGeneration

        state.selectSection(.pipeline)

        XCTAssertEqual(state.pipelineVideo?.id, clip.id)
        XCTAssertEqual(state.stackGeneration, oldStack)
    }

    @MainActor
    func test_changingPipelineDataset_clearsFiltersAndOldClip() async {
        let state = NavigationState(section: .pipeline)
        let oldDataset = Dataset(name: "First", type: .include)
        let newDataset = Dataset(name: "Second", type: .islcsltr)
        state.selectPipelineDataset(oldDataset)
        state.selectPipelineCategory("Animals")
        state.searchPipeline("Dog")
        state.pipelineVideo = video(dataset: oldDataset)
        state.pipelineAnalysisPresented = true

        state.selectPipelineDataset(newDataset)

        XCTAssertEqual(state.pipelineDataset?.id, newDataset.id)
        XCTAssertNil(state.pipelineCategory)
        XCTAssertEqual(state.pipelineSearch, "")
        XCTAssertNil(state.pipelineVideo)
        XCTAssertFalse(state.pipelineAnalysisPresented)
    }

    @MainActor
    func test_reselectingSameDataset_preservesFilters() async {
        let state = NavigationState(section: .pipeline)
        let dataset = Dataset(name: "INCLUDE", type: .include)
        state.selectPipelineDataset(dataset)
        state.selectPipelineCategory("Animals")
        state.searchPipeline("Dog")
        let clip = video(dataset: dataset)
        state.pipelineVideo = clip

        state.selectPipelineDataset(dataset)

        XCTAssertEqual(state.pipelineCategory, "Animals")
        XCTAssertEqual(state.pipelineSearch, "Dog")
        XCTAssertEqual(state.pipelineVideo?.id, clip.id)
    }

    @MainActor
    func test_changingCategory_dismissesClipAndKeepsSearch() async {
        let state = NavigationState(section: .pipeline)
        let dataset = Dataset(name: "INCLUDE", type: .include)
        state.selectPipelineDataset(dataset)
        state.searchPipeline("clip")
        state.pipelineVideo = video(dataset: dataset)
        state.pipelineAnalysisPresented = true

        state.selectPipelineCategory("Animals")

        XCTAssertEqual(state.pipelineDataset?.id, dataset.id)
        XCTAssertEqual(state.pipelineSearch, "clip")
        XCTAssertEqual(state.pipelineCategory, "Animals")
        XCTAssertNil(state.pipelineVideo)
        XCTAssertFalse(state.pipelineAnalysisPresented)
    }

    @MainActor
    func test_changingSearch_dismissesClipAndKeepsCategory() async {
        let state = NavigationState(section: .pipeline)
        let dataset = Dataset(name: "INCLUDE", type: .include)
        state.selectPipelineDataset(dataset)
        state.selectPipelineCategory("Animals")
        state.pipelineVideo = video(dataset: dataset)

        state.searchPipeline("Dog")

        XCTAssertEqual(state.pipelineCategory, "Animals")
        XCTAssertEqual(state.pipelineSearch, "Dog")
        XCTAssertNil(state.pipelineVideo)
    }

    @MainActor
    func test_clearingDataset_removesItsFiltersAndDestination() async {
        let state = NavigationState(section: .pipeline)
        let dataset = Dataset(name: "INCLUDE", type: .include)
        state.selectPipelineDataset(dataset)
        state.selectPipelineCategory("Animals")
        state.pipelineVideo = video(dataset: dataset)

        state.selectPipelineDataset(nil)

        XCTAssertNil(state.pipelineDataset)
        XCTAssertNil(state.pipelineCategory)
        XCTAssertNil(state.pipelineVideo)
    }

    @MainActor
    func test_clearingSidebarSelection_invalidatesOldDetail() async {
        let state = NavigationState(section: .pipeline)
        state.pipelineAnalysisPresented = true
        let oldStack = state.stackGeneration

        state.selectSection(nil)

        XCTAssertNil(state.selectedSection)
        XCTAssertNotEqual(state.stackGeneration, oldStack)
        XCTAssertFalse(state.pipelineAnalysisPresented)
    }

    @MainActor
    private func video(dataset: Dataset) -> VideoSample {
        VideoSample(localPath: "\(dataset.name)/clip.mp4", datasetName: dataset.name)
    }

    /// A synchronous caller reproduces the no-task teardown path used when
    /// SwiftUI destroys sidebar state. This previously aborted in libmalloc.
    @MainActor
    func test_sidebarStorageState_canBeReleasedOutsideAnAsyncTask() {
        var preflight: SystemPreflight? = SystemPreflight()
        weak var releasedState = preflight
        preflight?.refreshStorage()

        preflight = nil

        XCTAssertNil(releasedState)
    }
}
