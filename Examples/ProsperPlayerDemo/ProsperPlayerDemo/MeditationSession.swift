//
//  MeditationSession.swift
//  ProsperPlayerDemo
//
//  Meditation session state management using @Observable
//

import SwiftUI
import AudioServiceKit
import AudioServiceCore

@MainActor
@Observable
final class MeditationSession {

    // MARK: - State

    var currentStage: Stage = .idle
    var playbackState: PlayerState = .finished
    var currentTrackInfo: String = "No track loaded"
    var isOverlayPlaying: Bool = false
    var errorMessage: String?

    enum Stage: String {
        case idle = "Ready"
        case stage1 = "Stage 1: Introduction (5 min)"
        case stage2 = "Stage 2: Practice (20 min)"
        case stage3 = "Stage 3: Closing (5 min)"
        case finished = "Session Complete"
    }

    // MARK: - Dependencies

    private var audioService: AudioPlayerService!

    // Test tracks (will be loaded from bundle)
    private var stage1Music: Track?
    private var stage2Music: Track?
    private var stage3Music: Track?
    private var voiceOverlay: Track?
    
    // Sound effects
    private var gongEffect: SoundEffect?
    private var beepEffect: SoundEffect?

    // MARK: - Initialization

    init(crossfadeDuration: Double = 5.0, volume: Float = 0.8) {
        // Load test resources
        loadTestResources()
        
        // Initialize audio service asynchronously
        Task { @MainActor in
            let config = PlayerConfiguration(
                crossfadeDuration: crossfadeDuration,
                repeatCount: nil,
                volume: volume
            )
            
            do {
                self.audioService = try await AudioPlayerService(configuration: config)
            } catch {
                self.errorMessage = "Failed to initialize audio service: \(error.localizedDescription)"
            }
        }
    }
    
    // Update configuration
    func updateConfiguration(crossfadeDuration: Double, volume: Float) async {
        let newConfig = PlayerConfiguration(
            crossfadeDuration: crossfadeDuration,
            repeatCount: nil,
            volume: volume
        )
        
        try? await audioService.updateConfiguration(newConfig)
    }

    // MARK: - Actions

    func startSession() async {
        guard let track1 = stage1Music, let track2 = stage2Music, let track3 = stage3Music else {
            errorMessage = "Audio files not found"
            return
        }

        currentStage = .stage1

        do {
            try await audioService.loadPlaylist([track1, track2, track3])
            try await audioService.startPlaying(fadeDuration: 2.0)
            playbackState = await audioService.state
            await updateTrackInfo()
        } catch {
            errorMessage = "Failed to start: \(error.localizedDescription)"
        }
    }

    func nextStage() async {
        switch currentStage {
        case .idle, .stage1:
            await transitionToStage2()
        case .stage2:
            await transitionToStage3()
        case .stage3, .finished:
            await finishSession()
        }
    }

    func togglePlayPause() async {
        do {
            if playbackState == .playing {
                try await audioService.pause()
            } else if playbackState == .paused {
                try await audioService.resume()
            }
            playbackState = await audioService.state
        } catch {
            errorMessage = "Playback error: \(error.localizedDescription)"
        }
    }

    func toggleOverlay() async {
        guard let overlay = voiceOverlay else { return }

        if isOverlayPlaying {
            await audioService.stopOverlay()
            isOverlayPlaying = false
        } else {
            do {
                try await audioService.playOverlay(overlay)
                isOverlayPlaying = true
            } catch {
                errorMessage = "Overlay error: \(error.localizedDescription)"
            }
        }
    }

    func stopSession() async {
        await audioService.stop()
        currentStage = .idle
        playbackState = .finished
        currentTrackInfo = "Session stopped"
        isOverlayPlaying = false
    }
    
    func playGong() async {
        guard let gong = gongEffect else { return }
        await audioService.playSoundEffect(gong)
    }
    
    func playBeep() async {
        guard let beep = beepEffect else { return }
        await audioService.playSoundEffect(beep)
    }

    // MARK: - Private Helpers

    private func transitionToStage2() async {
        currentStage = .stage2

        do {
            try await audioService.skipToNext()
            await updateTrackInfo()
        } catch {
            errorMessage = "Transition error: \(error.localizedDescription)"
        }
    }

    private func transitionToStage3() async {
        currentStage = .stage3

        do {
            try await audioService.skipToNext()
            await updateTrackInfo()
        } catch {
            errorMessage = "Transition error: \(error.localizedDescription)"
        }
    }

    private func finishSession() async {
        do {
            try await audioService.finish(fadeDuration: 3.0)
            currentStage = .finished
            playbackState = .finished
            currentTrackInfo = "Session complete"
        } catch {
            errorMessage = "Finish error: \(error.localizedDescription)"
        }
    }

    private func updateTrackInfo() async {
        if let track = await audioService.currentTrack {
            if let title = track.title {
                currentTrackInfo = title
            } else {
                // Fallback - можна витягнути з URL якщо треба
                currentTrackInfo = "Track"
            }
        }
    }

    private func loadTestResources() {
        // Try to load audio files from bundle (Track init is sync)
        if let url1 = Bundle.main.url(forResource: "stage1_intro_music", withExtension: "mp3") {
            stage1Music = Track(url: url1)
        }
        if let url2 = Bundle.main.url(forResource: "stage2_practice_music", withExtension: "mp3") {
            stage2Music = Track(url: url2)
        }
        if let url3 = Bundle.main.url(forResource: "stage3_closing_music", withExtension: "mp3") {
            stage3Music = Track(url: url3)
        }
        if let voiceUrl = Bundle.main.url(forResource: "breathing_exercise", withExtension: "mp3") {
            voiceOverlay = Track(url: voiceUrl)
        }
        
        // Load sound effects asynchronously (SoundEffect init is async throws)
        Task { @MainActor in
            if let gongUrl = Bundle.main.url(forResource: "gong", withExtension: "mp3") {
                self.gongEffect = try? await SoundEffect(url: gongUrl)
            }
            if let beepUrl = Bundle.main.url(forResource: "beep", withExtension: "mp3") {
                self.beepEffect = try? await SoundEffect(url: beepUrl)
            }
        }
    }
}
