import Foundation
import AudioServiceCore

// MARK: - Playlist API Extension

extension AudioPlayerService {
    
    // MARK: - Private Logger
    
    private static let logger = Logger.playlist
    
    // MARK: - Playlist Properties
    
    /// Access playlist manager (already exists as stored property in AudioPlayerService)
    
    // MARK: - Playlist Management API
    
    /// Load and start playing a playlist
    /// - Parameters:
    ///   - tracks: Array of track URLs
    ///   - configuration: Player configuration (uses current if nil)
    /// - Throws: AudioPlayerError if playlist is empty or playback fails
    public func loadPlaylist(
        _ tracks: [URL],
        configuration: PlayerConfiguration? = nil
    ) async throws {
        // Validate playlist
        guard !tracks.isEmpty else {
            throw AudioPlayerError.emptyPlaylist
        }
        
        // Update configuration if provided
        if let newConfig = configuration {
            try newConfig.validate()
            self.configuration = newConfig
        }
        
        // Load playlist
        await playlistManager.load(tracks: tracks)
        
        // Get first track
        guard let firstTrack = await playlistManager.getCurrentTrack() else {
            throw AudioPlayerError.emptyPlaylist
        }
        
        Self.logger.info("Loaded playlist with \(tracks.count) tracks")
        
        // Start playback with fade in
        try await startPlayingTrack(
            url: firstTrack,
            fadeIn: (configuration ?? self.configuration).fadeInDuration
        )
    }
    
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
            await stop(fadeDuration: nil)
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
        
        guard let trackURL = await playlistManager.jumpTo(index: index) else {
            throw AudioPlayerError.noActiveTrack
        }
        
        Self.logger.info("Jumping to track \(index): \(trackURL.lastPathComponent)")
        
        // Crossfade to selected track
        try await crossfadeToTrack(url: trackURL)
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
        return await playlistManager.tracks
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
    /// - Throws: AudioPlayerError if crossfade fails
    public func nextTrack() async throws {
        guard let nextURL = await playlistManager.skipToNext() else {
            // No next track - stop if not looping
            if configuration.repeatMode == .off {
                Self.logger.info("Reached end of playlist, stopping")
                try await finish(fadeDuration: nil)
            }
            return
        }
        
        Self.logger.info("Next track: \(nextURL.lastPathComponent)")
        
        // Crossfade to next track
        try await crossfadeToTrack(url: nextURL)
    }
    
    /// Go to previous track in playlist (manual)
    /// - Throws: AudioPlayerError if crossfade fails
    public func previousTrack() async throws {
        guard let previousURL = await playlistManager.skipToPrevious() else {
            // No previous track
            Self.logger.debug("Already at first track")
            return
        }
        
        Self.logger.info("Previous track: \(previousURL.lastPathComponent)")
        
        // Crossfade to previous track
        try await crossfadeToTrack(url: previousURL)
    }
    
    // MARK: - Internal Auto-Advance
    
    /// Auto-advance to next track (called from loop crossfade logic)
    /// - Returns: Next track URL or nil if should stop
    func autoAdvanceToNextTrack() async -> URL? {
        return await playlistManager.getNextTrack()
    }
    
    // MARK: - Private Helpers
    
    /// Start playing specific track with fade in
    private func startPlayingTrack(url: URL, fadeIn: TimeInterval) async throws {
        // Configure audio session
        try await sessionManager.configure()
        try await sessionManager.activate()
        
        // Prepare audio engine
        try await audioEngine.prepare()
        
        // Load audio file
        let trackInfo = try await audioEngine.loadAudioFile(url: url)
        self.currentTrack = trackInfo
        self.currentTrackURL = url
        
        // Enter preparing state
        let success = await stateMachine.enterPreparing()
        Logger.state.assertTransition(
            success,
            from: state.description,
            to: "preparing"
        )
        
        guard success else {
            throw AudioPlayerError.invalidState(
                current: state.description,
                attempted: "start playing"
            )
        }
        
        Self.logger.info("Started playing track: \(trackInfo.title)")
        
        // Update now playing info
        await updateNowPlayingInfo()
        
        // Start playback timer
        startPlaybackTimer()
    }
    
    /// Crossfade to specific track
    private func crossfadeToTrack(url: URL) async throws {
        guard let position = playbackPosition else {
            throw AudioPlayerError.noActiveTrack
        }
        
        // Calculate crossfade duration based on remaining time
        let remainingTime = position.duration - position.currentTime
        let crossfadeDuration = min(configuration.crossfadeDuration, remainingTime)
        
        // Send preparing state to observers immediately (BEFORE replaceTrack)
        let prepareProgress = CrossfadeProgress(
            phase: .preparing,
            duration: crossfadeDuration,
            elapsed: 0
        )
        updateCrossfadeProgress(prepareProgress)
        
        // Use existing replaceTrack method
        // NOTE: Do NOT set isTrackReplacementInProgress here!
        // replaceTrack() will manage it and send proper progress updates
        try await replaceTrack(url: url, crossfadeDuration: crossfadeDuration)
    }
    

}
