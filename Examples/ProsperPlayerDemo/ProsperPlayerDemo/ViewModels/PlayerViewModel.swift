import SwiftUI
import AudioServiceCore
import AudioServiceKit

/// Main ViewModel - SDK showcase coordinator
@MainActor
@Observable
class PlayerViewModel: AudioPlayerObserver, CrossfadeProgressObserver {
    // MARK: - SDK Reference
    
    private let audioService: AudioPlayerService
    
    // MARK: - UI State
    
    var state: PlayerState = .finished
    var position: PlaybackPosition?
    var currentTrackIndex: Int = 0
    var currentPlaylistName: String = ""
    var errorMessage: String?
    
    // MARK: - Configuration
    
    var crossfadeDuration: TimeInterval = 10.0
    var selectedCurve: FadeCurve = .equalPower
    var repeatMode: RepeatMode = .off
    var volume: Float = 1.0
    
    // Volume Fade Settings
    var startFadeInDuration: TimeInterval = 0.0  // No fade-in by default
    var stopFadeOutDuration: TimeInterval = 3.0  // 3s fade-out by default
    
    // MARK: - Crossfade Tracking
    
    var crossfadeProgress: CrossfadeProgress?
    
    // MARK: - Overlay State
    
    var isOverlayPlaying: Bool = false
    var selectedOverlayTrack: String = "voiceover1"
    var overlayLoopEnabled: Bool = true  // Default: infinite loop
    var overlayLoopDelay: Double = 0.0  // Default: no delay
    var overlayVolume: Float = 0.5  // Default: 50%
    
    // MARK: - Sound Effects State
    
    var preloadedEffects: [SoundEffect] = []
    var currentEffect: SoundEffect?
    var isSoundEffectPlaying: Bool = false
    var soundEffectVolume: Float = 0.8  // Default: 80%
    
    // MARK: - Initialization
    
    init(audioService: AudioPlayerService) async {
        self.audioService = audioService
        await audioService.addObserver(self)
        await preloadSoundEffects()
    }
    
    // MARK: - Sound Effects Preload
    
    /// Preload sound effects on initialization
    private func preloadSoundEffects() async {
        var effects: [SoundEffect] = []
        
        // Preload all sound effects with base volume 1.0
        // (master volume controlled by player)
        for name in ["bell", "gong", "count_down"] {
            guard let url = trackURL(named: name) else {
                print("[WARNING] Sound effect '\(name).mp3' not found")
                continue
            }
            
            do {
                // Use volume 1.0 - master volume controlled by setSoundEffectVolume
                if let effect = try await SoundEffect(url: url, fadeIn: 0.0, fadeOut: 0.3, volume: 1.0) {
                    effects.append(effect)
                }
            } catch {
                print("[ERROR] Failed to load sound effect '\(name).mp3': \(error)")
            }
        }
        
        preloadedEffects = effects
        
        // Preload into audio service cache
        if !effects.isEmpty {
            await audioService.preloadSoundEffects(effects)
            print("[INFO] Preloaded \(effects.count) sound effects")
            
            // Set initial master volume
            await audioService.setSoundEffectVolume(soundEffectVolume)
        }
    }
    
    /// Update sound effect master volume (no reload needed)
    func setSoundEffectVolume(_ volume: Float) async {
        soundEffectVolume = volume
        
        // Set master volume - applies immediately, no reload needed
        await audioService.setSoundEffectVolume(volume)
    }
    
    // MARK: - Playback Control
    
    func loadPlaylist(_ tracks: [String]) async throws {
        let urls = tracks.compactMap { trackURL(named: $0) }
        guard !urls.isEmpty else {
            errorMessage = "No audio files found. Check Resources folder."
            throw AudioPlayerError.fileLoadFailed(reason: "No valid audio files in bundle")
        }
        try await audioService.loadPlaylist(urls)
        currentPlaylistName = detectPlaylistName(urls)
        await updateTrackInfo()

    }
    
    func play() async throws {
        await updateTrackInfo()

        try await audioService.startPlaying(fadeDuration: startFadeInDuration)
    }
    
    func pause() async throws {
        try await audioService.pause()
    }
    
    func resume() async throws {
        try await audioService.resume()
    }
    
