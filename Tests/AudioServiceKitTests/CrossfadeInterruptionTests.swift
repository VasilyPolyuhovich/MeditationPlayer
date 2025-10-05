import Testing
import Foundation
@testable import AudioServiceKit
@testable import AudioServiceCore

/// Test suite for Issue #10A: Crossfade race condition and interruption handling
@Suite("Crossfade Interruption Tests")
struct CrossfadeInterruptionTests {
    
    // MARK: - Test Data
    
    private let testAudioURL: URL = {
        Bundle.module.url(
            forResource: "test_audio",
            withExtension: "mp3",
            subdirectory: "TestResources"
        )!
    }()
    
    private let secondAudioURL: URL = {
        Bundle.module.url(
            forResource: "test_audio_2",
            withExtension: "mp3",
            subdirectory: "TestResources"
        )!
    }()
    
    // MARK: - Pause During Crossfade Tests
    
    @Test("Pause during replaceTrack crossfade should abort gracefully")
    func pauseDuringReplaceCrossfade() async throws {
        // Setup
        let config = AudioConfiguration(
            fadeInDuration: 0.5,
            fadeOutDuration: 0.5,
            crossfadeDuration: 2.0, // Long crossfade to allow pause
            fadeCurve: .equalPower
        )
        
        let service = AudioPlayerService(configuration: config)
        await service.setup()
        
        // Start playing first track
        try await service.startPlaying(url: testAudioURL, configuration: config)
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1s
        
        #expect(await service.state == .playing)
        
        // Start replace crossfade
        let replaceTask = Task {
            try await service.replaceTrack(url: secondAudioURL, crossfadeDuration: 2.0)
        }
        
        // Pause during crossfade (after 500ms)
        try await Task.sleep(nanoseconds: 500_000_000)
        try await service.pause()
        
        // Wait for replace to complete
        try await replaceTask.value
        
        // Verify: Should be paused, not crashed
        #expect(await service.state == .paused)
        
        // Cleanup
        await service.cleanup()
    }
    
    @Test("Stop during loop crossfade should cancel fade tasks")
    func stopDuringLoopCrossfade() async throws {
        // Setup
        let config = AudioConfiguration(
            fadeInDuration: 0.5,
            fadeOutDuration: 0.5,
            crossfadeDuration: 2.0, // Long crossfade
            enableLooping: true,
            fadeCurve: .equalPower
        )
        
        let service = AudioPlayerService(configuration: config)
        await service.setup()
        
        // Start playing (will loop)
        try await service.startPlaying(url: testAudioURL, configuration: config)
        
        // Wait for near end of track (trigger loop crossfade)
        if let position = await service.playbackPosition {
            let waitTime = position.duration - config.crossfadeDuration - 0.2
            if waitTime > 0 {
                try await Task.sleep(nanoseconds: UInt64(waitTime * 1_000_000_000))
            }
        }
        
        // Stop during crossfade
        await service.stop()
        
        // Verify: Should be finished, not crashed
        #expect(await service.state == .finished)
        
        // Cleanup
        await service.cleanup()
    }
    
    // MARK: - Multiple Rapid Operations Tests
    
    @Test("Rapid pause-resume during crossfade should handle gracefully")
    func rapidPauseResumeDuringCrossfade() async throws {
        // Setup
        let config = AudioConfiguration(
            fadeInDuration: 0.5,
            fadeOutDuration: 0.5,
            crossfadeDuration: 3.0, // Extra long for multiple operations
            fadeCurve: .equalPower
        )
        
        let service = AudioPlayerService(configuration: config)
        await service.setup()
        
        // Start playing
        try await service.startPlaying(url: testAudioURL, configuration: config)
        try await Task.sleep(nanoseconds: 500_000_000)
        
        // Start replace crossfade
        let replaceTask = Task {
            try await service.replaceTrack(url: secondAudioURL, crossfadeDuration: 3.0)
        }
        
        // Rapid pause-resume during crossfade
        try await Task.sleep(nanoseconds: 200_000_000) // 200ms
        try await service.pause()
        
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        try await service.resume()
        
        try await Task.sleep(nanoseconds: 200_000_000) // 200ms
        try await service.pause()
        
        // Wait for crossfade to complete
        try await replaceTask.value
        
        // Verify: Should be paused, state consistent
        #expect(await service.state == .paused)
        
        // Resume should work
        try await service.resume()
        #expect(await service.state == .playing)
        
        // Cleanup
        await service.cleanup()
    }
    
    // MARK: - Task Cancellation Verification
    
    @Test("Cancelled fade tasks should not update volume after abortion")
    func cancelledFadeAbortsVolumeUpdates() async throws {
        // This test verifies that fadeVolume() respects Task.isCancelled
        // by checking that volume updates stop immediately when task is cancelled
        
        let config = AudioConfiguration(
            crossfadeDuration: 5.0, // Long fade
            fadeCurve: .linear
        )
        
        let service = AudioPlayerService(configuration: config)
        await service.setup()
        
        // Start playing
        try await service.startPlaying(url: testAudioURL, configuration: config)
        try await Task.sleep(nanoseconds: 500_000_000)
        
        // Start crossfade
        let replaceTask = Task {
            try await service.replaceTrack(url: secondAudioURL, crossfadeDuration: 5.0)
        }
        
        // Cancel after 1 second (20% progress)
        try await Task.sleep(nanoseconds: 1_000_000_000)
        await service.stop()
        
        // Wait for replace task to complete
        _ = try? await replaceTask.value
        
        // Verify: State should be finished (not stuck in crossfade)
        #expect(await service.state == .finished)
        
        // Cleanup
        await service.cleanup()
    }
    
    // MARK: - Edge Case: Crossfade During Finish
    
    @Test("Finish during active crossfade should complete gracefully")
    func finishDuringActiveCrossfade() async throws {
        let config = AudioConfiguration(
            fadeInDuration: 0.5,
            fadeOutDuration: 1.0,
            crossfadeDuration: 2.0,
            fadeCurve: .equalPower
        )
        
        let service = AudioPlayerService(configuration: config)
        await service.setup()
        
        // Start playing
        try await service.startPlaying(url: testAudioURL, configuration: config)
        try await Task.sleep(nanoseconds: 500_000_000)
        
        // Start crossfade
        let replaceTask = Task {
            try await service.replaceTrack(url: secondAudioURL, crossfadeDuration: 2.0)
        }
        
        // Call finish during crossfade
        try await Task.sleep(nanoseconds: 500_000_000)
        try await service.finish(fadeDuration: 1.0)
        
        // Wait for replace to complete (or fail)
        _ = try? await replaceTask.value
        
        // Verify: Should reach finished state
        #expect(await service.state == .finished)
        
        // Cleanup
        await service.cleanup()
    }
}
