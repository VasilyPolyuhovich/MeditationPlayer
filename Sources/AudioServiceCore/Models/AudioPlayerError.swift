import Foundation

/// Errors that can occur during audio playback
///
/// This enum defines all possible error cases that can be thrown by the AudioPlayerService.
/// Each case includes detailed information about the error cause and context.
///
/// ## Usage Example
/// ```swift
/// do {
///     try await audioService.swapPlaylist(tracks: newTracks)
/// } catch AudioPlayerError.invalidConfiguration(let reason) {
///     print("Configuration error: \(reason)")
/// } catch AudioPlayerError.fileLoadFailed(let reason) {
///     print("Failed to load file: \(reason)")
/// } catch {
///     print("Unexpected error: \(error)")
/// }
/// ```
public enum AudioPlayerError: Error, Sendable, Equatable {
    
    // MARK: - File & Resource Errors
    
    /// Failed to load audio file from the specified URL
    ///
    /// **When it occurs:**
    /// - File does not exist at the given URL
    /// - File format is not supported by AVFoundation
    /// - File permissions prevent reading
    /// - Corrupted audio file
    ///
    /// **How to handle:**
    /// - Verify file exists using FileManager
    /// - Check file format (supported: MP3, M4A, WAV, AAC, etc.)
    /// - Ensure file permissions are correct
    /// - Validate file integrity before loading
    case fileLoadFailed(reason: String)
    
    /// Invalid audio format that cannot be processed
    ///
    /// **When it occurs:**
    /// - Unsupported codec or container format
    /// - Sample rate or channel count mismatch
    /// - Corrupted audio stream
    ///
    /// **How to handle:**
    /// - Convert audio to supported format (44.1kHz or 48kHz, 2 channels)
    /// - Use AVFoundation-compatible formats
    /// - Check audio file integrity
    case invalidFormat(reason: String)
    
    // MARK: - Configuration Errors
    
    /// Invalid configuration parameter provided
    ///
    /// **When it occurs:**
    /// - Empty playlist passed to swapPlaylist()
    /// - Invalid fade duration (outside 0.5-10.0s range)
    /// - Invalid crossfade duration (outside 1.0-30.0s range)
    /// - Invalid volume (outside 0.0-1.0 range)
    /// - Conflicting configuration parameters
    ///
    /// **How to handle:**
    /// - Validate parameters before calling SDK methods
    /// - Use AudioConfiguration.validate() before startPlaying()
    /// - Check parameter ranges in documentation
    /// - Provide user feedback for configuration errors
    ///
    /// **Example:**
    /// ```swift
    /// // Empty playlist validation
    /// guard !tracks.isEmpty else {
    ///     throw AudioPlayerError.invalidConfiguration(
    ///         reason: "Cannot swap to empty playlist"
    ///     )
    /// }
    /// ```
    case invalidConfiguration(reason: String)
    
    // MARK: - State Errors
    
    /// Invalid operation attempted in current player state
    ///
    /// **When it occurs:**
    /// - Calling pause() when already paused
    /// - Calling resume() when already playing
    /// - Calling resume() on finished player (use startPlaying instead)
    /// - Attempting operations before setup() is called
    ///
    /// **How to handle:**
    /// - Check player state before operations
    /// - Use state property to determine valid operations
    /// - Handle state transitions properly
    ///
    /// **Valid state transitions:**
    /// - finished → preparing (via startPlaying)
    /// - preparing → playing (automatic)
    /// - playing ↔ paused (via pause/resume)
    /// - playing → fadingOut → finished (via finish)
    case invalidState(current: String, attempted: String)
    
    // MARK: - System Errors
    
    /// Audio session configuration failed
    ///
    /// **When it occurs:**
    /// - Another app holds audio session exclusively
    /// - Background audio not enabled in capabilities
    /// - System denied audio session activation
    /// - Audio hardware not available
    ///
    /// **How to handle:**
    /// - Enable "Audio, AirPlay, and Picture in Picture" in Background Modes
    /// - Check Info.plist for UIBackgroundModes
    /// - Handle interruptions (phone calls, alarms)
    /// - Retry activation after brief delay
    case sessionConfigurationFailed(reason: String)
    
    /// Audio engine failed to start
    ///
    /// **When it occurs:**
    /// - Audio hardware initialization failed
    /// - Insufficient system resources
    /// - Audio route conflict
    /// - Engine already running
    ///
    /// **How to handle:**
    /// - Check audio session is active
    /// - Verify audio route is available
    /// - Reset engine and retry
    /// - Check for resource conflicts
    case engineStartFailed(reason: String)
    
    /// Hardware audio route change failed
    ///
    /// **When it occurs:**
    /// - Audio device disconnected during playback
    /// - Failed to switch to Bluetooth device
    /// - Output route became unavailable
    ///
    /// **How to handle:**
    /// - Monitor AVAudioSession.routeChangeNotification
    /// - Pause playback on device disconnect
    /// - Resume when valid route available
    /// - Handle .oldDeviceUnavailable reason
    case routeChangeFailed(reason: String)
    
    // MARK: - Playback Errors
    
