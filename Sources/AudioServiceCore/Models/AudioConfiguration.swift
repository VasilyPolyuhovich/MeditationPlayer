import Foundation

/// Types of fade curves for audio crossfading
public enum FadeCurve: Sendable, Equatable {
    /// Linear fade - simple but not perceptually optimal
    case linear
    
    /// Equal-power (constant-power) fade - maintains constant perceived loudness
    /// Best for crossfading between similar audio sources (DEFAULT)
    case equalPower
    
    /// Logarithmic fade - smooth natural-sounding fade
    case logarithmic
    
    /// Exponential fade - opposite of logarithmic
    case exponential
    
    /// S-curve (sigmoid) - slow at start/end, fast in middle
    case sCurve
}

/// Configuration for audio playback behavior
public struct AudioConfiguration: Sendable, Equatable {
    /// Duration of crossfade between loop iterations (1-30 seconds)
    public let crossfadeDuration: TimeInterval
    
    /// Duration of fade in at playback start
    public let fadeInDuration: TimeInterval
    
    /// Duration of fade out at playback end
    public let fadeOutDuration: TimeInterval
    
    /// Master volume level (0.0 - 1.0)
    public let volume: Float
    
    /// Number of times to repeat playback (nil = infinite)
    public let repeatCount: Int?
    
    /// Whether to enable looping with crossfade
    public let enableLooping: Bool
    
    /// Fade curve type for smooth transitions
    public let fadeCurve: FadeCurve
    
    /// Default fade duration when stopping playback with fade (0.0-10.0 seconds)
    public let stopFadeDuration: TimeInterval
    
    public init(
        crossfadeDuration: TimeInterval = 10.0,
        fadeInDuration: TimeInterval = 3.0,
        fadeOutDuration: TimeInterval = 6.0,
        volume: Float = 1.0,
        repeatCount: Int? = nil,
        enableLooping: Bool = true,
        fadeCurve: FadeCurve = .equalPower,
        stopFadeDuration: TimeInterval = 3.0
    ) {
        // Validate and clamp values
        self.crossfadeDuration = max(1.0, min(30.0, crossfadeDuration))
        self.fadeInDuration = max(0.0, min(10.0, fadeInDuration))
        self.fadeOutDuration = max(0.0, min(10.0, fadeOutDuration))
        self.volume = max(0.0, min(1.0, volume))
        self.repeatCount = repeatCount
        self.enableLooping = enableLooping
        self.fadeCurve = fadeCurve
        self.stopFadeDuration = max(0.0, min(10.0, stopFadeDuration))
    }
    
    /// Validate configuration parameters
    public func validate() throws {
        guard volume >= 0.0 && volume <= 1.0 else {
            throw AudioPlayerError.invalidFormat(reason: "Volume must be between 0.0 and 1.0")
        }
        
        guard crossfadeDuration >= 1.0 && crossfadeDuration <= 30.0 else {
            throw AudioPlayerError.invalidFormat(reason: "Crossfade duration must be between 1 and 30 seconds")
        }
        
        if let count = repeatCount, count < 0 {
            throw AudioPlayerError.invalidFormat(reason: "Repeat count cannot be negative")
        }
        
        guard stopFadeDuration >= 0.0 && stopFadeDuration <= 10.0 else {
            throw AudioPlayerError.invalidFormat(reason: "Stop fade duration must be between 0.0 and 10.0 seconds")
        }
    }
}
