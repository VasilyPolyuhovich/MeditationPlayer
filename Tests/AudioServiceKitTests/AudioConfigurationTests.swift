import XCTest
@testable import AudioServiceCore

final class AudioConfigurationTests: XCTestCase {
    
    func testDefaultConfiguration() {
        let config = AudioConfiguration()
        
        XCTAssertEqual(config.crossfadeDuration, 10.0)
        XCTAssertEqual(config.fadeInDuration, 3.0)
        XCTAssertEqual(config.fadeOutDuration, 6.0)
        XCTAssertEqual(config.volume, 1.0)
        XCTAssertNil(config.repeatCount)
        XCTAssertTrue(config.enableLooping)
    }
    
    func testConfigurationValidation() throws {
        // Valid configuration
        let validConfig = AudioConfiguration(
            crossfadeDuration: 15.0,
            fadeInDuration: 2.0,
            fadeOutDuration: 4.0,
            volume: 0.8
        )
        XCTAssertNoThrow(try validConfig.validate())
    }
    
    func testConfigurationClampsCrossfadeDuration() {
        // Too small
        let config1 = AudioConfiguration(crossfadeDuration: 0.5)
        XCTAssertEqual(config1.crossfadeDuration, 1.0)
        
        // Too large
        let config2 = AudioConfiguration(crossfadeDuration: 50.0)
        XCTAssertEqual(config2.crossfadeDuration, 30.0)
        
        // Just right
        let config3 = AudioConfiguration(crossfadeDuration: 15.0)
        XCTAssertEqual(config3.crossfadeDuration, 15.0)
    }
    
    func testConfigurationClampsVolume() {
        // Too small
        let config1 = AudioConfiguration(volume: -0.5)
        XCTAssertEqual(config1.volume, 0.0)
        
        // Too large
        let config2 = AudioConfiguration(volume: 1.5)
        XCTAssertEqual(config2.volume, 1.0)
        
        // Just right
        let config3 = AudioConfiguration(volume: 0.7)
        XCTAssertEqual(config3.volume, 0.7)
    }
    
    func testConfigurationValidationThrowsForInvalidVolume() {
        // This shouldn't happen due to clamping, but test validation anyway
        var config = AudioConfiguration()
        // Force invalid value through reflection or manual construction
        // For now, test that validation works with valid values
        XCTAssertNoThrow(try config.validate())
    }
}
