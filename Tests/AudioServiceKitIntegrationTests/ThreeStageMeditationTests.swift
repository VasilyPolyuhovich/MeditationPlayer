//
//  ThreeStageMeditationTests.swift
//  AudioServiceKitIntegrationTests
//
//  Real-world scenario: 30-minute meditation session
//

import XCTest
@testable import AudioServiceKit
@testable import AudioServiceCore

/// **Integration Test: 3-Stage Meditation Session**
///
/// **Real Use Case from REQUIREMENTS_ANSWERS.md:**
///
/// **Stage 1 (5 min):** Background music + voice overlay + countdown
/// **Stage 2 (20 min):** Different music + MANY overlay switches
/// **Stage 3 (5 min):** Calming music + voice + completion markers
///
/// **Critical Requirements:**
/// - Pause stability (TOP priority - daily morning routine)
/// - Overlay switches without interrupting main music
/// - Crossfade seamless loops (5-15s duration)
/// - Sound effects independent playback
final class ThreeStageMeditationTests: XCTestCase {
    
    var audioService: AudioPlayerService!
    
    // Test tracks
    var stage1Music: Track!
    var stage2Music: Track!
    var stage3Music: Track!
    
    var voiceInstruction1: Track!
    var voiceInstruction2: Track!
    var mantra1: Track!
    var mantra2: Track!
    var mantra3: Track!
    
    var gongSound: SoundEffect!
    var countdownBeep: SoundEffect!
    
    override func setUp() async throws {
        let config = PlayerConfiguration(
            crossfadeDuration: 5.0,
            repeatCount: nil,
            volume: 1.0
        )
        
        audioService = AudioPlayerService(configuration: config)
        
        // Load test audio files
        stage1Music = Track(url: Bundle.module.url(forResource: "stage1_intro_music", withExtension: "mp3")!)
        stage2Music = Track(url: Bundle.module.url(forResource: "stage2_practice_music", withExtension: "mp3")!)
        stage3Music = Track(url: Bundle.module.url(forResource: "stage3_closing_music", withExtension: "mp3")!)
        
        voiceInstruction1 = Track(url: Bundle.module.url(forResource: "breathing_exercise", withExtension: "mp3")!)
        voiceInstruction2 = Track(url: Bundle.module.url(forResource: "closing_guidance", withExtension: "mp3")!)
        
        mantra1 = Track(url: Bundle.module.url(forResource: "mantra_peace", withExtension: "mp3")!)
        mantra2 = Track(url: Bundle.module.url(forResource: "mantra_love", withExtension: "mp3")!)
        mantra3 = Track(url: Bundle.module.url(forResource: "mantra_gratitude", withExtension: "mp3")!)
        
        gongSound = SoundEffect(url: Bundle.module.url(forResource: "gong", withExtension: "mp3")!, volume: 0.8)
        countdownBeep = SoundEffect(url: Bundle.module.url(forResource: "beep", withExtension: "mp3")!, volume: 0.5)
    }
    
    override func tearDown() async throws {
        await audioService.stop()
        audioService = nil
    }
    
    // MARK: - Full Session Test
    
