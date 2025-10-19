//
//  OverlayIntegrationTests.swift
//  AudioServiceKitTests
//
//  Created on 2025-10-09.
//  Feature #4: Overlay Player - Phase 4 Integration Tests
//

import XCTest
import AVFoundation
@testable import AudioServiceKit
@testable import AudioServiceCore

/// Integration tests for overlay player functionality through AudioPlayerService public API.
///
/// ## Test Categories:
/// 1. Basic Overlay Control - Start, stop, pause, resume, replace, volume
/// 2. Simultaneous Playback - Main + overlay playing together
/// 3. Main Crossfade - Verify overlay unaffected by main player crossfades
/// 4. Playlist Swap - Verify overlay unaffected by playlist changes
/// 5. Global Control - pauseAll, resumeAll, stopAll
/// 6. Error Handling - Invalid operations, file errors
/// 7. Memory Management - Leak detection on repeated start/stop
final class OverlayIntegrationTests: XCTestCase {
    
    // MARK: - Test Properties
    
    var service: AudioPlayerService!
    var testAudioURL: URL!
    var overlayAudioURL: URL!
    
    // MARK: - Setup & Teardown
    
    override func setUp() async throws {
        try await super.setUp()
        
        // Create audio player service
        service = AudioPlayerService()
        await service.setup()
        
        // Create test audio files
        testAudioURL = createTestAudioFile(name: "test_main", duration: 2.0)
        overlayAudioURL = createTestAudioFile(name: "test_overlay", duration: 2.0)
    }
    
    override func tearDown() async throws {
        await service?.cleanup()
        service = nil
        
        // Cleanup test files
        try? FileManager.default.removeItem(at: testAudioURL)
        try? FileManager.default.removeItem(at: overlayAudioURL)
        
        try await super.tearDown()
    }
    
    // MARK: - Basic Overlay Control Tests
    
    func testStartOverlay() async throws {
        // Given
        let config = OverlayConfiguration(
            volume: 0.5,
            loopMode: .infinite,
            fadeInDuration: 0.1,
            fadeOutDuration: 0.1
        )
        
        // When
        try await service.startOverlay(url: overlayAudioURL, configuration: config)
        
        // Wait for fade in
        try await Task.sleep(nanoseconds: 150_000_000) // 150ms
        
        // Then
        let state = await service.getOverlayState()
        XCTAssertTrue(state.isPlaying, "Overlay should be playing after start")
    }
    
    func testStopOverlay() async throws {
        // Given - overlay playing
        let config = OverlayConfiguration.preset(.ambient)
        try await service.startOverlay(url: overlayAudioURL, configuration: config)
        
        // Wait for start
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        
        // When
        await service.stopOverlay()
        
        // Wait for fade-out (ambient preset has 2s fade-out)
        try await Task.sleep(nanoseconds: 2_100_000_000) // 2.1s
        
        // Then
        let state = await service.getOverlayState()
        XCTAssertTrue(state.isIdle, "Overlay should be idle after stop")
    }
    
    func testPauseResumeOverlay() async throws {
        // Given - overlay playing
        let config = OverlayConfiguration.preset(.ambient)
        try await service.startOverlay(url: overlayAudioURL, configuration: config)
        
        // Wait for fade in
        try await Task.sleep(nanoseconds: 2_100_000_000) // 2.1s
        
        // When - pause
        await service.pauseOverlay()
        
        // Then - paused
        let pausedState = await service.getOverlayState()
        XCTAssertTrue(pausedState.isPaused, "Overlay should be paused")
        
        // When - resume
        await service.resumeOverlay()
        
        // Then - playing
        let playingState = await service.getOverlayState()
        XCTAssertTrue(playingState.isPlaying, "Overlay should be playing after resume")
        
        // Cleanup
        await service.stopOverlay()
    }
    
    func testReplaceOverlay() async throws {
        // Given - overlay playing
        let config = OverlayConfiguration.preset(.ambient)
        try await service.startOverlay(url: overlayAudioURL, configuration: config)
        
        // Wait for start
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        
        let newOverlayURL = createTestAudioFile(name: "test_overlay_2", duration: 2.0)
        
        // When
        try await service.replaceOverlay(url: newOverlayURL)
        
        // Wait for crossfade
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        
        // Then
        let state = await service.getOverlayState()
        XCTAssertTrue(state.isPlaying, "Overlay should still be playing after replace")
        
        // Cleanup
        await service.stopOverlay()
        try? FileManager.default.removeItem(at: newOverlayURL)
    }
    
    func testSetOverlayVolume() async throws {
        // Given - overlay playing
        let config = OverlayConfiguration(volume: 1.0, loopMode: .infinite)
        try await service.startOverlay(url: overlayAudioURL, configuration: config)
        
        // Wait for start
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        
        // When
        await service.setOverlayVolume(0.3)
        
        // Wait for volume change
        try await Task.sleep(nanoseconds: 50_000_000) // 50ms
        
        // Then - volume changed (can't verify directly, but no crash)
        let state = await service.getOverlayState()
        XCTAssertTrue(state.isPlaying, "Overlay should still be playing after volume change")
        
        // Cleanup
        await service.stopOverlay()
    }
    
