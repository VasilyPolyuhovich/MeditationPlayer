//
//  RegressionTests.swift
//  AudioServiceKitIntegrationTests
//
//  Comprehensive regression test suite for AudioServiceKit
//  Ensures no breaking changes after refactoring
//

import Testing
import Foundation
import AVFoundation
@testable import AudioServiceKit
@testable import AudioServiceCore

/// Comprehensive regression tests covering all critical functionality
@Suite("Regression Tests - Critical Paths")
struct RegressionTests {
    
    // MARK: - Test Resources
    
    /// Load test audio files from bundle
    private func loadTestTracks() -> [Track] {
        let bundle = Bundle.module
        let fileNames = ["stage1_intro_music", "stage2_practice_music", "stage3_closing_music"]
        
        return fileNames.compactMap { fileName in
            guard let url = bundle.url(forResource: fileName, withExtension: "mp3") else {
                return nil
            }
            return Track(url: url)
        }
    }
    
    /// Load short test track (for quick tests)
    private func loadShortTrack() -> Track? {
        let bundle = Bundle.module
        guard let url = bundle.url(forResource: "gong_short", withExtension: "mp3") else {
            return nil
        }
        return Track(url: url)
    }
    
    // MARK: - Test 1: Basic Playback Flow
    
    @Test("Basic playback flow - load, play, stop")
    func testBasicPlaybackFlow() async throws {
        // Arrange
        let service = try await AudioPlayerService()
        let tracks = loadTestTracks()
        #require(tracks.count >= 2, "Need at least 2 test tracks")
        
        // Act: Load playlist
        try await service.loadPlaylist(tracks)
        
        // Assert: Playlist loaded
        #expect(await service.isPlaylistEmpty() == false)
        
        // Act: Start playing
        try await service.startPlaying(fadeDuration: 0.5)
        
        // Give it time to start
        try await Task.sleep(for: .seconds(0.5))
        
        // Assert: Playing
        let state = await service.state
        #expect(state == .playing)
        
        // Assert: Current track set
        let currentTrack = await service.currentTrack
        #expect(currentTrack != nil)
        
        // Act: Stop
        await service.stop()
        
        // Assert: Finished
        let finalState = await service.state
        #expect(finalState == .finished)
    }
    
    // MARK: - Test 2: Pause During Crossfade (CRITICAL!)
    
    @Test("Pause during crossfade - critical edge case")
    func testPauseDuringCrossfade() async throws {
        // Arrange
        let config = PlayerConfiguration(
            crossfadeDuration: 5.0,  // Long crossfade to have time to pause
            repeatCount: nil,
            volume: 0.8
        )
        let service = try await AudioPlayerService(configuration: config)
        let tracks = loadTestTracks()
        #require(tracks.count >= 2, "Need at least 2 tracks for crossfade")
        
        // Act: Load and play
        try await service.loadPlaylist(tracks)
        try await service.startPlaying()
        
        try await Task.sleep(for: .seconds(0.5))
        #expect(await service.state == .playing)
        
        // Wait for first track to near end (trigger crossfade)
        // Assuming tracks are ~10 seconds, crossfade starts at 5 seconds before end
        try await Task.sleep(for: .seconds(4.0))
        
        // Act: Pause during crossfade
        try await service.pause()
        
        // Assert: Paused
        let pausedState = await service.state
        #expect(pausedState == .paused, "Should be paused during crossfade")
        
        // Act: Resume
        try await service.resume()
        
        // Assert: Resumed playing
        try await Task.sleep(for: .seconds(0.5))
        let resumedState = await service.state
        #expect(resumedState == .playing, "Should resume playing after pause")
    }
    
    // MARK: - Test 3: Overlay Over Background Music
    
