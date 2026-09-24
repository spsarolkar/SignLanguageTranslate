import XCTest
@testable import SignLanguageTranslate
import MLX
import MLXNN

final class SignLanguageModelTests: XCTestCase {

    /// MLX needs Metal features the iOS Simulator does not provide (see mlx-swift
    /// "Running on iOS"). Tests that create MLX arrays run on device only.
    private func skipOnSimulator() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("MLX does not run on the iOS Simulator; run on device")
        #endif
    }
    
    func testT5SmallConfig() {
        let config = SignLanguageModelConfig.t5_small
        
        XCTAssertEqual(config.numLayers, 6)
        XCTAssertEqual(config.modelDim, 512)
        XCTAssertEqual(config.numHeads, 8)
        XCTAssertEqual(config.outputDim, 384)
        XCTAssertEqual(config.poolingType, .attention)
        
        // Check divisibility
        XCTAssertEqual(config.modelDim % config.numHeads, 0)
    }
    
    func testT5BaseConfig() {
        let config = SignLanguageModelConfig.t5_base
        
        XCTAssertEqual(config.numLayers, 12)
        XCTAssertEqual(config.modelDim, 768)
        XCTAssertEqual(config.numHeads, 12)
        XCTAssertEqual(config.outputDim, 384)
        XCTAssertEqual(config.poolingType, .attention)
        
        // Check divisibility
        XCTAssertEqual(config.modelDim % config.numHeads, 0)
    }
    
    func testModelInitializationT5Small() throws {
        try skipOnSimulator()
        let config = SignLanguageModelConfig.t5_small
        let model = SignLanguageModel(config: config)
        
        XCTAssertNotNil(model)
        XCTAssertEqual(model.encoderLayers.count, 6)
        
        // Verify input projection
        // MLX Linear weight is [outputDimensions, inputDimensions]
        XCTAssertEqual(model.inputProjection.weight.dim(0), 512)
        XCTAssertEqual(model.inputProjection.weight.dim(1), 180)
    }
    
    func testModelInitializationT5Base() throws {
        try skipOnSimulator()
        let config = SignLanguageModelConfig.t5_base
        let model = SignLanguageModel(config: config)
        
        XCTAssertNotNil(model)
        XCTAssertEqual(model.encoderLayers.count, 12)
        
        // Verify input projection
        XCTAssertEqual(model.inputProjection.weight.dim(0), 768)
        XCTAssertEqual(model.inputProjection.weight.dim(1), 180)
    }
}
