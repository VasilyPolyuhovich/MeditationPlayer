import XCTest
@testable import AudioServiceKit
@testable import AudioServiceCore

/// Tests for loop crossfade functionality
final class LoopCrossfadeTests: XCTestCase {
    
    var audioService: AudioPlayerService!
    
    override func setUp() async throws {
        audioService = AudioPlayerService()
        await audioService.setup()
    }
    
    override func tearDown() async throws {
        await audioService.stop()
        audioService = nil
    }
    
    // MARK: - Basic Loop Tests
    
    func testLoopIsEnabledByDefault() {
        let config = AudioConfiguration()
        XCTAssertTrue(config.enableLooping, "Looping should be enabled by default")
    }
    
    func testLoopCanBeDisabled() {
        let config = AudioConfiguration(enableLooping: false)
        XCTAssertFalse(config.enableLooping, "Looping should be disabled when configured")
    }
    
    func testRepeatCountStartsAtZero() async {
        let count = await audioService.getRepeatCount()
        XCTAssertEqual(count, 0, "Repeat count should start at 0")
    }
    
    // MARK: - Crossfade Timing Tests
    
    func testCrossfadeDurationValidation() throws {
        // Valid range: 1-30 seconds
        let validConfig = AudioConfiguration(crossfadeDuration: 10.0)
        XCTAssertNoThrow(try validConfig.validate())
        
        // Auto-clamped to valid range
        let tooShort = AudioConfiguration(crossfadeDuration: 0.5)
        XCTAssertEqual(tooShort.crossfadeDuration, 1.0, "Should clamp to 1.0")
        
        let tooLong = AudioConfiguration(crossfadeDuration: 50.0)
        XCTAssertEqual(tooLong.crossfadeDuration, 30.0, "Should clamp to 30.0")
    }
    
    func testCrossfadeTriggerPoint() async throws {
        // For 30s track with 10s crossfade, should trigger at 20s
        let config = AudioConfiguration(
            crossfadeDuration: 10.0,
            enableLooping: true
        )
        
        // Mock audio file (30 seconds)
        let testURL = createTestAudioFile(duration: 30.0)
        
        try await audioService.startPlaying(url: testURL, configuration: config)
        
        // Monitor position
        var crossfadeDetected = false
        let expectation = XCTestExpectation(description: "Crossfade triggered")
        
        // Check every 0.5s for crossfade trigger
        let timer = Task {
            for _ in 0..<60 {  // 30 seconds max
                try? await Task.sleep(nanoseconds: 500_000_000)
                
                // Get position (extract value before MainActor)
                let position = await audioService.playbackPosition
                guard let pos = position else { continue }
                
                // Check if in crossfade zone (last 10 seconds)
                let triggerPoint = pos.duration - 10.0
                if pos.currentTime >= triggerPoint {
                    crossfadeDetected = true
                    expectation.fulfill()
                    break
                }
            }
        }
        
        await fulfillment(of: [expectation], timeout: 35.0)
        timer.cancel()
        
        XCTAssertTrue(crossfadeDetected, "Crossfade should trigger at correct time")
    }
    
    // MARK: - Repeat Count Tests
    
    func testRepeatCountIncrementsAfterLoop() async throws {
        let config = AudioConfiguration(
            crossfadeDuration: 2.0,
            enableLooping: true,
            repeatCount: nil  // Infinite
        )
        
        // Use very short audio file for fast testing (5 seconds)
        let testURL = createTestAudioFile(duration: 5.0)
        
        try await audioService.startPlaying(url: testURL, configuration: config)
        
        // Wait for first loop to complete (5s + 2s buffer = 7s)
        try await Task.sleep(nanoseconds: 7_000_000_000)
        
        let count = await audioService.getRepeatCount()
        XCTAssertGreaterThanOrEqual(count, 1, "Should complete at least 1 loop")
    }
    
    func testStopsAfterMaxRepeats() async throws {
        let config = AudioConfiguration(
            crossfadeDuration: 1.0,
            enableLooping: true,
            repeatCount: 2  // Stop after 2 loops
        )
        
        let testURL = createTestAudioFile(duration: 3.0)
        
        try await audioService.startPlaying(url: testURL, configuration: config)
        
        // Wait for 2 loops to complete (3s * 2 + buffer = 8s)
        try await Task.sleep(nanoseconds: 8_000_000_000)
        
        let state = await audioService.state
        let count = await audioService.getRepeatCount()
        
        XCTAssertEqual(count, 2, "Should have completed 2 loops")
        // State should be finishing or finished
        XCTAssertTrue(
            state == .fadingOut || state == .finished,
            "Should be stopping after max repeats"
        )
    }
    
    // MARK: - Fade Curve Tests
    
    func testAllFadeCurvesWork() async throws {
        let curves: [FadeCurve] = [
            .linear,
            .equalPower,
            .logarithmic,
            .exponential,
            .sCurve
        ]
        
        for curve in curves {
            let config = AudioConfiguration(
                crossfadeDuration: 2.0,
                enableLooping: true,
                fadeCurve: curve
            )
            
            let testURL = createTestAudioFile(duration: 5.0)
            
            // Should not crash with any curve
            XCTAssertNoThrow(
                try await audioService.startPlaying(url: testURL, configuration: config),
                "Fade curve \(curve) should work"
            )
            
            await audioService.stop()
            
            // Small delay between tests
            try await Task.sleep(nanoseconds: 100_000_000)
        }
    }
    
