import Testing
import Foundation
import AVFoundation
@testable import AudioServiceKit
@testable import AudioServiceCore

/// Test suite: Bug #12 - Crossfade + Pause Race Condition (v2.8.0)
/// Root cause: v2.8.0 SSOT refactor removed critical state restoration
@Suite("Bug #12: Crossfade + Pause Race Regression")
struct Bug12CrossfadePauseRaceTests {
    
    // MARK: - Helper Methods
    
    private func createTestAudioFile() -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("test_\(UUID().uuidString).caf")
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
        
        do {
            let audioFile = try AVAudioFile(forWriting: fileURL, settings: format.settings)
            let frameCount = AVAudioFrameCount(44100 * 2.0) // 2 seconds
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
            buffer.frameLength = frameCount
            try audioFile.write(from: buffer)
            return fileURL
        } catch {
            fatalError("Failed to create test audio file: \(error)")
        }
    }
    
    // MARK: - Bug #12 Validation
    
    @Test("Bug #12: Pause blocked during track replacement")
    func testPauseBlockedDuringReplacement() async throws {
        let service = AudioPlayerService()
        await service.setup()
        
        let url1 = createTestAudioFile()
        let url2 = createTestAudioFile()
        defer {
            try? FileManager.default.removeItem(at: url1)
            try? FileManager.default.removeItem(at: url2)
        }
        
        try await service.startPlaying(url: url1, configuration: AudioConfiguration())
        
        // Launch concurrent track replacement
        Task {
            try? await service.replaceTrack(url: url2, crossfadeDuration: 2.0)
        }
        
        // Attempt pause during crossfade
        try? await Task.sleep(nanoseconds: 500_000_000) // 500ms into crossfade
        
        await #expect(throws: AudioPlayerError.self) {
            try await service.pause()
        }
    }
    
    @Test("Bug #12: Resume blocked during track replacement")
    func testResumeBlockedDuringReplacement() async throws {
        let service = AudioPlayerService()
        await service.setup()
        
        let url1 = createTestAudioFile()
        let url2 = createTestAudioFile()
        defer {
            try? FileManager.default.removeItem(at: url1)
            try? FileManager.default.removeItem(at: url2)
        }
        
        try await service.startPlaying(url: url1, configuration: AudioConfiguration())
        try await service.pause()
        
        // Launch track replacement while paused
        Task {
            try? await service.replaceTrack(url: url2, crossfadeDuration: 2.0)
        }
        
        // Attempt resume during replacement
        try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
        
        await #expect(throws: AudioPlayerError.self) {
            try await service.resume()
        }
    }
    
    @Test("Bug #12: State restored to playing after crossfade")
    func testStateRestoredAfterCrossfade() async throws {
        let service = AudioPlayerService()
        await service.setup()
        
        let url1 = createTestAudioFile()
        let url2 = createTestAudioFile()
        defer {
            try? FileManager.default.removeItem(at: url1)
            try? FileManager.default.removeItem(at: url2)
        }
        
        try await service.startPlaying(url: url1, configuration: AudioConfiguration())
        #expect(await service.state == .playing)
        
        // Replace with short crossfade
        try await service.replaceTrack(url: url2, crossfadeDuration: 1.0)
        
        // State should be playing after crossfade
        #expect(await service.state == .playing)
    }
    
    @Test("Bug #12: Track replacement flag cleared after completion")
    func testReplacementFlagClearedAfterCompletion() async throws {
        let service = AudioPlayerService()
        await service.setup()
        
        let url1 = createTestAudioFile()
        let url2 = createTestAudioFile()
        defer {
            try? FileManager.default.removeItem(at: url1)
            try? FileManager.default.removeItem(at: url2)
        }
        
        try await service.startPlaying(url: url1, configuration: AudioConfiguration())
        try await service.replaceTrack(url: url2, crossfadeDuration: 1.0)
        
        // After completion, pause should work
        try await service.pause()
        #expect(await service.state == .paused)
    }
    
    @Test("Bug #12: Replacement flag cleared on stop")
    func testReplacementFlagClearedOnStop() async throws {
        let service = AudioPlayerService()
        await service.setup()
        
        let url1 = createTestAudioFile()
        let url2 = createTestAudioFile()
        defer {
            try? FileManager.default.removeItem(at: url1)
            try? FileManager.default.removeItem(at: url2)
        }
        
        try await service.startPlaying(url: url1, configuration: AudioConfiguration())
        
        // Launch replacement
        Task {
            try? await service.replaceTrack(
                url: url2,
                crossfadeDuration: 5.0
            )
        }
        
        try? await Task.sleep(nanoseconds: 500_000_000)
        
        // Stop should clear flag
        await service.stop()
        
        // New playback should work
        try await service.startPlaying(url: url1, configuration: AudioConfiguration())
        #expect(await service.state == .playing)
    }
    
    @Test("Bug #12: Replacement flag cleared on reset")
    func testReplacementFlagClearedOnReset() async throws {
        let service = AudioPlayerService()
        await service.setup()
        
        let url1 = createTestAudioFile()
        let url2 = createTestAudioFile()
        defer {
            try? FileManager.default.removeItem(at: url1)
            try? FileManager.default.removeItem(at: url2)
        }
        
        try await service.startPlaying(url: url1, configuration: AudioConfiguration())
        
        // Launch replacement
        Task {
            try? await service.replaceTrack(
                url: url2,
                crossfadeDuration: 5.0
            )
        }
        
        try? await Task.sleep(nanoseconds: 500_000_000)
        
        // Reset should clear flag
        await service.reset()
        
        // New playback should work
        try await service.startPlaying(url: url1, configuration: AudioConfiguration())
        #expect(await service.state == .playing)
    }
}
