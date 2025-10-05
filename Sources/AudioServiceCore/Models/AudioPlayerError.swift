import Foundation

/// Errors that can occur during audio playback
public enum AudioPlayerError: Error, Sendable, Equatable {
    /// Failed to load audio file
    case fileLoadFailed(reason: String)
    
    /// Audio session configuration failed
    case sessionConfigurationFailed(reason: String)
    
    /// Audio engine failed to start
    case engineStartFailed(reason: String)
    
    /// Invalid audio format
    case invalidFormat(reason: String)
    
    /// Invalid operation in current state
    case invalidState(current: String, attempted: String)
    
    /// Hardware route change failed
    case routeChangeFailed(reason: String)
    
    /// Buffer scheduling failed
    case bufferSchedulingFailed(reason: String)
    
    /// Playlist is empty (cannot play)
    case emptyPlaylist
    
    /// No active track playing
    case noActiveTrack
    
    /// Invalid playlist index
    case invalidPlaylistIndex(index: Int, count: Int)
    
    /// Unknown error occurred
    case unknown(reason: String)
    
    public var localizedDescription: String {
        switch self {
        case .fileLoadFailed(let reason):
            return "Failed to load audio file: \(reason)"
        case .sessionConfigurationFailed(let reason):
            return "Audio session configuration failed: \(reason)"
        case .engineStartFailed(let reason):
            return "Audio engine failed to start: \(reason)"
        case .invalidFormat(let reason):
            return "Invalid audio format: \(reason)"
        case .invalidState(let current, let attempted):
            return "Cannot \(attempted) in \(current) state"
        case .routeChangeFailed(let reason):
            return "Audio route change failed: \(reason)"
        case .bufferSchedulingFailed(let reason):
            return "Buffer scheduling failed: \(reason)"
        case .emptyPlaylist:
            return "Playlist is empty - add tracks before playing"
        case .noActiveTrack:
            return "No active track playing"
        case .invalidPlaylistIndex(let index, let count):
            return "Invalid playlist index \(index) (playlist has \(count) tracks)"
        case .unknown(let reason):
            return "Unknown error: \(reason)"
        }
    }
}
