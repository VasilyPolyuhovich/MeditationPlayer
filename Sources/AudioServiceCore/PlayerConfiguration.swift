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
    
    /// Duration of crossfade transitions between tracks (1.0-30.0 seconds)
    /// This value is used for:
    /// - Auto-advance: Full crossfade at track end
    /// - Manual switch: Adaptive based on remaining time
    /// - Track start: fadeIn = crossfadeDuration * 0.3
    public var crossfadeDuration: TimeInterval
    
    /// Fade curve algorithm
    public var fadeCurve: FadeCurve
    
    // MARK: - Playback Mode
    
    /// Repeat mode for playback (default: .off)
    /// - .off: Play once, no repeat
    /// - .singleTrack: Loop current track with fade in/out
    /// - .playlist: Loop entire playlist
    public var repeatMode: RepeatMode
    
    /// Enable looping (true = cycle playlist, false = play once and stop)
    /// @deprecated Use repeatMode instead
    @available(*, deprecated, message: "Use repeatMode instead. Set to .playlist for looping, .off for no repeat")
    public var enableLooping: Bool {
        get { repeatMode == .playlist }
        set { repeatMode = newValue ? .playlist : .off }
    }
    
    /// Number of times to repeat playlist
    /// - nil: Infinite repeats (loop forever)
    /// - 0: Play once (same as repeatMode = .off)
    /// - N: Loop N times then stop
    public var repeatCount: Int?
    
    /// Fade in duration at track start when repeatMode = .singleTrack (0.5-10.0 seconds)
    public var singleTrackFadeInDuration: TimeInterval
    
    /// Fade out duration at track end when repeatMode = .singleTrack (0.5-10.0 seconds)
    public var singleTrackFadeOutDuration: TimeInterval
    
    // MARK: - Audio Settings
    
    /// Volume level (0-100, where 100 is maximum)
    /// Internally converted to Float 0.0-1.0
    public var volume: Int
    
    // MARK: - Stop Settings
    
    /// Default fade duration when stopping playback with fade (0.5-10.0 seconds)
    /// Used by stopWithDefaultFade() method
    /// - Note: Set to 0.0 for instant stop without fade
    public var stopFadeDuration: TimeInterval
    
    // MARK: - Audio Session Settings
    
    /// Mix with other audio apps (default: false - interrupts other audio)
    /// When true, allows playing alongside other audio sources (music, podcasts, etc.)
    /// When false, interrupts other audio sources (exclusive playback)
    public var mixWithOthers: Bool
    
    // MARK: - Computed Properties
    
    /// Fade in duration at track start (30% of crossfade)
    public var fadeInDuration: TimeInterval {
        crossfadeDuration * 0.3
    }
    
    /// Volume as Float (0.0-1.0) for internal use
    public var volumeFloat: Float {  // Made public for AudioPlayerService extension
        Float(max(0, min(100, volume))) / 100.0
    }
    
    // MARK: - Initialization
    
    public init(
        crossfadeDuration: TimeInterval = 10.0,
        fadeCurve: FadeCurve = .equalPower,
        repeatMode: RepeatMode = .off,
        repeatCount: Int? = nil,
        singleTrackFadeInDuration: TimeInterval = 3.0,
        singleTrackFadeOutDuration: TimeInterval = 3.0,
        volume: Int = 100,
        stopFadeDuration: TimeInterval = 3.0,
        mixWithOthers: Bool = false
    ) {
        self.crossfadeDuration = max(1.0, min(30.0, crossfadeDuration))
        self.fadeCurve = fadeCurve
        self.repeatMode = repeatMode
        self.repeatCount = repeatCount
        self.singleTrackFadeInDuration = max(0.5, min(10.0, singleTrackFadeInDuration))
        self.singleTrackFadeOutDuration = max(0.5, min(10.0, singleTrackFadeOutDuration))
        self.volume = max(0, min(100, volume))
        self.stopFadeDuration = max(0.0, min(10.0, stopFadeDuration))
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
        if volume < 0 || volume > 100 {
            throw ConfigurationError.invalidVolume(volume)
        }
        
        // RepeatCount validation
        if let count = repeatCount, count < 0 {
            throw ConfigurationError.invalidRepeatCount(count)
        }
        
        // StopFadeDuration validation
        if stopFadeDuration < 0.0 || stopFadeDuration > 10.0 {
            throw ConfigurationError.invalidStopFadeDuration(stopFadeDuration)
        }
        
        // Single track fade durations validation
        if singleTrackFadeInDuration < 0.5 || singleTrackFadeInDuration > 10.0 {
            throw ConfigurationError.invalidSingleTrackFadeInDuration(singleTrackFadeInDuration)
        }
        
        if singleTrackFadeOutDuration < 0.5 || singleTrackFadeOutDuration > 10.0 {
            throw ConfigurationError.invalidSingleTrackFadeOutDuration(singleTrackFadeOutDuration)
        }
    }
}

// MARK: - Configuration Errors

public enum ConfigurationError: Error, LocalizedError {
    case invalidCrossfadeDuration(TimeInterval)
    case invalidVolume(Int)
    case invalidRepeatCount(Int)
    case invalidStopFadeDuration(TimeInterval)
    case invalidSingleTrackFadeInDuration(TimeInterval)
    case invalidSingleTrackFadeOutDuration(TimeInterval)
    
    public var errorDescription: String? {
        switch self {
        case .invalidCrossfadeDuration(let duration):
            return "Crossfade duration must be between 1.0 and 30.0 seconds (got \(duration))"
        case .invalidVolume(let volume):
            return "Volume must be between 0 and 100 (got \(volume))"
        case .invalidRepeatCount(let count):
            return "Repeat count must be >= 0 or nil for infinite (got \(count))"
        case .invalidStopFadeDuration(let duration):
            return "Stop fade duration must be between 0.0 and 10.0 seconds (got \(duration))"
        case .invalidSingleTrackFadeInDuration(let duration):
            return "Single track fade in duration must be between 0.5 and 10.0 seconds (got \(duration))"
        case .invalidSingleTrackFadeOutDuration(let duration):
            return "Single track fade out duration must be between 0.5 and 10.0 seconds (got \(duration))"
        }
    }
}

// MARK: - Migration Helper (Deprecated)

extension PlayerConfiguration {
    /// Create from legacy AudioConfiguration
    /// - Parameter audioConfig: Legacy configuration
    /// - Returns: New PlayerConfiguration
    @available(*, deprecated, message: "Use PlayerConfiguration directly")
    public static func fromAudioConfiguration(_ audioConfig: AudioConfiguration) -> PlayerConfiguration {
        PlayerConfiguration(
            crossfadeDuration: audioConfig.crossfadeDuration,
            fadeCurve: audioConfig.fadeCurve,
            repeatMode: .playlist,  // Legacy behavior
            repeatCount: audioConfig.repeatCount,
            volume: Int(audioConfig.volume * 100)
        )
    }
}
