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
        
        // ✅ FIX: addObserver accepts both AudioPlayerObserver and CrossfadeProgressObserver
        await audioService.addObserver(self)
    }
    
    // MARK: - Playback Control
    
    func loadPlaylist(_ tracks: [String]) async throws {
        let urls = tracks.map { trackURL(named: $0) }
        
        // ✅ FIX: loadPlaylist only accepts [URL], no configuration parameter
        try await audioService.loadPlaylist(urls)
    }
    
    func play() async throws {
        // ✅ FIX: parameter name is fadeDuration, not fadeIn
        try await audioService.startPlaying(fadeDuration: crossfadeDuration * 0.3)
    }
    
    func pause() async throws {
        // ✅ FIX: pause() throws
        try await audioService.pause()
    }
    
    func resume() async throws {
        // ✅ FIX: resume() throws
        try await audioService.resume()
    }
    
    func stop() async {
        // ✅ FIX: stop() accepts fadeDuration: TimeInterval?
        await audioService.stop(fadeDuration: nil)
    }
    
    func skipForward() async throws {
        // ✅ FIX: use skipForward(by:), not skip(seconds:)
        try await audioService.skipForward(by: 15)
    }
    
    func skipBackward() async throws {
        // ✅ FIX: use skipBackward(by:), not skip(seconds:)
        try await audioService.skipBackward(by: 15)
    }
    
    func nextTrack() async throws {
        // ✅ FIX: use skipToNext(), not nextTrack()
        try await audioService.skipToNext()
    }
    
    func previousTrack() async throws {
        // ✅ FIX: use skipToPrevious(), not previousTrack()
        try await audioService.skipToPrevious()
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
    
    // MARK: - AudioPlayerObserver
    
    func playerStateDidChange(_ state: PlayerState) async {
        self.state = state
    }
    
    func playbackPositionDidUpdate(_ position: PlaybackPosition) async {
        self.position = position
        // ✅ FIX: getCurrentTrackIndex doesn't exist, manage index manually
        // Track index is managed by playlist, we can infer from state
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
        // ✅ FIX: use currentTime, not .current
        return "\(formatTime(pos.currentTime)) / \(formatTime(pos.duration))"
    }
    
    var progressValue: Double {
        guard let pos = position, pos.duration > 0 else { return 0 }
        // ✅ FIX: use currentTime, not .current
        return pos.currentTime / pos.duration
    }
    
    var isCrossfading: Bool {
        // ✅ FIX: check if phase is not .idle
        guard let phase = crossfadeProgress?.phase else { return false }
        if case .idle = phase {
            return false
        }
        return true
    }
    
    var crossfadePhaseText: String? {
        guard let phase = crossfadeProgress?.phase else { return nil }
        
        // ✅ FIX: use actual Phase cases
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

// MARK: - Preset Playlists

extension PlayerViewModel {
    static let presets: [String: [String]] = [
        "Single Track": ["voiceover1"],
        "Two Tracks": ["voiceover1", "voiceover2"],
        "All Three": ["voiceover1", "voiceover2", "sample2"],
        "Reverse Order": ["sample2", "voiceover2", "voiceover1"]
    ]
}
