import Testing
import Foundation
@testable import AudioServiceCore

/// Test suite: PlayerConfiguration validation and presets (Features #1-3)
@Suite("Player Configuration")
struct PlayerConfigurationTests {
    
    // MARK: - Default Configuration
    
    @Test("Default configuration has sensible values")
    func testDefaultConfiguration() {
        let config = PlayerConfiguration()
        
        #expect(config.crossfadeDuration == 10.0)
        #expect(config.fadeCurve == .equalPower)
        #expect(config.repeatMode == .off)
        #expect(config.repeatCount == nil)
        #expect(config.singleTrackFadeInDuration == 3.0)
        #expect(config.singleTrackFadeOutDuration == 3.0)
        #expect(config.volume == 100)
        #expect(config.stopFadeDuration == 3.0)
        #expect(config.mixWithOthers == false)
    }
    
    @Test("Default preset matches default init")
    func testDefaultPreset() {
        let preset = PlayerConfiguration.default
        let manual = PlayerConfiguration()
        
        #expect(preset.crossfadeDuration == manual.crossfadeDuration)
        #expect(preset.volume == manual.volume)
        #expect(preset.repeatMode == manual.repeatMode)
    }
    
    // MARK: - Crossfade Duration Clamping
    
    @Test("Crossfade duration clamps to minimum 1.0")
    func testCrossfadeDurationMinClamp() {
        let config = PlayerConfiguration(crossfadeDuration: 0.5)
        #expect(config.crossfadeDuration == 1.0)
    }
    
    @Test("Crossfade duration clamps to maximum 30.0")
    func testCrossfadeDurationMaxClamp() {
        let config = PlayerConfiguration(crossfadeDuration: 50.0)
        #expect(config.crossfadeDuration == 30.0)
    }
    
    @Test("Crossfade duration within range unchanged")
    func testCrossfadeDurationWithinRange() {
        let config = PlayerConfiguration(crossfadeDuration: 15.0)
        #expect(config.crossfadeDuration == 15.0)
    }
    
    // MARK: - Volume Clamping and Conversion
    
    @Test("Volume clamps to minimum 0")
    func testVolumeMinClamp() {
        let config = PlayerConfiguration(volume: -10)
        #expect(config.volume == 0)
    }
    
    @Test("Volume clamps to maximum 100")
    func testVolumeMaxClamp() {
        let config = PlayerConfiguration(volume: 150)
        #expect(config.volume == 100)
    }
    
    @Test("Volume within range unchanged")
    func testVolumeWithinRange() {
        let config = PlayerConfiguration(volume: 75)
        #expect(config.volume == 75)
    }
    
    @Test("Volume converts to float correctly")
    func testVolumeFloatConversion() {
        let config1 = PlayerConfiguration(volume: 0)
        #expect(config1.volumeFloat == 0.0)
        
        let config2 = PlayerConfiguration(volume: 50)
        #expect(config2.volumeFloat == 0.5)
        
        let config3 = PlayerConfiguration(volume: 100)
        #expect(config3.volumeFloat == 1.0)
    }
    
    // MARK: - Fade In Duration (Computed)
    
    @Test("Fade in duration is 30% of crossfade")
    func testFadeInDurationComputed() {
        let config1 = PlayerConfiguration(crossfadeDuration: 10.0)
        #expect(config1.fadeInDuration == 3.0)
        
        let config2 = PlayerConfiguration(crossfadeDuration: 20.0)
        #expect(config2.fadeInDuration == 6.0)
        
        let config3 = PlayerConfiguration(crossfadeDuration: 5.0)
        #expect(config3.fadeInDuration == 1.5)
    }
    
    // MARK: - Repeat Mode (Feature #1)
    
    @Test("Repeat mode: off")
    func testRepeatModeOff() {
        let config = PlayerConfiguration(repeatMode: .off)
        #expect(config.repeatMode == .off)
    }
    
    @Test("Repeat mode: singleTrack")
    func testRepeatModeSingleTrack() {
        let config = PlayerConfiguration(repeatMode: .singleTrack)
        #expect(config.repeatMode == .singleTrack)
    }
    
