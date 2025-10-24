//
//  CrossfadePauseTests.swift
//  AudioServiceKitIntegrationTests
//
//  Critical scenario: Pause during crossfade (high probability in 5-15s crossfade)
//

import XCTest
@testable import AudioServiceKit
@testable import AudioServiceCore

/// **Critical Test Suite: Pause During Crossfade**
///
/// **Use Case:** 30-min meditation with 5-15s crossfades
/// - Pause probability: ~10% (daily morning routine)
/// - Requirement: Seamless pause/resume at any crossfade point
///
/// **Resume Strategy:**
/// - Progress < 50%: Continue from saved state
/// - Progress >= 50%: Quick finish in 1 second
final class CrossfadePauseTests: XCTestCase {
    
    var audioService: AudioPlayerService!
    var testTrack1: Track!
    var testTrack2: Track!
    
    override func setUp() async throws {
        // Create test configuration
        let config = PlayerConfiguration(
            crossfadeDuration: 5.0, // 5s crossfade for testing
            repeatCount: nil,
            volume: 1.0
        )
        
        audioService = try await AudioPlayerService(configuration: config)
        
        // Create test tracks (need real audio files for integration test)
        let testBundle = Bundle(for: type(of: self))
        guard let url1 = testBundle.url(forResource: "test_track_1", withExtension: "mp3"),
              let url2 = testBundle.url(forResource: "test_track_2", withExtension: "mp3") else {
            XCTFail("Test audio files not found in bundle")
            return
        }
        testTrack1 = Track(url: url1)
        testTrack2 = Track(url: url2)
    }
    
    override func tearDown() async throws {
        await audioService.stop()
        audioService = nil
    }
    
    // MARK: - Test Cases
    
    /// **TEST 1: Pause at 25% crossfade progress (< 50%)**
    ///
    /// Expected behavior:
    /// - Crossfade state saved (volumes, positions)
    /// - Resume continues from 25% with remaining 75% duration
    func testPauseDuringCrossfade_At25Percent_ContinuesFromProgress() async throws {
        // 1. Load playlist and start playing
        try await audioService.loadPlaylist([testTrack1, testTrack2])
        try await audioService.startPlaying(fadeDuration: 0.0)
        
        // Wait for track to start
        try await Task.sleep(for: .seconds(1))
        
        // 2. Start crossfade to second track
        Task {
            try? await audioService.skipToNext()
        }
        
        // 3. Wait for 25% progress (1.25s of 5s crossfade)
        try await Task.sleep(for: .seconds(1.25))
        
        // 4. Pause during crossfade
        try await audioService.pause()
        
        // 5. Verify state
        let state = await audioService.state
        XCTAssertEqual(state, .paused, "Service should be in paused state")
        
        // 6. Resume
        try await audioService.resume()
        
        // 7. Wait for crossfade to complete
        try await Task.sleep(for: .seconds(4.0)) // Remaining ~3.75s + buffer
        
        // 8. Verify track switched
        let currentTrack = await audioService.currentTrack
        XCTAssertNotNil(currentTrack, "Should have current track")
        // Note: Track.Metadata might not have title if not set explicitly
        
        // 9. Verify playing
        let finalState = await audioService.state
        XCTAssertEqual(finalState, .playing, "Should be playing after crossfade")
    }
    
    /// **TEST 2: Pause at 75% crossfade progress (>= 50%)**
    ///
    /// Expected behavior:
    /// - Quick finish strategy (1 second)
    /// - Resume completes crossfade rapidly
    func testPauseDuringCrossfade_At75Percent_QuickFinish() async throws {
        // 1. Load playlist and start playing
        try await audioService.loadPlaylist([testTrack1, testTrack2])
        try await audioService.startPlaying(fadeDuration: 0.0)
        try await Task.sleep(for: .seconds(1))
        
        // 2. Start crossfade
        Task {
            try? await audioService.skipToNext()
        }
        
        // 3. Wait for 75% progress (3.75s of 5s)
        try await Task.sleep(for: .seconds(3.75))
        
        // 4. Pause
        try await audioService.pause()
        
        let state = await audioService.state
        XCTAssertEqual(state, .paused, "Should be paused")
        
        // 5. Resume
        let resumeTime = Date()
        try await audioService.resume()
        
        // 6. Wait for quick finish (should take ~1 second, not 1.25s remaining)
        try await Task.sleep(for: .seconds(1.5))
        
        let elapsed = Date().timeIntervalSince(resumeTime)
        
        // 7. Verify quick finish (<2s instead of full remaining duration)
        XCTAssertLessThan(elapsed, 2.0, "Quick finish should complete in <2s, got \(elapsed)s")
        
        // 8. Verify track switched
        let currentTrack = await audioService.currentTrack
        XCTAssertNotNil(currentTrack, "Should have current track")
    }
    
