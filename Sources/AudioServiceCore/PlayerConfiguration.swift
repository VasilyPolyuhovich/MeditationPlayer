import Foundation

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
    
    /// Enable looping (true = cycle playlist, false = play once and stop)
    public var enableLooping: Bool
    
    /// Number of times to repeat playlist
    /// - nil: Infinite repeats (loop forever)
    /// - 0: Play once (same as enableLooping = false)
    /// - N: Loop N times then stop
    public var repeatCount: Int?
    
    // MARK: - Audio Settings
    
    /// Volume level (0-100, where 100 is maximum)
    /// Internally converted to Float 0.0-1.0
    public var volume: Int
    
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
        enableLooping: Bool = true,
        repeatCount: Int? = nil,
        volume: Int = 100
    ) {
        self.crossfadeDuration = max(1.0, min(30.0, crossfadeDuration))
        self.fadeCurve = fadeCurve
        self.enableLooping = enableLooping
        self.repeatCount = repeatCount
        self.volume = max(0, min(100, volume))
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
    }
}

// MARK: - Configuration Errors

public enum ConfigurationError: Error, LocalizedError {
    case invalidCrossfadeDuration(TimeInterval)
    case invalidVolume(Int)
    case invalidRepeatCount(Int)
    
    public var errorDescription: String? {
        switch self {
        case .invalidCrossfadeDuration(let duration):
            return "Crossfade duration must be between 1.0 and 30.0 seconds (got \(duration))"
        case .invalidVolume(let volume):
            return "Volume must be between 0 and 100 (got \(volume))"
        case .invalidRepeatCount(let count):
            return "Repeat count must be >= 0 or nil for infinite (got \(count))"
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
            enableLooping: audioConfig.enableLooping,
            repeatCount: audioConfig.repeatCount,
            volume: Int(audioConfig.volume * 100)
        )
    }
}
