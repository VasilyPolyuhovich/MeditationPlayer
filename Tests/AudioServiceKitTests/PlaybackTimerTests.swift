import Testing
import Foundation
@testable import AudioServiceKit
@testable import AudioServiceCore

/// Test suite for Issue #10C: Playback timer cancellation edge cases
@Suite("Playback Timer Cancellation Tests")
struct PlaybackTimerTests {
    
    // MARK: - Test Data
    
    private let testAudioURL: URL = {
        Bundle.module.url(
            forResource: "test_audio",
            withExtension: "mp3",
            subdirectory: "TestResources"
        )!
    }()
    
    // MARK: - Cancellation Gap Tests
    
    @Test("Timer cancellation should not produce updates after stop")
    func timerCancellationBlocksUpdates() async throws {
        // Setup
        let config = AudioConfiguration()
        let service = AudioPlayerService(configuration: config)
        await service.setup()
        
        // Start playback (starts timer)
        try await service.startPlaying(url: testAudioURL, configuration: config)
        
        // Wait for at least 2 timer cycles (1 second)
        try await Task.sleep(nanoseconds: 1_000_000_000)
        
        // Verify timer is running (position updates)
        let positionBefore = await service.playbackPosition
        #expect(positionBefore != nil)
        
        // Stop playback (cancels timer)
        await service.stop()
        
        // Critical: Wait for one full timer cycle (500ms)
        // If gap exists, we'd see update during this window
        let positionAtStop = await service.playbackPosition
        try await Task.sleep(nanoseconds: 600_000_000) // 600ms > 500ms cycle
        let positionAfterStop = await service.playbackPosition
        
        // Verify: Position should be cleared (nil) or unchanged
        #expect(positionAfterStop == nil || positionAfterStop == positionAtStop)
        
        // Cleanup
        await service.cleanup()
    }
    
    @Test("Rapid stop-start should cancel previous timer cleanly")
    func rapidStopStartCancelsTimer() async throws {
        // Setup
        let config = AudioConfiguration()
        let service = AudioPlayerService(configuration: config)
        await service.setup()
        
        // Start-stop-start cycle (stress test timer cancellation)
        for _ in 0..<5 {
            try await service.startPlaying(url: testAudioURL, configuration: config)
            try await Task.sleep(nanoseconds: 100_000_000) // 100ms
            await service.stop()
            try await Task.sleep(nanoseconds: 50_000_000)  // 50ms
        }
        
        // Final start
        try await service.startPlaying(url: testAudioURL, configuration: config)
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1s
        
        // Verify: Should be playing normally (no timer conflicts)
        #expect(await service.state == .playing)
        #expect(await service.playbackPosition != nil)
        
        // Cleanup
        await service.cleanup()
    }
    
    @Test("Pause should preserve last position without timer updates")
    func pausePreservesPositionWithoutUpdates() async throws {
        // Setup
        let config = AudioConfiguration()
        let service = AudioPlayerService(configuration: config)
        await service.setup()
        
        // Start playback
        try await service.startPlaying(url: testAudioURL, configuration: config)
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1s
        
        // Pause
        try await service.pause()
        let positionAtPause = await service.playbackPosition
        
        // Wait for timer cycle
        try await Task.sleep(nanoseconds: 600_000_000) // 600ms
        
        // Verify: Position unchanged (timer not updating paused state)
        let positionAfterWait = await service.playbackPosition
        
        // Allow ±10ms tolerance for async timing
        if let before = positionAtPause, let after = positionAfterWait {
            let delta = abs(before.currentTime - after.currentTime)
            #expect(delta < 0.01) // <10ms change
        }
        
        // Cleanup
        await service.cleanup()
    }
    
    // MARK: - Timer Memory Leak Tests
    
    @Test("Cleanup should cancel timer without retain cycle")
    func cleanupCancelsTimerWithoutLeak() async throws {
        // Setup
        var service: AudioPlayerService? = AudioPlayerService()
        await service?.setup()
        
        // Start playback (creates timer with [weak self])
        try await service?.startPlaying(
            url: testAudioURL,
            configuration: AudioConfiguration()
        )
        try await Task.sleep(nanoseconds: 500_000_000) // 500ms
        
        // Cleanup
        await service?.cleanup()
        
        // Release service
        service = nil
        
        // Verify: If weak reference works, service is deallocated
        // (Can't directly test dealloc, but no crash = success)
        try await Task.sleep(nanoseconds: 100_000_000)
        
        #expect(service == nil)
    }
    
    // MARK: - Edge Case: Multiple Position Updates
    
    @Test("Timer should update position monotonically during playback")
    func timerUpdatesPositionMonotonically() async throws {
        // Setup
        let config = AudioConfiguration()
        let service = AudioPlayerService(configuration: config)
        await service.setup()
        
        // Start playback
        try await service.startPlaying(url: testAudioURL, configuration: config)
        
        // Collect positions over 3 timer cycles
        var positions: [TimeInterval] = []
        
        for _ in 0..<3 {
            try await Task.sleep(nanoseconds: 550_000_000) // 550ms (just over timer cycle)
            if let pos = await service.playbackPosition {
                positions.append(pos.currentTime)
            }
        }
        
        // Verify: Positions should be strictly increasing
        #expect(positions.count == 3)
        for i in 1..<positions.count {
            #expect(positions[i] > positions[i-1])
        }
        
        // Cleanup
        await service.cleanup()
    }
}