    func testEqualPowerCurveMaintainsConstantPower() {
        let curve = FadeCurve.equalPower
        
        // Test at various progress points
        let testPoints: [Float] = [0.0, 0.25, 0.5, 0.75, 1.0]
        
        for progress in testPoints {
            let fadeIn = curve.volume(for: progress)
            let fadeOut = curve.inverseVolume(for: progress)
            
            // Equal-power property: sin²θ + cos²θ = 1
            let totalPower = fadeIn * fadeIn + fadeOut * fadeOut
            
            XCTAssertEqual(
                totalPower,
                1.0,
                accuracy: 0.001,
                "Equal-power should maintain constant power at \(progress)"
            )
        }
    }
    
    // MARK: - State Machine Tests
    
    func testLoopPreservesPlayingState() async throws {
        let config = AudioConfiguration(
            crossfadeDuration: 1.0,
            enableLooping: true
        )
        
        let testURL = createTestAudioFile(duration: 3.0)
        
        try await audioService.startPlaying(url: testURL, configuration: config)
        
        // Wait for loop to happen
        try await Task.sleep(nanoseconds: 4_000_000_000)
        
        let state = await audioService.state
        XCTAssertEqual(state, .playing, "Should remain in playing state during loop")
    }
    
    func testLoopResetOnStop() async throws {
        let config = AudioConfiguration(enableLooping: true)
        let testURL = createTestAudioFile(duration: 5.0)
        
        try await audioService.startPlaying(url: testURL, configuration: config)
        
        // Wait for partial playback
        try await Task.sleep(nanoseconds: 2_000_000_000)
        
        await audioService.stop()
        
        let count = await audioService.getRepeatCount()
        XCTAssertEqual(count, 0, "Repeat count should reset on stop")
    }
    
    // MARK: - Integration Tests
    
    func testPauseDuringCrossfade() async throws {
        let config = AudioConfiguration(
            crossfadeDuration: 3.0,
            enableLooping: true
        )
        
        let testURL = createTestAudioFile(duration: 10.0)
        
        try await audioService.startPlaying(url: testURL, configuration: config)
        
        // Wait until crossfade zone (7s into 10s track)
        try await Task.sleep(nanoseconds: 7_500_000_000)
        
        // Pause during crossfade
        try await audioService.pause()
        
        let state = await audioService.state
        XCTAssertEqual(state, .paused, "Should be able to pause during crossfade")
        
        // Resume should work
        try await audioService.resume()
        
        let resumedState = await audioService.state
        XCTAssertEqual(resumedState, .playing, "Should resume after pause")
    }
    
    func testVolumeControlDuringLoop() async throws {
        let config = AudioConfiguration(
            crossfadeDuration: 2.0,
            enableLooping: true
        )
        
        let testURL = createTestAudioFile(duration: 5.0)
        
        try await audioService.startPlaying(url: testURL, configuration: config)
        
        // Change volume during playback
        await audioService.setVolume(0.5)
        
        // Wait for loop
        try await Task.sleep(nanoseconds: 6_000_000_000)
        
        // Volume should persist through loop
        // (We can't directly test volume, but ensuring no crash is valuable)
        let state = await audioService.state
        XCTAssertEqual(state, .playing, "Should continue playing after volume change")
    }
    
    // MARK: - Helper Methods
    
    private func createTestAudioFile(duration: TimeInterval) -> URL {
        // In real tests, you would:
        // 1. Use a pre-recorded test audio file from test bundle
        // 2. Or generate a simple sine wave programmatically
        
        // For this example, returning a bundle resource path
        let bundle = Bundle.module
        guard let url = bundle.url(
            forResource: "test-audio-\(Int(duration))s",
            withExtension: "mp3"
        ) else {
            fatalError("Test audio file not found")
        }
        return url
    }
}

// MARK: - Performance Tests

final class LoopCrossfadePerformanceTests: XCTestCase {
    
    func testCrossfadePerformance() async throws {
        let service = AudioPlayerService()
        await service.setup()
        
        let config = AudioConfiguration(
            crossfadeDuration: 10.0,
            enableLooping: true
        )
        
        let testURL = URL(fileURLWithPath: "/path/to/test-audio.mp3")
        
        measure {
            // Measure crossfade calculation time
            let expectation = XCTestExpectation(description: "Crossfade complete")
            
            Task {
                try? await service.startPlaying(url: testURL, configuration: config)
                
                // Wait for one complete loop
                try? await Task.sleep(nanoseconds: 35_000_000_000)
                
                await service.stop()
                expectation.fulfill()
            }
            
            wait(for: [expectation], timeout: 40.0)
        }
    }
    
    func testMemoryStabilityDuringLoops() async throws {
        let service = AudioPlayerService()
        await service.setup()
        
        let config = AudioConfiguration(
            crossfadeDuration: 2.0,
            enableLooping: true,
            repeatCount: 10  // 10 loops
        )
        
        let testURL = URL(fileURLWithPath: "/path/to/test-audio.mp3")
        
        // Measure memory before
        let memoryBefore = getMemoryUsage()
        
        try await service.startPlaying(url: testURL, configuration: config)
        
        // Wait for all loops to complete
        try await Task.sleep(nanoseconds: 30_000_000_000)
        
        // Measure memory after
        let memoryAfter = getMemoryUsage()
        
        // Memory should not increase significantly (< 10 MB)
        let memoryIncrease = memoryAfter - memoryBefore
        XCTAssertLessThan(
            memoryIncrease,
            10_000_000,  // 10 MB
            "Memory should remain stable during loops"
        )
    }
    
    private func getMemoryUsage() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4
        
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(
                    mach_task_self_,
                    task_flavor_t(MACH_TASK_BASIC_INFO),
                    $0,
                    &count
                )
            }
        }
        
        guard kerr == KERN_SUCCESS else { return 0 }
        return info.resident_size
    }
}
