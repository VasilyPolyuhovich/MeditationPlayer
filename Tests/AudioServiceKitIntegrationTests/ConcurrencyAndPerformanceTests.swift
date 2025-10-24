//
//  ConcurrencyAndPerformanceTests.swift
//  AudioServiceKitIntegrationTests
//
//  Tests for Swift concurrency safety and performance characteristics
//

import Testing
import Foundation
@testable import AudioServiceKit
@testable import AudioServiceCore

/// Concurrency and performance tests for AudioServiceKit
@Suite("Concurrency & Performance Tests")
struct ConcurrencyAndPerformanceTests {
    
    // MARK: - Test Resources
    
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
    
    // MARK: - Concurrency Tests
    
    @Test("Concurrent state queries don't cause data races")
    func testConcurrentStateQueries() async throws {
        // Arrange
        let service = try await AudioPlayerService()
        let tracks = loadTestTracks()
        #require(tracks.count >= 1)
        
        try await service.loadPlaylist([tracks[0]])
        try await service.startPlaying()
        
        try await Task.sleep(for: .seconds(0.5))
        
        // Act: Query state from multiple tasks simultaneously
        await withTaskGroup(of: PlayerState.self) { group in
            for _ in 0..<100 {
                group.addTask {
                    await service.state
                }
            }
            
            // Collect all results
            var states: [PlayerState] = []
            for await state in group {
                states.append(state)
            }
            
            // Assert: All queries succeeded, all same state
            #expect(states.count == 100)
            let firstState = states[0]
            for state in states {
                #expect(state == firstState, "All concurrent queries should return same state")
            }
        }
        
        await service.stop()
    }
    
    @Test("Concurrent playlist modifications are safe")
    func testConcurrentPlaylistModifications() async throws {
        // Arrange
        let service = try await AudioPlayerService()
        let tracks = loadTestTracks()
        #require(tracks.count >= 3)
        
        try await service.loadPlaylist([tracks[0]])
        
        // Act: Add tracks concurrently
        await withTaskGroup(of: Void.self) { group in
            for i in 1..<3 {
                group.addTask {
                    await service.addTrackToPlaylist(tracks[i].url)
                }
            }
        }
        
        // Assert: All tracks added (order may vary due to concurrency)
        let playlist = await service.getCurrentPlaylist()
        #expect(playlist.count == 3, "All concurrent adds should succeed")
    }
    
    @Test("Rapid play/pause calls are thread-safe")
    func testRapidPlayPauseThreadSafety() async throws {
        // Arrange
        let service = try await AudioPlayerService()
        let tracks = loadTestTracks()
        #require(tracks.count >= 1)
        
        try await service.loadPlaylist([tracks[0]])
        try await service.startPlaying()
        
        try await Task.sleep(for: .seconds(0.5))
        
        // Act: Rapid pause/resume from multiple tasks
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<20 {
                group.addTask {
                    do {
                        if i % 2 == 0 {
                            try await service.pause()
                        } else {
                            try await service.resume()
                        }
                    } catch {
                        // Expected: some calls may fail due to state transitions
                    }
                }
            }
        }
        
        // Assert: Service still functional (no crash)
        let finalState = await service.state
        #expect(finalState == .playing || finalState == .paused)
        
