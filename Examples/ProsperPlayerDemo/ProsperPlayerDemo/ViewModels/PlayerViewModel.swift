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
    
    // MARK: - Crossfade Tracking
    
    var crossfadeProgress: CrossfadeProgress?
    
    // MARK: - Initialization
    
    init(audioService: AudioPlayerService) async {
        self.audioService = audioService
        
        // Register observers
        await audioService.addObserver(self)
        await audioService.addCrossfadeObserver(self)
    }
    
    // MARK: - Playback Control
    
    func loadPlaylist(_ tracks: [String]) async throws {
        let urls = tracks.map { trackURL(named: $0) }
        
        let config = PlayerConfiguration(
            crossfadeDuration: crossfadeDuration,
            fadeInDuration: crossfadeDuration * 0.3,
            fadeOutDuration: crossfadeDuration * 0.3,
            fadeCurve: selectedCurve,
            repeatMode: repeatMode
        )
        
        try await audioService.loadPlaylist(urls, configuration: config)
    }
    
    func play() async throws {
        try await audioService.startPlaying(fadeIn: crossfadeDuration * 0.3)
    }
    
    func pause() async {
        await audioService.pause()
    }
    
    func resume() async {
        await audioService.resume()
    }
    
    func stop() async {
        await audioService.stop()
    }
    
    func skipForward() async throws {
        try await audioService.skip(seconds: 15)
    }
    
    func skipBackward() async throws {
        try await audioService.skip(seconds: -15)
    }
    
    func nextTrack() async throws {
        try await audioService.nextTrack()
    }
    
    func previousTrack() async throws {
        try await audioService.previousTrack()
    }
    
    func replacePlaylist(_ tracks: [String]) async throws {
        let urls = tracks.map { trackURL(named: $0) }
        try await audioService.replacePlaylist(urls)
    }
    
    func setVolume(_ value: Float) async {
        await audioService.setVolume(value)
        volume = value
    }
    
    func updateRepeatMode(_ mode: RepeatMode) async {
        await audioService.setRepeatMode(mode)
        repeatMode = mode
    }
    
    func updateConfiguration() async throws {
        let config = PlayerConfiguration(
            crossfadeDuration: crossfadeDuration,
            fadeInDuration: crossfadeDuration * 0.3,
            fadeOutDuration: crossfadeDuration * 0.3,
            fadeCurve: selectedCurve,
            repeatMode: repeatMode
        )
        
        try await audioService.updateConfiguration(config)
    }
    
    // MARK: - AudioPlayerObserver
    
    func playerStateDidChange(_ state: PlayerState) async {
        self.state = state
    }
    
    func playbackPositionDidUpdate(_ position: PlaybackPosition) async {
        self.position = position
        currentTrackIndex = await audioService.getCurrentTrackIndex()
    }
    
    func playerDidEncounterError(_ error: AudioPlayerError) async {
        errorMessage = error.localizedDescription
    }
    
    // MARK: - CrossfadeProgressObserver
    
    func crossfadeProgressDidUpdate(_ progress: CrossfadeProgress) async {
        crossfadeProgress = progress
    }
    
    // MARK: - Helpers
    
    private func trackURL(named name: String) -> URL {
        Bundle.main.url(forResource: name, withExtension: "mp3")!
    }
    
    // MARK: - Computed Properties
    
    var isPlaying: Bool { state == .playing }
    var isPaused: Bool { state == .paused }
    var canSkip: Bool { state == .playing || state == .paused }
    var canStop: Bool { state == .playing || state == .paused }
    
    var formattedPosition: String {
        guard let pos = position else { return "--:--" }
        return "\(formatTime(pos.current)) / \(formatTime(pos.duration))"
    }
    
    var progressValue: Double {
        guard let pos = position, pos.duration > 0 else { return 0 }
        return pos.current / pos.duration
    }
    
    var isCrossfading: Bool {
        crossfadeProgress?.phase != nil
    }
    
    var crossfadePhaseText: String? {
        guard let phase = crossfadeProgress?.phase else { return nil }
        
        switch phase {
        case .fadeOut:
            return "Fading Out..."
        case .overlap:
            return "Crossfading..."
        case .fadeIn:
            return "Fading In..."
        }
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Preset Playlists

extension PlayerViewModel {
    static let presets: [String: [String]] = [
        "Single Track": ["voiceover1"],
        "Two Tracks": ["voiceover1", "voiceover2"],
        "All Three": ["voiceover1", "voiceover2", "voiceover3"],
        "Reverse Order": ["voiceover3", "voiceover2", "voiceover1"]
    ]
}
