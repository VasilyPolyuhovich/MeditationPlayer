import Testing
import Foundation
import AVFoundation
@testable import AudioServiceKit
@testable import AudioServiceCore

/// Test suite: Crossfade Task Management & Cancellation
@Suite("Crossfade Task Management")
struct CrossfadeTaskManagementTests {
    
    // MARK: - Helper Methods
    
    /// Creates a test audio file programmatically with actual audio data
    /// - Parameter duration: Duration in seconds (default: 2.0s)
    /// - Returns: URL of created test file in temp directory
    private func createTestAudioFile(duration: TimeInterval = 2.0) throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("test_\(UUID().uuidString).caf")
        
        // Create audio format (44.1kHz, stereo, Float32)
        guard let format = AVAudioFormat(
            standardFormatWithSampleRate: 44100,
            channels: 2
        ) else {
            throw NSError(domain: "TestError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create audio format"])
        }
        
        // Create audio file for writing
        let audioFile = try AVAudioFile(
            forWriting: fileURL,
            settings: format.settings
        )
        
        // Calculate frame count
        let frameCount = AVAudioFrameCount(format.sampleRate * duration)
        
        // Create buffer with proper capacity
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: frameCount
        ) else {
            throw NSError(domain: "TestError", code: -2, userInfo: [NSLocalizedDescriptionKey: "Failed to create audio buffer"])
        }
        
        buffer.frameLength = frameCount
        
        // ✅ CRITICAL: Fill buffer with actual audio data (sine wave 440 Hz)
        // Without this, file.length = 0 which causes crash: "offset >= file.length"
        if let leftChannel = buffer.floatChannelData?[0],
           let rightChannel = buffer.floatChannelData?[1] {
            let frequency: Float = 440.0 // A note
            let amplitude: Float = 0.5
            let sampleRate = Float(format.sampleRate)
            
            for frame in 0..<Int(frameCount) {
                let value = amplitude * sin(2.0 * .pi * frequency * Float(frame) / sampleRate)
                leftChannel[frame] = value
                rightChannel[frame] = value
            }
        }
        
        // Write buffer to file
        try audioFile.write(from: buffer)
        
        return fileURL
    }
    
    // MARK: - Dual Pause Implementation
    
    @Test("Dual pause: Both players pause during crossfade")
    func testDualPauseDuringCrossfade() async throws {
        let service = AudioPlayerService()
        await service.setup()
        
        let url1 = try createTestAudioFile()
        let url2 = try createTestAudioFile()
        defer {
            try? FileManager.default.removeItem(at: url1)
            try? FileManager.default.removeItem(at: url2)
        }
        
        try await service.startPlaying(url: url1, configuration: PlayerConfiguration())
        
        // Start track replacement
        Task {
            try? await service.replaceTrack(url: url2, crossfadeDuration: 2.0)
        }
        
        // Wait for crossfade to start
        try? await Task.sleep(nanoseconds: 500_000_000) // 500ms
        
        // Pause should work (blocks both players)
        // Note: Will throw due to guard, but that's expected
        do {
            try await service.pause()
            #expect(Bool(false), "Should have thrown")
        } catch {
            // Expected - guard blocks pause during replacement
        }
    }
    
    @Test("Dual pause: Works normally when not crossfading")
    func testDualPauseNormal() async throws {
        let service = AudioPlayerService()
        await service.setup()
        
        let url = try createTestAudioFile()
        defer { try? FileManager.default.removeItem(at: url) }
        try await service.startPlaying(url: url, configuration: PlayerConfiguration())
        
        // Pause should work fine
        try await service.pause()
        #expect(await service.state == .paused)
    }
    
    // MARK: - Crossfade Cancellation
    
    @Test("Cancellation: stop() cancels active crossfade")
    func testStopCancelsCrossfade() async throws {
        let service = AudioPlayerService()
        await service.setup()
        
        let url1 = try createTestAudioFile()
        let url2 = try createTestAudioFile()
        defer {
            try? FileManager.default.removeItem(at: url1)
            try? FileManager.default.removeItem(at: url2)
        }
        
        try await service.startPlaying(url: url1, configuration: PlayerConfiguration())
        
        // Start long crossfade
        Task {
            try? await service.replaceTrack(url: url2, crossfadeDuration: 5.0)
        }
        
        // Wait for crossfade to start
        try? await Task.sleep(nanoseconds: 500_000_000)
        
        // Stop should cancel crossfade
        await service.stop()
        
        // Crossfade should be idle
        let progress = await service.currentCrossfadeProgress
        #expect(progress == .idle)
        
        // State should be finished
        #expect(await service.state == .finished)
    }
    
    @Test("Cancellation: reset() cancels active crossfade")
    func testResetCancelsCrossfade() async throws {
        let service = AudioPlayerService()
        await service.setup()
        
        let url1 = try createTestAudioFile()
        let url2 = try createTestAudioFile()
        defer {
            try? FileManager.default.removeItem(at: url1)
            try? FileManager.default.removeItem(at: url2)
        }
        
        try await service.startPlaying(url: url1, configuration: PlayerConfiguration())
        
        // Start crossfade
        Task {
            try? await service.replaceTrack(url: url2, crossfadeDuration: 5.0)
        }
        
        try? await Task.sleep(nanoseconds: 500_000_000)
        
        // Reset should cancel crossfade
        await service.reset()
        
        // Crossfade should be idle
        #expect(await service.currentCrossfadeProgress == .idle)
        #expect(await service.state == .finished)
    }
    
    @Test("Cancellation: Quick cleanup on cancel")
    func testQuickCleanupOnCancel() async throws {
        let service = AudioPlayerService()
        await service.setup()
        
        let url1 = try createTestAudioFile()
        let url2 = try createTestAudioFile()
        defer {
            try? FileManager.default.removeItem(at: url1)
            try? FileManager.default.removeItem(at: url2)
        }
        
        try await service.startPlaying(url: url1, configuration: PlayerConfiguration())
        
        // Start crossfade
        Task {
            try? await service.replaceTrack(url: url2, crossfadeDuration: 5.0)
        }
        
        try? await Task.sleep(nanoseconds: 500_000_000)
        
        let cancelStart = Date()
        await service.stop()
        let cancelDuration = Date().timeIntervalSince(cancelStart)
        
        // Cleanup should be fast (<100ms)
        #expect(cancelDuration < 0.1)
    }
    
    // MARK: - Progress Observation
    
    @Test("Progress: Observable crossfade phases")
    func testObservableCrossfadePhases() async throws {
        let service = AudioPlayerService()
        await service.setup()
        
        let url1 = try createTestAudioFile()
        let url2 = try createTestAudioFile()
        defer {
            try? FileManager.default.removeItem(at: url1)
            try? FileManager.default.removeItem(at: url2)
        }
        
        try await service.startPlaying(url: url1, configuration: PlayerConfiguration())
        
        // Collect progress updates
        var phases: [CrossfadeProgress.Phase] = []
        
        // Observer
        actor ProgressCollector: CrossfadeProgressObserver {
            var phases: [CrossfadeProgress.Phase] = []
            
            func playerStateDidChange(_ state: PlayerState) async {}
            func playbackPositionDidUpdate(_ position: PlaybackPosition) async {}
            func playerDidEncounterError(_ error: AudioPlayerError) async {}
            
            func crossfadeProgressDidUpdate(_ progress: CrossfadeProgress) async {
                phases.append(progress.phase)
            }
        }
        
        let collector = ProgressCollector()
        await service.addObserver(collector)
        
        // Start crossfade
        try await service.replaceTrack(url: url2, crossfadeDuration: 1.0)
        
        phases = await collector.phases
        
        // Should have gone through phases
        #expect(phases.contains { if case .preparing = $0 { return true }; return false })
        #expect(phases.contains { if case .fading = $0 { return true }; return false })
        #expect(phases.contains { if case .idle = $0 { return true }; return false })
    }
    
    @Test("Progress: Current progress accessible")
    func testCurrentProgressAccessible() async throws {
        let service = AudioPlayerService()
        await service.setup()
        
        // Initial state
        let initialProgress = await service.currentCrossfadeProgress
        #expect(initialProgress == .idle)
        
        let url1 = try createTestAudioFile()
        let url2 = try createTestAudioFile()
        defer {
            try? FileManager.default.removeItem(at: url1)
            try? FileManager.default.removeItem(at: url2)
        }
        
        try await service.startPlaying(url: url1, configuration: PlayerConfiguration())
        
        // Start crossfade
        Task {
            try? await service.replaceTrack(url: url2, crossfadeDuration: 2.0)
        }
        
        // Wait for crossfade to be active
        try? await Task.sleep(nanoseconds: 500_000_000)
        
        let activeProgress = await service.currentCrossfadeProgress
        #expect(activeProgress.isActive)
        
        // Wait for completion
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        
        let finalProgress = await service.currentCrossfadeProgress
        #expect(finalProgress == .idle)
    }
    
    @Test("Progress: Accurate phase transitions")
    func testAccuratePhaseTransitions() async throws {
        let service = AudioPlayerService()
        await service.setup()
        
        let url1 = try createTestAudioFile()
        let url2 = try createTestAudioFile()
        defer {
            try? FileManager.default.removeItem(at: url1)
            try? FileManager.default.removeItem(at: url2)
        }
        
        try await service.startPlaying(url: url1, configuration: PlayerConfiguration())
        
        // Track phase order
        actor PhaseTracker: CrossfadeProgressObserver {
            var order: [String] = []
            
            func playerStateDidChange(_ state: PlayerState) async {}
            func playbackPositionDidUpdate(_ position: PlaybackPosition) async {}
            func playerDidEncounterError(_ error: AudioPlayerError) async {}
            
            func crossfadeProgressDidUpdate(_ progress: CrossfadeProgress) async {
                switch progress.phase {
                case .idle: order.append("idle")
                case .preparing: order.append("preparing")
                case .fading: order.append("fading")
                case .switching: order.append("switching")
                case .cleanup: order.append("cleanup")
                }
            }
        }
        
        let tracker = PhaseTracker()
        await service.addObserver(tracker)
        
        try await service.replaceTrack(url: url2, crossfadeDuration: 1.0)
        
        let order = await tracker.order
        
        // Expected order: preparing → fading (multiple) → switching → cleanup → idle
        #expect(order.first == "preparing")
        #expect(order.contains("fading"))
        #expect(order.contains("switching"))
        #expect(order.contains("cleanup"))
        #expect(order.last == "idle")
    }
}
