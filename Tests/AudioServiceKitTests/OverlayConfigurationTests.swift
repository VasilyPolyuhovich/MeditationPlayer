//
//  OverlayConfigurationTests.swift
//  AudioServiceKitTests
//
//  Created on 2025-10-09.
//  Feature #4: Overlay Player - Unit Tests
//

import XCTest
@testable import AudioServiceCore

final class OverlayConfigurationTests: XCTestCase {
  
  // MARK: - Initialization Tests
  
  func testDefaultInitialization() {
    let config = OverlayConfiguration()
    
    XCTAssertEqual(config.loopMode, .once)
    XCTAssertEqual(config.loopDelay, 0.0)
    XCTAssertEqual(config.volume, 1.0)
    XCTAssertEqual(config.fadeInDuration, 0.0)
    XCTAssertEqual(config.fadeOutDuration, 0.0)
    XCTAssertEqual(config.fadeCurve, .linear)
    XCTAssertTrue(config.applyFadeOnEachLoop)
  }
  
  func testCustomInitialization() {
    let config = OverlayConfiguration(
      loopMode: .count(3),
      loopDelay: 300.0,
      volume: 0.5,
      fadeInDuration: 1.0,
      fadeOutDuration: 2.0,
      fadeCurve: .easeInOut,
      applyFadeOnEachLoop: false
    )
    
    XCTAssertEqual(config.loopMode, .count(3))
    XCTAssertEqual(config.loopDelay, 300.0)
    XCTAssertEqual(config.volume, 0.5)
    XCTAssertEqual(config.fadeInDuration, 1.0)
    XCTAssertEqual(config.fadeOutDuration, 2.0)
    XCTAssertEqual(config.fadeCurve, .easeInOut)
    XCTAssertFalse(config.applyFadeOnEachLoop)
  }
  
  // MARK: - Validation Tests
  
  func testValidConfiguration() {
    var config = OverlayConfiguration()
    XCTAssertTrue(config.isValid, "Default configuration should be valid")
    
    config.volume = 0.0
    XCTAssertTrue(config.isValid, "Zero volume should be valid")
    
    config.volume = 1.0
    XCTAssertTrue(config.isValid, "Full volume should be valid")
    
    config.volume = 0.5
    XCTAssertTrue(config.isValid, "Mid-range volume should be valid")
  }
  
  func testInvalidVolume() {
    var config = OverlayConfiguration()
    
    config.volume = -0.1
    XCTAssertFalse(config.isValid, "Negative volume should be invalid")
    
    config.volume = 1.1
    XCTAssertFalse(config.isValid, "Volume above 1.0 should be invalid")
    
    config.volume = 2.0
    XCTAssertFalse(config.isValid, "Volume of 2.0 should be invalid")
  }
  
  func testInvalidLoopDelay() {
    var config = OverlayConfiguration()
    
    config.loopDelay = -1.0
    XCTAssertFalse(config.isValid, "Negative loop delay should be invalid")
    
    config.loopDelay = -0.1
    XCTAssertFalse(config.isValid, "Negative loop delay should be invalid")
  }
  
  func testInvalidFadeDurations() {
    var config = OverlayConfiguration()
    
    config.fadeInDuration = -1.0
    XCTAssertFalse(config.isValid, "Negative fade-in duration should be invalid")
    
    config.fadeInDuration = 0.0
    config.fadeOutDuration = -1.0
    XCTAssertFalse(config.isValid, "Negative fade-out duration should be invalid")
  }
  
  func testInvalidLoopCount() {
    var config = OverlayConfiguration()
    
    config.loopMode = .count(0)
    XCTAssertFalse(config.isValid, "Loop count of 0 should be invalid")
    
    config.loopMode = .count(-1)
    XCTAssertFalse(config.isValid, "Negative loop count should be invalid")
    
    config.loopMode = .count(1)
    XCTAssertTrue(config.isValid, "Loop count of 1 should be valid")
    
    config.loopMode = .count(100)
    XCTAssertTrue(config.isValid, "Large loop count should be valid")
  }
  
  // MARK: - Loop Mode Tests
  
