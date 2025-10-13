import SwiftUI
import AudioServiceCore
import AudioServiceKit

/// Playback mode selection
enum PlaybackMode: String, CaseIterable {
    case playlist = "Playlist (2 tracks)"
    case singleLoop = "Single Loop"
    
    var description: String {
        switch self {
        case .playlist:
            return "sample1 → sample2 → repeat"
        case .singleLoop:
            return "sample1 → loop with crossfade"
        }
    }
}

/// Main ViewModel for audio player UI
/// Manages state, configuration, and delegates playlist logic to SDK
@MainActor
@Observable
class AudioPlayerViewModel: AudioPlayerObserver, CrossfadeProgressObserver {
    
    // MARK: - Player State
    
    private(set) var state: PlayerState = .finished
    private(set) var position: PlaybackPosition?
    private(set) var currentTrack: String = ""
    private(set) var crossfadeProgress: CrossfadeProgress = .idle
    
    // MARK: - Playback Mode
    
    var playbackMode: PlaybackMode = .playlist
    
    // MARK: - Configuration (Editable)
    
    var crossfadeDuration: Double = 10.0
    var volume: Float = 1.0  // 0.0-1.0 (v4.0)
    var repeatCount: Int? = nil
    var selectedCurve: FadeCurve = .equalPower
    
    // Repeat Mode (v4.0)
    var repeatMode: RepeatMode = .off
    private(set) var currentRepeatCount: Int = 0
    
    // Audio Session (NEW)
    var mixWithOthers: Bool = false  // Mix with other audio apps
    
    // MARK: - Private Properties
    
    private let allTracks = ["sample1", "sample2"]
    private(set) var currentTrackIndex = 0  // Exposed for UI
    private let audioService: AudioPlayerService
    
    // Track switching debounce
    private var lastTrackSwitchTime: Date = .distantPast
    private let trackSwitchDebounceInterval: TimeInterval = 0.5  // 500ms minimum between switches
    
    // MARK: - Initialization
    
    init(audioService: AudioPlayerService) {
        self.audioService = audioService
        
        Task {
            await audioService.addObserver(self)
        }
    }
    
    // MARK: - User Actions
    
    func play() async {
        do {
            let trackURLs = currentPlaylist.map { trackURL(named: $0) }
            currentTrack = currentPlaylist[0]
            currentTrackIndex = 0
            
            // Reset repeat count for new playback
            currentRepeatCount = 0
            
            // v4.0 API: loadPlaylist, then startPlaying with fade-in
            try await audioService.loadPlaylist(trackURLs)
            try await audioService.startPlaying(fadeDuration: 2.0)
        } catch {
            print("❌ Play failed: \(error)")
        }
    }
    
    func pause() async {
        try? await audioService.pause()
    }
    
    func resume() async {
        try? await audioService.resume()
    }
    
    func stop() async {
        await audioService.stop()
    }
    
    func reset() async {
        await audioService.reset()  // SDK clears playlist automatically
        resetConfigurationToDefaults()
        currentTrackIndex = 0
        currentTrack = ""
    }
    
    func skipForward() async {
        guard let position = position else { return }
        let newTime = min(position.currentTime + 15.0, position.duration)
        try? await audioService.seekWithFade(to: newTime, fadeDuration: 0.1)
    }
    
    func skipBackward() async {
        guard let position = position else { return }
        let newTime = max(position.currentTime - 15.0, 0)
        try? await audioService.seekWithFade(to: newTime, fadeDuration: 0.1)
    }
    
    /// Navigate to next track using SDK
    func nextTrack() async {
        // Debounce: prevent rapid track switching
        let now = Date()
        guard now.timeIntervalSince(lastTrackSwitchTime) >= trackSwitchDebounceInterval else {
            print("⏳ Track switch debounced (too fast)")
            return
        }
        lastTrackSwitchTime = now
        
        do {
            try await audioService.nextTrack()
            // Update UI state
            currentTrackIndex = await audioService.getCurrentTrackIndex()
            if currentTrackIndex < currentPlaylist.count {
                currentTrack = currentPlaylist[currentTrackIndex]
            }
        } catch {
            print("❌ Next track failed: \(error)")
        }
    }
    
    /// Navigate to previous track using SDK
    func previousTrack() async {
        // Debounce: prevent rapid track switching
        let now = Date()
        guard now.timeIntervalSince(lastTrackSwitchTime) >= trackSwitchDebounceInterval else {
            print("⏳ Track switch debounced (too fast)")
            return
        }
        lastTrackSwitchTime = now
        
        do {
            try await audioService.previousTrack()
            // Update UI state
            currentTrackIndex = await audioService.getCurrentTrackIndex()
            if currentTrackIndex < currentPlaylist.count {
                currentTrack = currentPlaylist[currentTrackIndex]
            }
        } catch {
            print("❌ Previous track failed: \(error)")
        }
    }
    
    func setVolume(_ value: Float) async {
        self.volume = value
        await audioService.setVolume(value)
    }
    
    // MARK: - Repeat Mode Control (v4.0)
    
    /// Set repeat mode using SDK
    func updateRepeatMode(_ mode: RepeatMode) async {
        self.repeatMode = mode
        await audioService.setRepeatMode(mode)
        print("✅ Repeat mode set to: \(mode)")
    }
    
    // MARK: - AudioPlayerObserver Protocol
    
    func playerStateDidChange(_ state: PlayerState) async {
        // CRITICAL: Ensure state update happens on MainActor for UI consistency
        await MainActor.run {
            self.state = state
        }
    }
    
