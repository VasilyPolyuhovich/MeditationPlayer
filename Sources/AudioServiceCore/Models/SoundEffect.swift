import Foundation
import AVFoundation

/// Sound effect ready for instant playback
///
/// Wraps a validated Track with playback metadata (fade, volume).
/// Audio buffer is loaded into RAM for instant trigger response.
///
/// Example:
/// ```swift
/// // Create and preload
/// let gong = try await SoundEffect(
///     url: Bundle.main.url(forResource: "gong", withExtension: "mp3")!,
///     fadeIn: 0.1,
///     fadeOut: 0.5,
///     volume: 0.9
/// )
///
/// await soundEffects.preload(gong)
/// await soundEffects.play(gong.id)  // Instant!
/// ```
public struct SoundEffect: Identifiable, Sendable {
    /// Unique identifier (from Track)
    public var id: UUID { track.id }

    /// Validated audio track
    public let track: Track

    /// Fade-in duration in seconds (0.0 = no fade)
    public let fadeInDuration: TimeInterval

    /// Fade-out duration in seconds (0.0 = no fade)
    public let fadeOutDuration: TimeInterval

    /// Playback volume (0.0 - 1.0)
    public let volume: Float

    /// Preloaded audio buffer (loaded into RAM)
    /// nonisolated(unsafe): Safe because buffer is immutable after creation
    package nonisolated(unsafe) let buffer: AVAudioPCMBuffer

    /// Create sound effect with validation and preloading
    ///
    /// Returns `nil` if:
    /// - File doesn't exist (validation via Track)
    /// - Audio file cannot be loaded
    ///
    /// - Parameters:
    ///   - url: Audio file URL
    ///   - fadeIn: Fade-in duration (default: 0.0)
    ///   - fadeOut: Fade-out duration (default: 0.3)
    ///   - volume: Playback volume 0.0-1.0 (default: 0.8)
    public init?(
        url: URL,
        fadeIn: TimeInterval = 0.0,
        fadeOut: TimeInterval = 0.3,
        volume: Float = 0.8
    ) async throws {
        // Validate file exists via Track
        guard let track = Track(url: url) else {
            return nil  // File not found
        }

        // Load audio file into buffer (RAM)
        let file = try AVAudioFile(forReading: url)

        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: file.processingFormat,
            frameCapacity: AVAudioFrameCount(file.length)
        ) else {
            throw AudioPlayerError.fileLoadFailed(reason: "Cannot create audio buffer for \(url.lastPathComponent)")
        }

        try file.read(into: buffer)

        // Initialize
        self.track = track
        self.fadeInDuration = fadeIn
        self.fadeOutDuration = fadeOut
        self.volume = min(1.0, max(0.0, volume))  // Clamp 0-1
        self.buffer = buffer
    }
}