  func testLoopModeEquality() {
    XCTAssertEqual(OverlayConfiguration.LoopMode.once, .once)
    XCTAssertEqual(OverlayConfiguration.LoopMode.infinite, .infinite)
    XCTAssertEqual(OverlayConfiguration.LoopMode.count(3), .count(3))
    
    XCTAssertNotEqual(OverlayConfiguration.LoopMode.count(3), .count(5))
    XCTAssertNotEqual(OverlayConfiguration.LoopMode.once, .infinite)
    XCTAssertNotEqual(OverlayConfiguration.LoopMode.once, .count(1))
  }
  
  func testLoopModeCases() {
    let once = OverlayConfiguration.LoopMode.once
    let count = OverlayConfiguration.LoopMode.count(5)
    let infinite = OverlayConfiguration.LoopMode.infinite
    
    // Test pattern matching
    switch once {
    case .once: break
    default: XCTFail("Should match .once case")
    }
    
    switch count {
    case .count(let times):
      XCTAssertEqual(times, 5)
    default:
      XCTFail("Should match .count case")
    }
    
    switch infinite {
    case .infinite: break
    default: XCTFail("Should match .infinite case")
    }
  }
  
  // MARK: - Preset Configuration Tests
  
  func testAmbientPreset() {
    let config = OverlayConfiguration.ambient
    
    XCTAssertEqual(config.loopMode, .infinite)
    XCTAssertEqual(config.volume, 0.3)
    XCTAssertEqual(config.fadeInDuration, 2.0)
    XCTAssertEqual(config.fadeOutDuration, 2.0)
    XCTAssertFalse(config.applyFadeOnEachLoop)
    XCTAssertTrue(config.isValid)
  }
  
  func testBellPreset() {
    let config = OverlayConfiguration.bell(times: 3, interval: 300.0)
    
    XCTAssertEqual(config.loopMode, .count(3))
    XCTAssertEqual(config.loopDelay, 300.0)
    XCTAssertEqual(config.volume, 0.5)
    XCTAssertEqual(config.fadeInDuration, 0.5)
    XCTAssertEqual(config.fadeOutDuration, 0.5)
    XCTAssertTrue(config.applyFadeOnEachLoop)
    XCTAssertTrue(config.isValid)
  }
  
  func testBellPresetCustomization() {
    var config = OverlayConfiguration.bell(times: 5, interval: 600.0)
    
    XCTAssertEqual(config.loopMode, .count(5))
    XCTAssertEqual(config.loopDelay, 600.0)
    
    // Modify preset
    config.volume = 0.7
    config.fadeCurve = .easeIn
    
    XCTAssertEqual(config.volume, 0.7)
    XCTAssertEqual(config.fadeCurve, .easeIn)
    XCTAssertTrue(config.isValid)
  }
  
  // MARK: - Sendable & Equatable Tests
  
  func testSendableCompliance() {
    // Test that OverlayConfiguration can be passed across isolation boundaries
    let config = OverlayConfiguration()
    
    Task {
      let _ = config  // Should compile without warnings
    }
  }
  
  func testEquality() {
    let config1 = OverlayConfiguration(
      loopMode: .count(3),
      loopDelay: 300.0,
      volume: 0.5
    )
    
    let config2 = OverlayConfiguration(
      loopMode: .count(3),
      loopDelay: 300.0,
      volume: 0.5
    )
    
    let config3 = OverlayConfiguration(
      loopMode: .count(3),
      loopDelay: 300.0,
      volume: 0.6  // Different volume
    )
    
    XCTAssertEqual(config1, config2)
    XCTAssertNotEqual(config1, config3)
  }
  
  // MARK: - Edge Cases
  
  func testZeroValues() {
    let config = OverlayConfiguration(
      loopMode: .once,
      loopDelay: 0.0,
      volume: 0.0,  // Silent
      fadeInDuration: 0.0,
      fadeOutDuration: 0.0
    )
    
    XCTAssertTrue(config.isValid, "Zero values should be valid")
  }
  