    /// Buffer scheduling failed during playback
    ///
    /// **When it occurs:**
    /// - Audio file read error during streaming
    /// - Insufficient memory for buffer
    /// - Engine stopped unexpectedly
    /// - Node connection issue
    ///
    /// **How to handle:**
    /// - Check file integrity
    /// - Monitor memory usage
    /// - Verify engine state
    /// - Reset and retry playback
    case bufferSchedulingFailed(reason: String)
    
    // MARK: - Playlist Errors
    
    /// Playlist is empty (no tracks to play)
    ///
    /// **When it occurs:**
    /// - Calling playlist operations on empty playlist
    /// - All tracks removed from playlist
    /// - Playlist cleared before playback
    ///
    /// **How to handle:**
    /// - Check playlist.isEmpty before operations
    /// - Ensure at least one track loaded
    /// - Provide user feedback for empty state
    /// - Load default playlist if needed
    case emptyPlaylist
    
    /// No active track currently playing
    ///
    /// **When it occurs:**
    /// - Querying position before playback started
    /// - Track finished but not advanced
    /// - Playback stopped unexpectedly
    ///
    /// **How to handle:**
    /// - Check state == .playing before track queries
    /// - Verify currentTrack is not nil
    /// - Handle finished state appropriately
    case noActiveTrack
    
    /// Invalid playlist index accessed
    ///
    /// **When it occurs:**
    /// - Jumping to index beyond playlist bounds
    /// - Accessing track after playlist modified
    /// - Race condition during playlist update
    ///
    /// **How to handle:**
    /// - Validate index < playlist.count
    /// - Use safe array access patterns
    /// - Synchronize playlist modifications
    case invalidPlaylistIndex(index: Int, count: Int)
    
    // MARK: - Unknown Errors
    
    /// Unknown or unexpected error occurred
    ///
    /// **When it occurs:**
    /// - Unhandled system error
    /// - Unexpected AVFoundation error
    /// - Internal SDK error
    ///
    /// **How to handle:**
    /// - Log error details for debugging
    /// - Reset player state
    /// - Report to SDK maintainers if reproducible
    /// - Provide generic error message to user
    case unknown(reason: String)
    
    // MARK: - Localized Descriptions
    
    /// Human-readable error description
    ///
    /// Provides user-friendly error messages suitable for display in UI.
    /// Each message includes relevant context about the error cause.
    public var localizedDescription: String {
        switch self {
        // File & Resource Errors
        case .fileLoadFailed(let reason):
            return "Failed to load audio file: \(reason)"
            
        case .invalidFormat(let reason):
            return "Invalid audio format: \(reason)"
            
        // Configuration Errors
        case .invalidConfiguration(let reason):
            return "Invalid configuration: \(reason)"
            
        // State Errors
        case .invalidState(let current, let attempted):
            return "Cannot \(attempted) in \(current) state"
            
        // System Errors
        case .sessionConfigurationFailed(let reason):
            return "Audio session configuration failed: \(reason)"
            
        case .engineStartFailed(let reason):
            return "Audio engine failed to start: \(reason)"
            
        case .routeChangeFailed(let reason):
            return "Audio route change failed: \(reason)"
            
        // Playback Errors
        case .bufferSchedulingFailed(let reason):
            return "Buffer scheduling failed: \(reason)"
            
        // Playlist Errors
        case .emptyPlaylist:
            return "Playlist is empty - add tracks before playing"
            
        case .noActiveTrack:
            return "No active track playing"
            
        case .invalidPlaylistIndex(let index, let count):
            return "Invalid playlist index \(index) (playlist has \(count) tracks)"
            
        // Unknown Errors
        case .unknown(let reason):
            return "Unknown error: \(reason)"
        }
    }
    
    /// Error category for grouping and filtering
    ///
    /// Use this property to determine the type of error for logging,
    /// analytics, or custom error handling logic.
    ///
    /// ## Example
    /// ```swift
    /// catch let error as AudioPlayerError {
    ///     switch error.category {
    ///     case .configuration:
    ///         // Show configuration dialog
    ///     case .system:
    ///         // Retry or show system error
    ///     case .file:
    ///         // File picker or re-download
    ///     default:
    ///         // Generic error handling
    ///     }
    /// }
    /// ```
    public var category: ErrorCategory {
        switch self {
        case .fileLoadFailed, .invalidFormat:
            return .file
        case .invalidConfiguration:
            return .configuration
        case .invalidState:
            return .state
        case .sessionConfigurationFailed, .engineStartFailed, .routeChangeFailed:
            return .system
        case .bufferSchedulingFailed:
            return .playback
        case .emptyPlaylist, .noActiveTrack, .invalidPlaylistIndex:
            return .playlist
        case .unknown:
            return .unknown
        }
    }
}

// MARK: - Error Category

/// Categories for grouping related errors
public enum ErrorCategory: String, Sendable {
    /// File loading or format errors
    case file
    /// Configuration validation errors
    case configuration
    /// Invalid state transition errors
    case state
    /// System-level errors (audio session, engine)
    case system
    /// Playback-specific errors
    case playback
    /// Playlist management errors
    case playlist
    /// Unknown or unexpected errors
    case unknown
}