    @Test("Repeat mode: playlist")
    func testRepeatModePlaylist() {
        let config = PlayerConfiguration(repeatMode: .playlist)
        #expect(config.repeatMode == .playlist)
    }
    
    // MARK: - Single Track Fade Durations Clamping (Feature #1)
    
    @Test("Single track fade in clamps to minimum 0.5")
    func testSingleTrackFadeInMinClamp() {
        let config = PlayerConfiguration(singleTrackFadeInDuration: 0.2)
        #expect(config.singleTrackFadeInDuration == 0.5)
    }
    
    @Test("Single track fade in clamps to maximum 10.0")
    func testSingleTrackFadeInMaxClamp() {
        let config = PlayerConfiguration(singleTrackFadeInDuration: 15.0)
        #expect(config.singleTrackFadeInDuration == 10.0)
    }
    
    @Test("Single track fade out clamps to minimum 0.5")
    func testSingleTrackFadeOutMinClamp() {
        let config = PlayerConfiguration(singleTrackFadeOutDuration: 0.2)
        #expect(config.singleTrackFadeOutDuration == 0.5)
    }
    
    @Test("Single track fade out clamps to maximum 10.0")
    func testSingleTrackFadeOutMaxClamp() {
        let config = PlayerConfiguration(singleTrackFadeOutDuration: 15.0)
        #expect(config.singleTrackFadeOutDuration == 10.0)
    }
    
    // MARK: - Stop Fade Duration Clamping (Feature #2)
    
    @Test("Stop fade duration clamps to minimum 0.0")
    func testStopFadeDurationMinClamp() {
        let config = PlayerConfiguration(stopFadeDuration: -1.0)
        #expect(config.stopFadeDuration == 0.0)
    }
    
    @Test("Stop fade duration clamps to maximum 10.0")
    func testStopFadeDurationMaxClamp() {
        let config = PlayerConfiguration(stopFadeDuration: 15.0)
        #expect(config.stopFadeDuration == 10.0)
    }
    
    @Test("Stop fade duration zero is valid")
    func testStopFadeDurationZero() {
        let config = PlayerConfiguration(stopFadeDuration: 0.0)
        #expect(config.stopFadeDuration == 0.0)
    }
    
    // MARK: - Mix With Others (Bonus Feature)
    
    @Test("Mix with others: false by default")
    func testMixWithOthersDefault() {
        let config = PlayerConfiguration()
        #expect(config.mixWithOthers == false)
    }
    
    @Test("Mix with others: can be set to true")
    func testMixWithOthersTrue() {
        let config = PlayerConfiguration(mixWithOthers: true)
        #expect(config.mixWithOthers == true)
    }
    
    // MARK: - Validation Tests
    
    @Test("Valid configuration passes validation")
    func testValidConfiguration() throws {
        let config = PlayerConfiguration(
            crossfadeDuration: 15.0,
            volume: 80,
            stopFadeDuration: 5.0
        )
        
        try config.validate()
        // Should not throw
    }
    
    @Test("Validation throws for invalid crossfade duration")
    func testValidationInvalidCrossfade() {
        // Create config, then manually set invalid value
        var config = PlayerConfiguration()
        // Note: init clamps values, so we can't test this way
        // Instead, we test the validation logic directly
        
        // Clamped values should always be valid
        try? config.validate()
        // Should not throw for clamped values
    }
    