    func stop() async {
        await audioService.stop(fadeDuration: stopFadeOutDuration)
    }
    
    func skipForward() async throws {
        try await audioService.skip(forward: 15)
    }
    
    func skipBackward() async throws {
        try await audioService.skip(backward: 15)
    }
    
    func nextTrack() async throws {
        try await audioService.skipToNext()
        await updateTrackInfo()

    }
    
    func previousTrack() async throws {
        try await audioService.skipToPrevious()
        await updateTrackInfo()
    }
    
    func replacePlaylist(_ tracks: [String]) async throws {
        let urls = tracks.compactMap { trackURL(named: $0) }
        guard !urls.isEmpty else {
            errorMessage = "No audio files found. Check Resources folder."
            throw AudioPlayerError.fileLoadFailed(reason: "No valid audio files in bundle")
        }
        try await audioService.replacePlaylist(urls)
        currentPlaylistName = detectPlaylistName(urls)
        await updateTrackInfo()
    }
    
    func nextPlaylist() async throws {
        let presetKeys = Self.presets.keys.sorted()
        guard !presetKeys.isEmpty else { return }
        
        // Cycle to next playlist
        let nextIndex = (currentTrackIndex + 1) % presetKeys.count
        let nextPreset = presetKeys[nextIndex]
        
        if let tracks = Self.presets[nextPreset] {
            try await replacePlaylist(tracks)
        }
    }
    
    func setVolume(_ value: Float) async {
        await audioService.setVolume(value)
        volume = value
    }
    
    func updateRepeatMode(_ mode: RepeatMode) async {
        await audioService.setRepeatMode(mode)
        repeatMode = mode
    }
    
    // MARK: - Overlay Control
    
    func playOverlay(_ trackName: String) async throws {
        guard let url = trackURL(named: trackName) else {
            errorMessage = "Overlay file '\(trackName).mp3' not found"
            throw AudioPlayerError.fileLoadFailed(reason: "File not found: \(trackName).mp3")
        }
        
        // Use current loop settings
        let loopMode: OverlayConfiguration.LoopMode = overlayLoopEnabled ? .infinite : .once
        
        let config = OverlayConfiguration(
            loopMode: loopMode,
            loopDelay: overlayLoopDelay,
            volume: 0.5,
            fadeInDuration: 1.0,
            fadeOutDuration: 1.0,
            fadeCurve: .linear
        )
        
        // Set configuration first
        try await audioService.setOverlayConfiguration(config)
        
        // Then play overlay
        try await audioService.playOverlay(url)
        isOverlayPlaying = true
        selectedOverlayTrack = trackName
    }
    
    func stopOverlay() async {
        await audioService.stopOverlay()
        isOverlayPlaying = false
    }
    
    /// Set overlay loop mode dynamically
    func setOverlayLoopMode(enabled: Bool) async {
        overlayLoopEnabled = enabled
        let mode: OverlayConfiguration.LoopMode = enabled ? .infinite : .once
        
        // Get current config and update loop mode
        if let currentConfig = await audioService.getOverlayConfiguration() {
            var newConfig = currentConfig
            newConfig.loopMode = mode
            try? await audioService.setOverlayConfiguration(newConfig)
        }
    }
    
    /// Set overlay loop delay dynamically
    func setOverlayLoopDelay(_ delay: TimeInterval) async {
        overlayLoopDelay = delay
        
        // Get current config and update loop delay
        if let currentConfig = await audioService.getOverlayConfiguration() {
            var newConfig = currentConfig
            newConfig.loopDelay = delay
            try? await audioService.setOverlayConfiguration(newConfig)
        }
    }
    
    /// Set overlay volume (0.0 - 1.0)
    func setOverlayVolume(_ volume: Float) async {
        overlayVolume = volume
        await audioService.setOverlayVolume(volume)
    }
    
    // MARK: - Sound Effects Control
    
