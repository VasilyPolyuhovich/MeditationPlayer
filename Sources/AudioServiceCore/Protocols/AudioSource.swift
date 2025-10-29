import Foundation

/// Protocol for audio source that provides audio content
public protocol AudioSource: Sendable {
    /// Load audio file from source
    /// - Returns: URL of loaded audio file
    /// - Throws: AudioPlayerError if loading fails
    func load() async throws -> URL

    /// Get track information without loading full file
    /// - Returns: Track metadata
    func getTrackInfo() async throws -> TrackInfo

    /// Release any held resources
    func cleanup() async
}

/// Local file audio source
public struct LocalAudioSource: AudioSource {
    private let fileURL: URL
    private let title: String?
    private let artist: String?

    public init(fileURL: URL, title: String? = nil, artist: String? = nil) {
        self.fileURL = fileURL
        self.title = title
        self.artist = artist
    }

    public func load() async throws -> URL {
        // Verify file exists
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw AudioPlayerError.fileLoadFailed(reason: "File not found at \(fileURL.path)")
        }
        return fileURL
    }

    public func getTrackInfo() async throws -> TrackInfo {
        // For now, return basic info - will be enhanced when we load AVAudioFile
        return TrackInfo(
            title: title ?? fileURL.lastPathComponent,
            artist: artist,
            duration: 0, // Will be updated after loading
            format: .standard
        )
    }

    public func cleanup() async {
        // Local files don't need cleanup
    }
}
