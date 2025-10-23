import Foundation

/// Represents a single audio track
///
/// Minimal structure with automatic validation.
/// Files that don't exist will fail initialization (return nil).
///
/// Example:
/// ```swift
/// // From bundle
/// let urls = [
///     Bundle.main.url(forResource: "ocean", withExtension: "mp3"),
///     Bundle.main.url(forResource: "forest", withExtension: "mp3")
/// ].compactMap { $0 }
///
/// let tracks = urls.compactMap { Track(url: $0) }
/// print("✅ Loaded \(tracks.count) valid tracks")
/// ```
public struct Track: Identifiable, Sendable, Equatable {
    /// Unique identifier
    public let id: UUID

    /// URL to audio file (local or remote)
    public let url: URL
    
    /// Track metadata (filled after AVAudioFile load)
    ///
    /// This field is `nil` until the audio file is loaded by AudioEngine.
    /// Once loaded, contains duration, format, and optional title/artist.
    public var metadata: Metadata?

    /// Create track with validation
    ///
    /// Returns `nil` if:
    /// - File URL points to non-existent file
    ///
    /// Remote URLs (http/https) are not validated.
    ///
    /// - Parameter url: Audio file URL
    public init?(url: URL) {
        // Validate file URLs (local files, including bundle)
        if url.isFileURL {
            guard FileManager.default.fileExists(atPath: url.path) else {
                return nil  // File not found
            }
        }
        // Remote URLs (http/https) - skip validation

        self.id = UUID()
        self.url = url
    }

    // MARK: - Equatable

    public static func == (lhs: Track, rhs: Track) -> Bool {
        lhs.id == rhs.id
    }
    
    // MARK: - Nested Types
    
    /// Track metadata extracted from audio file
    ///
    /// Created by AudioEngine when loading AVAudioFile.
    /// Contains file properties like duration and format.
    public struct Metadata: Sendable, Equatable {
        /// Track title (extracted from file metadata or filename)
        public let title: String?
        
        /// Track artist or creator
        public let artist: String?
        
        /// Track duration in seconds
        public let duration: TimeInterval
        
        /// Audio format information
        public let format: AudioFormat
        
        public init(
            title: String? = nil,
            artist: String? = nil,
            duration: TimeInterval,
            format: AudioFormat
        ) {
            self.title = title
            self.artist = artist
            self.duration = duration
            self.format = format
        }
    }
}

// MARK: - Convenience Extensions

extension Array where Element == URL {
    /// Convert URL array to Track array with validation
    ///
    /// Invalid URLs (files not found) are automatically removed.
    ///
    /// Example:
    /// ```swift
    /// let urls = [validURL, brokenURL, anotherURL]
    /// let tracks = urls.toTracks()  // brokenURL filtered out
    /// print("⚠️ \(urls.count - tracks.count) tracks removed")
    /// ```
    public func toTracks() -> [Track] {
        self.compactMap { Track(url: $0) }
    }
}

extension Array where Element == Track {
    /// Extract URLs from Track array
    public var urls: [URL] {
        self.map { $0.url }
    }
}
