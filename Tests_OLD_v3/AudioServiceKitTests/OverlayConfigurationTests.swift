import Testing
import Foundation
@testable import AudioServiceCore

/// Test suite: OverlayConfiguration validation and presets (Feature #4)
@Suite("Overlay Configuration")
struct OverlayConfigurationTests {
    
    // MARK: - Default Configuration
    
    @Test("Default configuration has sensible values")
    func testDefaultConfiguration() {
        let config = OverlayConfiguration()
        
        #expect(config.loopMode == .once)
        #expect(config.loopDelay == 0.0)
        #expect(config.volume == 1.0)
        #expect(config.fadeInDuration == 0.0)
        #expect(config.fadeOutDuration == 0.0)
        #expect(config.fadeCurve == .linear)
        #expect(config.applyFadeOnEachLoop == true)
    }
    
    // MARK: - Validation Tests
    
    @Test("Valid configuration passes validation")
    func testValidConfiguration() {
        let config = OverlayConfiguration(
            loopMode: .count(3),
            loopDelay: 5.0,
            volume: 0.8,
            fadeInDuration: 1.0,
            fadeOutDuration: 1.0,
            fadeCurve: .equalPower,
            applyFadeOnEachLoop: true
        )
        
        #expect(config.isValid == true)
    }
    
    @Test("Volume below 0.0 is invalid")
    func testInvalidVolumeLow() {
        var config = OverlayConfiguration()
        config.volume = -0.1
        
        #expect(config.isValid == false)
    }
    
    @Test("Volume above 1.0 is invalid")
    func testInvalidVolumeHigh() {
        var config = OverlayConfiguration()
        config.volume = 1.5
        
        #expect(config.isValid == false)
    }
    
    @Test("Volume at boundaries is valid")
    func testValidVolumeBoundaries() {
        var config1 = OverlayConfiguration()
        config1.volume = 0.0
        #expect(config1.isValid == true)
        
        var config2 = OverlayConfiguration()
        config2.volume = 1.0
        #expect(config2.isValid == true)
    }
    
    @Test("Negative loop delay is invalid")
    func testInvalidLoopDelay() {
        var config = OverlayConfiguration()
        config.loopDelay = -1.0
        
        #expect(config.isValid == false)
    }
    
    @Test("Zero loop delay is valid")
    func testValidZeroLoopDelay() {
        var config = OverlayConfiguration()
        config.loopDelay = 0.0
        
        #expect(config.isValid == true)
    }
    
    @Test("Negative fade in duration is invalid")
    func testInvalidFadeInDuration() {
        var config = OverlayConfiguration()
        config.fadeInDuration = -0.5
        
        #expect(config.isValid == false)
    }
    
    @Test("Negative fade out duration is invalid")
    func testInvalidFadeOutDuration() {
        var config = OverlayConfiguration()
        config.fadeOutDuration = -0.5
        
        #expect(config.isValid == false)
    }
    
    @Test("Zero fade durations are valid")
    func testValidZeroFadeDurations() {
        let config = OverlayConfiguration(
            fadeInDuration: 0.0,
            fadeOutDuration: 0.0
        )
        
        #expect(config.isValid == true)
    }
    
    // MARK: - Loop Mode Tests
    
    @Test("Loop mode: once")
    func testLoopModeOnce() {
        let config = OverlayConfiguration(loopMode: .once)
        
        #expect(config.loopMode == .once)
        #expect(config.isValid == true)
    }
    
    @Test("Loop mode: count with valid value")
    func testLoopModeCountValid() {
        let config = OverlayConfiguration(loopMode: .count(5))
        
        if case .count(let times) = config.loopMode {
            #expect(times == 5)
        } else {
            Issue.record("Expected .count(5) loop mode")
        }
        #expect(config.isValid == true)
    }
    
    @Test("Loop mode: count with zero is invalid")
    func testLoopModeCountZero() {
        var config = OverlayConfiguration()
        config.loopMode = .count(0)
        
        #expect(config.isValid == false)
    }
    
    @Test("Loop mode: count with negative is invalid")
    func testLoopModeCountNegative() {
        var config = OverlayConfiguration()
        config.loopMode = .count(-1)
        
        #expect(config.isValid == false)
    }
    
    @Test("Loop mode: infinite")
    func testLoopModeInfinite() {
        let config = OverlayConfiguration(loopMode: .infinite)
        
        #expect(config.loopMode == .infinite)
        #expect(config.isValid == true)
    }
    
    // MARK: - Preset Tests
    
    @Test("Preset: ambient configuration")
    func testAmbientPreset() {
        let config = OverlayConfiguration.ambient
        
        #expect(config.loopMode == .infinite)
        #expect(config.volume == 0.3)
        #expect(config.fadeInDuration == 2.0)
        #expect(config.fadeOutDuration == 2.0)
        #expect(config.applyFadeOnEachLoop == false)
        #expect(config.isValid == true)
    }
    
