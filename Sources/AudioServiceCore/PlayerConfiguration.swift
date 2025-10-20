import Foundation
import AVFoundation

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
    
    // MARK: - Audio Session Presets
    
    /// Default audio session options for peaceful coexistence with other audio apps
    /// 
    /// **Configuration:**
    /// - `.mixWithOthers`: Play alongside other apps (no audio session war)
    /// - `.allowBluetoothA2DP`: High-quality Bluetooth audio (output + input)
    /// - `.allowAirPlay`: AirPlay streaming support
    /// 
    /// This preset ensures the SDK:
    /// - Coexists peacefully with other audio apps
    /// - Supports Bluetooth headsets (audio + microphone)
    /// - Supports AirPlay streaming
    /// - Works with `.playAndRecord` category (for microphone access)
    /// 
    /// **Note:** The following options are NOT included:
    /// - `.duckOthers`: Requires special modes (.voiceChat, .videoChat, .spokenAudio)
    ///   Using this with `.default` mode causes **error -50** on real devices.
    /// 
    /// **Category:** These options are compatible with `.playAndRecord` category,
    /// which allows both audio playback AND microphone recording.
    /// 
    /// **Warning:** Only override if you understand iOS audio session behavior!
    /// Custom options may cause conflicts with other audio sources.
    public static let defaultAudioSessionOptions: [AVAudioSession.CategoryOptions] = [
        .mixWithOthers,      // Coexist peacefully with other audio
        .allowBluetoothA2DP, // Bluetooth support (headsets, speakers)
        .allowAirPlay,       // AirPlay streaming support
        .defaultToSpeaker    // Use loudspeaker instead of ear speaker (for .playAndRecord category)
    ]
    
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
    
    /// Audio session category options
    /// 
    /// **Default:** `PlayerConfiguration.defaultAudioSessionOptions`
    /// - Peaceful coexistence with other audio apps
    /// - High-quality Bluetooth and AirPlay support
    /// 
    /// **Custom Options:**
    /// Only override if you have specific audio session requirements.
    /// 
    /// **Warning:** Custom options trigger a console warning to ensure intentional use.
    /// 
    /// **Example:**
    /// ```swift
    /// // Use defaults (recommended)
    /// let config = PlayerConfiguration()
    /// 
    /// // Custom options (advanced)
    /// let customConfig = PlayerConfiguration(
    ///     audioSessionOptions: [.mixWithOthers, .duckOthers]
    /// )
    /// ```
    public let audioSessionOptions: [AVAudioSession.CategoryOptions]
    
    // MARK: - Computed Properties
    
    
    
    // MARK: - Initialization
    
    public init(
        crossfadeDuration: TimeInterval = 10.0,
        fadeCurve: FadeCurve = .equalPower,
        repeatMode: RepeatMode = .off,
        repeatCount: Int? = nil,
        volume: Float = 1.0,
        audioSessionOptions: [AVAudioSession.CategoryOptions] = PlayerConfiguration.defaultAudioSessionOptions
    ) {
        self.crossfadeDuration = max(1.0, min(30.0, crossfadeDuration))
        self.fadeCurve = fadeCurve
        self.repeatMode = repeatMode
        self.repeatCount = repeatCount
        self.volume = max(0.0, min(1.0, volume))
        self.audioSessionOptions = audioSessionOptions
        
        // Warning: User is overriding default audio session options
        if audioSessionOptions != PlayerConfiguration.defaultAudioSessionOptions {
            print("")
            print("⚠️ WARNING: Custom audio session options detected!")
            print("  You are using custom AVAudioSession.CategoryOptions instead of defaults.")
            print("  Default options: \(PlayerConfiguration.defaultAudioSessionOptions)")
            print("  Your options:    \(audioSessionOptions)")
            print("  ")
            print("  This may cause conflicts with:")
            print("    - Other audio apps (AVAudioPlayer, music apps)")
            print("    - System audio (alerts, notifications)")
            print("    - Bluetooth/AirPlay devices")
            print("  ")
            print("  Only use custom options if you understand iOS audio session behavior!")
            print("  Recommended: Use PlayerConfiguration.defaultAudioSessionOptions")
            print("")
        }
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