  func testMaximumValues() {
    let config = OverlayConfiguration(
      loopMode: .count(Int.max),
      loopDelay: TimeInterval.greatestFiniteMagnitude,
      volume: 1.0,
      fadeInDuration: TimeInterval.greatestFiniteMagnitude,
      fadeOutDuration: TimeInterval.greatestFiniteMagnitude
    )
    
    XCTAssertTrue(config.isValid, "Maximum values should be valid")
  }
  
  func testApplyFadeOnEachLoopBehavior() {
    var config = OverlayConfiguration()
    
    // Default: true
    XCTAssertTrue(config.applyFadeOnEachLoop)
    
    // For continuous sounds (rain)
    config.applyFadeOnEachLoop = false
    XCTAssertFalse(config.applyFadeOnEachLoop)
    
    // For distinct sounds (bell)
    config.applyFadeOnEachLoop = true
    XCTAssertTrue(config.applyFadeOnEachLoop)
  }
}

// MARK: - Overlay State Tests

final class OverlayStateTests: XCTestCase {
  
  func testStateEquality() {
    XCTAssertEqual(OverlayState.idle, .idle)
    XCTAssertEqual(OverlayState.preparing, .preparing)
    XCTAssertEqual(OverlayState.playing, .playing)
    XCTAssertEqual(OverlayState.paused, .paused)
    XCTAssertEqual(OverlayState.stopping, .stopping)
    
    XCTAssertNotEqual(OverlayState.idle, .playing)
    XCTAssertNotEqual(OverlayState.playing, .paused)
  }
  
  func testIsPlayingProperty() {
    XCTAssertTrue(OverlayState.playing.isPlaying)
    
    XCTAssertFalse(OverlayState.idle.isPlaying)
    XCTAssertFalse(OverlayState.preparing.isPlaying)
    XCTAssertFalse(OverlayState.paused.isPlaying)
    XCTAssertFalse(OverlayState.stopping.isPlaying)
  }
  
  func testIsPausedProperty() {
    XCTAssertTrue(OverlayState.paused.isPaused)
    
    XCTAssertFalse(OverlayState.idle.isPaused)
    XCTAssertFalse(OverlayState.preparing.isPaused)
    XCTAssertFalse(OverlayState.playing.isPaused)
    XCTAssertFalse(OverlayState.stopping.isPaused)
  }
  
  func testIsTransitioningProperty() {
    XCTAssertTrue(OverlayState.preparing.isTransitioning)
    XCTAssertTrue(OverlayState.stopping.isTransitioning)
    
    XCTAssertFalse(OverlayState.idle.isTransitioning)
    XCTAssertFalse(OverlayState.playing.isTransitioning)
    XCTAssertFalse(OverlayState.paused.isTransitioning)
  }
  
  func testIsIdleProperty() {
    XCTAssertTrue(OverlayState.idle.isIdle)
    
    XCTAssertFalse(OverlayState.preparing.isIdle)
    XCTAssertFalse(OverlayState.playing.isIdle)
    XCTAssertFalse(OverlayState.paused.isIdle)
    XCTAssertFalse(OverlayState.stopping.isIdle)
  }
  
  func testDescription() {
    XCTAssertEqual(OverlayState.idle.description, "Idle")
    XCTAssertEqual(OverlayState.preparing.description, "Preparing")
    XCTAssertEqual(OverlayState.playing.description, "Playing")
    XCTAssertEqual(OverlayState.paused.description, "Paused")
    XCTAssertEqual(OverlayState.stopping.description, "Stopping")
  }
  
  func testSendableCompliance() {
    // Test that OverlayState can be passed across isolation boundaries
    let state = OverlayState.playing
    
    Task {
      let _ = state  // Should compile without warnings
    }
  }
  
  func testStateTransitionLogic() {
    // Typical state transitions
    var state = OverlayState.idle
    XCTAssertTrue(state.isIdle)
    
    state = .preparing
    XCTAssertTrue(state.isTransitioning)
    
    state = .playing
    XCTAssertTrue(state.isPlaying)
    
    state = .paused
    XCTAssertTrue(state.isPaused)
    
    state = .playing
    XCTAssertTrue(state.isPlaying)
    
    state = .stopping
    XCTAssertTrue(state.isTransitioning)
    
    state = .idle
    XCTAssertTrue(state.isIdle)
  }
}
