//
//  OverlayPlayerActorTests.swift
//  AudioServiceKitTests
//
//  Created on 2025-10-09.
//  Feature #4: Overlay Player - Phase 2 Tests
//

import XCTest
import AVFoundation
@testable import AudioServiceKit
@testable import AudioServiceCore

/// Tests for OverlayPlayerActor - independent overlay audio player with looping support.
///
/// ## Test Categories:
/// 1. Initialization - Actor creation and configuration validation
/// 2. State Management - State transitions and validation
/// 3. Loop Logic - Loop modes (once, count, infinite)
/// 4. Loop Delay - Delay timing and cancellation
/// 5. Fades - Volume fade algorithms and timing
/// 6. File Operations - Loading and replacement
/// 7. Volume Control - Independent volume management
/// 8. Playback Control - Play, pause, resume, stop
/// 9. Edge Cases - Error handling and cancellation
final class OverlayPlayerActorTests: XCTestCase {
  
  // MARK: - Test Properties
  
  var engine: AVAudioEngine!
  var player: AVAudioPlayerNode!
  var mixer: AVAudioMixerNode!
  
  // MARK: - Setup & Teardown
  
  override func setUp() async throws {
    try await super.setUp()
    
    // Create real audio nodes for testing
    engine = AVAudioEngine()
    player = AVAudioPlayerNode()
    mixer = AVAudioMixerNode()
    
    // Attach nodes to engine
    engine.attach(player)
    engine.attach(mixer)
    
    // Connect nodes
    let format = engine.outputNode.outputFormat(forBus: 0)
    engine.connect(player, to: mixer, format: format)
    engine.connect(mixer, to: engine.mainMixerNode, format: format)
    
    // Prepare engine
    engine.prepare()
  }
  
  override func tearDown() async throws {
    engine.stop()
    engine = nil
    player = nil
    mixer = nil
    
    try await super.tearDown()
  }
  
  // MARK: - Initialization Tests
  
  func testInitialization_WithDefaultConfiguration() async throws {
    // Given
    let config = OverlayConfiguration()
    
    // When
    let overlay = OverlayPlayerActor(
      player: player,
      mixer: mixer,
      configuration: config
    )
    
    // Then
    let state = await overlay.getState()
    XCTAssertEqual(state, .idle)
  }
  
  func testInitialization_WithCustomConfiguration() async throws {
    // Given
    var config = OverlayConfiguration()
    config.loopMode = .count(3)
    config.volume = 0.5
    config.fadeInDuration = 1.0
    config.fadeOutDuration = 1.0
    
    // When
    let overlay = OverlayPlayerActor(
      player: player,
      mixer: mixer,
      configuration: config
    )
    
    // Then
    let state = await overlay.getState()
    XCTAssertEqual(state, .idle)
  }
  
  func testInitialization_WithAmbientPreset() async throws {
    // Given
    let config = OverlayConfiguration.ambient
    
    // When
    let overlay = OverlayPlayerActor(
      player: player,
      mixer: mixer,
      configuration: config
    )
    
    // Then
    let state = await overlay.getState()
    XCTAssertEqual(state, .idle)
  }
  
  // MARK: - State Management Tests
  
  func testState_InitiallyIdle() async throws {
    // Given
    let config = OverlayConfiguration()
    let overlay = OverlayPlayerActor(
      player: player,
      mixer: mixer,
      configuration: config
    )
    
    // When
    let state = await overlay.getState()
    
    // Then
    XCTAssertEqual(state, .idle)
  }
  
  func testState_PauseWhenNotPlaying_NoEffect() async throws {
    // Given
    let config = OverlayConfiguration()
    let overlay = OverlayPlayerActor(
      player: player,
      mixer: mixer,
      configuration: config
    )
    
    // When
    await overlay.pause()
    
    // Then
    let state = await overlay.getState()
    XCTAssertEqual(state, .idle)
  }
  
  func testState_ResumeWhenNotPaused_NoEffect() async throws {
    // Given
    let config = OverlayConfiguration()
    let overlay = OverlayPlayerActor(
      player: player,
      mixer: mixer,
      configuration: config
    )
    
    // When
    await overlay.resume()
    
    // Then
    let state = await overlay.getState()
    XCTAssertEqual(state, .idle)
  }
  
