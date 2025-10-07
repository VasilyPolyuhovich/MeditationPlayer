import Foundation
import AVFoundation
import AudioServiceCore

// MARK: - Future Enhancements (v3.2)

/// TODO: ValidationFeedback System
/// ================================
/// Return validation results with warnings/errors instead of prints
///
/// Proposed API:
/// ```swift
/// struct ValidationFeedback {
///     let isValid: Bool
///     let warnings: [ValidationWarning]
///     let errors: [ValidationError]
/// }
///
/// enum ValidationWarning {
///     case totalFadeExceedsRecommended(total: TimeInterval, track: TimeInterval)
///     case fadeOutConflictsWithCrossfade(fadeOut: TimeInterval, crossfade: TimeInterval)
///     case trackTooShortForFade(duration: TimeInterval)
/// }
///
/// func setSingleTrackFadeDurations(...) async throws -> ValidationFeedback
/// ```
///
/// Benefits:
/// - UI can show warnings before applying
/// - Programmer can handle conflicts proactively
/// - Better UX (inform user about auto-adjustments)

/// Main audio player service implementing the AudioPlayerProtocol
public actor AudioPlayerService: AudioPlayerProtocol {
    // MARK: - Properties
    
    // Private logger
    private static let logger = Logger.audio
    
    // SSOT: State managed exclusively by state machine
    private var _state: PlayerState
    public var state: PlayerState { _state }
    public internal(set) var configuration: AudioConfiguration  // Public read, internal write for playlist API
    public internal(set) var currentTrack: TrackInfo?  // Public read, internal write for playlist API
    public private(set) var playbackPosition: PlaybackPosition?
    
    // Internal components
    internal let audioEngine: AudioEngineActor  // Allow internal access for playlist API
    internal let sessionManager: AudioSessionManager  // Allow internal access for playlist API
    // RemoteCommandManager is now @MainActor isolated for thread safety
    // Must be created in setup() due to MainActor isolation
    private var remoteCommandManager: RemoteCommandManager!
    internal var stateMachine: AudioStateMachine!  // Allow internal access for playlist API
    
    // Playback timer for position updates
    private var playbackTimer: Task<Void, Never>?
    
    // Observers
    private var observers: [AudioPlayerObserver] = []
    
    // Loop tracking
    private var currentRepeatCount = 0
    internal var currentTrackURL: URL?  // Allow internal access for playlist API
    private var isLoopCrossfadeInProgress = false
    internal var isTrackReplacementInProgress: Bool = false  // Allow internal access for playlist API
    
    // Crossfade progress observation
    private var crossfadeProgressTask: Task<Void, Never>?
    public private(set) var currentCrossfadeProgress: CrossfadeProgress = .idle
    
    // Playlist manager (NEW)
    internal var playlistManager: PlaylistManager  // Allow internal access for playlist API
    
    // MARK: - Initialization
    
    public init(configuration: AudioConfiguration = AudioConfiguration()) {
        self._state = .finished
        self.configuration = configuration
        self.audioEngine = AudioEngineActor()
        self.sessionManager = AudioSessionManager()
        // Initialize playlist manager with default config
        self.playlistManager = PlaylistManager(
            configuration: PlayerConfiguration(
                crossfadeDuration: configuration.crossfadeDuration,
                fadeCurve: configuration.fadeCurve,
                repeatMode: configuration.repeatMode,
                repeatCount: configuration.repeatCount,
                singleTrackFadeInDuration: configuration.singleTrackFadeInDuration,
                singleTrackFadeOutDuration: configuration.singleTrackFadeOutDuration,
                volume: Int(configuration.volume * 100),
                stopFadeDuration: configuration.stopFadeDuration
            )
        )
        // remoteCommandManager will be created in setup() on MainActor
    }
    
    /// Setup the service (must be called after initialization)
    public func setup() async {
        // Initialize components
        await audioEngine.setup()
        await sessionManager.setup()
        
        // FIXED: Create RemoteCommandManager on MainActor
        remoteCommandManager = await MainActor.run {
            RemoteCommandManager()
        }
        
        // Initialize state machine
        initializeStateMachine()
        await setupSessionHandlers()
        await setupRemoteCommands()
    }
    
    private func initializeStateMachine() {
        self.stateMachine = AudioStateMachine(context: self)
    }
    
    // MARK: - Setup
    
    private func setupSessionHandlers() async {
        // Handle interruptions
        await sessionManager.setInterruptionHandler { [weak self] shouldResume in
            guard let self = self else { return }
            Task {
                await self.handleInterruption(shouldResume: shouldResume)
            }
        }
        
        // Handle route changes
        await sessionManager.setRouteChangeHandler { [weak self] reason in
            guard let self = self else { return }
            Task {
                await self.handleRouteChange(reason: reason)
            }
        }
    }
    
    private func setupRemoteCommands() {
        // Capture manager before MainActor hop
        let manager = remoteCommandManager!
        
        Task { @MainActor in
            manager.setupCommands(
                playHandler: { [weak self] in
                    try? await self?.resume()
                },
                pauseHandler: { [weak self] in
                    try? await self?.pause()
                },
                skipForwardHandler: { [weak self] interval in
                    try? await self?.skipForward(by: interval)
                },
                skipBackwardHandler: { [weak self] interval in
                    try? await self?.skipBackward(by: interval)
                }
            )
        }
    }
    
    // MARK: - AudioPlayerProtocol Implementation
    
    public func startPlaying(url: URL, configuration: AudioConfiguration) async throws {
        // Validate configuration
        try configuration.validate()
        self.configuration = configuration
        
        // Sync configuration with playlist manager
        await syncConfigurationToPlaylistManager()
        
        // Reset loop tracking
        self.currentTrackURL = url
        self.currentRepeatCount = 0
        self.isLoopCrossfadeInProgress = false
        self.isTrackReplacementInProgress = false
        
        // Configure audio session
        try await sessionManager.configure()
        try await sessionManager.activate()
        
        // Prepare audio engine
        try await audioEngine.prepare()
        
        // Load audio file
        let trackInfo = try await audioEngine.loadAudioFile(url: url)
        self.currentTrack = trackInfo
        
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
        
        // Update now playing info
        await updateNowPlayingInfo()
        
        // Start playback timer
        startPlaybackTimer()
    }
    
    public func pause() async throws {
        // Rollback any active crossfade before pausing
        if isLoopCrossfadeInProgress || isTrackReplacementInProgress {
            await rollbackCrossfade()
        }
        
        // TODO v3.2: Handle pause during single track fade in/out
        // Current: Fade resets on pause (simple behavior)
        // Future: Consider preserving fade state for smooth resume
        
        // Guard: only pause if playing or preparing (to prevent Error 4)
        guard state == .playing || state == .preparing else {
            // If already paused or finished, just return
            if state == .paused || state == .finished {
                return
            }
            throw AudioPlayerError.invalidState(
                current: state.description,
                attempted: "pause"
            )
        }
        
        // ✅ FIX: Delegate to state machine (removes duplicate call)
        // State machine will call context.pausePlayback() which handles:
        // - Capturing position ONCE
        // - Pausing audio engine
        // - Stopping playback timer
        await stateMachine.enterPaused()
        
        // Update UI
        await updateNowPlayingPlaybackRate(0.0)
    }
    
    public func resume() async throws {
        // Rollback any active crossfade before resuming
        if isLoopCrossfadeInProgress || isTrackReplacementInProgress {
            await rollbackCrossfade()
        }
        
        // Guard: only resume if paused or finished
        guard state == .paused || state == .finished else {
            // If already playing, just return
            if state == .playing {
                return
            }
            throw AudioPlayerError.invalidState(
                current: state.description,
                attempted: "resume"
            )
        }
        
        // If finished - need to restart
        if state == .finished {
            throw AudioPlayerError.invalidState(
                current: "finished",
                attempted: "resume - use startPlaying instead"
            )
        }
        
        // ✅ FIX: Delegate to state machine (removes duplicate call)
        // State machine will call context.resumePlayback() which handles:
        // - Rescheduling buffer from saved position
        // - Playing audio engine
        // - Restarting playback timer
        await stateMachine.enterPlaying()
        
        // Update UI
        await updateNowPlayingPlaybackRate(1.0)
    }
    
    /// Stop playback with optional fade out
    /// - Parameter fadeDuration: Duration of fade out (nil = instant stop, 0.0-10.0 seconds)
    /// - Note: Use nil or 0.0 for instant stop (default behavior)
    /// - Note: Fade duration is clamped to 0.0-10.0 seconds range
    public func stop(fadeDuration: TimeInterval? = nil) async {
        if let duration = fadeDuration, duration > 0 {
            // Stop with fade
            await stopWithFade(duration: duration)
        } else {
            // Instant stop (existing behavior)
            await stopImmediately()
        }
    }
    
    /// Stop playback with fade out
    /// - Parameter duration: Duration of fade out (clamped to 0.0-10.0 seconds)
    private func stopWithFade(duration: TimeInterval) async {
        // Clamp duration to safe range
        let clampedDuration = max(0.0, min(10.0, duration))
        
        // Get current volume before fade
        let currentVolume = configuration.volume
        
        // Fade out active mixer
        await audioEngine.fadeActiveMixer(
            from: currentVolume,
            to: 0.0,
            duration: clampedDuration,
            curve: configuration.fadeCurve
        )
        
        // Then perform instant stop
        await stopImmediately()
    }
    
    /// Stop playback immediately without fade
    /// - Note: This is the original stop() behavior
    private func stopImmediately() async {
        // Stop playback components
        stopPlaybackTimer()
        await audioEngine.stopBothPlayers()
        
        // ISSUE #7 FIX: Deactivate audio session
        try? await sessionManager.deactivate()
        
        // Reset ALL state for clean restart (including crossfade flags)
        playbackPosition = nil
        currentTrack = nil
        currentTrackURL = nil
        currentRepeatCount = 0
        isLoopCrossfadeInProgress = false
        isTrackReplacementInProgress = false
        
        // State change via state machine
        await stateMachine.enterFinished()
        
        // Clear UI
        let manager = remoteCommandManager!  // Capture before MainActor hop
        Task { @MainActor in
            manager.clearNowPlayingInfo()
        }
    }
    
    /// Stop playback with default fade duration from configuration
    /// - Note: Uses stopFadeDuration from AudioConfiguration (default: 3.0 seconds)
    public func stopWithDefaultFade() async {
        await stop(fadeDuration: configuration.stopFadeDuration)
    }
    
    /// Stop playback immediately without any fade
    /// - Note: Alias for stop() without parameters for code clarity
    public func stopImmediatelyWithoutFade() async {
        await stop(fadeDuration: nil)
    }
    
    public func finish(fadeDuration: TimeInterval?) async throws {
        let duration = fadeDuration ?? configuration.fadeOutDuration
        
        let success = await stateMachine.enterFadingOut(duration: duration)
        Logger.state.assertTransition(
            success,
            from: state.description,
            to: "fading out"
        )
        
        guard success else {
            throw AudioPlayerError.invalidState(
                current: state.description,
                attempted: "finish"
            )
        }
    }
    
    public func skipForward(by interval: TimeInterval = 15.0) async throws {
        // Rollback any active crossfade before skipping
        if isLoopCrossfadeInProgress || isTrackReplacementInProgress {
            await rollbackCrossfade()
        }
        
        // TODO v3.2: Enhanced skip logic during single track fade
        // Current: Fade is cancelled (reset), seek happens instantly
        // Future Options:
        //   1. Skip should preserve fade state if within fade region
        //   2. Skip outside fade region should restart appropriate fade
        //   3. Add skipWithFade() API for smooth transition
        // Recommendation: Option 2 (context-aware fade restart)
        
        guard let position = playbackPosition else {
            throw AudioPlayerError.invalidState(
                current: "no playback position",
                attempted: "skip forward"
            )
        }
        
        let newTime = min(position.currentTime + interval, position.duration)
        try await audioEngine.seek(to: newTime)
    }
    
    public func skipBackward(by interval: TimeInterval = 15.0) async throws {
        // Rollback any active crossfade before skipping
        if isLoopCrossfadeInProgress || isTrackReplacementInProgress {
            await rollbackCrossfade()
        }
        
        // TODO v3.2: Enhanced skip logic during single track fade
        // Same considerations as skipForward (see above)
        
        guard let position = playbackPosition else {
            throw AudioPlayerError.invalidState(
                current: "no playback position",
                attempted: "skip backward"
            )
        }
        
        let newTime = max(position.currentTime - interval, 0)
        try await audioEngine.seek(to: newTime)
    }
    
    /// Seek to position with fade to eliminate clicking/popping sounds
    /// - Parameters:
    ///   - time: Target position in seconds
    ///   - fadeDuration: Duration of fade in/out (default: 0.1s, imperceptible to users)
    /// - Throws: AudioPlayerError if seek fails
    /// - Note: Uses brief fade to avoid buffer discontinuity artifacts (clicking sounds)
    /// - Note: Automatically rolls back any active crossfade before seeking
    public func seekWithFade(to time: TimeInterval, fadeDuration: TimeInterval = 0.1) async throws {
        // Rollback any active crossfade before seeking
        if isLoopCrossfadeInProgress || isTrackReplacementInProgress {
            await rollbackCrossfade()
        }
        
        let wasPlaying = state == .playing
        
        // 1. Fade out if playing (eliminates click from buffer discontinuity)
        if wasPlaying {
            await audioEngine.fadeActiveMixer(
                from: configuration.volume,
                to: 0.0,
                duration: fadeDuration,
                curve: .linear
            )
        }
        
        // 2. Perform seek (instant, but silent)
        try await audioEngine.seek(to: time)
        
        // 3. Fade in if was playing (smooth re-entry)
        if wasPlaying {
            await audioEngine.fadeActiveMixer(
                from: 0.0,
                to: configuration.volume,
                duration: fadeDuration,
                curve: .linear
            )
        }
    }
    
    public func setVolume(_ volume: Float) async {
        let clampedVolume = max(0.0, min(1.0, volume))
        await audioEngine.setVolume(clampedVolume)
    }
    
    /// Get current repeat count (number of loop iterations completed)
    public func getRepeatCount() -> Int {
        return currentRepeatCount
    }
    
    // MARK: - Repeat Mode Control (Feature #1 - Phase 4)
    
    /// Sets the repeat mode for playback
    ///
    /// The repeat mode determines how playback continues after a track ends:
    /// - `.off`: Play once, then stop
    /// - `.singleTrack`: Loop current track with configurable fade in/out
    /// - `.playlist`: Advance to next track with crossfade
    ///
    /// - Parameter mode: The repeat mode to set
    /// - Note: Changes apply immediately without restarting playback
    /// - Note: For `.singleTrack` mode, use `setSingleTrackFadeDurations()` to configure fade behavior
    /// - SeeAlso: `getRepeatMode()`, `setSingleTrackFadeDurations(fadeIn:fadeOut:)`
    public func setRepeatMode(_ mode: RepeatMode) async {
        // Update configuration with new repeat mode
        configuration = AudioConfiguration(
            crossfadeDuration: configuration.crossfadeDuration,
            fadeInDuration: configuration.fadeInDuration,
            fadeOutDuration: configuration.fadeOutDuration,
            volume: configuration.volume,
            repeatCount: configuration.repeatCount,
            enableLooping: mode == .playlist, // Backward compatibility
            fadeCurve: configuration.fadeCurve,
            stopFadeDuration: configuration.stopFadeDuration,
            repeatMode: mode,
            singleTrackFadeInDuration: configuration.singleTrackFadeInDuration,
            singleTrackFadeOutDuration: configuration.singleTrackFadeOutDuration
        )
        
        // Sync to PlaylistManager
        await syncConfigurationToPlaylistManager()
        
        Self.logger.info("Repeat mode set to: \(mode)")
    }
    
    /// Returns the current repeat mode
    /// - Returns: Current repeat mode (.off, .singleTrack, .playlist)
    public func getRepeatMode() -> RepeatMode {
        return configuration.repeatMode
    }
    
    /// Sets fade durations for single track repeat mode
    ///
    /// Configures fade in/out durations used when `repeatMode = .singleTrack`.
    /// These values are validated statically and adapted dynamically per track at runtime.
    ///
    /// - Parameters:
    ///   - fadeIn: Fade in duration at track start (0.5-10.0 seconds)
    ///   - fadeOut: Fade out duration at track end (0.5-10.0 seconds)
    /// - Throws: ConfigurationError if durations are outside valid range
    /// - Note: **Static Validation**: Range checked against 0.5-10.0 seconds
    /// - Note: **Dynamic Validation**: Auto-adapted per track at loop time (max 40% each, 80% total)
    /// - Note: **Crossfade Overlap**: For `.playlist` mode, fadeOut may be auto-adjusted to prevent overlap
    /// - Warning: Total fade duration \u003E 15s may not work well for short tracks (\u003c20s)
    /// - Warning: Changes apply to **next loop iteration** (current loop unaffected)
    /// - TODO: v3.2 - Add ValidationFeedback system to return warnings/errors
    public func setSingleTrackFadeDurations(
        fadeIn: TimeInterval,
        fadeOut: TimeInterval
    ) async throws {
        // ✅ Level 1: Static Validation (Range Check)
        guard fadeIn >= 0.5 && fadeIn <= 10.0 else {
            throw ConfigurationError.invalidSingleTrackFadeInDuration(fadeIn)
        }
        
        guard fadeOut >= 0.5 && fadeOut <= 10.0 else {
            throw ConfigurationError.invalidSingleTrackFadeOutDuration(fadeOut)
        }
        
        // ⚠️ Level 2: Warning for large total (may not fit short tracks)
        let totalFade = fadeIn + fadeOut
        if totalFade > 15.0 {
            // TODO v3.2: Return ValidationWarning instead of logger
            Self.logger.warning("Total fade duration (\(totalFade)s) may not work for short tracks (<20s)")
        }
        
        // ⚠️ Level 3: Crossfade Overlap Check (only for .playlist mode)
        // Note: .singleTrack mode has no crossfade overlap (loops same track)
        if configuration.repeatMode == .playlist {
            let crossfadeDuration = configuration.crossfadeDuration
            if fadeOut > crossfadeDuration {
                // TODO v3.2: Return ValidationWarning with conflicting values
                Self.logger.warning("fadeOut (\(fadeOut)s) exceeds crossfade (\(crossfadeDuration)s) in .playlist mode")
                Self.logger.info("fadeOut will be auto-adjusted at runtime to prevent overlap")
            }
        }
        
        // ✅ Update configuration (values stored, dynamic adaptation happens at loop time)
        configuration = AudioConfiguration(
            crossfadeDuration: configuration.crossfadeDuration,
            fadeInDuration: configuration.fadeInDuration,
            fadeOutDuration: configuration.fadeOutDuration,
            volume: configuration.volume,
            repeatCount: configuration.repeatCount,
            enableLooping: configuration.enableLooping,
            fadeCurve: configuration.fadeCurve,
            stopFadeDuration: configuration.stopFadeDuration,
            repeatMode: configuration.repeatMode,
            singleTrackFadeInDuration: fadeIn,
            singleTrackFadeOutDuration: fadeOut
        )
        
        // ✅ Sync to PlaylistManager
        await syncConfigurationToPlaylistManager()
        
        Self.logger.info("Single track fade durations set: fadeIn=\(fadeIn)s, fadeOut=\(fadeOut)s")
        Self.logger.debug("Changes apply to NEXT loop iteration (current loop unaffected)")
    }
    
    /// Reset player to initial state with default configuration
    public func reset() async {
        // Stop timer first
        stopPlaybackTimer()
        
        // Full engine reset (clears all files and state)
        await audioEngine.fullReset()
        
        // ISSUE #7 FIX: Deactivate audio session
        try? await sessionManager.deactivate()
        
        // Reset configuration
        configuration = AudioConfiguration()
        
        // Clear playlist
        await playlistManager.clear()
        await syncConfigurationToPlaylistManager()
        
        // Clear all state (including crossfade flags)
        currentTrack = nil
        currentTrackURL = nil
        playbackPosition = nil
        currentRepeatCount = 0
        isLoopCrossfadeInProgress = false
        isTrackReplacementInProgress = false
        
        // CRITICAL: Reinitialize state machine to FinishedState
        // This prevents Error 4 (invalidState) on next play()
        initializeStateMachine()
        
        // Re-setup engine for fresh start
        await audioEngine.setup()
        
        // Notify observers
        notifyObservers(stateChange: .finished)
        
        // Clear Now Playing
        let manager = remoteCommandManager!  // Capture before MainActor hop
        Task { @MainActor in
            manager.clearNowPlayingInfo()
        }
    }
    
    /// Cleanup all resources (call before deallocation if needed)
    public func cleanup() async {
        // Stop timer and playback
        stopPlaybackTimer()
        await audioEngine.fullReset()
        
        // Deactivate audio session
        try? await sessionManager.deactivate()
        
        // Clear all state (including crossfade flags)
        currentTrack = nil
        currentTrackURL = nil
        playbackPosition = nil
        currentRepeatCount = 0
        isLoopCrossfadeInProgress = false
        isTrackReplacementInProgress = false
        await stateMachine.enterFinished()
        
        // Remove remote commands
        let manager = remoteCommandManager!  // Capture before MainActor hop
        Task { @MainActor in
            manager.removeCommands()
            manager.clearNowPlayingInfo()
        }
        
        // Clear observers
        observers.removeAll()
    }
    
    /// Replace current track with a new one using synchronized crossfade
    /// - Parameters:
    ///   - url: URL of the new audio file
    ///   - crossfadeDuration: Duration of the crossfade in seconds (default: 5.0, range: 1.0-30.0)
    ///   - retryDelay: Delay before retry if crossfade is in progress (default: 1.5s)
    /// - Throws: AudioPlayerError if file cannot be loaded or crossfade fails
    /// - Note: Validates and clamps crossfade duration to safe range (1.0-30.0 seconds)
    /// - Note: If crossfade is in progress, performs rollback and retries after delay
    public func replaceTrack(url: URL, crossfadeDuration: TimeInterval = 5.0, retryDelay: TimeInterval = 1.5) async throws {
        // Validate and clamp crossfade duration
        let validatedDuration = max(1.0, min(30.0, crossfadeDuration))
        
        // If crossfade in progress - rollback and retry
        if isTrackReplacementInProgress {
            // 1. Rollback current transition
            await rollbackCrossfade()
            
            // 2. Short delay before retry (1-2 seconds)
            try await Task.sleep(nanoseconds: UInt64(retryDelay * 1_000_000_000))
            
            // 3. Continue with new track (fall through)
        }
        
        // Store new URL
        currentTrackURL = url
        
        // CRITICAL: Remember state BEFORE any async operations
        let wasPlaying = state == .playing
        
        // Load new file on secondary player (suspension point)
        let newTrack = try await audioEngine.loadAudioFileOnSecondaryPlayer(url: url)
        
        // CRITICAL: Recheck state after async operation (actor reentrancy protection)
        let isStillPlaying = state == .playing
        
        // Decision: crossfade only if BOTH conditions true
        if wasPlaying && isStillPlaying {
            // Mark replacement in progress
            isTrackReplacementInProgress = true
            defer { isTrackReplacementInProgress = false }
            
            // Still playing - do crossfade
            await audioEngine.prepareSecondaryPlayer()
            
            // Perform synchronized crossfade with progress observation
            let progressStream = await audioEngine.performSynchronizedCrossfade(
                duration: validatedDuration,
                curve: configuration.fadeCurve
            )
            
            // Observe progress
            crossfadeProgressTask = Task { [weak self] in
                for await progress in progressStream {
                    await self?.updateCrossfadeProgress(progress)
                }
            }
            
            // Wait for crossfade completion
            await crossfadeProgressTask?.value
            crossfadeProgressTask = nil
            
            // CRITICAL ORDER: Switch THEN stop inactive to avoid stopping new track
            // 1. Switch active reference (primary → secondary, new track becomes active)
            await audioEngine.switchActivePlayer()
            
            // 2. Stop OLD player (now inactive after switch)
            await audioEngine.stopInactivePlayer()
            
            // 3. Reset OLD mixer volume (now inactive)
            await audioEngine.resetInactiveMixer()
            
            // 4. Clear inactive file to free memory
            await audioEngine.clearInactiveFile()
            
            // CRITICAL FIX: Ensure state=.playing after crossfade
            // During crossfade (5-10s), state may have changed (e.g., pause())
            // Force state back to playing since new track is now active
            if state != .playing {
                await stateMachine.enterPlaying()
            }
        } else {
            // Paused or stopped during load - just switch files without starting
            await audioEngine.switchActivePlayer()
            await audioEngine.stopInactivePlayer()
            
            // Keep current state (paused if paused, finished if stopped)
            // state remains unchanged
        }
        
        // Update track info
        currentTrack = newTrack
        
        // Reset repeat count for new track
        currentRepeatCount = 0
        isLoopCrossfadeInProgress = false
        isTrackReplacementInProgress = false  // Ensure cleared
        
        // Update now playing info
        await updateNowPlayingInfo()
    }
    
    /// Replace entire playlist with smooth crossfade to first track
    /// - Parameters:
    ///   - tracks: New playlist track URLs
    ///   - crossfadeDuration: Duration of crossfade (default: 5.0s, range: 1.0-30.0s)
    /// - Throws: AudioPlayerError if playlist is empty or swap fails
    /// - Note: Preserves playback state (playing → crossfade, paused → silent switch)
    /// - Note: Resets playlist index to 0 and repeat count to 0
    /// - Note: If crossfade in progress, performs rollback and retries after 1.5s delay
    public func swapPlaylist(
        tracks: [URL],
        crossfadeDuration: TimeInterval = 5.0
    ) async throws {
        // 1. Validation
        guard !tracks.isEmpty else {
            throw AudioPlayerError.invalidConfiguration(
                reason: "Cannot swap to empty playlist"
            )
        }
        
        // Validate and clamp crossfade duration
        let validDuration = max(1.0, min(30.0, crossfadeDuration))
        
        // 2. Rollback if crossfade in progress
        if isTrackReplacementInProgress || isLoopCrossfadeInProgress {
            await rollbackCrossfade()
            try await Task.sleep(nanoseconds: 1_500_000_000) // 1.5s delay
        }
        
        // 3. State preservation (BEFORE async operations!)
        let wasPlaying = state == .playing
        
        // 4. Load first track of new playlist on secondary player
        let firstTrackURL = tracks[0]
        let newTrack = try await audioEngine.loadAudioFileOnSecondaryPlayer(url: firstTrackURL)
        
        // 5. Recheck state after async (actor reentrancy protection)
        let isStillPlaying = state == .playing
        
        // 6. Decision: crossfade or silent switch
        if wasPlaying && isStillPlaying {
            // Mark as in progress
            isTrackReplacementInProgress = true
            defer { isTrackReplacementInProgress = false }
            
            // Prepare secondary player
            await audioEngine.prepareSecondaryPlayer()
            
            // Perform synchronized crossfade with progress
            let progressStream = await audioEngine.performSynchronizedCrossfade(
                duration: validDuration,
                curve: configuration.fadeCurve
            )
            
            // Observe progress
            crossfadeProgressTask = Task { [weak self] in
                for await progress in progressStream {
                    await self?.updateCrossfadeProgress(progress)
                }
            }
            
            // Wait for completion
            await crossfadeProgressTask?.value
            crossfadeProgressTask = nil
            
            // Switch players (secondary becomes active)
            await audioEngine.switchActivePlayer()
            
            // Stop old player (now inactive)
            await audioEngine.stopInactivePlayer()
            
            // Reset inactive mixer
            await audioEngine.resetInactiveMixer()
            
            // Clear inactive file
            await audioEngine.clearInactiveFile()
            
            // Ensure playing state after crossfade
            if state != .playing {
                await stateMachine.enterPlaying()
            }
        } else {
            // Paused or stopped - just switch without playback
            await audioEngine.switchActivePlayer()
            await audioEngine.stopInactivePlayer()
            // Keep current state (paused/finished)
        }
        
        // 7. Update PlaylistManager
        await playlistManager.replacePlaylist(tracks)
        
        // 8. Update current track state
        currentTrack = newTrack
        currentTrackURL = firstTrackURL
        
        // 9. Reset counters
        currentRepeatCount = 0
        isLoopCrossfadeInProgress = false
        isTrackReplacementInProgress = false
        
        // 10. Update UI
        await updateNowPlayingInfo()
        
        Self.logger.info("Playlist swapped successfully (\(tracks.count) tracks)")
    }
    
    // MARK: - Observers
    
    public func addObserver(_ observer: AudioPlayerObserver) {
        observers.append(observer)
    }
    
    public func removeAllObservers() {
        observers.removeAll()
    }
    
    private func notifyObservers(stateChange state: PlayerState) {
        for observer in observers {
            Task {
                await observer.playerStateDidChange(state)
            }
        }
    }
    
    private func notifyObservers(positionUpdate position: PlaybackPosition) {
        for observer in observers {
            Task {
                await observer.playbackPositionDidUpdate(position)
            }
        }
    }
    
    private func notifyObservers(error: AudioPlayerError) {
        for observer in observers {
            Task {
                await observer.playerDidEncounterError(error)
            }
        }
    }
    
    // MARK: - Playback Timer
    
    internal func startPlaybackTimer() {  // Allow internal access for playlist API
        stopPlaybackTimer()
        
        // CRITICAL: Use [weak self] to prevent retain cycle
        playbackTimer = Task { [weak self] in
            // Early exit if self is deallocated
            guard let self = self else { return }
            
            while !Task.isCancelled {
                // Update position every 0.5 seconds
                try? await Task.sleep(nanoseconds: 500_000_000)
                
                // FIXED Issue #10C: Multi-point cancellation guards
                // Prevent race condition between sleep and position update
                guard !Task.isCancelled else { return }
                
                if let position = await self.audioEngine.getCurrentPosition() {
                    // Guard after suspension point to prevent stale updates
                    guard !Task.isCancelled else { return }
                    
                    await self.updatePosition(position)
                }
            }
        }
    }
    
    /// Update playback position and check for loop triggers
    /// - Parameter position: Current playback position
    private func updatePosition(_ position: PlaybackPosition) async {
        self.playbackPosition = position
        notifyObservers(positionUpdate: position)
        await updateNowPlayingPosition()
        
        // Check for loop crossfade trigger (with race condition protection)
        if shouldTriggerLoopCrossfade(position) && !isLoopCrossfadeInProgress {
            await startLoopCrossfade()
        }
    }
    
    private func stopPlaybackTimer() {
        playbackTimer?.cancel()
        playbackTimer = nil
    }
    
    // MARK: - Now Playing Updates
    
    internal func updateNowPlayingInfo() async {  // Allow internal access for playlist API
        guard let track = currentTrack else { return }
        
        // Read actor-isolated properties before MainActor hop
        let currentTime = playbackPosition?.currentTime ?? 0
        let playbackRate: Double = state == .playing ? 1.0 : 0.0
        let manager = remoteCommandManager!  // Capture before MainActor hop
        
        await MainActor.run {
            manager.updateNowPlayingInfo(
                title: track.title,
                artist: track.artist,
                duration: track.duration,
                elapsedTime: currentTime,
                playbackRate: playbackRate
            )
        }
    }
    
    private func updateNowPlayingPosition() async {
        guard let position = playbackPosition else { return }
        
        // Read actor-isolated state before MainActor hop
        let playbackRate: Double = state == .playing ? 1.0 : 0.0
        let manager = remoteCommandManager!  // Capture before MainActor hop
        
        await MainActor.run {
            manager.updatePlaybackPosition(
                elapsedTime: position.currentTime,
                playbackRate: playbackRate
            )
        }
    }
    
    private func updateNowPlayingPlaybackRate(_ rate: Double) async {
        // Read actor-isolated property before MainActor hop
        let currentTime = playbackPosition?.currentTime ?? 0
        let manager = remoteCommandManager!  // Capture before MainActor hop
        
        await MainActor.run {
            manager.updatePlaybackPosition(
                elapsedTime: currentTime,
                playbackRate: rate
            )
        }
    }
    
    // MARK: - Session Event Handlers
    
    private func handleInterruption(shouldResume: Bool) async {
        if shouldResume {
            // Try to resume playback
            try? await resume()
        } else {
            // Pause playback
            try? await pause()
        }
    }
    
    private func handleRouteChange(reason: AVAudioSession.RouteChangeReason) async {
        switch reason {
        case .oldDeviceUnavailable:
            // Headphones unplugged - pause immediately
            try? await pause()
            
        case .newDeviceAvailable:
            // Headphones plugged in - don't auto-resume, let user decide
            break
            
        case .categoryChange, .override:
            // Route changed - continue playback
            break
            
        default:
            break
        }
    }
    
    // MARK: - Loop Crossfade Logic (UPDATED - Phase 3)
    
    /// Epsilon tolerance for floating-point comparison (100ms)
    /// Prevents precision errors in IEEE 754 arithmetic (e.g., 49.999999999 ≠ 50.0)
    private let triggerTolerance: TimeInterval = 0.1
    
    /// Check if we should trigger loop crossfade
    /// - Parameter position: Current playback position
    /// - Returns: True if crossfade should be triggered
    /// - Note: Uses epsilon tolerance to handle floating-point precision errors
    /// - Note: Now checks repeatMode instead of enableLooping (Phase 3)
    private func shouldTriggerLoopCrossfade(_ position: PlaybackPosition) -> Bool {
        // Only loop if repeat mode is not .off
        guard configuration.repeatMode != .off else { return false }
        
        // Don't trigger if already in progress
        guard !isLoopCrossfadeInProgress else { return false }
        
        // Only trigger when playing
        guard state == .playing else { return false }
        
        // Calculate trigger point (crossfade duration before end)
        // For .singleTrack mode, use max(fadeIn, fadeOut) as crossfade duration
        let crossfadeDuration: TimeInterval
        if configuration.repeatMode == .singleTrack {
            crossfadeDuration = max(
                configuration.singleTrackFadeInDuration,
                configuration.singleTrackFadeOutDuration
            )
        } else {
            crossfadeDuration = configuration.crossfadeDuration
        }
        
        let triggerPoint = position.duration - crossfadeDuration
        
        // FIXED Issue #8: Use epsilon tolerance for float precision
        // Trigger when: triggerPoint - tolerance ≤ currentTime < duration
        return position.currentTime >= (triggerPoint - triggerTolerance) && 
               position.currentTime < position.duration
    }
    
    /// Start the loop crossfade process with support for all repeat modes
    /// - Note: Handles .off (finish), .singleTrack (loop current), .playlist (advance)
    private func startLoopCrossfade() async {
        // Mark as in progress BEFORE any async operations
        isLoopCrossfadeInProgress = true
        
        // Determine action based on repeat mode
        switch configuration.repeatMode {
        case .off:
            // Finish playback with fade out
            try? await finish(fadeDuration: configuration.fadeOutDuration)
            isLoopCrossfadeInProgress = false
            
        case .singleTrack:
            // Loop current track with fade
            await loopCurrentTrackWithFade()
            isLoopCrossfadeInProgress = false
            
        case .playlist:
            // Advance to next playlist track
            await advanceToNextPlaylistTrack()
            isLoopCrossfadeInProgress = false
        }
    }
    
    /// Loop current track with fade out at end and fade in at start
    /// - Note: Used only when repeatMode = .singleTrack
    /// - Note: Respects singleTrackFadeInDuration and singleTrackFadeOutDuration
    /// - Note: Dynamically adapts fade durations to track duration (max 40% each, 80% total)
    private func loopCurrentTrackWithFade() async {
        // 1. Validation
        guard let currentURL = currentTrackURL,
              let position = playbackPosition else {
            Self.logger.error("Cannot loop: no current track URL or position")
            return
        }
        
        let trackDuration = position.duration
        
        // ✅ Level 2: Dynamic Validation Per Track
        
        // 2. Check minimum duration (5s)
        guard trackDuration >= 5.0 else {
            Self.logger.warning("Track too short (\(trackDuration)s) for fade, using minimal fade (0.5s)")
            // TODO v3.2: Add to ValidationFeedback system
            return
        }
        
        // 3. Get configured fade durations
        let configuredFadeIn = configuration.singleTrackFadeInDuration
        let configuredFadeOut = configuration.singleTrackFadeOutDuration
        
        // 4. Adaptive scaling to track duration (max 40% each = 80% total)
        let maxFadeIn = min(configuredFadeIn, trackDuration * 0.4)
        let maxFadeOut = min(configuredFadeOut, trackDuration * 0.4)
        
        // 5. Ensure total doesn't exceed 80%
        var actualFadeIn = maxFadeIn
        var actualFadeOut = maxFadeOut
        
        if actualFadeIn + actualFadeOut > trackDuration * 0.8 {
            let ratio = (trackDuration * 0.8) / (actualFadeIn + actualFadeOut)
            actualFadeIn *= ratio
            actualFadeOut *= ratio
            Self.logger.info("Fade durations adapted to track: fadeIn=\(actualFadeIn)s, fadeOut=\(actualFadeOut)s")
        }
        
        // 6. Calculate crossfade duration (max of adapted fade in/out)
        let crossfadeDuration = max(actualFadeOut, actualFadeIn)
        
        Self.logger.debug("Single track loop: configured(\(configuredFadeIn)s,\(configuredFadeOut)s) → actual(\(actualFadeIn)s,\(actualFadeOut)s)")
        Self.logger.debug("Track duration: \(trackDuration)s, crossfade: \(crossfadeDuration)s")
        
        // 7. Send .preparing state for instant UI feedback
        let prepareProgress = CrossfadeProgress(
            phase: .preparing,
            duration: crossfadeDuration,
            elapsed: 0
        )
        updateCrossfadeProgress(prepareProgress)
        
        // 4. Load same file on secondary player
        do {
            let trackInfo = try await audioEngine.loadAudioFileOnSecondaryPlayer(url: currentURL)
            
            // 5. Prepare secondary player
            await audioEngine.prepareSecondaryPlayer()
            
            // 6. Perform synchronized crossfade with progress
            let progressStream = await audioEngine.performSynchronizedCrossfade(
                duration: crossfadeDuration,
                curve: configuration.fadeCurve
            )
            
            // 7. Observe progress
            crossfadeProgressTask = Task { [weak self] in
                for await progress in progressStream {
                    await self?.updateCrossfadeProgress(progress)
                }
            }
            
            // Wait for completion
            await crossfadeProgressTask?.value
            crossfadeProgressTask = nil
            
            // 8. Switch players (secondary becomes active)
            await audioEngine.switchActivePlayer()
            
            // 9. Stop old player (now inactive)
            await audioEngine.stopInactivePlayer()
            
            // 10. Reset inactive mixer
            await audioEngine.resetInactiveMixer()
            
            // 11. Clear inactive file to free memory
            await audioEngine.clearInactiveFile()
            
            // 12. Update track info (same URL, but refreshed)
            currentTrack = trackInfo
            // currentTrackURL stays the same
            
            // 13. Increment repeat count
            currentRepeatCount += 1
            
            // 14. Update now playing
            await updateNowPlayingInfo()
            
            Self.logger.info("Single track loop completed (repeat #\(currentRepeatCount))")
            
        } catch {
            Self.logger.error("Single track loop failed: \(error)")
        }
    }
    
    /// Advance to next track in playlist with crossfade
    /// - Note: Used only when repeatMode = .playlist
    /// - Note: Existing logic moved from startLoopCrossfade()
    private func advanceToNextPlaylistTrack() async {
        // Send .preparing state immediately
        let prepareProgress = CrossfadeProgress(
            phase: .preparing,
            duration: configuration.crossfadeDuration,
            elapsed: 0
        )
        updateCrossfadeProgress(prepareProgress)
        
        // 1. Get next track from playlist manager
        guard let nextURL = await playlistManager.getNextTrack() else {
            // No more tracks - finish playback
            try? await finish(fadeDuration: configuration.fadeOutDuration)
            return
        }
        
        // 2. Load next track on secondary player
        do {
            let nextTrack = try await audioEngine.loadAudioFileOnSecondaryPlayer(url: nextURL)
            
            // 3. Prepare secondary player
            await audioEngine.prepareSecondaryPlayer()
            
            // 4. Perform synchronized crossfade with progress observation
            let progressStream = await audioEngine.performSynchronizedCrossfade(
                duration: configuration.crossfadeDuration,
                curve: configuration.fadeCurve
            )
            
            // Observe progress
            crossfadeProgressTask = Task { [weak self] in
                for await progress in progressStream {
                    await self?.updateCrossfadeProgress(progress)
                }
            }
            
            // Wait for completion
            await crossfadeProgressTask?.value
            crossfadeProgressTask = nil
            
            // 5. Cleanup: switch active player, then stop old (now inactive) player
            await audioEngine.switchActivePlayer()
            await audioEngine.stopInactivePlayer()
            await audioEngine.resetInactiveMixer()
            
            // Clear inactive file reference to free memory
            await audioEngine.clearInactiveFile()
            
            // 6. Update current track info
            currentTrack = nextTrack
            currentTrackURL = nextURL
            
            // 7. Update now playing
            await updateNowPlayingInfo()
            
            Self.logger.info("Playlist auto-advance completed")
            
        } catch {
            // Failed to load next track
            Self.logger.error("Auto-advance failed: \(error)")
        }
    }
    
    /// Sync current configuration to playlist manager
    private func syncConfigurationToPlaylistManager() async {
        let playerConfig = PlayerConfiguration(
            crossfadeDuration: configuration.crossfadeDuration,
            fadeCurve: configuration.fadeCurve,
            repeatMode: configuration.repeatMode,
            repeatCount: configuration.repeatCount,
            singleTrackFadeInDuration: configuration.singleTrackFadeInDuration,
            singleTrackFadeOutDuration: configuration.singleTrackFadeOutDuration,
            volume: Int(configuration.volume * 100),
            stopFadeDuration: configuration.stopFadeDuration
        )
        await playlistManager.updateConfiguration(playerConfig)
    }
    
    // MARK: - Crossfade Progress
    
    /// Rollback active crossfade transaction to stable state
    /// - Parameter rollbackDuration: Duration to restore active volume (default: 0.5s)
    /// - Note: Clears both loop and replacement flags (works for all repeat modes)
    private func rollbackCrossfade(rollbackDuration: TimeInterval = 0.5) async {
        // Perform rollback on audio engine
        _ = await audioEngine.rollbackCrossfade(rollbackDuration: rollbackDuration)
        
        // Clear crossfade flags (handles all repeat modes)
        isLoopCrossfadeInProgress = false
        isTrackReplacementInProgress = false
        
        // Cancel progress observation
        crossfadeProgressTask?.cancel()
        crossfadeProgressTask = nil
        
        // Update progress state
        currentCrossfadeProgress = .idle
        
        // Notify observers about rollback
        for observer in observers {
            Task {
                if let progressObserver = observer as? CrossfadeProgressObserver {
                    await progressObserver.crossfadeProgressDidUpdate(.idle)
                }
            }
        }
    }
    
    /// Update crossfade progress and notify observers
    internal func updateCrossfadeProgress(_ progress: CrossfadeProgress) {
        Self.logger.debug("[PROGRESS] Updating crossfade progress: \(progress.phase), observers count: \(observers.count)")
        currentCrossfadeProgress = progress
        
        // Notify observers about crossfade progress
        for observer in observers {
            Task {
                if let progressObserver = observer as? CrossfadeProgressObserver {
                    Self.logger.debug("[PROGRESS] Notifying observer...")
                    await progressObserver.crossfadeProgressDidUpdate(progress)
                }
            }
        }
    }
}