    @Test("Overlay playback over background music")
    func testOverlayPlayback() async throws {
        // Arrange
        let service = try await AudioPlayerService()
        let tracks = loadTestTracks()
        #require(tracks.count >= 1, "Need at least 1 background track")
        
        let bundle = Bundle.module
        guard let overlayURL = bundle.url(forResource: "stage1_begin_voice", withExtension: "mp3") else {
            throw TestError.resourceNotFound
        }
        
        // Act: Start background music
        try await service.loadPlaylist([tracks[0]])
        try await service.startPlaying()
        
        try await Task.sleep(for: .seconds(0.5))
        #expect(await service.state == .playing)
        
        // Act: Play overlay
        try await service.playOverlay(overlayURL)
        
        // Give overlay time to start
        try await Task.sleep(for: .seconds(0.5))
        
        // Assert: Background still playing
        let stateAfterOverlay = await service.state
        #expect(stateAfterOverlay == .playing, "Background should continue playing")
        
        // Cleanup
        await service.stopOverlay()
        await service.stop()
    }
    
    // MARK: - Test 4: RepeatCount Loop
    
    @Test("RepeatCount loops playlist correctly")
    func testRepeatCount() async throws {
        // Arrange
        let config = PlayerConfiguration(
            crossfadeDuration: 1.0,  // Short crossfade for fast test
            repeatCount: 2,          // Loop 2 times
            volume: 0.8
        )
        let service = try await AudioPlayerService(configuration: config)
        
        guard let shortTrack = loadShortTrack() else {
            throw TestError.resourceNotFound
        }
        
        // Act: Load and play
        try await service.loadPlaylist([shortTrack])
        try await service.startPlaying()
        
        try await Task.sleep(for: .seconds(0.5))
        #expect(await service.state == .playing)
        
        // Wait for loops to complete
        // Short track is ~2 seconds, 2 loops = 4 seconds + crossfades
        try await Task.sleep(for: .seconds(10))
        
        // Assert: Finished after loops
        let finalState = await service.state
        #expect(finalState == .finished, "Should finish after repeat count")
    }
    
    // MARK: - Test 5: SkipToNext/Previous
    
    @Test("Skip navigation - next and previous")
    func testSkipNavigation() async throws {
        // Arrange
        let service = try await AudioPlayerService()
        let tracks = loadTestTracks()
        #require(tracks.count >= 3, "Need at least 3 tracks for navigation")
        
        // Act: Load and play
        try await service.loadPlaylist(tracks)
        try await service.startPlaying()
        
        try await Task.sleep(for: .seconds(0.5))
        
        // Assert: First track
        var currentIndex = await service.getCurrentTrackIndex()
        #expect(currentIndex == 0, "Should start at track 0")
        
        // Act: Skip to next
        try await service.skipToNext()
        try await Task.sleep(for: .seconds(0.5))
        
        // Assert: Second track
        currentIndex = await service.getCurrentTrackIndex()
        #expect(currentIndex == 1, "Should be at track 1 after skip")
        
        // Act: Skip to previous
        try await service.previousTrack()
        try await Task.sleep(for: .seconds(0.5))
        
        // Assert: Back to first track
        currentIndex = await service.getCurrentTrackIndex()
        #expect(currentIndex == 0, "Should return to track 0")
        
        await service.stop()
    }
    
    // MARK: - Test 6: Audio Session Interruption
    
    @Test("Audio session interruption handling")
    func testInterruptionHandling() async throws {
        // Arrange
        let service = try await AudioPlayerService()
        let tracks = loadTestTracks()
        #require(tracks.count >= 1)
        
        // Act: Start playing
        try await service.loadPlaylist([tracks[0]])
        try await service.startPlaying()
        
        try await Task.sleep(for: .seconds(0.5))
        #expect(await service.state == .playing)
        
        // Note: Cannot easily simulate actual iOS interruption in unit test
        // This test verifies the service doesn't crash when handling interruption
        // Real interruption testing requires UI testing or manual testing
        
        // Verify pause/resume works (same code path as interruption)
        try await service.pause()
        #expect(await service.state == .paused)
        
        try await service.resume()
        try await Task.sleep(for: .seconds(0.5))
        #expect(await service.state == .playing)
        
        await service.stop()
    }
    
