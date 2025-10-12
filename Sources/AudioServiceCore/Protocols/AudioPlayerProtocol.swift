import Foundation

/// Protocol defining core audio player capabilities
public protocol AudioPlayerProtocol: Actor {
    /// Current playback state
    var state: PlayerState { get }
    
    /// Current configuration
    var configuration: PlayerConfiguration { get }
    
    /// Current track information (if available)
    var currentTrack: TrackInfo? { get }
    
    /// Current playback position
    var playbackPosition: PlaybackPosition? { get }
    
    /// Start playback with optional fade-in
    ///
    /// Plays the current track from playlist with configurable fade-in.
    /// Uses track from playlist manager's current track.
    ///
    /// - Parameter fadeDuration: Fade-in duration in seconds (0.0 = no fade, instant start)
    /// - Throws:
    ///   - `AudioPlayerError.noTrackLoaded` if playlist is empty
    ///   - `AudioPlayerError.invalidState` if cannot transition to playing
    ///   - `AudioPlayerError.fileNotFound` if track file doesn't exist
    ///
    /// - Note: Configuration must be set via initializer or `updateConfiguration()`
    /// - Note: fadeDuration is independent from crossfade between tracks
    func startPlaying(fadeDuration: TimeInterval) async throws
    
    /// Pause playback
    /// - Throws: AudioPlayerError if cannot pause in current state
    func pause() async throws
    
    /// Resume playback from paused state
    /// - Throws: AudioPlayerError if cannot resume in current state
    func resume() async throws
    
    /// Stop playback and cleanup resources
    /// - Parameter fadeDuration: Optional fade out duration (nil = instant stop)
    func stop(fadeDuration: TimeInterval?) async
    
    /// Finish playback with fade out
    /// - Parameter fadeDuration: Custom fade out duration (uses config default if nil)
    /// - Throws: AudioPlayerError if cannot finish in current state
    func finish(fadeDuration: TimeInterval?) async throws
    
    /// Skip forward by specified interval
    /// - Parameter interval: Time interval in seconds (default: 15)
    /// - Throws: AudioPlayerError if seek fails
    func skipForward(by interval: TimeInterval) async throws
    
    /// Skip backward by specified interval
    /// - Parameter interval: Time interval in seconds (default: 15)
    /// - Throws: AudioPlayerError if seek fails
    func skipBackward(by interval: TimeInterval) async throws
    
    /// Set volume level
    /// - Parameter volume: Volume level (0.0 - 1.0)
    func setVolume(_ volume: Float) async
}

/// Protocol for audio player with playlist management
public protocol PlaylistAudioPlayerProtocol: AudioPlayerProtocol {
    /// Load initial playlist before playback
    /// - Parameter tracks: Array of track URLs
    /// - Throws: AudioPlayerError if playlist is empty
    func loadPlaylist(_ tracks: [URL]) async throws
    
    /// Replace current playlist with crossfade
    /// - Parameter tracks: New playlist tracks
    /// - Throws: AudioPlayerError if replacement fails
    /// - Note: Uses configuration.crossfadeDuration for crossfade
    func replacePlaylist(_ tracks: [URL]) async throws
    
    /// Skip to next track in playlist
    /// - Throws: AudioPlayerError if no next track
    func skipToNext() async throws
    
    /// Skip to previous track in playlist
    /// - Throws: AudioPlayerError if no previous track
    func skipToPrevious() async throws
}

/// Protocol for observing player state changes
public protocol AudioPlayerObserver: Sendable {
    /// Called when player state changes
    func playerStateDidChange(_ state: PlayerState) async
    
    /// Called when playback position updates
    func playbackPositionDidUpdate(_ position: PlaybackPosition) async
    
    /// Called when an error occurs
    func playerDidEncounterError(_ error: AudioPlayerError) async
}
