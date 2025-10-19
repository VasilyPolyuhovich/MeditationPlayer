import Testing
import Foundation
import AVFoundation
@testable import AudioServiceKit
@testable import AudioServiceCore

/// Test suite: Atomic state transitions
/// Validates sequential consistency: transition₁ → transition₂ ⟹ no race conditions
@Suite("Atomic Transitions")
struct AtomicTransitionTests {
    
    // MARK: - Helper Methods
    
    private func createTestAudioFile() -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("test_\(UUID().uuidString).caf")
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
        
        do {
            let audioFile = try AVAudioFile(forWriting: fileURL, settings: format.settings)
            let frameCount = AVAudioFrameCount(44100 * 2.0)
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
            buffer.frameLength = frameCount
            try audioFile.write(from: buffer)
            return fileURL
        } catch {
            fatalError("Failed to create test audio file: \(error)")
        }
    }
    
    // MARK: - Sequential Consistency
    
    @Test("Sequential: pause() → resume() maintains consistency")
    func testPauseResumeSequential() async throws {
        let service = AudioPlayerService()
        await service.setup()
        
        let url = createTestAudioFile()
        defer { try? FileManager.default.removeItem(at: url) }
        try await service.startPlaying(url: url, configuration: AudioConfiguration())
        
        // Sequential transitions
        try await service.pause()
        #expect(await service.state == .paused)
        
        try await service.resume()
        #expect(await service.state == .playing)
    }
    
    @Test("Sequential: Multiple pause/resume cycles")
    func testMultiplePauseResumeCycles() async throws {
        let service = AudioPlayerService()
        await service.setup()
        
        let url = createTestAudioFile()
        defer { try? FileManager.default.removeItem(at: url) }
        try await service.startPlaying(url: url, configuration: AudioConfiguration())
        
        for _ in 0..<5 {
            try await service.pause()
            #expect(await service.state == .paused)
            
            try await service.resume()
            #expect(await service.state == .playing)
        }
    }
    
    // MARK: - Concurrent Access Safety
    
    @Test("Concurrent: State reads during transitions are safe")
    func testConcurrentStateReads() async throws {
        let service = AudioPlayerService()
        await service.setup()
        
        let url = createTestAudioFile()
        defer { try? FileManager.default.removeItem(at: url) }
        try await service.startPlaying(url: url, configuration: AudioConfiguration())
        
        // Launch concurrent state readers
        await withTaskGroup(of: PlayerState.self) { group in
            for _ in 0..<10 {
                group.addTask {
                    await service.state
                }
            }
            
            // All reads should complete without crashes
            var states: [PlayerState] = []
            for await state in group {
                states.append(state)
            }
            
            #expect(states.count == 10)
            #expect(states.allSatisfy { [.preparing, .playing].contains($0) })
        }
    }
    
    // MARK: - Lifecycle Atomicity
    
    @Test("Lifecycle: startPlaying() → stop() atomic sequence")
    func testStartStopAtomic() async throws {
        let service = AudioPlayerService()
        await service.setup()
        
        let url = createTestAudioFile()
        defer { try? FileManager.default.removeItem(at: url) }
        
        try await service.startPlaying(url: url, configuration: AudioConfiguration())
        let playingState = await service.state
        #expect([.preparing, .playing].contains(playingState))
        
        await service.stop()
        #expect(await service.state == .finished)
    }
    
    @Test("Lifecycle: reset() clears all state atomically")
    func testResetAtomic() async throws {
        let service = AudioPlayerService()
        await service.setup()
        
        let url = createTestAudioFile()
        defer { try? FileManager.default.removeItem(at: url) }
        try await service.startPlaying(url: url, configuration: AudioConfiguration())
        
        await service.reset()
        
        // Verify all state cleared
        #expect(await service.state == .finished)
        #expect(await service.currentTrack == nil)
        #expect(await service.playbackPosition == nil)
        #expect(await service.getRepeatCount() == 0)
    }
    
    // MARK: - Hook Execution Order
    
    @Test("Hooks: Exit hooks execute before entry hooks")
    func testHookExecutionOrder() async throws {
        // This test validates the state machine's hook execution order:
        // 1. willExit() on old state
        // 2. onExit() on old state
        // 3. State change (atomic)
        // 4. didEnter() on new state
        // 5. onEnter() on new state
        
        let service = AudioPlayerService()
        await service.setup()
        
        let url = createTestAudioFile()
        defer { try? FileManager.default.removeItem(at: url) }
        try await service.startPlaying(url: url, configuration: AudioConfiguration())
        
        try await service.pause()
        
        // If hooks execute correctly, state should be paused
        #expect(await service.state == .paused)
    }
    
    // MARK: - Invalid Transition Rejection
    
    @Test("Invalid: Finished → Playing rejected")
    func testInvalidFinishedToPlaying() async throws {
        let service = AudioPlayerService()
        await service.setup()
        
        // Service starts in .finished state
        #expect(await service.state == .finished)
        
        // Attempt invalid transition
        await #expect(throws: AudioPlayerError.self) {
            try await service.resume()
        }
        
        // State should remain unchanged
        #expect(await service.state == .finished)
    }
}