    // MARK: - Test 7: Multiple Player Instances
    
    @Test("Multiple player instances coexist")
    func testMultipleInstances() async throws {
        // Arrange
        let player1 = try await AudioPlayerService()
        let player2 = try await AudioPlayerService()
        
        let tracks = loadTestTracks()
        #require(tracks.count >= 2)
        
        // Act: Start both players
        try await player1.loadPlaylist([tracks[0]])
        try await player2.loadPlaylist([tracks[1]])
        
        try await player1.startPlaying()
        try await player2.startPlaying()
        
        try await Task.sleep(for: .seconds(0.5))
        
        // Assert: Both playing
        #expect(await player1.state == .playing)
        #expect(await player2.state == .playing)
        
        // Cleanup
        await player1.stop()
        await player2.stop()
    }
    
    // MARK: - Test 8: Configuration Validation
    
    @Test("Invalid configuration throws error")
    func testInvalidConfiguration() async throws {
        // Test invalid crossfade duration (too long)
        await #expect(throws: ConfigurationError.self) {
            let _ = PlayerConfiguration(
                crossfadeDuration: 100.0,  // Max is 30.0
                repeatCount: nil,
                volume: 0.8
            )
        }
        
        // Test invalid crossfade duration (too short)
        await #expect(throws: ConfigurationError.self) {
            let _ = PlayerConfiguration(
                crossfadeDuration: 0.5,  // Min is 1.0
                repeatCount: nil,
                volume: 0.8
            )
        }
        
        // Test invalid repeat count (negative)
        await #expect(throws: ConfigurationError.self) {
            let _ = PlayerConfiguration(
                crossfadeDuration: 5.0,
                repeatCount: -1,  // Must be positive
                volume: 0.8
            )
        }
    }
    
    // MARK: - Test 9: Playlist Management
    
    @Test("Playlist management - add, remove, move")
    func testPlaylistManagement() async throws {
        // Arrange
        let service = try await AudioPlayerService()
        let tracks = loadTestTracks()
        #require(tracks.count >= 3)
        
        // Act: Load initial playlist
        try await service.loadPlaylist([tracks[0], tracks[1]])
        
        // Assert: 2 tracks
        var playlist = await service.getCurrentPlaylist()
        #expect(playlist.count == 2)
        
        // Act: Add track
        await service.addTrackToPlaylist(tracks[2].url)
        
        // Assert: 3 tracks
        playlist = await service.getCurrentPlaylist()
        #expect(playlist.count == 3)
        
        // Act: Remove track
        try await service.removeTrackFromPlaylist(at: 1)
        
        // Assert: 2 tracks again
        playlist = await service.getCurrentPlaylist()
        #expect(playlist.count == 2)
    }
    
    // MARK: - Test 10: Stop Behavior
    
    @Test("Stop clears playback state")
    func testStopBehavior() async throws {
        // Arrange
        let service = try await AudioPlayerService()
        let tracks = loadTestTracks()
        #require(tracks.count >= 1)
        
        // Act: Start playing
        try await service.loadPlaylist([tracks[0]])
        try await service.startPlaying()
        
        try await Task.sleep(for: .seconds(0.5))
        #expect(await service.state == .playing)
        
        // Act: Stop
        await service.stop()
        
        // Assert: Finished state
        let state = await service.state
        #expect(state == .finished)
        
        // Assert: No current track
        let currentTrack = await service.currentTrack
        #expect(currentTrack == nil, "Current track should be nil after stop")
    }
    
    // MARK: - Edge Case Tests
    
    @Test("Empty playlist throws error on play")
    func testEmptyPlaylist() async throws {
        // Arrange
        let service = try await AudioPlayerService()
        
        // Act & Assert: Should throw when trying to play empty playlist
        await #expect(throws: AudioPlayerError.self) {
            try await service.startPlaying()
        }
    }
    
    @Test("Invalid audio file returns nil Track")
    func testInvalidAudioFile() {
        // Arrange
        let invalidURL = URL(fileURLWithPath: "/nonexistent/file.mp3")
        
        // Act
        let track = Track(url: invalidURL)
        
        // Assert
        #expect(track == nil, "Track init should return nil for invalid file")
    }
    
    @Test("Crossfade with single track doesn't crash")
    func testCrossfadeWithOneTrack() async throws {
        // Arrange
        let config = PlayerConfiguration(
            crossfadeDuration: 5.0,
            repeatCount: nil,
            volume: 0.8
        )
        let service = try await AudioPlayerService(configuration: config)
        let tracks = loadTestTracks()
        #require(tracks.count >= 1)
        
        // Act: Play single track with crossfade configured
        try await service.loadPlaylist([tracks[0]])
        try await service.startPlaying()
        
        try await Task.sleep(for: .seconds(0.5))
        
        // Assert: Should play normally without crash
        let state = await service.state
        #expect(state == .playing, "Should play single track without crossfade")
        
        await service.stop()
    }
    
    @Test("Rapid pause/resume calls don't crash")
    func testRapidPauseResumeCalls() async throws {
        // Arrange
        let service = try await AudioPlayerService()
        let tracks = loadTestTracks()
        #require(tracks.count >= 1)
        
        try await service.loadPlaylist([tracks[0]])
        try await service.startPlaying()
        
        try await Task.sleep(for: .seconds(0.5))
        
        // Act: Rapid pause/resume (stress test)
        for _ in 0..<5 {
            try await service.pause()
            try await Task.sleep(for: .milliseconds(100))
            try await service.resume()
            try await Task.sleep(for: .milliseconds(100))
        }
        
        // Assert: Should still work
        let state = await service.state
        #expect(state == .playing, "Should handle rapid pause/resume")
        
        await service.stop()
    }
    
    @Test("Configuration update during playback")
    func testConfigurationUpdateDuringPlayback() async throws {
        // Arrange
        let service = try await AudioPlayerService()
        let tracks = loadTestTracks()
        #require(tracks.count >= 1)
        
        // Act: Start playing
        try await service.loadPlaylist([tracks[0]])
        try await service.startPlaying()
        
        try await Task.sleep(for: .seconds(0.5))
        #expect(await service.state == .playing)
        
        // Act: Update configuration while playing
        let newConfig = PlayerConfiguration(
            crossfadeDuration: 3.0,
            repeatCount: 2,
            volume: 0.5
        )
        try await service.updateConfiguration(newConfig)
        
        // Assert: Still playing
        let state = await service.state
        #expect(state == .playing, "Should continue playing after config update")
        
        // Assert: Volume changed
        // Note: This would require exposing volume getter
        
        await service.stop()
    }
    
    @Test("JumpToTrack with invalid index throws")
    func testJumpToInvalidIndex() async throws {
        // Arrange
        let service = try await AudioPlayerService()
        let tracks = loadTestTracks()
        #require(tracks.count >= 2)
        
        try await service.loadPlaylist([tracks[0], tracks[1]])
        try await service.startPlaying()
        
        try await Task.sleep(for: .seconds(0.5))
        
        // Act & Assert: Jump to invalid index
        await #expect(throws: AudioPlayerError.self) {
            try await service.jumpToTrack(at: 99)  // Invalid index
        }
        
        await service.stop()
    }
    
    @Test("Overlay with invalid URL throws")
    func testOverlayInvalidURL() async throws {
        // Arrange
        let service = try await AudioPlayerService()
        let tracks = loadTestTracks()
        try await service.loadPlaylist([tracks[0]])
        try await service.startPlaying()
        
        try await Task.sleep(for: .seconds(0.5))
        
        let invalidURL = URL(fileURLWithPath: "/nonexistent/overlay.mp3")
        
        // Act & Assert
        await #expect(throws: AudioPlayerError.self) {
            try await service.playOverlay(invalidURL)
        }
        
        await service.stop()
    }
}

// MARK: - Test Errors

enum TestError: Error {
    case resourceNotFound
}