// MARK: - AudioStateMachineContext

extension AudioPlayerService: AudioStateMachineContext {
    func stateDidChange(to state: PlayerState) async {
        self._state = state  // SSOT: Only update point
        notifyObservers(stateChange: state)
    }
    
    func startEngine() async throws {
        try await audioEngine.start()
        await audioEngine.scheduleFile(
            fadeIn: true,
            fadeInDuration: configuration.fadeInDuration,
            fadeCurve: configuration.fadeCurve
        )
    }
    
    func stopEngine() async {
        await audioEngine.stop()
        stopPlaybackTimer()
    }
    
    func pausePlayback() async {
        // Stop playback timer BEFORE pausing
        // This prevents position updates during pause
        stopPlaybackTimer()
        
        // Pause audio engine (captures position accurately)
        await audioEngine.pause()
    }
    
    func resumePlayback() async throws {
        await audioEngine.play()
        // Restart playback timer after resume
        startPlaybackTimer()
    }
    
    func startFadeOut(duration: TimeInterval) async {
        // Fade out directly within actor context
        await audioEngine.fadeActiveMixer(
            from: 1.0,
            to: 0.0,
            duration: duration,
            curve: configuration.fadeCurve
        )
    }
    
    func transitionToFinished() async {
        // Properly transition to finished state after fade out
        await stop()
    }
    
    func transitionToPlaying() async {
        await stateMachine.enterPlaying()
    }
    
    func transitionToFailed(error: AudioPlayerError) async {
        await stateMachine.enterFailed(error: error)
    }
}

// MARK: - PlayerState Description

internal extension PlayerState {  // Made internal for playlist extension access
    var description: String {
        switch self {
        case .preparing: return "preparing"
        case .playing: return "playing"
        case .paused: return "paused"
        case .fadingOut: return "fading out"
        case .finished: return "finished"
        case .failed: return "failed"
        }
    }
}