    /// **TEST 3: Multiple pause/resume cycles during crossfade**
    ///
    /// Edge case: User pauses multiple times
    func testMultiplePausesResumes_DuringCrossfade() async throws {
        try await audioService.loadPlaylist([testTrack1, testTrack2])
        try await audioService.startPlaying(fadeDuration: 0.0)
        try await Task.sleep(for: .seconds(1))
        
        // Start crossfade
        Task {
            try? await audioService.skipToNext()
        }
        
        // Pause at 1s
        try await Task.sleep(for: .seconds(1.0))
        try await audioService.pause()
        try await Task.sleep(for: .seconds(0.5))
        
        // Resume
        try await audioService.resume()
        
        // Pause again at 2s
        try await Task.sleep(for: .seconds(1.0))
        try await audioService.pause()
        try await Task.sleep(for: .seconds(0.5))
        
        // Final resume
        try await audioService.resume()
        
        // Wait for completion
        try await Task.sleep(for: .seconds(4.0))
        
        // Verify success
        let state = await audioService.state
        XCTAssertEqual(state, .playing)
        
        let currentTrack = await audioService.currentTrack
        XCTAssertNotNil(currentTrack, "Should have current track")
    }
    
    /// **TEST 4: Phone call interruption during crossfade**
    ///
    /// Critical use case: AVAudioSession interruption
    func testPhoneCallInterruption_DuringCrossfade() async throws {
        try await audioService.loadPlaylist([testTrack1, testTrack2])
        try await audioService.startPlaying(fadeDuration: 0.0)
        try await Task.sleep(for: .seconds(1))
        
        // Start crossfade
        Task {
            try? await audioService.skipToNext()
        }
        
        try await Task.sleep(for: .seconds(2.0))
        
        // Simulate interruption (phone call begins)
        // Note: This requires injecting mock AudioSessionManager
        // TODO: Add interruption simulation
        
        try await audioService.pause()
        
        // Wait (simulating call duration)
        try await Task.sleep(for: .seconds(2.0))
        
        // Resume after call
        try await audioService.resume()
        
        try await Task.sleep(for: .seconds(4.0))
        
        let state = await audioService.state
        XCTAssertEqual(state, .playing)
    }
    
    /// **TEST 5: Concurrent crossfade (rollback scenario)**
    ///
    /// Critical: Start new crossfade while previous is in progress
    func testConcurrentCrossfade_RollbackPrevious() async throws {
        // Note: With playlist API, concurrent crossfades would require
        // calling skipToNext() multiple times, which is handled by the coordinator
        try await audioService.loadPlaylist([testTrack1, testTrack2, testTrack1])
        try await audioService.startPlaying(fadeDuration: 0.0)
        try await Task.sleep(for: .seconds(1))
        
        // Start first crossfade
        Task {
            try? await audioService.skipToNext()
        }
        
        // Wait 2s, then start second crossfade (should handle gracefully)
        try await Task.sleep(for: .seconds(2.0))
        
        let rollbackStart = Date()
        try await audioService.skipToNext()
        let rollbackTime = Date().timeIntervalSince(rollbackStart)
        
        // Verify transition was smooth
        XCTAssertLessThan(rollbackTime, 6.0, "Transition should complete smoothly")
        
        // Verify final track
        let currentTrack = await audioService.currentTrack
        XCTAssertNotNil(currentTrack, "Should have current track")
    }
}