  // MARK: - File Loading Tests
  
  func testLoad_InvalidFile_ThrowsError() async throws {
    // Given
    let config = OverlayConfiguration()
    let overlay = OverlayPlayerActor(
      player: player,
      mixer: mixer,
      configuration: config
    )
    
    let invalidURL = URL(fileURLWithPath: "/invalid/path/test.mp3")
    
    // When/Then
    do {
      try await overlay.load(url: invalidURL)
      XCTFail("Expected error to be thrown")
    } catch {
      // Expected error
      XCTAssertTrue(error is AudioPlayerError)
    }
  }
  
  func testLoad_WhenNotIdle_ThrowsError() async throws {
    // Given
    let config = OverlayConfiguration()
    let overlay = OverlayPlayerActor(
      player: player,
      mixer: mixer,
      configuration: config
    )
    
    // Create test audio file
    let testURL = createTestAudioFile()
    try await overlay.load(url: testURL)
    try await overlay.play()
    
    // When/Then
    do {
      try await overlay.load(url: testURL)
      XCTFail("Expected error to be thrown")
    } catch let error as AudioPlayerError {
      // Expected error
      if case .invalidState = error {
        // Success
      } else {
        XCTFail("Wrong error type: \(error)")
      }
    }
    
    // Cleanup
    await overlay.stop()
  }
  
  // MARK: - Playback Control Tests
  
  func testPlay_WithoutLoad_ThrowsError() async throws {
    // Given
    let config = OverlayConfiguration()
    let overlay = OverlayPlayerActor(
      player: player,
      mixer: mixer,
      configuration: config
    )
    
    // When/Then
    do {
      try await overlay.play()
      XCTFail("Expected error to be thrown")
    } catch let error as AudioPlayerError {
      // Expected error
      if case .invalidState = error {
        // Success
      } else {
        XCTFail("Wrong error type: \(error)")
      }
    }
  }
  
  func testPlay_WhenAlreadyPlaying_ThrowsError() async throws {
    // Given
    let config = OverlayConfiguration()
    let overlay = OverlayPlayerActor(
      player: player,
      mixer: mixer,
      configuration: config
    )
    
    let testURL = createTestAudioFile()
    try await overlay.load(url: testURL)
    try await overlay.play()
    
    // When/Then
    do {
      try await overlay.play()
      XCTFail("Expected error to be thrown")
    } catch let error as AudioPlayerError {
      // Expected error
      if case .invalidState = error {
        // Success
      } else {
        XCTFail("Wrong error type: \(error)")
      }
    }
    
    // Cleanup
    await overlay.stop()
  }
  
  func testStop_TransitionsToIdle() async throws {
    // Given
    let config = OverlayConfiguration()
    let overlay = OverlayPlayerActor(
      player: player,
      mixer: mixer,
      configuration: config
    )
    
    let testURL = createTestAudioFile()
    try await overlay.load(url: testURL)
    try await overlay.play()
    
    // When
    await overlay.stop()
    
    // Then
    let state = await overlay.getState()
    XCTAssertEqual(state, .idle)
  }
  
  // MARK: - Volume Control Tests
  
  func testSetVolume_ClampedToValidRange() async throws {
    // Given
    let config = OverlayConfiguration()
    let overlay = OverlayPlayerActor(
      player: player,
      mixer: mixer,
      configuration: config
    )
    
    // When - Set too high
    await overlay.setVolume(1.5)
    
    // Then - Should be clamped to 1.0
    XCTAssertEqual(mixer.volume, 1.0, accuracy: 0.01)
    
    // When - Set too low
    await overlay.setVolume(-0.5)
    
    // Then - Should be clamped to 0.0
    XCTAssertEqual(mixer.volume, 0.0, accuracy: 0.01)
  }
  
  func testSetVolume_ValidRange() async throws {
    // Given
    let config = OverlayConfiguration()
    let overlay = OverlayPlayerActor(
      player: player,
      mixer: mixer,
      configuration: config
    )
    
    // When
    await overlay.setVolume(0.7)
    
    // Then
    XCTAssertEqual(mixer.volume, 0.7, accuracy: 0.01)
  }
  
