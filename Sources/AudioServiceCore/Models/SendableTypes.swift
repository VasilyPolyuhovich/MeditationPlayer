import Foundation

/// Audio format information that can be safely passed between actors
public struct AudioFormat: Sendable, Equatable {
    /// Sample rate in Hz (typically 44100 or 48000)
    public let sampleRate: Double
    
    /// Number of audio channels (1 = mono, 2 = stereo)
    public let channelCount: Int
    
    /// Bit depth for audio samples
    public let bitDepth: Int
    
    /// Whether audio is interleaved
    public let isInterleaved: Bool
    
    public init(
        sampleRate: Double,
        channelCount: Int,
        bitDepth: Int = 32,
        isInterleaved: Bool = false
    ) {
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.bitDepth = bitDepth
        self.isInterleaved = isInterleaved
    }
    
    /// Standard format for playback (Float32, 48kHz, stereo, non-interleaved)
    public static var standard: AudioFormat {
        AudioFormat(
            sampleRate: 48000.0,
            channelCount: 2,
            bitDepth: 32,
            isInterleaved: false
        )
    }
}

/// Playback position information
public struct PlaybackPosition: Sendable, Equatable {
    /// Current playback time in seconds
    public let currentTime: TimeInterval
    
    /// Total duration in seconds
    public let duration: TimeInterval
    
    /// Progress as percentage (0.0 - 1.0)
    public var progress: Double {
        guard duration > 0 else { return 0 }
        return currentTime / duration
    }
    
    /// Remaining time in seconds
    public var remainingTime: TimeInterval {
        return max(0, duration - currentTime)
    }
    
    public init(currentTime: TimeInterval, duration: TimeInterval) {
        self.currentTime = currentTime
        self.duration = duration
    }
}

/// Information about currently playing track
///
/// **DEPRECATED:** Use `Track.Metadata` instead.
/// This typealias provides backward compatibility during migration.
@available(*, deprecated, renamed: "Track.Metadata", message: "Use Track.Metadata instead of TrackInfo")
public typealias TrackInfo = Track.Metadata
