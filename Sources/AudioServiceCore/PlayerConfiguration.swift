import Foundation

/// Repeat mode for playback
public enum RepeatMode: Sendable, Equatable {
    /// Play once, no repeat
    case off
    
    /// Loop current track with fade in/out
    case singleTrack
    
    /// Loop entire playlist
    case playlist
}

/// Simplified player configuration with automatic fade calculations
/// Replaces AudioConfiguration with more intuitive API
public struct PlayerConfiguration: Sendable {
    
    // MARK: - Crossfade Settings
    
    /// Crossfade duration between tracks (Spotify-style)
    ///
    /// Both tracks fade simultaneously over the full duration:
    /// - Outgoing track: fade OUT from 1.0 to 0.0 over `crossfadeDuration`
    /// - Incoming track: fade IN from 0.0 to 1.0 over `crossfadeDuration`
    /// - Total overlap: equals `crossfadeDuration`
    ///
    /// Valid range: 1.0-30.0 seconds
    public let crossfadeDuration: TimeInterval
    
    /// Fade curve algorithm
    public let fadeCurve: FadeCurve
    
    // MARK: - Playback Mode
    
    /// Repeat mode for playback (default: .off)
    /// - .off: Play once, no repeat
    /// - .singleTrack: Loop current track with fade in/out
    /// - .playlist: Loop entire playlist
    public let repeatMode: RepeatMode
    
    
    /// Number of times to repeat playlist
    /// - nil: Infinite repeats (loop forever)
    /// - 0: Play once (same as repeatMode = .off)
    /// - N: Loop N times then stop
    public let repeatCount: Int?
    
    // DELETED (v4.0): singleTrackFadeInDuration and singleTrackFadeOutDuration
    // Now using crossfadeDuration for all track transitions
    
    // MARK: - Audio Settings
    
    /// Volume level (0.0 = silent, 1.0 = maximum)
    /// Standard AVFoundation audio range
    public let volume: Float
    
    // MARK: - Stop Settings
    
    // DELETED (v4.0): stopFadeDuration
    // Now always passed as method parameter in stop(fadeDuration:)
    
    // MARK: - Audio Session Settings
    
    /// Mix with other audio apps (default: false - interrupts other audio)
    /// When true, allows playing alongside other audio sources (music, podcasts, etc.)
    /// When false, interrupts other audio sources (exclusive playback)
    public let mixWithOthers: Bool
    
    // MARK: - Computed Properties
    
    
    
    // MARK: - Initialization
    
    public init(
        crossfadeDuration: TimeInterval = 10.0,
        fadeCurve: FadeCurve = .equalPower,
        repeatMode: RepeatMode = .off,
        repeatCount: Int? = nil,
        volume: Float = 1.0,
        mixWithOthers: Bool = false
    ) {
        self.crossfadeDuration = max(1.0, min(30.0, crossfadeDuration))
        self.fadeCurve = fadeCurve
        self.repeatMode = repeatMode
        self.repeatCount = repeatCount
        self.volume = max(0.0, min(1.0, volume))
        self.mixWithOthers = mixWithOthers
    }
    
    // MARK: - Default Configuration
    
    /// Default configuration with sensible defaults
    public static let `default` = PlayerConfiguration()
    
    // MARK: - Validation
    
    /// Validate configuration values
    /// - Throws: ConfigurationError if invalid
    public func validate() throws {
        // Crossfade duration range check
        if crossfadeDuration < 1.0 || crossfadeDuration > 30.0 {
            throw ConfigurationError.invalidCrossfadeDuration(crossfadeDuration)
        }
        
        // Volume range check
        if volume < 0.0 || volume > 1.0 {
            throw ConfigurationError.invalidVolume(volume)
        }
        
        // RepeatCount validation
        if let count = repeatCount, count < 0 {
            throw ConfigurationError.invalidRepeatCount(count)
        }
        
        // DELETED (v4.0): stopFadeDuration, singleTrackFadeInDuration, singleTrackFadeOutDuration validations
    }
}

// MARK: - Configuration Errors

public enum ConfigurationError: Error, LocalizedError {
    case invalidCrossfadeDuration(TimeInterval)
    case invalidVolume(Float)
    case invalidRepeatCount(Int)
    // DELETED (v4.0): invalidStopFadeDuration, invalidSingleTrackFadeInDuration, invalidSingleTrackFadeOutDuration
    
    public var errorDescription: String? {
        switch self {
        case .invalidCrossfadeDuration(let duration):
            return "Crossfade duration must be between 1.0 and 30.0 seconds (got \(duration))"
        case .invalidVolume(let volume):
            return "Volume must be between 0.0 and 1.0 (got \(volume))"
        case .invalidRepeatCount(let count):
            return "Repeat count must be >= 0 or nil for infinite (got \(count))"
        }
    }
}

