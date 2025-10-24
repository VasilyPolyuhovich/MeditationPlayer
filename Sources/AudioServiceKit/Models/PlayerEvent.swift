import Foundation
import AudioServiceCore

/// Events emitted by AudioPlayerService for UI updates and monitoring
///
/// Use AsyncStream<PlayerEvent> to observe long-running operations
/// and update UI with progress feedback.
///
/// ## Event Categories
///
/// **File Loading Events:**
/// - Track file I/O operations with timeout protection
/// - Report progress for large files
/// - Notify on timeout or errors
///
/// **Crossfade Events:**
/// - Track crossfade progress (0.0-1.0)
/// - Notify on start/complete/cancel
/// - Report timeout if crossfade hangs
///
/// **System Events:**
/// - Audio session interruptions (phone calls, alarms)
/// - Route changes (headphones plug/unplug)
///
/// **State Events:**
/// - Playback state changes (playing/paused/stopped)
/// - Track changes with metadata
///
/// ## Example Usage
///
/// ```swift
/// for await event in player.events {
///     switch event {
///     case .fileLoadStarted(let url):
///         showLoadingIndicator(url)
///     case .fileLoadProgress(_, let progress):
///         updateProgressBar(progress)
///     case .fileLoadCompleted(let url, let duration):
///         hideLoadingIndicator()
///         logMetric("fileLoad", duration)
///     case .fileLoadTimeout(let url):
///         showError("Timeout loading: \(url.lastPathComponent)")
///     }
/// }
/// ```
public enum PlayerEvent: Sendable {

    // MARK: - File Loading

    /// File loading started
    /// - Parameter url: Track URL being loaded
    case fileLoadStarted(URL)

    /// File loading progress update
    /// - Parameters:
    ///   - url: Track URL being loaded
    ///   - progress: Loading progress (0.0-1.0)
    case fileLoadProgress(URL, progress: Double)

    /// File loading completed successfully
    /// - Parameters:
    ///   - url: Track URL that was loaded
    ///   - duration: Time taken to load
    case fileLoadCompleted(URL, duration: Duration)

    /// File loading timed out
    /// - Parameter url: Track URL that timed out
    /// - Note: Timeout duration is adaptive (2x-5x expected time)
    case fileLoadTimeout(URL)

    /// File loading failed with error
    /// - Parameters:
    ///   - url: Track URL that failed
    ///   - error: Error that occurred
    case fileLoadError(URL, Error)

    // MARK: - Crossfade Progress

    /// Crossfade started between tracks
    /// - Parameters:
    ///   - from: Current track title
    ///   - to: Next track title
    case crossfadeStarted(from: String, to: String)

    /// Crossfade progress update
    /// - Parameter progress: Crossfade progress (0.0-1.0)
    case crossfadeProgress(Double)

    /// Crossfade completed successfully
    case crossfadeCompleted

    /// Crossfade cancelled (user skip or stop)
    case crossfadeCancelled

    /// Crossfade timed out (exceeded expected duration)
    case crossfadeTimeout

    // MARK: - System Events

    /// Audio session interrupted (phone call, alarm, etc.)
    case audioSessionInterruption

    /// Audio route changed (headphones plug/unplug)
    case audioSessionRouteChange

    // MARK: - State Changes

    /// Playback state changed
    /// - Parameter state: New playback state
    case stateChanged(PlayerState)

    /// Track changed with metadata
    /// - Parameter metadata: New track metadata
    case trackChanged(Track.Metadata)
}

// MARK: - CustomStringConvertible

extension PlayerEvent: CustomStringConvertible {
    public var description: String {
        switch self {
        case .fileLoadStarted(let url):
            return "FileLoadStarted(\(url.lastPathComponent))"
        case .fileLoadProgress(let url, let progress):
            return "FileLoadProgress(\(url.lastPathComponent), \(Int(progress * 100))%)"
        case .fileLoadCompleted(let url, let duration):
            return "FileLoadCompleted(\(url.lastPathComponent), \(duration.formatted()))"
        case .fileLoadTimeout(let url):
            return "FileLoadTimeout(\(url.lastPathComponent))"
        case .fileLoadError(let url, let error):
            return "FileLoadError(\(url.lastPathComponent), \(error.localizedDescription))"
        case .crossfadeStarted(let from, let to):
            return "CrossfadeStarted(\(from) → \(to))"
        case .crossfadeProgress(let progress):
            return "CrossfadeProgress(\(Int(progress * 100))%)"
        case .crossfadeCompleted:
            return "CrossfadeCompleted"
        case .crossfadeCancelled:
            return "CrossfadeCancelled"
        case .crossfadeTimeout:
            return "CrossfadeTimeout"
        case .audioSessionInterruption:
            return "AudioSessionInterruption"
        case .audioSessionRouteChange:
            return "AudioSessionRouteChange"
        case .stateChanged(let state):
            return "StateChanged(\(state))"
        case .trackChanged(let metadata):
            return "TrackChanged(\(metadata.title ?? "Unknown"))"
        }
    }
}
