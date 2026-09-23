import XCTest
@testable import SignLanguageTranslate
import MLX
import MLXNN

final class SignLanguageModelTests: XCTestCase {
    
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
    
    func testModelInitializationT5Small() {
        let config = SignLanguageModelConfig.t5_small
        let model = SignLanguageModel(config: config)
        
        XCTAssertNotNil(model)
        XCTAssertEqual(model.encoderLayers.count, 6)
        
        // Verify input projection
        XCTAssertEqual(model.inputProjection.weight.dim(1), 512) // Output dim of projection is modelDim
    }
    
    func testModelInitializationT5Base() {
        let config = SignLanguageModelConfig.t5_base
        let model = SignLanguageModel(config: config)
        
        XCTAssertNotNil(model)
        XCTAssertEqual(model.encoderLayers.count, 12)
        
        // Verify input projection
        XCTAssertEqual(model.inputProjection.weight.dim(1), 768)
    }
}