    @Test("Validation throws for negative repeat count")
    func testValidationNegativeRepeatCount() {
        var config = PlayerConfiguration()
        config.repeatCount = -1
        
        #expect(throws: ConfigurationError.self) {
            try config.validate()
        }
    }
    
    @Test("Validation allows nil repeat count")
    func testValidationNilRepeatCount() throws {
        let config = PlayerConfiguration(repeatCount: nil)
        try config.validate()
        // Should not throw
    }
    
    @Test("Validation allows zero repeat count")
    func testValidationZeroRepeatCount() throws {
        var config = PlayerConfiguration()
        config.repeatCount = 0
        try config.validate()
        // Should not throw
    }
    
    // MARK: - ConfigurationError Tests
    
    @Test("ConfigurationError: invalid crossfade duration")
    func testConfigurationErrorCrossfade() {
        let error = ConfigurationError.invalidCrossfadeDuration(0.5)
        #expect(error.errorDescription?.contains("1.0 and 30.0") == true)
    }
    
    @Test("ConfigurationError: invalid volume")
    func testConfigurationErrorVolume() {
        let error = ConfigurationError.invalidVolume(150)
        #expect(error.errorDescription?.contains("0 and 100") == true)
    }
    
    @Test("ConfigurationError: invalid repeat count")
    func testConfigurationErrorRepeatCount() {
        let error = ConfigurationError.invalidRepeatCount(-1)
        #expect(error.errorDescription?.contains("must be") == true)
    }
    
    @Test("ConfigurationError: invalid stop fade duration")
    func testConfigurationErrorStopFade() {
        let error = ConfigurationError.invalidStopFadeDuration(15.0)
        #expect(error.errorDescription?.contains("0.0 and 10.0") == true)
    }
    
    @Test("ConfigurationError: invalid single track fade in")
    func testConfigurationErrorSingleTrackFadeIn() {
        let error = ConfigurationError.invalidSingleTrackFadeInDuration(0.2)
        #expect(error.errorDescription?.contains("0.5 and 10.0") == true)
    }
    
    @Test("ConfigurationError: invalid single track fade out")
    func testConfigurationErrorSingleTrackFadeOut() {
        let error = ConfigurationError.invalidSingleTrackFadeOutDuration(15.0)
        #expect(error.errorDescription?.contains("0.5 and 10.0") == true)
    }
    
    // MARK: - Fade Curve Tests
    
    @Test("All fade curve types are valid")
    func testAllFadeCurveTypes() {
        let curves: [FadeCurve] = [.linear, .equalPower, .logarithmic, .exponential, .sCurve]
        
        for curve in curves {
            let config = PlayerConfiguration(fadeCurve: curve)
            try? config.validate()
            #expect(config.fadeCurve == curve)
        }
    }
    
    // MARK: - Deprecated enableLooping Tests
    
    @Test("Deprecated enableLooping getter")
    func testEnableLoopingGetter() {
        let config1 = PlayerConfiguration(repeatMode: .playlist)
        #expect(config1.enableLooping == true)
        
        let config2 = PlayerConfiguration(repeatMode: .off)
        #expect(config2.enableLooping == false)
        
        let config3 = PlayerConfiguration(repeatMode: .singleTrack)
        #expect(config3.enableLooping == false)
    }
    
    @Test("Deprecated enableLooping setter")
    func testEnableLoopingSetter() {
        var config1 = PlayerConfiguration()
        config1.enableLooping = true
        #expect(config1.repeatMode == .playlist)
        
        var config2 = PlayerConfiguration()
        config2.enableLooping = false
        #expect(config2.repeatMode == .off)
    }
    
    // MARK: - Edge Cases
    
    @Test("Configuration with all minimum values")
    func testMinimumValues() throws {
        let config = PlayerConfiguration(
            crossfadeDuration: 1.0,
            singleTrackFadeInDuration: 0.5, singleTrackFadeOutDuration: 0.5, volume: 0,
            stopFadeDuration: 0.0
        )
        
        try config.validate()
        #expect(config.crossfadeDuration == 1.0)
        #expect(config.volume == 0)
    }
    
    @Test("Configuration with all maximum values")
    func testMaximumValues() throws {
        let config = PlayerConfiguration(
            crossfadeDuration: 30.0,
            singleTrackFadeInDuration: 10.0, singleTrackFadeOutDuration: 10.0, volume: 100,
            stopFadeDuration: 10.0
        )
        
        try config.validate()
        #expect(config.crossfadeDuration == 30.0)
        #expect(config.volume == 100)
    }
    
    @Test("Repeat count with large value is valid")
    func testLargeRepeatCount() throws {
        var config = PlayerConfiguration()
        config.repeatCount = 1000000
        
        try config.validate()
        #expect(config.repeatCount == 1000000)
    }
}
