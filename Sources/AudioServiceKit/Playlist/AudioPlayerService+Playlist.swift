import Foundation
import AudioServiceCore

// MARK: - Playlist API Extension

extension AudioPlayerService {

    // MARK: - Private Logger

    private static let logger = Logger.playlist

    // MARK: - Playlist Properties

    /// Access playlist manager (already exists as stored property in AudioPlayerService)

    // MARK: - Playlist Management API

    /// Add track to playlist
    /// - Parameter url: Track URL to add
    public func addTrackToPlaylist(_ url: URL) async {
        await playlistManager.addTrack(url)
        Self.logger.debug("Added track to playlist: \(url.lastPathComponent)")
    }

    /// Remove track from playlist at index
    /// - Parameter index: Index of track to remove
    /// - Throws: AudioPlayerError if index invalid
    public func removeTrackFromPlaylist(at index: Int) async throws {
        let count = await playlistManager.count

        guard index < count else {
            throw AudioPlayerError.invalidPlaylistIndex(index: index, count: count)
        }

        await playlistManager.removeTrack(at: index)
        Self.logger.debug("Removed track at index \(index)")

        // Check if playlist is now empty
        if await playlistManager.isEmpty {
            // Stop playback and disable controls
            await stop(fadeDuration: 0.0)
        } else if await playlistManager.isSingleTrack && self.configuration.repeatMode == .off {
            // Single track without looping - will stop after this track
            // No action needed, will stop naturally
        }
    }

    /// Jump to track at index
    /// - Parameter index: Target track index
    /// - Throws: AudioPlayerError if index invalid or crossfade fails
    public func jumpToTrack(at index: Int) async throws {
        let count = await playlistManager.count

        guard index < count else {
            throw AudioPlayerError.invalidPlaylistIndex(index: index, count: count)
        }

        guard let track = await playlistManager.jumpTo(index: index) else {
            throw AudioPlayerError.noActiveTrack
        }

        Self.logger.info("Jumping to track \(index): \(track.url.lastPathComponent)")

        // Crossfade to selected track
        try await crossfadeToTrack(url: track.url)
    }

    /// Move track in playlist
    /// - Parameters:
    ///   - fromIndex: Source index
    ///   - toIndex: Destination index
    /// - Throws: AudioPlayerError if indices invalid
    public func moveTrackInPlaylist(from fromIndex: Int, to toIndex: Int) async throws {
        let count = await playlistManager.count

        guard fromIndex < count && toIndex < count else {
            throw AudioPlayerError.invalidPlaylistIndex(
                index: max(fromIndex, toIndex),
                count: count
            )
        }

        await playlistManager.moveTrack(from: fromIndex, to: toIndex)
        Self.logger.debug("Moved track from \(fromIndex) to \(toIndex)")
    }

    /// Get current playlist
    /// - Returns: Array of track URLs
    public func getCurrentPlaylist() async -> [URL] {
        return await playlistManager.getPlaylist()
    }

    /// Get current track index in playlist
    /// - Returns: Current index
    public func getCurrentTrackIndex() async -> Int {
        return await playlistManager.currentIndex
    }

    /// Check if playlist is empty
    /// - Returns: True if empty
    public func isPlaylistEmpty() async -> Bool {
        return await playlistManager.isEmpty
    }

    // MARK: - Track Navigation

    /// Go to next track in playlist (manual)
    /// - Throws: AudioPlayerError if crossfade fails or no valid tracks
    public func nextTrack() async throws {
        // Use retry logic to find next valid track
        guard let nextTrack = await playlistManager.skipToTrackWithRetry(
            direction: .next,
            maxAttempts: 3
        ) else {
            // All retry attempts failed
            if configuration.repeatMode == .off {
                Self.logger.info("Reached end of playlist or no valid tracks, stopping")
                try await finish(fadeDuration: nil)
            } else {
                // In loop mode, if all tracks invalid, throw error
                Self.logger.error("No valid tracks found in playlist")
                throw AudioPlayerError.noValidTracksInPlaylist
            }
            return
        }

        Self.logger.info("Next track: \(nextTrack.url.lastPathComponent)")

        // Preload the track after next (while crossfading)
        if let trackAfterNext = await playlistManager.peekNext() {
            await audioEngine.preloadTrack(url: trackAfterNext.url)
        }

        // Crossfade to next track
        do {
            try await crossfadeToTrack(url: nextTrack.url)
        } catch {
            Self.logger.error("Crossfade to next track failed: \(error.localizedDescription)")
            throw AudioPlayerError.skipFailed(reason: "Crossfade failed: \(error.localizedDescription)")
        }
    }

    /// Go to previous track in playlist (manual)
    /// - Throws: AudioPlayerError if crossfade fails or no valid tracks
    public func previousTrack() async throws {
        // Use retry logic to find previous valid track
        guard let previousTrack = await playlistManager.skipToTrackWithRetry(
            direction: .previous,
            maxAttempts: 3
        ) else {
            // All retry attempts failed or at start
            Self.logger.debug("Already at first track or no valid tracks")
            return
        }

        Self.logger.info("Previous track: \(previousTrack.url.lastPathComponent)")

        // Preload the track before previous (while crossfading)
        if let trackBeforePrevious = await playlistManager.peekPrevious() {
            await audioEngine.preloadTrack(url: trackBeforePrevious.url)
        }

        // Crossfade to previous track
        do {
            try await crossfadeToTrack(url: previousTrack.url)
        } catch {
            Self.logger.error("Crossfade to previous track failed: \(error.localizedDescription)")
            throw AudioPlayerError.skipFailed(reason: "Crossfade failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Internal Auto-Advance

    /// Auto-advance to next track (called from loop crossfade logic)
    /// - Returns: Next track URL or nil if should stop
    func autoAdvanceToNextTrack() async -> URL? {
        // Preload the track after next (while crossfading to next)
        if let trackAfterNext = await playlistManager.peekNext() {
            await audioEngine.preloadTrack(url: trackAfterNext.url)
        }

        return await playlistManager.getNextTrack()?.url
    }

    // MARK: - Private Helpers

    /// Crossfade to specific track
    private func crossfadeToTrack(url: URL) async throws {
        guard let position = playbackPosition else {
            throw AudioPlayerError.noActiveTrack
        }

        // Calculate crossfade duration based on remaining time
        let remainingTime = position.duration - position.currentTime
        let crossfadeDuration = min(configuration.crossfadeDuration, remainingTime)

        // Create Track from URL (validates file exists)
        guard let track = Track(url: url) else {
            throw AudioPlayerError.fileLoadFailed(reason: "Track file not found: \(url.lastPathComponent)")
        }

        // Use internal replaceCurrentTrack method
        // NOTE: Do NOT set activeCrossfadeOperation here!
        // replaceCurrentTrack() will manage it and send proper progress updates
        try await replaceCurrentTrack(track: track, crossfadeDuration: crossfadeDuration)
    }

}