    func testGetOverlayState_NoOverlayLoaded() async throws {
        // Given - no overlay
        
        // When
        let state = await service.getOverlayState()
        
        // Then
        XCTAssertTrue(state.isIdle, "State should be idle when no overlay loaded")
    }
    
    // MARK: - Simultaneous Playback Tests
    
    func testMainAndOverlaySimultaneous() async throws {
        // Given - main track loaded
        let config = AudioConfiguration()
        try await service.startPlaying(url: testAudioURL, configuration: config)
        
        // Wait for main to start
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        
        // When - start overlay
        try await service.startOverlay(
            url: overlayAudioURL,
            configuration: .preset(.ambient)
        )
        
        // Wait for overlay to start
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        
        // Then - both playing
        let mainState = await service.state
        let overlayState = await service.getOverlayState()
        
        XCTAssertEqual(mainState, .playing, "Main player should be playing")
        XCTAssertTrue(overlayState.isPlaying, "Overlay player should be playing")
        
        // Cleanup
        await service.stop()
        await service.stopOverlay()
    }
    
    func testMainCrossfadeWithOverlay() async throws {
        // Given - main + overlay playing
        let config = AudioConfiguration()
        try await service.startPlaying(url: testAudioURL, configuration: config)
        
        try await service.startOverlay(
            url: overlayAudioURL,
            configuration: .preset(.ambient)
        )
        
        // Wait for both to start
        try await Task.sleep(nanoseconds: 200_000_000) // 200ms
        
        let secondTrackURL = createTestAudioFile(name: "test_track_2", duration: 2.0)
        
        // When - crossfade main track
        try await service.replaceTrack(url: secondTrackURL, crossfadeDuration: 0.5)
        
        // Wait for crossfade to complete
        try await Task.sleep(nanoseconds: 600_000_000) // 600ms
        
        // Then - overlay unaffected
        let overlayState = await service.getOverlayState()
        XCTAssertTrue(overlayState.isPlaying, "Overlay should remain playing during main crossfade")
        
        // Cleanup
        await service.stop()
        await service.stopOverlay()
        try? FileManager.default.removeItem(at: secondTrackURL)
    }
    
    func testPlaylistSwapWithOverlay() async throws {
        // Given - playlist + overlay playing
        let track2URL = createTestAudioFile(name: "track2", duration: 2.0)
        let tracks = [testAudioURL!, track2URL]
        
        let config = AudioConfiguration()
        try await service.startPlaying(url: testAudioURL, configuration: config)
        
        try await service.startOverlay(
            url: overlayAudioURL,
            configuration: .preset(.ambient)
        )
        
        // Wait for both to start
        try await Task.sleep(nanoseconds: 200_000_000) // 200ms
        
        let track3URL = createTestAudioFile(name: "track3", duration: 2.0)
        let newPlaylist = [track3URL]
        
        // When - swap playlist
        try await service.swapPlaylist(tracks: newPlaylist, crossfadeDuration: 0.5)
        
        // Wait for swap to complete
        try await Task.sleep(nanoseconds: 600_000_000) // 600ms
        
        // Then - overlay unaffected
        let overlayState = await service.getOverlayState()
        XCTAssertTrue(overlayState.isPlaying, "Overlay should remain playing during playlist swap")
        
        // Cleanup
        await service.stop()
        await service.stopOverlay()
        try? FileManager.default.removeItem(at: track2URL)
        try? FileManager.default.removeItem(at: track3URL)
    }
    
    // MARK: - Global Control Tests
    
    func testPauseAll() async throws {
        // Given - both playing
        let config = AudioConfiguration()
        try await service.startPlaying(url: testAudioURL, configuration: config)
        
        try await service.startOverlay(
            url: overlayAudioURL,
            configuration: .preset(.ambient)
        )
        
        // Wait for both to start
        try await Task.sleep(nanoseconds: 200_000_000) // 200ms
        
        // When
        await service.pauseAll()
        
        // Wait for pause to complete
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        
        // Then - both paused
        let mainState = await service.state
        let overlayState = await service.getOverlayState()
        
        XCTAssertEqual(mainState, .paused, "Main player should be paused")
        XCTAssertTrue(overlayState.isPaused, "Overlay player should be paused")
        
        // Cleanup
        await service.stop()
        await service.stopOverlay()
    }
    