    /// Play sound effect by name
    func playSoundEffect(named name: String) async throws {
        guard let effect = preloadedEffects.first(where: { $0.track.url.lastPathComponent.contains(name) }) else {
            errorMessage = "Sound effect '\(name)' not preloaded"
            throw AudioPlayerError.fileLoadFailed(reason: "Sound effect not found: \(name)")
        }
        
        currentEffect = effect
        isSoundEffectPlaying = true
        
        await audioService.playSoundEffect(effect, fadeDuration: 0.1)
        
        // Auto-detect when effect finishes (approximate)
        Task {
            // Wait for effect duration + fade out
            let duration = effect.fadeOutDuration + 0.5
            try? await Task.sleep(for: .seconds(duration))
            
            // Check if still playing this effect
            if let current = await audioService.currentSoundEffect, current.id == effect.id {
                // Still playing
            } else {
                // Effect finished
                await MainActor.run {
                    isSoundEffectPlaying = false
                    currentEffect = nil
                }
            }
        }
    }
    
    /// Stop current sound effect
    func stopSoundEffect() async {
        await audioService.stopSoundEffect(fadeDuration: 0.3)
        isSoundEffectPlaying = false
        currentEffect = nil
    }
    
    /// Get available sound effect names
    var availableSoundEffects: [String] {
        preloadedEffects.map { effect in
            effect.track.url.deletingPathExtension().lastPathComponent
        }
    }
    
    // MARK: - AudioPlayerObserver
    
    func playerStateDidChange(_ state: PlayerState) async {
        self.state = state
    }
    
    func playbackPositionDidUpdate(_ position: PlaybackPosition) async {
        self.position = position
    }
    
    func playerDidEncounterError(_ error: AudioPlayerError) async {
        errorMessage = error.localizedDescription
    }
    
    // MARK: - CrossfadeProgressObserver
    // MARK: - CrossfadeProgressObserver
    
    func crossfadeProgressDidUpdate(_ progress: CrossfadeProgress) async {
        // Check if crossfade finished (idle phase)
        if case .idle = progress.phase {
            // Add 0.5s delay before hiding visualizer (better UX)
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(500))
                crossfadeProgress = progress
            }
        } else {
            // Immediately update for active phases
            crossfadeProgress = progress
        }
    }

    
    // MARK: - Helpers
    
    private func trackURL(named name: String) -> URL? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "mp3") else {
            print("[ERROR] Audio file '\(name).mp3' not found in Bundle.main")
            return nil
        }
        return url
    }
    
    /// Update track info from audio service
    private func updateTrackInfo() async {
        currentTrackIndex = await audioService.getCurrentTrackIndex()
    }
    
    /// Detect playlist name by comparing track arrays
    private func detectPlaylistName(_ urls: [URL]) -> String {
        // Extract track names from URLs
        let trackNames = urls.map { url in
            url.deletingPathExtension().lastPathComponent
        }
        
        // Compare with presets
        for (name, presetTracks) in Self.presets {
            if presetTracks == trackNames {
                return name
            }
        }
        
        return "Custom Playlist (\(urls.count) tracks)"
    }

    
    // MARK: - Computed Properties
    
    var isPlaying: Bool { state == .playing }
    var isPaused: Bool { state == .paused }
    var canSkip: Bool { state == .playing || state == .paused }
    var canStop: Bool { state == .playing || state == .paused }
    
    var formattedPosition: String {
        guard let pos = position else { return "--:--" }
        return "\(formatTime(pos.currentTime)) / \(formatTime(pos.duration))"
    }
    
    var progressValue: Double {
        guard let pos = position, pos.duration > 0 else { return 0 }
        return pos.currentTime / pos.duration
    }
    
    var isCrossfading: Bool {
        guard let phase = crossfadeProgress?.phase else { return false }
        if case .idle = phase {
            return false
        }
        return true
    }
    
    var crossfadePhaseText: String? {
        guard let phase = crossfadeProgress?.phase else { return nil }
        
        switch phase {
        case .idle:
            return nil
        case .preparing:
            return "Preparing..."
        case .fading(let progress):
            return "Crossfading \(Int(progress * 100))%"
        case .switching:
            return "Switching..."
        case .cleanup:
            return "Cleanup..."
        }
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Preset Playlists (Main Player - sample files)

extension PlayerViewModel {
    static let presets: [String: [String]] = [
        "Single Track": ["sample1"],
        "Two Tracks": ["sample2", "sample3"],
        "Mixed Tracks": ["sample1", "sample4"]
    ]
    
    static let overlayTracks = ["voiceover1", "voiceover2", "voiceover3"]
}
