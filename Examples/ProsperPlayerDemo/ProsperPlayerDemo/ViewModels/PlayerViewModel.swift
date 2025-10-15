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
    
    // MARK: - Initialization
    
    init(audioService: AudioPlayerService) async {
        self.audioService = audioService
        await audioService.addObserver(self)
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
        try await audioService.skipForward(by: 15)
    }
    
    func skipBackward() async throws {
        try await audioService.skipBackward(by: 15)
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
            applyFadeOnEachLoop: false  // Continuous ambient sound
        )
        try await audioService.startOverlay(url: url, configuration: config)
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
        try? await audioService.setOverlayLoopMode(mode)
    }
    
    /// Set overlay loop delay dynamically
    func setOverlayLoopDelay(_ delay: TimeInterval) async {
        overlayLoopDelay = delay
        try? await audioService.setOverlayLoopDelay(delay)
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