    func testResumeAll() async throws {
        // Given - both paused
        let config = AudioConfiguration()
        try await service.startPlaying(url: testAudioURL, configuration: config)
        
        try await service.startOverlay(
            url: overlayAudioURL,
            configuration: .preset(.ambient)
        )
        
        // Wait for both to start
        try await Task.sleep(nanoseconds: 200_000_000) // 200ms
        
        await service.pauseAll()
        
        // Wait for pause
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        
        // When
        await service.resumeAll()
        
        // Wait for resume
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        
        // Then - both playing
        let mainState = await service.state
        let overlayState = await service.getOverlayState()
        
        XCTAssertEqual(mainState, .playing, "Main player should be playing after resumeAll")
        XCTAssertTrue(overlayState.isPlaying, "Overlay player should be playing after resumeAll")
        
        // Cleanup
        await service.stop()
        await service.stopOverlay()
    }
    
    func testStopAll() async throws {
        // Given - both playing
        let config = AudioConfiguration()
        try await service.startPlaying(url: testAudioURL, configuration: config)
        
        try await service.startOverlay(
            url: overlayAudioURL,
            configuration: .preset(.ambient)
        )
        
        // Wait for both to start
        try await Task.sleep(nanoseconds: 200_000_000) // 200ms
        
        // When
        await service.stopAll()
        
        // Wait for stop to complete
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        
        // Then - both stopped
        let mainState = await service.state
        let overlayState = await service.getOverlayState()
        
        XCTAssertEqual(mainState, .finished, "Main player should be stopped")
        XCTAssertTrue(overlayState.isIdle, "Overlay player should be idle")
    }
    
    // MARK: - Error Handling Tests
    
    func testReplaceOverlayWithoutStart() async throws {
        // Given - no overlay playing
        
        // When/Then - should throw
        do {
            try await service.replaceOverlay(url: overlayAudioURL)
            XCTFail("Should throw invalidState error")
        } catch let error as AudioPlayerError {
            if case .invalidState = error {
                // Expected
            } else {
                XCTFail("Wrong error type: \(error)")
            }
        }
    }
    
    func testStartOverlayWithInvalidFile() async throws {
        // Given
        let invalidURL = URL(fileURLWithPath: "/nonexistent/file.mp3")
        let config = OverlayConfiguration.preset(.ambient)
        
        // When/Then - should throw
        do {
            try await service.startOverlay(url: invalidURL, configuration: config)
            XCTFail("Should throw error for invalid file")
        } catch {
            // Expected - file error
            XCTAssertTrue(error is AudioPlayerError, "Should throw AudioPlayerError")
        }
    }
    
    func testPauseOverlay_WhenNotPlaying_NoEffect() async throws {
        // Given - no overlay
        
        // When
        await service.pauseOverlay()
        
        // Then - no crash, state remains idle
        let state = await service.getOverlayState()
        XCTAssertTrue(state.isIdle, "State should remain idle")
    }
    
    func testResumeOverlay_WhenNotPaused_NoEffect() async throws {
        // Given - no overlay
        
        // When
        await service.resumeOverlay()
        
        // Then - no crash, state remains idle
        let state = await service.getOverlayState()
        XCTAssertTrue(state.isIdle, "State should remain idle")
    }
    
    func testStopOverlay_WhenNotPlaying_NoEffect() async throws {
        // Given - no overlay
        
        // When
        await service.stopOverlay()
        
        // Then - no crash, state remains idle
        let state = await service.getOverlayState()
        XCTAssertTrue(state.isIdle, "State should remain idle")
    }
    
    // MARK: - Memory Leak Tests
    
    func testMemoryLeakOnMultipleStartStop() async throws {
        // Test that starting/stopping overlay 100 times doesn't leak memory
        let config = OverlayConfiguration(
            volume: 0.5,
            loopMode: .once,
            fadeInDuration: 0.01,
            fadeOutDuration: 0.01
        )
        
        for i in 0..<100 {
            try await service.startOverlay(url: overlayAudioURL, configuration: config)
            
            // Short delay
            try await Task.sleep(nanoseconds: 20_000_000) // 20ms
            
            await service.stopOverlay()
            
            // Short delay
            try await Task.sleep(nanoseconds: 20_000_000) // 20ms
            
            // Progress indicator every 25 iterations
            if (i + 1) % 25 == 0 {
                print("Memory leak test progress: \(i + 1)/100")
            }
        }
        
        // If we get here without crash, no obvious leaks
        let state = await service.getOverlayState()
        XCTAssertTrue(state.isIdle, "State should be idle after 100 start/stop cycles")
    }
    
    // MARK: - Helper Methods
    
    /// Creates a test audio file with specified duration
    /// - Parameters:
    ///   - name: File name (without extension)
    ///   - duration: Duration in seconds
    /// - Returns: URL of created test file
    private func createTestAudioFile(name: String, duration: TimeInterval = 2.0) -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("\(name)_\(UUID().uuidString).caf")
        
        // Create audio format (44.1kHz, stereo)
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
            
            // Create silence of specified duration
            let frameCount = AVAudioFrameCount(44100 * duration)
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