    /// **TEST: Complete 30-minute meditation (compressed to 30 seconds)**
    ///
    /// Simulates real session with time compression (10ms = 1s)
    func testFullMeditationSession_AllStages() async throws {
        // ═══════════════════════════════════════════
        // STAGE 1: Introduction (5 min → 5s)
        // ═══════════════════════════════════════════
        
        // 1. Start background music
        try await audioService.startPlaying(track: stage1Music)
        
        var state = await audioService.state
        XCTAssertEqual(state, .playing, "Stage 1 music should start")
        
        // 2. Play voice overlay (breathing instructions)
        try await audioService.playOverlay(voiceInstruction1)
        
        // 3. Countdown beeps (3, 2, 1)
        try await Task.sleep(for: .seconds(0.5))
        try await audioService.playSoundEffect(countdownBeep)
        try await Task.sleep(for: .seconds(0.5))
        try await audioService.playSoundEffect(countdownBeep)
        try await Task.sleep(for: .seconds(0.5))
        try await audioService.playSoundEffect(countdownBeep)
        
        // 4. Gong marks stage transition
        try await Task.sleep(for: .seconds(3.5)) // Complete stage 1
        try await audioService.playSoundEffect(gongSound)
        
        // ═══════════════════════════════════════════
        // STAGE 2: Main Practice (20 min → 10s)
        // ═══════════════════════════════════════════
        
        // 5. Crossfade to stage 2 music (5s crossfade)
        try await audioService.replaceCurrentTrack(stage2Music, fadeDuration: 5.0)
        
        // 6. CRITICAL: MANY overlay switches (Stage 2 requirement)
        // Simulate switching mantras without interrupting music
        try await Task.sleep(for: .seconds(1.0))
        try await audioService.playOverlay(mantra1)
        
        try await Task.sleep(for: .seconds(1.0))
        try await audioService.playOverlay(mantra2)
        
        try await Task.sleep(for: .seconds(1.0))
        try await audioService.playOverlay(mantra3)
        
        try await Task.sleep(for: .seconds(1.0))
        try await audioService.playOverlay(mantra1) // Repeat
        
        // 7. CRITICAL: Pause during stage 2 (high probability scenario)
        await audioService.pauseAll()
        
        state = await audioService.state
        XCTAssertEqual(state, .paused, "Should pause all players")
        
        // Simulate user pause duration
        try await Task.sleep(for: .seconds(2.0))
        
        // 8. Resume
        try await audioService.resumeAll()
        
        state = await audioService.state
        XCTAssertEqual(state, .playing, "Should resume seamlessly")
        
        // Continue stage 2
        try await Task.sleep(for: .seconds(2.0))
        
        // Transition marker
        try await audioService.playSoundEffect(gongSound)
        
        // ═══════════════════════════════════════════
        // STAGE 3: Closing (5 min → 5s)
        // ═══════════════════════════════════════════
        
        // 9. Crossfade to closing music
        try await audioService.replaceCurrentTrack(stage3Music, fadeDuration: 5.0)
        
        // 10. Play closing voice guidance
        try await Task.sleep(for: .seconds(1.0))
        try await audioService.playOverlay(voiceInstruction2)
        
        // 11. Completion marker (3 gongs)
        try await Task.sleep(for: .seconds(3.0))
        try await audioService.playSoundEffect(gongSound)
        try await Task.sleep(for: .seconds(0.5))
        try await audioService.playSoundEffect(gongSound)
        try await Task.sleep(for: .seconds(0.5))
        try await audioService.playSoundEffect(gongSound)
        
        // 12. Graceful finish (fade out 3s)
        try await audioService.finish(fadeDuration: 3.0)
        
        // Wait for fade out
        try await Task.sleep(for: .seconds(3.5))
        
        // ═══════════════════════════════════════════
        // VERIFICATION
        // ═══════════════════════════════════════════
        
        state = await audioService.state
        XCTAssertEqual(state, .finished, "Session should complete gracefully")
        
        // Verify no crashes, no audio glitches (manual listening test)
        print("✅ 3-stage meditation session completed successfully")
    }
    
    // MARK: - Individual Stage Tests
    
    /// **TEST: Stage 2 overlay switches without music interruption**
    ///
    /// Critical requirement: MANY switches during Stage 2
    func testStage2_FrequentOverlaySwitches() async throws {
        try await audioService.startPlaying(track: stage2Music)
        
        // Rapid overlay switches (10 times)
        for i in 1...10 {
            let mantra = [mantra1, mantra2, mantra3][i % 3]
            try await audioService.playOverlay(mantra)
            try await Task.sleep(for: .seconds(0.5))
        }
        
        // Verify music still playing
        let state = await audioService.state
        XCTAssertEqual(state, .playing, "Main music should continue uninterrupted")
    }
    
    /// **TEST: Pause stability during session**
    ///
    /// TOP priority requirement: pause must be rock-solid
    func testPauseStability_MultipleScenarios() async throws {
        try await audioService.startPlaying(track: stage1Music)
        
        // Scenario 1: Pause immediately after start
        try await Task.sleep(for: .seconds(0.5))
        await audioService.pause()
        try await Task.sleep(for: .seconds(1.0))
        try await audioService.resume()
        
        var state = await audioService.state
        XCTAssertEqual(state, .playing, "Resume should work after immediate pause")
        
        // Scenario 2: Pause during overlay playback
        try await audioService.playOverlay(voiceInstruction1)
        try await Task.sleep(for: .seconds(0.5))
        await audioService.pauseAll()
        try await Task.sleep(for: .seconds(1.0))
        try await audioService.resumeAll()
        
        state = await audioService.state
        XCTAssertEqual(state, .playing, "Resume should work with active overlay")
        
        // Scenario 3: Rapid pause/resume cycles
        for _ in 1...5 {
            await audioService.pause()
            try await Task.sleep(for: .seconds(0.2))
            try await audioService.resume()
            try await Task.sleep(for: .seconds(0.2))
        }
        
        state = await audioService.state
        XCTAssertEqual(state, .playing, "Should handle rapid pause/resume")
    }
    
    /// **TEST: Sound effects during crossfade**
    ///
    /// Verify sound effects play independently during transitions
    func testSoundEffects_DuringCrossfade() async throws {
        try await audioService.startPlaying(track: stage1Music)
        try await Task.sleep(for: .seconds(1.0))
        
        // Start crossfade
        Task {
            try? await audioService.replaceCurrentTrack(stage2Music, fadeDuration: 5.0)
        }
        
        // Play gong during crossfade
        try await Task.sleep(for: .seconds(2.5)) // Mid-crossfade
        try await audioService.playSoundEffect(gongSound)
        
        // Wait for crossfade completion
        try await Task.sleep(for: .seconds(3.0))
        
        // Verify success
        let state = await audioService.state
        XCTAssertEqual(state, .playing)
        
        let currentTrack = await audioService.currentTrack
        XCTAssertEqual(currentTrack?.metadata?.title, stage2Music.url.lastPathComponent)
    }
}
