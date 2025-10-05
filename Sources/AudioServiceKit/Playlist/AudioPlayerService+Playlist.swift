import Foundation
import AudioServiceCore

// MARK: - Playlist API Extension

extension AudioPlayerService {
    
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
            await updatePlayerConfiguration(newConfig)
        }
        
        // Load playlist
        let manager = await playlistManager
        await manager.load(tracks: tracks)
        
        // Get first track
        guard let firstTrack = await manager.getCurrentTrack() else {
            throw AudioPlayerError.emptyPlaylist
        }
        
        // Start playback with fade in
        try await startPlayingTrack(
            url: firstTrack,
            fadeIn: (configuration ?? convertToPlayerConfiguration()).fadeInDuration
        )
    }
    
    /// Add track to playlist
    /// - Parameter url: Track URL to add
    public func addTrackToPlaylist(_ url: URL) async {
        let manager = await playlistManager
        await manager.addTrack(url)
    }
    
    /// Remove track from playlist at index
    /// - Parameter index: Index of track to remove
    /// - Throws: AudioPlayerError if index invalid
    public func removeTrackFromPlaylist(at index: Int) async throws {
        let manager = await playlistManager
        let count = await manager.count
        
        guard index < count else {
            throw AudioPlayerError.invalidPlaylistIndex(index: index, count: count)
        }
        
        await manager.removeTrack(at: index)
        
        // Check if playlist is now empty
        if await manager.isEmpty {
            // Stop playback and disable controls
            await stop()
        } else if await manager.isSingleTrack && !self.configuration.enableLooping {
            // Single track without looping - will stop after this track
            // No action needed, will stop naturally
        }
    }
    
    /// Jump to track at index
    /// - Parameter index: Target track index
    /// - Throws: AudioPlayerError if index invalid or crossfade fails
    public func jumpToTrack(at index: Int) async throws {
        let manager = await playlistManager
        let count = await manager.count
        
        guard index < count else {
            throw AudioPlayerError.invalidPlaylistIndex(index: index, count: count)
        }
        
        guard let trackURL = await manager.jumpTo(index: index) else {
            throw AudioPlayerError.noActiveTrack
        }
        
        // Crossfade to selected track
        try await crossfadeToTrack(url: trackURL)
    }
    
    /// Move track in playlist
    /// - Parameters:
    ///   - fromIndex: Source index
    ///   - toIndex: Destination index
    /// - Throws: AudioPlayerError if indices invalid
    public func moveTrackInPlaylist(from fromIndex: Int, to toIndex: Int) async throws {
        let manager = await playlistManager
        let count = await manager.count
        
        guard fromIndex < count && toIndex < count else {
            throw AudioPlayerError.invalidPlaylistIndex(
                index: max(fromIndex, toIndex),
                count: count
            )
        }
        
        await manager.moveTrack(from: fromIndex, to: toIndex)
    }
    
    /// Get current playlist
    /// - Returns: Array of track URLs
    public func getCurrentPlaylist() async -> [URL] {
        let manager = await playlistManager
        return await manager.tracks
    }
    
    /// Get current track index in playlist
    /// - Returns: Current index
    public func getCurrentTrackIndex() async -> Int {
        let manager = await playlistManager
        return await manager.currentIndex
    }
    
    /// Check if playlist is empty
    /// - Returns: True if empty
    public func isPlaylistEmpty() async -> Bool {
        let manager = await playlistManager
        return await manager.isEmpty
    }
    
    // MARK: - Track Navigation
    
    /// Go to next track in playlist (manual)
    /// - Throws: AudioPlayerError if crossfade fails
    public func nextTrack() async throws {
        let manager = await playlistManager
        
        guard let nextURL = await manager.skipToNext() else {
            // No next track - stop if not looping
            if !configuration.enableLooping {
                try await finish()
            }
            return
        }
        
        // Crossfade to next track
        try await crossfadeToTrack(url: nextURL)
    }
    
    /// Go to previous track in playlist (manual)
    /// - Throws: AudioPlayerError if crossfade fails
    public func previousTrack() async throws {
        let manager = await playlistManager
        
        guard let previousURL = await manager.skipToPrevious() else {
            // No previous track
            return
        }
        
        // Crossfade to previous track
        try await crossfadeToTrack(url: previousURL)
    }
    
    // MARK: - Internal Auto-Advance
    
    /// Auto-advance to next track (called from loop crossfade logic)
    /// - Returns: Next track URL or nil if should stop
    func autoAdvanceToNextTrack() async -> URL? {
        let manager = await playlistManager
        return await manager.getNextTrack()
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
        guard await stateMachine.enterPreparing() else {
            throw AudioPlayerError.invalidState(
                current: state.description,
                attempted: "start playing"
            )
        }
        
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
        
        // Use existing replaceTrack method
        try await replaceTrack(url: url, crossfadeDuration: crossfadeDuration)
    }
    
    /// Update player configuration from PlayerConfiguration
    private func updatePlayerConfiguration(_ config: PlayerConfiguration) async {
        // Convert to legacy AudioConfiguration for now
        // TODO: Replace AudioConfiguration with PlayerConfiguration throughout
        self.configuration = AudioConfiguration(
            crossfadeDuration: config.crossfadeDuration,
            fadeInDuration: config.fadeInDuration,
            fadeOutDuration: 0, // Not used in new API
            volume: config.volumeFloat,
            repeatCount: config.repeatCount,
            enableLooping: config.enableLooping,
            fadeCurve: config.fadeCurve
        )
    }
    
    /// Convert current AudioConfiguration to PlayerConfiguration
    private func convertToPlayerConfiguration() -> PlayerConfiguration {
        PlayerConfiguration(
            crossfadeDuration: configuration.crossfadeDuration,
            fadeCurve: configuration.fadeCurve,
            enableLooping: configuration.enableLooping,
            repeatCount: configuration.repeatCount,
            volume: Int(configuration.volume * 100)
        )
    }
}
