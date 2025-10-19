import Testing
import Foundation
import AVFoundation
@testable import AudioServiceKit
@testable import AudioServiceCore

/// Test suite: SSOT enforcement in state management
/// Validates invariant: ∀t: service.state ≡ stateMachine.currentState
@Suite("State Management - SSOT")
struct StateManagementTests {
    
    // MARK: - Helper Methods
    
    /// Creates a test audio file programmatically
    /// - Parameter duration: Duration in seconds (default: 2.0s)
    /// - Returns: URL of created test file in temp directory
    private func createTestAudioFile(duration: TimeInterval = 2.0) -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("test_\(UUID().uuidString).caf")
        
        // Create audio format (44.1kHz, stereo)
        let format = AVAudioFormat(
            standardFormatWithSampleRate: 44100,
            channels: 2
        )!
        
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
    
    // MARK: - SSOT Invariant Tests
    
    @Test("SSOT: State reflects state machine at initialization")
    func testStateReflectsStateMachineOnInit() async throws {
        let service = AudioPlayerService()
        await service.setup()
        
        let serviceState = await service.state
        let machineState = await service.stateMachine.currentState
        
        #expect(serviceState == machineState)
        #expect(serviceState == .finished)
    }
    
    @Test("SSOT: State reflects state machine after pause")
    func testStateReflectsStateMachineAfterPause() async throws {
        let service = AudioPlayerService()
        await service.setup()
        
        // Start playback
        let url = createTestAudioFile()
        defer { try? FileManager.default.removeItem(at: url) }
        try await service.startPlaying(url: url, configuration: AudioConfiguration())
        
        // Pause
        try await service.pause()
        
        let serviceState = await service.state
        let machineState = await service.stateMachine.currentState
        
        #expect(serviceState == machineState)
        #expect(serviceState == .paused)
    }
    
    @Test("SSOT: State reflects state machine after resume")
    func testStateReflectsStateMachineAfterResume() async throws {
        let service = AudioPlayerService()
        await service.setup()
        
        let url = createTestAudioFile()
        defer { try? FileManager.default.removeItem(at: url) }
        try await service.startPlaying(url: url, configuration: AudioConfiguration())
        try await service.pause()
        try await service.resume()
        
        let serviceState = await service.state
        let machineState = await service.stateMachine.currentState
        
        #expect(serviceState == machineState)
        #expect(serviceState == .playing)
    }
    
    @Test("SSOT: State reflects state machine after stop")
    func testStateReflectsStateMachineAfterStop() async throws {
        let service = AudioPlayerService()
        await service.setup()
        
        let url = createTestAudioFile()
        defer { try? FileManager.default.removeItem(at: url) }
        try await service.startPlaying(url: url, configuration: AudioConfiguration())
        await service.stop()
        
        let serviceState = await service.state
        let machineState = await service.stateMachine.currentState
        
        #expect(serviceState == machineState)
        #expect(serviceState == .finished)
    }
    
    @Test("SSOT: State reflects state machine after reset")
    func testStateReflectsStateMachineAfterReset() async throws {
        let service = AudioPlayerService()
        await service.setup()
        
        let url = createTestAudioFile()
        defer { try? FileManager.default.removeItem(at: url) }
        try await service.startPlaying(url: url, configuration: AudioConfiguration())
        await service.reset()
        
        let serviceState = await service.state
        let machineState = await service.stateMachine.currentState
        
        #expect(serviceState == machineState)
        #expect(serviceState == .finished)
    }
    
    // MARK: - Atomic Transition Tests
    
    @Test("Atomic: State changes are instantaneous (no intermediate states)")
    func testAtomicStateTransitions() async throws {
        let service = AudioPlayerService()
        await service.setup()
        
        // Rapid state queries during transition should never see intermediate states
        let url = createTestAudioFile()
        defer { try? FileManager.default.removeItem(at: url) }
        
        Task {
            try? await service.startPlaying(url: url, configuration: AudioConfiguration())
        }
        
        // Sample state during transition
        try await Task.sleep(nanoseconds: 1_000_000) // 1ms
        let observedState = await service.state
        
        // State should be valid (no undefined/transient states)
        #expect([.finished, .preparing, .playing].contains(observedState))
    }
    
    // MARK: - Regression Tests (Bug #11B)
    
    @Test("Regression #11B: Reset reinitializes state machine correctly")
    func testResetReinitializesStateMachine() async throws {
        let service = AudioPlayerService()
        await service.setup()
        
        let url = createTestAudioFile()
        defer { try? FileManager.default.removeItem(at: url) }
        
        // Play → Reset cycle
        try await service.startPlaying(url: url, configuration: AudioConfiguration())
        await service.reset()
        
        // Should be able to play again without Error 4
        try await service.startPlaying(url: url, configuration: AudioConfiguration())
        
        let state = await service.state
        #expect([.preparing, .playing].contains(state))
    }
}