    @Test("Preset: bell with valid parameters")
    func testBellPreset() {
        let config = OverlayConfiguration.bell(times: 3, interval: 300.0)
        
        if case .count(let times) = config.loopMode {
            #expect(times == 3)
        } else {
            Issue.record("Expected .count(3) loop mode")
        }
        #expect(config.loopDelay == 300.0)
        #expect(config.volume == 0.5)
        #expect(config.fadeInDuration == 0.5)
        #expect(config.fadeOutDuration == 0.5)
        #expect(config.applyFadeOnEachLoop == true)
        #expect(config.isValid == true)
    }
    
    @Test("Preset: bell with single ring")
    func testBellPresetSingleRing() {
        let config = OverlayConfiguration.bell(times: 1, interval: 0.0)
        
        if case .count(let times) = config.loopMode {
            #expect(times == 1)
        } else {
            Issue.record("Expected .count(1) loop mode")
        }
        #expect(config.isValid == true)
    }
    
    @Test("Preset: bell with many rings")
    func testBellPresetManyRings() {
        let config = OverlayConfiguration.bell(times: 100, interval: 60.0)
        
        if case .count(let times) = config.loopMode {
            #expect(times == 100)
        } else {
            Issue.record("Expected .count(100) loop mode")
        }
        #expect(config.loopDelay == 60.0)
        #expect(config.isValid == true)
    }
    
    // MARK: - Fade Curve Tests
    
    @Test("All fade curve types are valid")
    func testAllFadeCurveTypes() {
        let curves: [FadeCurve] = [.linear, .equalPower, .logarithmic, .exponential, .sCurve]
        
        for curve in curves {
            let config = OverlayConfiguration(fadeCurve: curve)
            #expect(config.isValid == true)
        }
    }
    
    // MARK: - ApplyFadeOnEachLoop Tests
    
    @Test("Apply fade on each loop: true")
    func testApplyFadeOnEachLoopTrue() {
        let config = OverlayConfiguration(
            loopMode: .count(3),
            fadeInDuration: 1.0,
            fadeOutDuration: 1.0,
            applyFadeOnEachLoop: true
        )
        
        #expect(config.applyFadeOnEachLoop == true)
        #expect(config.isValid == true)
    }
    
    @Test("Apply fade on each loop: false")
    func testApplyFadeOnEachLoopFalse() {
        let config = OverlayConfiguration(
            loopMode: .infinite,
            fadeInDuration: 2.0,
            fadeOutDuration: 2.0,
            applyFadeOnEachLoop: false
        )
        
        #expect(config.applyFadeOnEachLoop == false)
        #expect(config.isValid == true)
    }
    
    // MARK: - Equatable Tests
    
    @Test("Identical configurations are equal")
    func testEquatableIdentical() {
        let config1 = OverlayConfiguration(
            loopMode: .count(3),
            loopDelay: 5.0,
            volume: 0.8,
            fadeInDuration: 1.0,
            fadeOutDuration: 1.0,
            fadeCurve: .equalPower,
            applyFadeOnEachLoop: true
        )
        
        let config2 = OverlayConfiguration(
            loopMode: .count(3),
            loopDelay: 5.0,
            volume: 0.8,
            fadeInDuration: 1.0,
            fadeOutDuration: 1.0,
            fadeCurve: .equalPower,
            applyFadeOnEachLoop: true
        )
        
        #expect(config1 == config2)
    }
    
    @Test("Different configurations are not equal")
    func testEquatableDifferent() {
        let config1 = OverlayConfiguration(volume: 0.5)
        let config2 = OverlayConfiguration(volume: 0.8)
        
        #expect(config1 != config2)
    }
    
    // MARK: - Edge Cases
    
    @Test("Configuration with all zeros is valid")
    func testAllZerosConfiguration() {
        let config = OverlayConfiguration(
            loopMode: .once,
            loopDelay: 0.0,
            volume: 0.0,
            fadeInDuration: 0.0,
            fadeOutDuration: 0.0
        )
        
        #expect(config.isValid == true)
    }
    
    @Test("Configuration with maximum reasonable values")
    func testMaximumValues() {
        let config = OverlayConfiguration(
            loopMode: .count(1000),
            loopDelay: 3600.0, // 1 hour
            volume: 1.0,
            fadeInDuration: 30.0,
            fadeOutDuration: 30.0
        )
        
        #expect(config.isValid == true)
    }
    
    @Test("Mixed valid and invalid creates invalid configuration")
    func testMixedValidInvalid() {
        var config = OverlayConfiguration(
            volume: 0.5,  // valid
            fadeInDuration: 1.0  // valid
        )
        config.loopDelay = -1.0  // invalid
        
        #expect(config.isValid == false)
    }
}