        await service.stop()
    }
    
    @Test("Multiple services don't interfere with each other")
    func testMultipleServicesIsolation() async throws {
        // Arrange
        let service1 = try await AudioPlayerService()
        let service2 = try await AudioPlayerService()
        let service3 = try await AudioPlayerService()
        
        let tracks = loadTestTracks()
        #require(tracks.count >= 3)
        
        // Act: Start all services simultaneously
        async let start1: Void = {
            try await service1.loadPlaylist([tracks[0]])
            try await service1.startPlaying()
        }()
        
        async let start2: Void = {
            try await service2.loadPlaylist([tracks[1]])
            try await service2.startPlaying()
        }()
        
        async let start3: Void = {
            try await service3.loadPlaylist([tracks[2]])
            try await service3.startPlaying()
        }()
        
        // Wait for all to start
        _ = try await (start1, start2, start3)
        
        try await Task.sleep(for: .seconds(0.5))
        
        // Assert: All playing independently
        #expect(await service1.state == .playing)
        #expect(await service2.state == .playing)
        #expect(await service3.state == .playing)
        
        // Assert: Different tracks
        let track1 = await service1.currentTrack
        let track2 = await service2.currentTrack
        let track3 = await service3.currentTrack
        
        #expect(track1?.title != track2?.title)
        #expect(track2?.title != track3?.title)
        
        // Cleanup
        await service1.stop()
        await service2.stop()
        await service3.stop()
    }
    
    @Test("Actor isolation prevents data races in state updates")
    func testActorIsolationStateUpdates() async throws {
        // Arrange
        let service = try await AudioPlayerService()
        let tracks = loadTestTracks()
        #require(tracks.count >= 2)
        
        try await service.loadPlaylist(tracks)
        try await service.startPlaying()
        
        try await Task.sleep(for: .seconds(0.5))
        
        // Act: Trigger state transitions from multiple tasks
        await withTaskGroup(of: Void.self) { group in
            // Task 1: Skip tracks
            group.addTask {
                for _ in 0..<5 {
                    try? await service.skipToNext()
                    try? await Task.sleep(for: .milliseconds(100))
                }
            }
            
            // Task 2: Pause/resume
            group.addTask {
                for _ in 0..<5 {
                    try? await service.pause()
                    try? await Task.sleep(for: .milliseconds(50))
                    try? await service.resume()
                    try? await Task.sleep(for: .milliseconds(50))
                }
            }
            
            // Task 3: Query state
            group.addTask {
                for _ in 0..<20 {
                    let _ = await service.state
                    try? await Task.sleep(for: .milliseconds(50))
                }
            }
        }
        
        // Assert: No crash, service still functional
        let finalState = await service.state
        #expect(finalState == .playing || finalState == .paused)
        
        await service.stop()
    }
    
    // MARK: - Performance Tests
    
    @Test("Service initialization is fast")
    func testServiceInitializationPerformance() async throws {
        // Measure initialization time
        let startTime = CFAbsoluteTimeGetCurrent()
        
        let service = try await AudioPlayerService()
        
        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        
        // Assert: Init should complete in < 1 second
        #expect(elapsed < 1.0, "Service init took \(elapsed)s, should be < 1s")
        
        // Verify service is functional
        let tracks = loadTestTracks()
        try await service.loadPlaylist([tracks[0]])
        try await service.startPlaying()
        
        try await Task.sleep(for: .seconds(0.5))
        #expect(await service.state == .playing)
        
        await service.stop()
    }
    
    @Test("Playlist load is efficient for large playlists")
    func testLargePlaylistLoadPerformance() async throws {
        // Arrange
        let service = try await AudioPlayerService()
        let tracks = loadTestTracks()
        #require(tracks.count >= 1)
        
        // Create large playlist by repeating tracks
        var largePlaylist: [Track] = []
        for _ in 0..<50 {
            largePlaylist.append(contentsOf: tracks)
        }
        
        // Act: Load large playlist
        let startTime = CFAbsoluteTimeGetCurrent()
        
        try await service.loadPlaylist(largePlaylist)
        
        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        
        // Assert: Should load quickly (< 500ms for 150 tracks)
        #expect(elapsed < 0.5, "Loading 150 tracks took \(elapsed)s, should be < 0.5s")
        
        // Verify playlist loaded
        let playlist = await service.getCurrentPlaylist()
        #expect(playlist.count == largePlaylist.count)
    }
    
    @Test("Skip operations are fast")
    func testSkipPerformance() async throws {
        // Arrange
        let service = try await AudioPlayerService()
        let tracks = loadTestTracks()
        #require(tracks.count >= 3)
        
        try await service.loadPlaylist(tracks)
        try await service.startPlaying()
        
        try await Task.sleep(for: .seconds(0.5))
        
        // Act: Measure skip time
        let startTime = CFAbsoluteTimeGetCurrent()
        
        try await service.skipToNext()
        
        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        
        // Assert: Skip should be fast (< 100ms)
        #expect(elapsed < 0.1, "Skip took \(elapsed)s, should be < 0.1s")
        
        await service.stop()
    }
    
    @Test("Configuration update is fast")
    func testConfigurationUpdatePerformance() async throws {
        // Arrange
        let service = try await AudioPlayerService()
        
        // Act: Measure config update time
        let startTime = CFAbsoluteTimeGetCurrent()
        
        let newConfig = PlayerConfiguration(
            crossfadeDuration: 3.0,
            repeatCount: 5,
            volume: 0.7
        )
        try await service.updateConfiguration(newConfig)
        
        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        
        // Assert: Update should be instant (< 10ms)
        #expect(elapsed < 0.01, "Config update took \(elapsed)s, should be < 0.01s")
    }
    
    @Test("State query overhead is minimal")
    func testStateQueryPerformance() async throws {
        // Arrange
        let service = try await AudioPlayerService()
        let tracks = loadTestTracks()
        try await service.loadPlaylist([tracks[0]])
        try await service.startPlaying()
        
        try await Task.sleep(for: .seconds(0.5))
        
        // Act: Query state many times
        let startTime = CFAbsoluteTimeGetCurrent()
        
        for _ in 0..<1000 {
            let _ = await service.state
        }
        
        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        
        // Assert: 1000 queries should be fast (< 100ms)
        #expect(elapsed < 0.1, "1000 state queries took \(elapsed)s, should be < 0.1s")
        
        await service.stop()
    }
    
    @Test("Memory doesn't leak with repeated play/stop cycles")
    func testMemoryLeakOnPlayStopCycles() async throws {
        // This is a basic check - proper memory leak testing requires Instruments
        
        let service = try await AudioPlayerService()
        let tracks = loadTestTracks()
        #require(tracks.count >= 1)
        
        // Act: Repeated play/stop cycles
        for _ in 0..<10 {
            try await service.loadPlaylist([tracks[0]])
            try await service.startPlaying()
            try await Task.sleep(for: .milliseconds(100))
            await service.stop()
        }
        
        // Assert: Service still functional (no crash from memory corruption)
        try await service.loadPlaylist([tracks[0]])
        try await service.startPlaying()
        try await Task.sleep(for: .milliseconds(100))
        
        #expect(await service.state == .playing)
        
        await service.stop()
    }
    
    // MARK: - Stress Tests
    
    @Test("Handles rapid configuration changes")
    func testRapidConfigurationChanges() async throws {
        // Arrange
        let service = try await AudioPlayerService()
        
        // Act: Rapid config updates
        for i in 0..<50 {
            let config = PlayerConfiguration(
                crossfadeDuration: Double(i % 10 + 1),
                repeatCount: i % 5,
                volume: Float(i % 10) / 10.0
            )
            try await service.updateConfiguration(config)
        }
        
        // Assert: Service still functional
        let tracks = loadTestTracks()
        try await service.loadPlaylist([tracks[0]])
        try await service.startPlaying()
        
        try await Task.sleep(for: .seconds(0.5))
        #expect(await service.state == .playing)
        
        await service.stop()
    }
    
    @Test("Handles rapid overlay start/stop")
    func testRapidOverlayStartStop() async throws {
        // Arrange
        let service = try await AudioPlayerService()
        let tracks = loadTestTracks()
        try await service.loadPlaylist([tracks[0]])
        try await service.startPlaying()
        
        try await Task.sleep(for: .seconds(0.5))
        
        let bundle = Bundle.module
        guard let overlayURL = bundle.url(forResource: "stage1_begin_voice", withExtension: "mp3") else {
            throw TestError.resourceNotFound
        }
        
        // Act: Rapid overlay start/stop
        for _ in 0..<10 {
            try await service.playOverlay(overlayURL)
            try await Task.sleep(for: .milliseconds(100))
            await service.stopOverlay()
            try await Task.sleep(for: .milliseconds(100))
        }
        
        // Assert: Service still functional
        #expect(await service.state == .playing)
        
        await service.stop()
    }
    
    @Test("Concurrent skip operations are handled gracefully")
    func testConcurrentSkipOperations() async throws {
        // Arrange
        let service = try await AudioPlayerService()
        let tracks = loadTestTracks()
        #require(tracks.count >= 3)
        
        try await service.loadPlaylist(tracks)
        try await service.startPlaying()
        
        try await Task.sleep(for: .seconds(0.5))
        
        // Act: Multiple concurrent skips
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<10 {
                group.addTask {
                    try? await service.skipToNext()
                }
            }
        }
        
        // Assert: Service still functional, at valid index
        let currentIndex = await service.getCurrentTrackIndex()
        #expect(currentIndex >= 0 && currentIndex < tracks.count)
        
        await service.stop()
    }
}

// MARK: - Test Errors

enum TestError: Error {
    case resourceNotFound
}
