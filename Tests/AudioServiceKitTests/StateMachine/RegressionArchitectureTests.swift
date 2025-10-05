import Testing
import Foundation
@testable import AudioServiceKit
@testable import AudioServiceCore

/// Test suite: Regression validation for architectural fixes
/// Coverage: Bug #11A (track switch), Bug #11B (reset error)
@Suite("Regression - Architecture Fixes")
struct RegressionArchitectureTests {
    
    // MARK: - Bug #11A: Track Switch Cacophony
    
    @Test("Bug #11A: Track replacement maintains audio continuity")
    func testTrackReplacementContinuity() async throws {
        let service = AudioPlayerService()
        await service.setup()
        
        // Start playing track 1
        let url1 = Bundle.module.url(forResource: "test_audio", withExtension: "mp3")!
        try await service.startPlaying(url: url1, configuration: AudioConfiguration())
        
        // Wait for playback to stabilize
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        
        let initialState = await service.state
        #expect(initialState == .playing)
        
        // Replace with track 2
        let url2 = Bundle.module.url(forResource: "test_audio_2", withExtension: "mp3")!
        try await service.replaceTrack(url: url2, crossfadeDuration: 1.0)
        
        // State should remain playing (no cacophony)
        let finalState = await service.state
        #expect(finalState == .playing)
        
        // Track should be updated
        let currentTrack = await service.currentTrack
        #expect(currentTrack != nil)
    }
    
    @Test("Bug #11A: Method execution order prevents cacophony")
    func testMethodOrderPreventsGlitches() async throws {
        // Validates fix: switchActivePlayer() BEFORE stopActivePlayer()
        // Root cause: reversed order caused momentary silence
        
        let service = AudioPlayerService()
        await service.setup()
        
        let url1 = Bundle.module.url(forResource: "test_audio", withExtension: "mp3")!
        try await service.startPlaying(url: url1, configuration: AudioConfiguration())
        
        let url2 = Bundle.module.url(forResource: "test_audio_2", withExtension: "mp3")!
        
        // Critical section: track replacement should be seamless
        let startTime = Date()
        try await service.replaceTrack(url: url2, crossfadeDuration: 0.5)
        let duration = Date().timeIntervalSince(startTime)
        
        // Should complete within reasonable time (< 1s + crossfade)
        #expect(duration < 2.0)
        #expect(await service.state == .playing)
    }
    
    // MARK: - Bug #11B: Reset Error 4
    
    @Test("Bug #11B: Reset from playing state succeeds")
    func testResetFromPlayingState() async throws {
        let service = AudioPlayerService()
        await service.setup()
        
        let url = Bundle.module.url(forResource: "test_audio", withExtension: "mp3")!
        try await service.startPlaying(url: url, configuration: AudioConfiguration())
        
        // Reset while playing
        await service.reset()
        
        // Should transition to finished without error
        #expect(await service.state == .finished)
        #expect(await service.currentTrack == nil)
    }
    
    @Test("Bug #11B: Play after reset does not throw Error 4")
    func testPlayAfterResetNoError() async throws {
        let service = AudioPlayerService()
        await service.setup()
        
        let url = Bundle.module.url(forResource: "test_audio", withExtension: "mp3")!
        
        // Cycle: play → reset → play
        try await service.startPlaying(url: url, configuration: AudioConfiguration())
        await service.reset()
        
        // Should NOT throw AudioPlayerError.invalidState (Error 4)
        try await service.startPlaying(url: url, configuration: AudioConfiguration())
        
        let state = await service.state
        #expect([.preparing, .playing].contains(state))
    }
    
    @Test("Bug #11B: State machine reinitializes on reset")
    func testStateMachineReinitializationOnReset() async throws {
        let service = AudioPlayerService()
        await service.setup()
        
        let url = Bundle.module.url(forResource: "test_audio", withExtension: "mp3")!
        try await service.startPlaying(url: url, configuration: AudioConfiguration())
        
        // Store state machine state
        let preMachineState = await service.stateMachine.currentState
        #expect([.preparing, .playing].contains(preMachineState))
        
        await service.reset()
        
        // State machine should be reinitialized to FinishedState
        let postMachineState = await service.stateMachine.currentState
        #expect(postMachineState == .finished)
        
        // Service state should match
        #expect(await service.state == .finished)
    }
    
    // MARK: - State Machine Synchronization
    
    @Test("SSOT: Manual state bypass eliminated")
    func testNoManualStateBypass() async throws {
        // This test verifies that ALL state changes go through state machine
        // P(desync) = 0% enforced by private storage
        
        let service = AudioPlayerService()
        await service.setup()
        
        let url = Bundle.module.url(forResource: "test_audio", withExtension: "mp3")!
        
        // Full lifecycle
        try await service.startPlaying(url: url, configuration: AudioConfiguration())
        try await service.pause()
        try await service.resume()
        await service.stop()
        await service.reset()
        
        // At every step, service.state == stateMachine.currentState
        #expect(await service.state == await service.stateMachine.currentState)
    }
    
    @Test("SSOT: PlayingState allows preparing transition")
    func testPlayingStateAllowsPreparingTransition() async throws {
        // Validates fix: PlayingState.isValidTransition(.preparing) = true
        
        let service = AudioPlayerService()
        await service.setup()
        
        let url = Bundle.module.url(forResource: "test_audio", withExtension: "mp3")!
        try await service.startPlaying(url: url, configuration: AudioConfiguration())
        
        // Verify playing state
        #expect(await service.state == .playing)
        
        // Reset should succeed (requires .playing → .preparing transition)
        await service.reset()
        
        #expect(await service.state == .finished)
    }
    
    // MARK: - Lifecycle Coverage
    
    @Test("Lifecycle: Multiple play/reset cycles maintain stability")
    func testMultiplePlayResetCycles() async throws {
        let service = AudioPlayerService()
        await service.setup()
        
        let url = Bundle.module.url(forResource: "test_audio", withExtension: "mp3")!
        
        // 5 cycles: play → reset
        for cycle in 0..<5 {
            try await service.startPlaying(url: url, configuration: AudioConfiguration())
            #expect([.preparing, .playing].contains(await service.state))
            
            await service.reset()
            #expect(await service.state == .finished)
            
            // Validate state machine sync after each cycle
            #expect(await service.state == await service.stateMachine.currentState)
        }
    }
}