    func playbackPositionDidUpdate(_ position: PlaybackPosition) async {
        // CRITICAL: Ensure position update happens on MainActor for UI consistency
        await MainActor.run {
            self.position = position
        }
        
        // NOTE: Auto-advance is now handled by SDK internally
        // No playlist logic needed here
        
        // Update repeat count from SDK (Feature #1)
        if repeatMode == .singleTrack {
            let count = await audioService.getRepeatCount()
            await MainActor.run {
                self.currentRepeatCount = count
            }
        }
    }
    
    func playerDidEncounterError(_ error: AudioPlayerError) async {
        print("❌ Player Error: \(error)")
    }
    
    // MARK: - CrossfadeProgressObserver Protocol
    
    func crossfadeProgressDidUpdate(_ progress: CrossfadeProgress) async {
        print("🟠 [VIEWMODEL] Received crossfade progress: \(progress.phase)")
        await MainActor.run {
            self.crossfadeProgress = progress
            print("🟠 [VIEWMODEL] Updated crossfadeProgress property")
        }
    }
    
    // MARK: - Helpers
    
    private var currentPlaylist: [String] {
        switch playbackMode {
        case .playlist:
            return allTracks  // ["sample1", "sample2"]
        case .singleLoop:
            return [allTracks[0]]  // ["sample1"] only
        }
    }
    
    private var currentConfiguration: PlayerConfiguration {
        PlayerConfiguration(
            crossfadeDuration: crossfadeDuration,
            fadeCurve: selectedCurve,
            repeatMode: repeatMode,
            volume: volume,
            mixWithOthers: mixWithOthers
        )
    }
    
    private func trackURL(named name: String) -> URL {
        Bundle.main.url(forResource: name, withExtension: "mp3")!
    }
    
    private func resetConfigurationToDefaults() {
        crossfadeDuration = 10.0
        volume = 1.0  // v4.0: Float 0.0-1.0
        repeatCount = nil
        selectedCurve = .equalPower
        repeatMode = .off
        currentRepeatCount = 0
        mixWithOthers = false
    }
    
    // MARK: - Computed Properties for UI
    
    var isPlaying: Bool { state == .playing }
    var isPaused: Bool { state == .paused }
    var canSkip: Bool { state == .playing || state == .paused }
    var canStop: Bool { state != .finished }
    
    var formattedPosition: String {
        guard let pos = position else { return "0:00 / 0:00" }
        return "\(formatTime(pos.currentTime)) / \(formatTime(pos.duration))"
    }
    
    var progressValue: Double {
        guard let pos = position else { return 0 }
        return pos.currentTime / pos.duration
    }
    
    // MARK: - Crossfade Zone Calculation
    
    /// Returns the normalized position where crossfade zone starts (0.0-1.0)
    var crossfadeZoneStart: Double {
        guard let pos = position, pos.duration > 0 else { return 1.0 }
        let crossfadeStartTime = pos.duration - crossfadeDuration
        return max(0, crossfadeStartTime / pos.duration)
    }
    
    /// Returns true if currently in crossfade zone
    var isInCrossfadeZone: Bool {
        guard let pos = position else { return false }
        let crossfadeStartTime = pos.duration - crossfadeDuration
        return pos.currentTime >= crossfadeStartTime
    }
    
    /// Returns true if crossfade is actively happening
    var isCrossfading: Bool {
        switch crossfadeProgress.phase {
        case .idle:
            return false
        case .preparing, .switching, .cleanup:
            return true
        case .fading:
            return true
        }
    }
    
    /// Returns crossfade phase description for UI
    var crossfadePhase: String? {
        switch crossfadeProgress.phase {
        case .idle:
            return nil
        case .preparing:
            return "Preparing..."
        case .fading(let progress):
            return "Crossfading \(Int(progress * 100))%"
        case .switching:
            return "Switching..."
        case .cleanup:
            return "Finishing..."
        }
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    // MARK: - Playlist Management (Feature #3)
    
    /// Preset playlists for quick access
    static let presetPlaylists: [String: [String]] = [
        "Sample 1+2": ["sample1", "sample2"],
        "Sample 3+4": ["sample3", "sample4"],
        "Single Track": ["sample1"],
        "All 4 Tracks": ["sample1", "sample2", "sample3", "sample4"]
    ]
    
    /// Get current playlist track names (async)
    func getCurrentPlaylistNames() async -> [String] {
        let urls = await audioService.getPlaylist()
        return urls.compactMap { url in
            url.deletingPathExtension().lastPathComponent
        }
    }
    
    /// Swap entire playlist with crossfade (Feature #3)
    /// - Parameters:
    ///   - tracks: Array of track names (without extension)
    ///   - crossfadeDuration: Duration of crossfade if playing
    func swapPlaylist(tracks: [String], crossfadeDuration: TimeInterval) async throws {
        let trackURLs = tracks.map { trackURL(named: $0) }
        
        // Call SDK's swapPlaylist method
        try await audioService.swapPlaylist(
            tracks: trackURLs,
            crossfadeDuration: crossfadeDuration
        )
        
        // Update UI state
        currentTrackIndex = await audioService.getCurrentTrackIndex()
        if currentTrackIndex < tracks.count {
            currentTrack = tracks[currentTrackIndex]
        }
        
        print("✅ Playlist swapped to: \(tracks.joined(separator: ", "))")
    }
}