  func testSetVolume_ZeroVolume() async throws {
    // Given
    let config = OverlayConfiguration()
    let overlay = OverlayPlayerActor(
      player: player,
      mixer: mixer,
      configuration: config
    )
    
    // When
    await overlay.setVolume(0.0)
    
    // Then
    XCTAssertEqual(mixer.volume, 0.0, accuracy: 0.01)
  }
  
  // MARK: - Configuration Tests
  
  func testConfiguration_AmbientPreset() async throws {
    // Given
    let config = OverlayConfiguration.ambient
    
    // Then
    XCTAssertEqual(config.loopMode, .infinite)
    XCTAssertEqual(config.volume, 0.3, accuracy: 0.01)
    XCTAssertEqual(config.fadeInDuration, 2.0, accuracy: 0.01)
    XCTAssertEqual(config.fadeOutDuration, 2.0, accuracy: 0.01)
    XCTAssertEqual(config.applyFadeOnEachLoop, false)
  }
  
  func testConfiguration_BellPreset() async throws {
    // Given
    let config = OverlayConfiguration.bell(times: 3, interval: 300)
    
    // Then
    XCTAssertEqual(config.loopMode, .count(3))
    XCTAssertEqual(config.loopDelay, 300.0, accuracy: 0.01)
    XCTAssertEqual(config.volume, 0.5, accuracy: 0.01)
    XCTAssertEqual(config.fadeInDuration, 0.5, accuracy: 0.01)
    XCTAssertEqual(config.fadeOutDuration, 0.5, accuracy: 0.01)
    XCTAssertEqual(config.applyFadeOnEachLoop, true)
  }
  
  // MARK: - Integration Tests
  
  func testIntegration_LoadAndPlay() async throws {
    // Given
    let config = OverlayConfiguration()
    let overlay = OverlayPlayerActor(
      player: player,
      mixer: mixer,
      configuration: config
    )
    
    // Start engine
    try engine.start()
    
    // When
    let testURL = createTestAudioFile()
    try await overlay.load(url: testURL)
    
    let stateAfterLoad = await overlay.getState()
    XCTAssertEqual(stateAfterLoad, .idle)
    
    try await overlay.play()
    
    let stateAfterPlay = await overlay.getState()
    XCTAssertEqual(stateAfterPlay, .playing)
    
    // Cleanup
    await overlay.stop()
  }
  
  func testIntegration_PauseAndResume() async throws {
    // Given
    let config = OverlayConfiguration()
    let overlay = OverlayPlayerActor(
      player: player,
      mixer: mixer,
      configuration: config
    )
    
    try engine.start()
    
    let testURL = createTestAudioFile()
    try await overlay.load(url: testURL)
    try await overlay.play()
    
    // When - Pause
    await overlay.pause()
    
    // Then
    let stateAfterPause = await overlay.getState()
    XCTAssertEqual(stateAfterPause, .paused)
    
    // When - Resume
    await overlay.resume()
    
    // Then
    let stateAfterResume = await overlay.getState()
    XCTAssertEqual(stateAfterResume, .playing)
    
    // Cleanup
    await overlay.stop()
  }
  
  // MARK: - Helper Methods
  
  /// Creates a test audio file (1 second of silence at 44.1kHz, stereo)
  private func createTestAudioFile() -> URL {
    let tempDir = FileManager.default.temporaryDirectory
    let fileURL = tempDir.appendingPathComponent("test_audio_\(UUID().uuidString).caf")
    
    // Create audio format
    let format = AVAudioFormat(
      standardFormatWithSampleRate: 44100,
      channels: 2
    )!
    
    // Create audio file
    do {
      let audioFile = try AVAudioFile(
        forWriting: fileURL,
        settings: format.settings
      )
      
      // Create 1 second of silence
      let frameCount = AVAudioFrameCount(44100)
      let buffer = AVAudioPCMBuffer(
        pcmFormat: format,
        frameCapacity: frameCount
      )!
      buffer.frameLength = frameCount
      
      // Write silence
      try audioFile.write(from: buffer)
      
      return fileURL
    } catch {
      fatalError("Failed to create test audio file: \(error)")
    }
  }
}
