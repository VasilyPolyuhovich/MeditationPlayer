import Foundation
import AVFoundation
import AudioServiceCore

/// Manages playlist state and navigation
/// Handles track sequencing, repeat logic, and dynamic playlist modifications
actor PlaylistManager {

    // MARK: - Properties

    /// Current playlist tracks
    private(set) var tracks: [Track] = []

    /// Current track index in playlist
    private(set) var currentIndex: Int = 0

    /// Configuration for playback behavior
    private var configuration: PlayerConfiguration

    /// Current repeat iteration count (for repeatCount tracking)
    private var currentRepeatCount: Int = 0

    // MARK: - Initialization

    init(configuration: PlayerConfiguration = .default) {
        self.configuration = configuration
    }

    // MARK: - Playlist Management

    /// Load new playlist and reset state
    /// - Parameter tracks: Array of tracks
    func load(tracks: [Track]) {
        self.tracks = tracks
        self.currentIndex = 0
        self.currentRepeatCount = 0
    }

    /// Load new playlist from URLs (backward compatibility)
    /// - Parameter tracks: Array of track URLs
    /// - Note: Invalid URLs (files not found) are automatically filtered out
    func load(tracks urls: [URL]) {
        let validTracks = urls.toTracks()
        if validTracks.count < urls.count {
            print("[PlaylistManager] ⚠️ Warning: \(urls.count - validTracks.count) tracks filtered out (files not found)")
        }
        self.load(tracks: validTracks)
    }

    /// Add track to end of playlist
    /// - Parameter track: Track to add
    func addTrack(_ track: Track) {
        tracks.append(track)
    }

    /// Add track from URL (backward compatibility)
    /// - Parameter url: Track URL to add
    /// - Note: Silently fails if file doesn't exist
    func addTrack(_ url: URL) {
        guard let track = Track(url: url) else {
            print("[PlaylistManager] ⚠️ Warning: Track not added - file not found: \(url.lastPathComponent)")
            return
        }
        tracks.append(track)
    }

    /// Insert track at specific position
    /// - Parameters:
    ///   - track: Track to insert
    ///   - index: Position to insert at
    func insertTrack(_ track: Track, at index: Int) {
        guard index <= tracks.count else { return }
        tracks.insert(track, at: index)

        // Adjust current index if insertion affects it
        if index <= currentIndex {
            currentIndex += 1
        }
    }

    /// Insert track from URL (backward compatibility)
    /// - Parameters:
    ///   - url: Track URL to insert
    ///   - index: Position to insert at
    func insertTrack(_ url: URL, at index: Int) {
        guard let track = Track(url: url) else {
            print("[PlaylistManager] ⚠️ Warning: Track not inserted - file not found: \(url.lastPathComponent)")
            return
        }
        insertTrack(track, at: index)
    }

    /// Remove track at index
    /// - Parameter index: Index of track to remove
    /// - Returns: True if removed, false if index invalid
    @discardableResult
    func removeTrack(at index: Int) -> Bool {
        guard index < tracks.count else { return false }

        tracks.remove(at: index)

        // Adjust current index if needed
        if index < currentIndex {
            currentIndex -= 1
        } else if index == currentIndex && currentIndex >= tracks.count {
            // Removed current track and it was last - move to previous
            currentIndex = max(0, tracks.count - 1)
        }

        return true
    }

    /// Move track from one position to another
    /// - Parameters:
    ///   - fromIndex: Source index
    ///   - toIndex: Destination index
    /// - Returns: True if moved successfully
    @discardableResult
    func moveTrack(from fromIndex: Int, to toIndex: Int) -> Bool {
        guard fromIndex < tracks.count && toIndex < tracks.count else { return false }
        guard fromIndex != toIndex else { return true }

        let track = tracks.remove(at: fromIndex)
        tracks.insert(track, at: toIndex)

        // Adjust current index
        if fromIndex == currentIndex {
            // Moving current track
            currentIndex = toIndex
        } else if fromIndex < currentIndex && toIndex >= currentIndex {
            // Track moved from before to after current
            currentIndex -= 1
        } else if fromIndex > currentIndex && toIndex <= currentIndex {
            // Track moved from after to before current
            currentIndex += 1
        }

        return true
    }

    /// Clear entire playlist
    func clear() {
        tracks.removeAll()
        currentIndex = 0
        currentRepeatCount = 0
    }

    /// Replace entire playlist and reset state
    /// - Parameter tracks: New playlist tracks
    /// - Note: Resets currentIndex to 0 and repeatCount to 0
    /// - Note: Used by replacePlaylist() API for hot playlist replacement
    func replacePlaylist(_ tracks: [Track]) {
        self.tracks = tracks
        self.currentIndex = 0
        self.currentRepeatCount = 0
    }

    /// Replace playlist from URLs (backward compatibility)
    /// - Parameter tracks: New playlist track URLs
    /// - Note: Invalid URLs are automatically filtered out
    func replacePlaylist(_ urls: [URL]) {
        let validTracks = urls.toTracks()
        if validTracks.count < urls.count {
            print("[PlaylistManager] ⚠️ Warning: \(urls.count - validTracks.count) tracks filtered out (files not found)")
        }
        self.replacePlaylist(validTracks)
    }

    /// Get current playlist tracks (NEW)
    /// - Returns: Array of all tracks in current playlist
    func getTracks() -> [Track] {
        return tracks
    }

    /// Get current playlist URLs (backward compatibility)
    /// - Returns: Array of all track URLs in current playlist
    func getPlaylist() -> [URL] {
        return tracks.urls
    }

    // MARK: - Navigation

    /// Get current track
    /// - Returns: Current track or nil if playlist empty
    func getCurrentTrack() -> Track? {
        guard currentIndex < tracks.count else { return nil }
        return tracks[currentIndex]
    }

    /// Get current track URL (backward compatibility)
    /// - Returns: Current track URL or nil if playlist empty
    func getCurrentTrackURL() -> URL? {
        return getCurrentTrack()?.url
    }

    /// Get next track according to repeat mode
    /// - Returns: Next track, nil if should stop
    func getNextTrack() -> Track? {
        guard !tracks.isEmpty else { return nil }

        switch configuration.repeatMode {
        case .off:
            // Play once, no repeat
            return getNextTrackSequential()

        case .singleTrack:
            // Loop current track - return same track
            return tracks[currentIndex]

        case .playlist:
            // Loop entire playlist
            return getNextTrackLooping()
        }
    }

    /// Check if should advance to next track based on repeat mode
    /// - Returns: True if should advance, false if should loop current or stop
    func shouldAdvanceToNextTrack() -> Bool {
        guard !tracks.isEmpty else { return false }

        switch configuration.repeatMode {
        case .off:
            // Advance until end of playlist
            return currentIndex + 1 < tracks.count

        case .singleTrack:
            // Never advance - loop current track
            return false

        case .playlist:
            // Always advance in playlist loop
            return true
        }
    }

    /// Jump to specific track index
    /// - Parameter index: Target index
    /// - Returns: Track at index, nil if invalid
    @discardableResult
    func jumpTo(index: Int) -> Track? {
        guard index < tracks.count else { return nil }
        currentIndex = index
        return tracks[currentIndex]
    }

    /// Jump to next track (manual skip forward)
    /// - Returns: Next track, nil if at end in sequential mode
    func skipToNext() -> Track? {
        guard !tracks.isEmpty else { return nil }

        if tracks.count == 1 {
            // Single track - return same track for loop
            return tracks[0]
        }

        // Check repeat mode for navigation behavior
        switch configuration.repeatMode {
        case .off:
            // Sequential mode - return nil at end
            if currentIndex + 1 < tracks.count {
                currentIndex += 1
                return tracks[currentIndex]
            } else {
                return nil // At end, no wrap-around
            }

        case .singleTrack, .playlist:
            // Loop mode - wrap around
            currentIndex = (currentIndex + 1) % tracks.count
            return tracks[currentIndex]
        }
    }

    /// Jump to previous track (manual skip backward)
    /// - Returns: Previous track, nil if at start in sequential mode
    func skipToPrevious() -> Track? {
        guard !tracks.isEmpty else { return nil }

        if tracks.count == 1 {
            // Single track - return same track
            return tracks[0]
        }

        // Check repeat mode for navigation behavior
        switch configuration.repeatMode {
        case .off:
            // Sequential mode - return nil at start
            if currentIndex > 0 {
                currentIndex -= 1
                return tracks[currentIndex]
            } else {
                return nil // At start, no wrap-around
            }

        case .singleTrack, .playlist:
            // Loop mode - wrap around
            currentIndex = (currentIndex - 1 + tracks.count) % tracks.count
            return tracks[currentIndex]
        }
    }

    /// Peek at next track without advancing index
    /// - Returns: Next track without modifying state, nil if at end in sequential mode
    func peekNext() -> Track? {
        guard !tracks.isEmpty else { return nil }

        if tracks.count == 1 {
            // Single track - return same track for loop
            return tracks[0]
        }

        // Calculate next index based on repeat mode
        switch configuration.repeatMode {
        case .off:
            // Sequential mode - return nil at end
            if currentIndex + 1 < tracks.count {
                let nextIndex = currentIndex + 1
                return tracks[nextIndex]
            } else {
                return nil // At end, no wrap-around
            }

        case .singleTrack, .playlist:
            // Loop mode - wrap around
            let nextIndex = (currentIndex + 1) % tracks.count
            return tracks[nextIndex]
        }
    }

    /// Peek at previous track without changing index
    /// - Returns: Previous track without modifying state, nil if at start in sequential mode
    func peekPrevious() -> Track? {
        guard !tracks.isEmpty else { return nil }

        if tracks.count == 1 {
            // Single track - return same track
            return tracks[0]
        }

        // Calculate previous index based on repeat mode
        switch configuration.repeatMode {
        case .off:
            // Sequential mode - return nil at start
            if currentIndex > 0 {
                let prevIndex = currentIndex - 1
                return tracks[prevIndex]
            } else {
                return nil // At start, no wrap-around
            }

        case .singleTrack, .playlist:
            // Loop mode - wrap around
            let prevIndex = (currentIndex - 1 + tracks.count) % tracks.count
            return tracks[prevIndex]
        }
    }

    // MARK: - State Queries

    /// Check if playlist is empty
    var isEmpty: Bool {
        tracks.isEmpty
    }

    /// Check if playlist has only one track
    var isSingleTrack: Bool {
        tracks.count == 1
    }

    /// Get playlist count
    var count: Int {
        tracks.count
    }

    /// Get current repeat count
    var repeatCount: Int {
        currentRepeatCount
    }

    /// Update configuration
    func updateConfiguration(_ configuration: PlayerConfiguration) {
        self.configuration = configuration
    }
    
    // MARK: - File Load Retry Support (Bug Fix #1)
    
    /// Restore playlist index (rollback on validation failure)
    /// - Parameter index: Index to restore
    func restoreIndex(_ index: Int) {
        self.currentIndex = index
    }
    
    /// Validate track file accessibility and audio format
    /// - Parameter track: Track to validate
    /// - Returns: True if track is valid and playable
    func validateTrack(_ track: Track) async -> Bool {
        // Check file exists
        guard FileManager.default.fileExists(atPath: track.url.path) else {
            print("[PlaylistManager] ⚠️ Track validation failed: file not found - \(track.url.lastPathComponent)")
            return false
        }
        
        // Attempt to open audio file (validates format and readability)
        do {
            let file = try AVAudioFile(forReading: track.url)
            _ = file.processingFormat // Access format to ensure file is readable
            return true
        } catch {
            print("[PlaylistManager] ⚠️ Track validation failed: \(track.url.lastPathComponent), error: \(error.localizedDescription)")
            return false
        }
    }
    
    /// Skip to track with automatic retry on validation failure (two-phase commit)
    /// - Parameters:
    ///   - direction: Skip direction (.next or .previous)
    ///   - maxAttempts: Maximum validation attempts (default: 3)
    /// - Returns: Valid track or nil if all attempts failed
    func skipToTrackWithRetry(
        direction: SkipDirection,
        maxAttempts: Int = 3
    ) async -> Track? {
        guard !tracks.isEmpty else { return nil }
        
        // Phase 0: Save original index for rollback
        let originalIndex = currentIndex
        var attempts = 0
        
        while attempts < maxAttempts {
            attempts += 1
            
            // Phase 1: Peek at candidate track (non-destructive)
            guard let candidateTrack = peekInDirection(direction) else {
                print("[PlaylistManager] No more tracks in \(direction) direction")
                restoreIndex(originalIndex)
                return nil
            }
            
            // Phase 2: Validate track file
            let isValid = await validateTrack(candidateTrack)
            
            if isValid {
                // Phase 3: Commit index change
                _ = skipInDirection(direction)
                print("[PlaylistManager] ✅ Skip successful (attempt \(attempts)): \(candidateTrack.url.lastPathComponent)")
                return candidateTrack
            } else {
                // Validation failed - advance to skip corrupted file
                print("[PlaylistManager] ⚠️ Attempt \(attempts) failed, trying next track...")
                _ = skipInDirection(direction)
                
                // Detect infinite loop (wrapped back to start)
                if currentIndex == originalIndex {
                    print("[PlaylistManager] ❌ Wrapped around - all tracks invalid")
                    restoreIndex(originalIndex)
                    return nil
                }
            }
        }
        
        // All attempts exhausted
        print("[PlaylistManager] ❌ All \(maxAttempts) attempts failed")
        restoreIndex(originalIndex)
        return nil
    }

    // MARK: - Private Helpers

    /// Get next track in looping mode (playlist repeat)
    private func getNextTrackLooping() -> Track? {
        // Single track - always return it (loop on same track)
        if tracks.count == 1 {
            return tracks[0]
        }

        // Multiple tracks - advance to next
        let nextIndex = (currentIndex + 1) % tracks.count

        // Check if we completed a loop cycle
        if nextIndex == 0 {
            currentRepeatCount += 1

            // Check repeat limit (nil = infinite)
            if let maxRepeats = configuration.repeatCount, currentRepeatCount >= maxRepeats {
                return nil // Reached repeat limit
            }
        }

        currentIndex = nextIndex
        return tracks[currentIndex]
    }

    /// Get next track in sequential mode (play once)
    private func getNextTrackSequential() -> Track? {
        // Check if we're at the end
        if currentIndex + 1 < tracks.count {
            currentIndex += 1
            return tracks[currentIndex]
        } else {
            // End of playlist - stop
            return nil
        }
    }
    
    /// Peek at track in specified direction without modifying index
    private func peekInDirection(_ direction: SkipDirection) -> Track? {
        switch direction {
        case .next:
            return peekNext()
        case .previous:
            return peekPrevious()
        }
    }
    
    /// Skip in specified direction (commits index change)
    private func skipInDirection(_ direction: SkipDirection) -> Track? {
        switch direction {
        case .next:
            return skipToNext()
        case .previous:
            return skipToPrevious()
        }
    }
}

// MARK: - Skip Direction

/// Direction for track navigation with retry
enum SkipDirection {
    case next
    case previous
}
