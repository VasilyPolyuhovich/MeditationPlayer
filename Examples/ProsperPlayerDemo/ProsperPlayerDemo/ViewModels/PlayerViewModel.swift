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
            throw AudioPlayerError.fileNotFound("No valid audio files")
        }
        try await audioService.loadPlaylist(urls)
    }
    
    func play() async throws {
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
    }
    
    func previousTrack() async throws {
        try await audioService.skipToPrevious()
    }
    
    func replacePlaylist(_ tracks: [String]) async throws {
        let urls = tracks.compactMap { trackURL(named: $0) }
        guard !urls.isEmpty else {
            errorMessage = "No audio files found. Check Resources folder."
            throw AudioPlayerError.fileNotFound("No valid audio files")
        }
        try await audioService.replacePlaylist(urls)
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
            throw AudioPlayerError.fileNotFound(trackName)
        }
        let config = OverlayConfiguration(
            loopMode: .once,
            volume: 0.5,
            fadeInDuration: 1.0,
            fadeOutDuration: 1.0
        )
        try await audioService.startOverlay(url: url, configuration: config)
        isOverlayPlaying = true
        selectedOverlayTrack = trackName
    }
    
    func stopOverlay() async {
        await audioService.stopOverlay()
        isOverlayPlaying = false
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
    
    func crossfadeProgressDidUpdate(_ progress: CrossfadeProgress) async {
        crossfadeProgress = progress
    }
    
    // MARK: - Helpers
    
    private func trackURL(named name: String) -> URL? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "mp3") else {
            print("[ERROR] Audio file '\(name).mp3' not found in Bundle.main")
            return nil
        }
        return url
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
