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

/// Main audio player service implementing the AudioPlayerProtocol
public actor AudioPlayerService: AudioPlayerProtocol {
    // MARK: - Properties
    
    // Private logger
    private static let logger = Logger.audio
    
    // SSOT: State managed by PlaybackStateCoordinator
    // Cached state for sync protocol conformance
    private var _cachedState: PlayerState = .finished
    public var state: PlayerState { _cachedState }
    
    // Cached Track.Metadata for sync protocol conformance
    private var _cachedTrackInfo: Track.Metadata? = nil
    public var currentTrack: Track.Metadata? { _cachedTrackInfo }
    
    // Helper: Update state via coordinator and sync cache
    private func updateState(_ newState: PlayerState) async {
        await playbackStateCoordinator.updateMode(newState)
        await syncCachedState()  // Read from coordinator + yield
    }
    
    // Helper: Sync cached state from coordinator
    private func syncCachedState() async {
        _cachedState = await playbackStateCoordinator.getPlaybackMode()
        // Yield to AsyncStream
        stateContinuation.yield(_cachedState)  // ✅ Non-optional continuation
    }
    
    // Helper: Sync cached TrackInfo from coordinator
    private func syncCachedTrackInfo() async {
        _cachedTrackInfo = await playbackStateCoordinator.getActiveTrackInfo()
        // Yield to AsyncStream
        trackContinuation.yield(_cachedTrackInfo)  // ✅ Non-optional continuation
    }
    public private(set) var configuration: PlayerConfiguration  // Public read, private write (use updateConfiguration)
    public private(set) var playbackPosition: PlaybackPosition?
    
    // Internal components
    internal let audioEngine: AudioEngineActor  // Allow internal access for playlist API
    private let playbackStateCoordinator: PlaybackStateCoordinator  // SSOT for player state (Phase 5: will become pure StateStore)
    private let crossfadeOrchestrator: CrossfadeOrchestrator  // PHASE 5: Crossfade orchestration
    internal let sessionManager: AudioSessionManager  // Allow internal access for playlist API
    // RemoteCommandManager is now @MainActor isolated for thread safety
    // Must be created in setup() due to MainActor isolation
    private var remoteCommandManager: RemoteCommandManager!
    // Removed: stateMachine - replaced by PlaybackStateCoordinator
    
    // Playback timer for position updates
    private var playbackTimer: Task<Void, Never>?
    
    // Observers removed in v3.1 - use AsyncStream APIs instead
    
    // AsyncStream support (SwiftUI-friendly API)
    // ✅ FIXED: Producer-owned AsyncStream with makeStream() pattern
    // Non-optional stored streams + continuations eliminate race conditions
    private let stateStream: AsyncStream<PlayerState>
    private let stateContinuation: AsyncStream<PlayerState>.Continuation
    private let trackStream: AsyncStream<Track.Metadata?>
    private let trackContinuation: AsyncStream<Track.Metadata?>.Continuation
    private let positionStream: AsyncStream<PlaybackPosition>
    private let positionContinuation: AsyncStream<PlaybackPosition>.Continuation
    private let eventStream: AsyncStream<PlayerEvent>
    private let eventContinuation: AsyncStream<PlayerEvent>.Continuation
    
    // Loop tracking
    private var currentRepeatCount = 0
    // Removed: currentTrackURL - now using playbackStateCoordinator.getActiveTrack()?.url
    // Removed: CrossfadeOperation enum - now in PlaybackStateCoordinator
    // Removed: activeCrossfadeOperation - managed by PlaybackStateCoordinator
    // Removed: PausedCrossfadeState struct - now in PlaybackStateCoordinator
    // Removed: pausedCrossfadeState - managed by PlaybackStateCoordinator
    // Removed: crossfadeProgressTask - managed by PlaybackStateCoordinator
    
    // Crossfade cleanup task (for resumed crossfades)
    private var crossfadeCleanupTask: Task<Void, Never>?
    // Removed: currentCrossfadeProgress - not used by Demo app, coordinator manages progress
    
    // Operation queue for serializing async operations (prevents actor re-entrancy)
    private let operationQueue = AsyncOperationQueue(maxDepth: 3)
    
    // Route change debounce (prevents rapid-fire iOS events from breaking state)
    private var routeChangeDebounceTask: Task<Void, Never>?
    private var isHandlingRouteChange = false
    
    // Playlist manager
    internal var playlistManager: PlaylistManager  // Allow internal access for playlist API
    
    // Sound effects player (independent from main engine)
    private let soundEffectsPlayer: SoundEffectsPlayerActor

    /// Pending fade-in duration for next startPlaying call
    /// Allows per-call fade-in override without changing configuration
    private var pendingFadeInDuration: TimeInterval = 0.0
    
    /// Lazy setup flag - setup() called automatically on first use
    private var isSetupComplete = false
    
    // MARK: - Initialization
    
    /// Initialize AudioPlayerService with configuration
    ///
    /// **Async Initialization:**
    /// This initializer is async because it performs complete setup:
    /// - Configures and activates audio session
    /// - Sets up audio engine and nodes
    /// - Initializes remote commands
    /// - Configures session handlers
    ///
    /// After initialization, the service is **fully ready** to use.
    ///
    /// **Example:**
    /// ```swift
    /// let audioService = await AudioPlayerService()
    /// try await audioService.loadPlaylist(tracks)
    /// try await audioService.startPlaying()
    /// ```
    ///
    /// - Parameter configuration: Player configuration (optional, uses defaults if not provided)
    public init(configuration: PlayerConfiguration = PlayerConfiguration()) async throws {
        
        // ✅ CRITICAL FIX: Initialize AsyncStreams FIRST (before any async calls)
        // Using makeStream() with buffering ensures early events aren't lost
        let (stateStream, stateCont) = AsyncStream<PlayerState>.makeStream(bufferingPolicy: .bufferingNewest(1))
        self.stateStream = stateStream
        self.stateContinuation = stateCont
        
        let (trackStream, trackCont) = AsyncStream<Track.Metadata?>.makeStream(bufferingPolicy: .bufferingNewest(1))
        self.trackStream = trackStream
        self.trackContinuation = trackCont
        
        let (positionStream, posCont) = AsyncStream<PlaybackPosition>.makeStream(bufferingPolicy: .bufferingNewest(1))
        self.positionStream = positionStream
        self.positionContinuation = posCont
        
        let (eventStream, eventCont) = AsyncStream<PlayerEvent>.makeStream(bufferingPolicy: .bufferingNewest(10))
        self.eventStream = eventStream
        self.eventContinuation = eventCont
        
        self.configuration = configuration
        self.audioEngine = AudioEngineActor()
        self.playbackStateCoordinator = PlaybackStateCoordinator()  // ✅ Phase 5: No audioEngine dependency
        self.sessionManager = AudioSessionManager.shared  // Use singleton

        // ✅ PHASE 5: Initialize CrossfadeOrchestrator (PHASE 2: direct AudioEngineActor)
        self.crossfadeOrchestrator = CrossfadeOrchestrator(
            audioEngine: audioEngine,
            stateStore: playbackStateCoordinator
        )

        // Initialize playlist manager with configuration
        self.playlistManager = PlaylistManager(configuration: configuration)
        // Initialize sound effects player with nodes from AudioEngineActor
        // Nodes (playerNodeD, mixerNodeD) are already created and will be attached in setup()
        // Create inside actor context to avoid Sendable issues
        self.soundEffectsPlayer = await audioEngine.createSoundEffectsPlayer()
        // remoteCommandManager will be created in setup() on MainActor

        // ✅ NEW: Perform full setup immediately
        // Service is ready to use after init completes
        try await setup()
    }
    
    /// Internal setup - called automatically on first use.
    /// You no longer need to call this manually!
    internal func setup() async throws {
        guard !isSetupComplete else { return }
        isSetupComplete = true
        // Configure and activate audio session BEFORE engine setup
        // This prevents crashes when engine accesses outputNode
        do {
            try await sessionManager.configure(options: configuration.audioSessionOptions)
            try await sessionManager.activate()
            Self.logger.debug("Audio session activated in setup()")
        } catch {
            Self.logger.error("Failed to activate audio session in setup(): \(error)")
            // Continue anyway - will retry in startPlaying()
        }
        
        // Now safe to setup engine (accesses outputNode)
        try await audioEngine.setup()
        
        // Apply initial volume from configuration
        await audioEngine.setVolume(configuration.volume)
        
        // FIXED: Create RemoteCommandManager on MainActor
        remoteCommandManager = await MainActor.run {
            RemoteCommandManager()
        }
        
        // State machine removed - using PlaybackStateCoordinator
        await setupSessionHandlers()
        await setupRemoteCommands()
    }
    
    // ensureSetup() removed - setup() is now called in async init()
    
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
        
        // Handle media services reset (critical for AVAudioPlayer coexistence)
        await sessionManager.setMediaServicesResetHandler { [weak self] in
            guard let self = self else { return }
            Task {
                await self.handleMediaServicesReset()
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
                    try? await self?.skip(forward: interval)
                },
                skipBackwardHandler: { [weak self] interval in
                    try? await self?.skip(backward: interval)
                }
            )
        }
    }
    
    // MARK: - AudioPlayerProtocol Implementation
    
    /// Start playback with optional fade-in
    ///
    /// Plays the current track from playlist with configurable fade-in.
    /// Uses track from `playlistManager.getCurrentTrack()`.
    ///
    /// - Parameter fadeDuration: Fade-in duration in seconds (0.0 = no fade, instant start)
    /// - Throws:
    ///   - `AudioPlayerError.emptyPlaylist` if playlist is empty
    ///   - `AudioPlayerError.invalidState` if cannot transition to playing
    ///   - `AudioPlayerError.fileNotFound` if track file doesn't exist
    ///
    /// - Note: Configuration must be set via initializer or `updateConfiguration()`
    /// - Note: fadeDuration is independent from crossfade between tracks
    public func startPlaying(fadeDuration: TimeInterval = 0.0) async throws {
        // ✅ BUG FIX #3: Check current state and stop if needed
        let currentState = await playbackStateCoordinator.getPlaybackMode()
        if currentState == .playing || currentState == .preparing {
            Self.logger.debug("[SERVICE] Already playing, stopping first")
            await stop(fadeDuration: 0.0) // Stop without fade
        }


        // Get current track from playlist
        guard let track = await playlistManager.getCurrentTrack() else {
            throw AudioPlayerError.emptyPlaylist
        }

        // Validate configuration
        try configuration.validate()

        // Sync configuration with playlist manager
        await syncConfigurationToPlaylistManager()

        // Reset loop tracking
        self.currentRepeatCount = 0

        // ✅ PHASE 1 SIMPLIFICATION: Inline orchestrator logic (5 steps)
        
        // 1. Activate audio session
        do {
            try await sessionManager.activate()
            Self.logger.debug("[SERVICE] ✅ Audio session activated")
        } catch {
            Self.logger.error("[SERVICE] ❌ Failed to activate session: \(error)")
            throw AudioPlayerError.sessionConfigurationFailed(
                reason: "Failed to activate: \(error.localizedDescription)"
            )
        }
        
        // 2. Prepare and start audio engine
        do {
            try await audioEngine.prepare()
            try await audioEngine.start()
            Self.logger.debug("[SERVICE] ✅ Engine prepared and started")
        } catch {
            Self.logger.error("[SERVICE] ❌ Failed to prepare/start engine: \(error)")
            throw AudioPlayerError.engineStartFailed(
                reason: "Failed to prepare/start: \(error.localizedDescription)"
            )
        }
        
        // 3. Load audio file and update state
        let trackWithMetadata = try await audioEngine.loadAudioFile(track: track)
        await playbackStateCoordinator.atomicSwitch(newTrack: trackWithMetadata, mode: .preparing)
        await syncCachedState()  // ✅ Sync .preparing state to AsyncStream
        await syncCachedTrackInfo()  // ✅ Sync track metadata to AsyncStream
        Self.logger.debug("[SERVICE] ✅ File loaded: \(trackWithMetadata.metadata?.title ?? "Unknown")")
        
        // 4. Schedule file with optional fade-in
        await audioEngine.scheduleFile(
            fadeIn: fadeDuration > 0,
            fadeInDuration: fadeDuration,
            fadeCurve: .equalPower
        )
        
        // 5. Start playback and update state
        await audioEngine.play()
        await updateState(.playing)

        // Update now playing info
        await updateNowPlayingInfo()

        // Start playback timer
        startPlaybackTimer()

        Self.logger.info("[SERVICE] ✅ Started playing (orchestrator)")
    }
    
    public func pause() async throws {
        try await operationQueue.enqueue(
            priority: .high,
            description: "pause"
        ) {
            try await self._pauseImpl()
        }
    }
    
    private func _pauseImpl() async throws {
        // ✅ PHASE 2: Added fade out before pause
        Self.logger.debug("[SERVICE] pause()")
        
        // Delegate crossfade pause to coordinator (if any active)
        let pausedCrossfade = try await crossfadeOrchestrator.pauseCrossfade()
        
        // 1. Validate current state
        let currentState = await playbackStateCoordinator.getPlaybackMode()
        guard currentState == .playing || currentState == .preparing else {
            // Already paused - idempotent operation
            if currentState == .paused {
                Self.logger.debug("[SERVICE] Already paused - no-op")
                return
            }
            Self.logger.error("[SERVICE] ❌ Invalid state for pause: \(currentState)")
            throw AudioPlayerError.invalidState(
                current: currentState.description,
                attempted: "pause"
            )
        }
        
        // 2. Fade out before pause (only if not pausing crossfade)
        if pausedCrossfade == nil {
            await crossfadeOrchestrator.performSimpleFadeOut(duration: 0.3)
        }
        
        // 3. Pause engine (captures position internally)
        await audioEngine.pause()
        Self.logger.debug("[SERVICE] ✅ Engine paused")
        
        // 3. Update state ONLY after success
        await updateState(.paused)
        
        // 4. Stop playback timer (CRITICAL: prevent crossfade during pause!)
        stopPlaybackTimer()
        
        // Update UI
        await updateNowPlayingPlaybackRate(0.0)
        
        Self.logger.info("[SERVICE] ✅ Paused")
    }
    
    public func resume() async throws {
        try await operationQueue.enqueue(
            priority: .normal,
            description: "resume"
        ) {
            try await self._resumeImpl()
        }
    }
    
    private func _resumeImpl() async throws {
        // ✅ PHASE 1 SIMPLIFICATION: Inline orchestrator logic
        Self.logger.debug("[SERVICE] resume()")
        
        // Try resume crossfade from coordinator (if any paused)
        let resumedCrossfade = try await crossfadeOrchestrator.resumeCrossfade()
        
        if resumedCrossfade {
            // ✅ Sync state after crossfade resume (orchestrator changed SSOT internally)
            await syncCachedState()
            await syncCachedTrackInfo()
        }
        
        if !resumedCrossfade {
            // No crossfade to resume - normal resume
            Self.logger.debug("[SERVICE] Normal resume (no paused crossfade)")
            
            // 1. Validate current state
            let currentState = await playbackStateCoordinator.getPlaybackMode()
            guard currentState == .paused else {
                // Already playing - idempotent operation
                if currentState == .playing {
                    Self.logger.debug("[SERVICE] Already playing - no-op")
                    return
                }
                Self.logger.error("[SERVICE] ❌ Invalid state for resume: \(currentState)")
                throw AudioPlayerError.invalidState(
                    current: currentState.description,
                    attempted: "resume"
                )
            }
            
            // 2. Ensure audio session is active
            do {
                try await sessionManager.ensureActive()
                Self.logger.debug("[SERVICE] ✅ Session ensured active")
            } catch {
                Self.logger.error("[SERVICE] ❌ Failed to ensure session active: \(error)")
                throw AudioPlayerError.sessionConfigurationFailed(
                    reason: "Failed to ensure active: \(error.localizedDescription)"
                )
            }
            
            // 3. Resume engine playback (restores from saved position)
            await audioEngine.play()
            Self.logger.debug("[SERVICE] ✅ Engine resumed")
            
            // 4. Fade in (PHASE 2: smooth resume)
            await crossfadeOrchestrator.performSimpleFadeIn(duration: 0.3)
            
            Self.logger.info("[SERVICE] ✅ Normal resume completed")
        }
        
        // ✅ CRITICAL FIX: Update state for BOTH paths (normal + crossfade)
        await updateState(.playing)
        
        // 5. Restart playback timer (CRITICAL: restore crossfade monitoring!)
        startPlaybackTimer()
        
        // Update UI
        await updateNowPlayingPlaybackRate(1.0)
    }

    /// Stop playback with optional fade out
    /// - Parameter fadeDuration: Duration of fade out in seconds (0.0 = instant stop, clamped to 0.0-10.0)
    /// - Note: Default is instant stop (fadeDuration = 0.0)
    /// - Note: If stop called during crossfade, crossfade is cancelled and fadeout is performed on active track
    public func stop(fadeDuration: TimeInterval = 0.0) async {
        do {
            try await operationQueue.enqueue(
                priority: .high,
                description: "stop"
            ) {
                await self._stopImpl(fadeDuration: fadeDuration)
            }
        } catch {
            Self.logger.error("[QUEUE] stop() enqueue failed: \(error)")
            // Fallback: execute directly if queue is full
            await _stopImpl(fadeDuration: fadeDuration)
        }
    }
    
    private func _stopImpl(fadeDuration: TimeInterval) async {
        // ✅ PHASE 4: Simplified to thin facade
        Self.logger.debug("[SERVICE] stop(fade: \(fadeDuration)s) → orchestrator")

        // Clear paused crossfade state (stop invalidates saved state)
        await crossfadeOrchestrator.clearPausedCrossfade()

        // Cancel active crossfade if any
        if await crossfadeOrchestrator.hasActiveCrossfade() {
            Self.logger.debug("[STOP] Cancel crossfade in progress")
            await crossfadeOrchestrator.cancelActiveCrossfade()
            await audioEngine.cancelCrossfadeAndStopInactive()
        }
        
        // ✅ PHASE 1 SIMPLIFICATION: Inline orchestrator logic
        
        // 1. Apply fade-out if requested
        if fadeDuration > 0 {
            let currentVolume = await audioEngine.getActiveMixerVolume()
            Self.logger.debug("[SERVICE] Fading out from \(currentVolume) to 0")
            await audioEngine.fadeActiveMixer(
                from: currentVolume,
                to: 0.0,
                duration: fadeDuration,
                curve: .equalPower
            )
        }
        
        // 2. Stop both players
        await audioEngine.stopBothPlayers()
        Self.logger.debug("[SERVICE] ✅ Players stopped")
        
        // 3. Update state to finished
        await updateState(.finished)
        
        // Stop timer and clear UI
        stopPlaybackTimer()
        let manager = remoteCommandManager!
        Task { @MainActor in
            manager.clearNowPlayingInfo()
        }
    }
    
    // ✅ PHASE 4: Removed stopWithFade() and stopImmediately()
    // Logic moved to PlaybackOrchestrator.stop()

    
    public func finish(fadeDuration: TimeInterval?) async throws {
        try await operationQueue.enqueue(
            priority: .high,
            description: "finish"
        ) {
            try await self._finishImpl(fadeDuration: fadeDuration)
        }
    }
    
    private func _finishImpl(fadeDuration: TimeInterval?) async throws {
        // ✅ BUG FIX #4: Implement proper finish() logic
        let duration = fadeDuration ?? 3.0
        
        // 1. Validate current state
        let currentState = await playbackStateCoordinator.getPlaybackMode()
        guard currentState == .playing || currentState == .paused else {
            throw AudioPlayerError.invalidState(
                current: currentState.description,
                attempted: "finish"
            )
        }
        
        // 2. Transition to fadingOut
        await updateState(.fadingOut)
        Self.logger.debug("[FINISH] State transition: \(currentState) → fadingOut")
        
        // 3. Perform fade-out
        let currentVolume = await audioEngine.getActiveMixerVolume()
        Self.logger.debug("[FINISH] Fading out from \(currentVolume) to 0 (duration: \(duration)s)")
        await audioEngine.fadeActiveMixer(
            from: currentVolume,
            to: 0.0,
            duration: duration,
            curve: .equalPower
        )
        
        // 4. Stop playback (call impl directly - no fade as already faded)
        Self.logger.debug("[FINISH] Fade complete, stopping playback")
        await _stopImpl(fadeDuration: 0.0)
        
        Self.logger.info("[FINISH] ✅ Finished with graceful fade-out (\(duration)s)")
    }
    
    public func skip(forward interval: TimeInterval = 15.0) async throws {
        // Cancel any active crossfade (without rollback)
        if await crossfadeOrchestrator.hasActiveCrossfade() {
            await audioEngine.cancelCrossfadeAndStopInactive()
            
            // Removed: activeCrossfadeOperation = nil (managed by coordinator)
            
            // Removed: crossfadeProgressTask cancel (managed by coordinator)
            // Removed: currentCrossfadeProgress = .idle (managed by coordinator)
        }
        
        // ✅ PHASE 2: Enhanced skip with fade-seek-fade
        
        guard let position = playbackPosition else {
            throw AudioPlayerError.invalidState(
                current: "no playback position",
                attempted: "skip forward"
            )
        }
        
        let newTime = min(position.currentTime + interval, position.duration)
        try await crossfadeOrchestrator.performFadeSeekFade(seekTo: newTime, fadeOutDuration: 0.3, fadeInDuration: 0.3)
    }
    
    public func skip(backward interval: TimeInterval = 15.0) async throws {
        // Cancel any active crossfade (without rollback)
        if await crossfadeOrchestrator.hasActiveCrossfade() {
            await audioEngine.cancelCrossfadeAndStopInactive()
            
            // Removed: activeCrossfadeOperation = nil (managed by coordinator)
            
            // Removed: crossfadeProgressTask cancel (managed by coordinator)
            // Removed: currentCrossfadeProgress = .idle (managed by coordinator)
        }
        
        // ✅ PHASE 2: Enhanced skip with fade-seek-fade
        
        guard let position = playbackPosition else {
            throw AudioPlayerError.invalidState(
                current: "no playback position",
                attempted: "skip backward"
            )
        }
        
        let newTime = max(position.currentTime - interval, 0)
        try await crossfadeOrchestrator.performFadeSeekFade(seekTo: newTime, fadeOutDuration: 0.3, fadeInDuration: 0.3)
    }
    
    /// Seek to position with fade to eliminate clicking/popping sounds
    /// - Parameters:
    ///   - time: Target position in seconds
    ///   - fadeDuration: Duration of fade in/out (default: 0.1s, imperceptible to users)
    /// - Throws: AudioPlayerError if seek fails
    /// - Note: Uses brief fade to avoid buffer discontinuity artifacts (clicking sounds)
    /// - Note: Automatically cancels any active crossfade before seeking
    public func seek(to time: TimeInterval, fadeDuration: TimeInterval = 0.1) async throws {
        // Clear paused crossfade state (new position invalidates saved state)
        await crossfadeOrchestrator.clearPausedCrossfade()
        
        Self.logger.debug("[SEEK] Seeking to \(time)s, crossfadeActive=\(await crossfadeOrchestrator.hasActiveCrossfade())")

        // Cancel any active crossfade (without rollback)
        if await crossfadeOrchestrator.hasActiveCrossfade() {
            await audioEngine.cancelCrossfadeAndStopInactive()

            // Removed: activeCrossfadeOperation = nil (managed by coordinator)

            // Removed: crossfadeProgressTask cancel (managed by coordinator)
            // Removed: currentCrossfadeProgress = .idle (managed by coordinator)
        }
        
        let wasPlaying = await state == .playing
        
        let currentVolume = await audioEngine.getTargetVolume()
        
        // 1. Fade out if playing (eliminates click from buffer discontinuity)
        if wasPlaying {
            await audioEngine.fadeActiveMixer(
                from: currentVolume,
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
                to: currentVolume,
                duration: fadeDuration,
                curve: .linear
            )
        }
    }
    
    public func setVolume(_ volume: Float) async {
        let clampedVolume = max(0.0, min(1.0, volume))
        
        // Update audio engine
        await audioEngine.setVolume(clampedVolume)
        
        // Update configuration with new volume
        configuration = PlayerConfiguration(
            crossfadeDuration: configuration.crossfadeDuration,
            fadeCurve: configuration.fadeCurve,
            repeatMode: configuration.repeatMode,
            repeatCount: configuration.repeatCount,
            volume: clampedVolume,
            audioSessionOptions: configuration.audioSessionOptions
        )
    }
    
    /// Current repeat count (number of loop iterations completed)
    public var repeatCount: Int {
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
    public func setRepeatMode(_ mode: RepeatMode) async {
        // Update configuration with new repeat mode
        configuration = PlayerConfiguration(
            crossfadeDuration: configuration.crossfadeDuration,
            fadeCurve: configuration.fadeCurve,
            repeatMode: mode,
            repeatCount: configuration.repeatCount,
            volume: configuration.volume,
            audioSessionOptions: configuration.audioSessionOptions
        )
        
        // Sync to PlaylistManager
        await syncConfigurationToPlaylistManager()
        
        Self.logger.info("Repeat mode set to: \(mode)")
    }
    
    /// Current repeat mode
    /// - Returns: Current repeat mode (.off, .singleTrack, .playlist)
    public var repeatMode: RepeatMode {
        return configuration.repeatMode
    }
    
    /// Update player configuration (stops playback first)
    ///
    /// Changes global playback settings. Requires stop to apply changes safely.
    /// After updating, call startPlaying() to resume with new configuration.
    ///
    /// **Configurable Settings:**
    /// - Crossfade duration (affects playlist transitions and single track loops)
    /// - Fade curve (linear, easeIn, easeOut, etc.)
    /// - Repeat mode (off, singleTrack, playlist)
    /// - Repeat count (for repeat modes)
    /// - Volume level
    /// - Audio session options
    ///
    /// **Example:**
    /// ```swift
    /// var newConfig = player.configuration
    /// newConfig.crossfadeDuration = 8.0
    /// newConfig.fadeCurve = .easeInOut
    /// 
    /// try await player.updateConfiguration(newConfig)
    /// try await player.startPlaying()  // Resume with new settings
    /// ```
    ///
    /// - Parameter config: New configuration to apply
    /// - Throws: AudioPlayerError if validation fails
    /// - Note: Playback is stopped before applying changes for safety
    /// - Note: Configuration changes take effect immediately for next playback
    public func updateConfiguration(_ config: PlayerConfiguration) async throws {
        // 1. Force stop to ensure clean state
        await stop(fadeDuration: 0.0)
        
        // 2. Validate configuration
        try config.validate()
        
        // 3. Update configuration
        self.configuration = config
        
        // 4. Sync to playlist manager
        await syncConfigurationToPlaylistManager()
        
        Self.logger.info("Configuration updated: crossfade=\(config.crossfadeDuration)s, repeatMode=\(config.repeatMode)")
    }
    
    
    #if DEBUG
    /// Reset player to initial state with default configuration (DEBUG only)
    ///
    /// **⚠️ DEBUG ONLY:** This method is only available in debug builds.
    ///
    /// Performs full cleanup and re-initialization of the player:
    /// - Stops all playback (main, overlay, sound effects)
    /// - Clears playlist and all state
    /// - Resets configuration to defaults
    /// - Reinitializes state machine
    /// - Deactivates audio session
    ///
    /// **Use Cases:**
    /// - Testing: Reset between test cases
    /// - Debugging: Clean slate for reproduction
    /// - Development: Quick reset during iteration
    ///
    /// **Production Alternative:**
    /// In production, create a new AudioPlayerService instance instead of reset().
    ///
    /// **Example:**
    /// ```swift
    /// // DEBUG: Quick reset
    /// await player.reset()
    ///
    /// // PRODUCTION: Create new instance
    /// player = AudioPlayerService(configuration: myConfig)
    /// await player.setup()
    /// ```
    public func reset() async {
        // Stop timer first
        stopPlaybackTimer()
        
        // Full engine reset (clears all files and state)
        await audioEngine.fullReset()
        
        // Session stays active - following Apple's AVAudioPlayer pattern
        // iOS manages session lifecycle automatically
        
        // Reset configuration
        configuration = PlayerConfiguration()
        
        // Clear playlist
        await playlistManager.clear()
        await syncConfigurationToPlaylistManager()
        
        // Clear all state (including crossfade flags)
        // currentTrack removed - coordinator manages active track via atomicSwitch()
        playbackPosition = nil
        currentRepeatCount = 0
        // Removed: activeCrossfadeOperation = nil (managed by coordinator)
        
        // CRITICAL: Reset state to finished
        // This prevents Error 4 (invalidState) on next play()
        await updateState(.finished)
        
        // Re-setup engine for fresh start
        try? await audioEngine.setup()
        
        // Clear Now Playing
        let manager = remoteCommandManager!  // Capture before MainActor hop
        Task { @MainActor in
            manager.clearNowPlayingInfo()
        }
    }
    #endif
    
    /// Cleanup all resources (automatic deallocation)
    ///
    /// **Note:** This is called automatically during deallocation.
    /// You don't need to call this manually in production code.
    ///
    /// Swift's automatic reference counting handles cleanup when
    /// AudioPlayerService is deallocated. This method exists for
    /// explicit cleanup in special scenarios.
    internal func cleanup() async {
        // Stop timer and playback
        stopPlaybackTimer()
        await audioEngine.fullReset()
        
        // Session stays active - following Apple's AVAudioPlayer pattern
        // iOS manages session lifecycle automatically
        
        // Clear all state (including crossfade flags)
        // currentTrack removed - coordinator manages active track via atomicSwitch()
        playbackPosition = nil
        currentRepeatCount = 0
        // Removed: activeCrossfadeOperation = nil (managed by coordinator)
        await updateState(.finished)
        
        // Remove remote commands
        let manager = remoteCommandManager!  // Capture before MainActor hop
        Task { @MainActor in
            manager.removeCommands()
            manager.clearNowPlayingInfo()
        }
        
        // Observers removed in v3.1 - AsyncStream continuations cleared separately
    }
    


    // MARK: - Playlist Management
    
    /// Load initial playlist before playback (Track version)
    ///
    /// Loads validated tracks into playlist manager without starting playback.
    /// Use this method to prepare the player before calling `startPlaying()`.
    ///
    /// - Parameter tracks: Array of validated Track objects (must not be empty)
    /// - Throws:
    ///   - `AudioPlayerError.emptyPlaylist` if tracks array is empty
    ///
    /// - Note: This is a lightweight operation - no audio loading or playback
    /// - Note: For replacing playlist during playback, use `replacePlaylist(_:)`
    ///
    /// **Example:**
    /// ```swift
    /// // Validate and load
    /// let tracks = [introURL, meditationURL].compactMap { Track(url: $0) }
    /// try await player.loadPlaylist(tracks)
    /// ```
    public func loadPlaylist(_ tracks: [Track]) async throws {
        
        guard !tracks.isEmpty else {
            throw AudioPlayerError.emptyPlaylist
        }
        
        await playlistManager.load(tracks: tracks)
        
        Self.logger.info("Loaded playlist with \(tracks.count) tracks")
    }

    /// Load initial playlist before playback (URL version - backward compatible)
    ///
    /// Loads tracks from URLs into playlist manager without starting playback.
    /// Invalid files are automatically filtered out during Track creation.
    ///
    /// - Parameter tracks: Array of track URLs (must not be empty)
    /// - Throws:
    ///   - `AudioPlayerError.emptyPlaylist` if tracks array is empty
    ///
    /// - Note: Prefer using Track version for early validation feedback
    /// - Note: Invalid URLs (files not found) are filtered with warning
    ///
    /// **Example:**
    /// ```swift
    /// try await player.loadPlaylist([introURL, meditationURL, outroURL])
    /// ```
    public func loadPlaylist(_ tracks: [URL]) async throws {
        
        guard !tracks.isEmpty else {
            throw AudioPlayerError.emptyPlaylist
        }
        
        await playlistManager.load(tracks: tracks)
        
        Self.logger.info("Loaded playlist with \(tracks.count) tracks")
    }

    /// Replace current playlist with crossfade (Track version)
    ///
    /// Replaces the current playlist with validated tracks. If playing, performs
    /// smooth crossfade to first track of new playlist. If paused/stopped,
    /// performs silent switch.
    ///
    /// - Parameter tracks: New playlist validated Track objects (must not be empty)
    /// - Throws:
    ///   - `AudioPlayerError.invalidConfiguration` if tracks array is empty
    ///   - Other errors from audio engine
    ///
    /// - Note: Uses `configuration.crossfadeDuration` for crossfade
    /// - Note: Resets playlist index to 0 and repeat count to 0
    ///
    /// **Example:**
    /// ```swift
    /// let newTracks = urls.compactMap { Track(url: $0) }
    /// try await player.replacePlaylist(newTracks)
    /// ```
    public func replacePlaylist(_ tracks: [Track]) async throws {
        
        // 1. Validation
        guard !tracks.isEmpty else {
            throw AudioPlayerError.invalidConfiguration(
                reason: "Cannot swap to empty playlist"
            )
        }

        // Use crossfade duration from configuration
        let validDuration = configuration.crossfadeDuration

        // Clear paused crossfade state (starting new operation)
        await crossfadeOrchestrator.clearPausedCrossfade()

        // Rollback if crossfade in progress
        if await crossfadeOrchestrator.hasActiveCrossfade() {
            await rollbackCrossfade()
            try await Task.sleep(nanoseconds: 1_500_000_000) // 1.5s delay
        }

        // State preservation (BEFORE async operations!)
        let wasPlaying = await state == .playing

        // Load first track of new playlist on secondary player
        let firstTrack = tracks[0]
        let firstTrackWithMetadata = try await audioEngine.loadAudioFileOnSecondaryPlayer(track: firstTrack)

        // Recheck state after async (actor reentrancy protection)
        let isStillPlaying = await state == .playing

        // Decision: crossfade or silent switch
        if wasPlaying && isStillPlaying {
            // Prepare secondary player
            await audioEngine.prepareSecondaryPlayer()

            // Execute crossfade with automatic pause handling
            let result = try await crossfadeOrchestrator.startCrossfade(
                to: firstTrackWithMetadata,
                duration: validDuration,
                curve: configuration.fadeCurve,
                operation: .manualChange
            )

            // If paused, cleanup will be done on resume
            if result == .paused {
                return
            }
        } else {
            // Paused or stopped - prepare player and switch without playback
            await audioEngine.prepareSecondaryPlayer()
            await audioEngine.switchActivePlayerWithVolume()
            await audioEngine.stopInactivePlayer()
        }

        // 7. Update PlaylistManager
        await playlistManager.replacePlaylist(tracks)
        
        // 8. Update current track state via coordinator
        await playbackStateCoordinator.atomicSwitch(newTrack: firstTrackWithMetadata)
        await syncCachedState()  // ✅ Sync state (activePlayer, playbackMode)
        await syncCachedTrackInfo()
        // currentTrackURL removed - coordinator manages active track
        
        // 9. Reset counters
        currentRepeatCount = 0
        // Removed: activeCrossfadeOperation = nil (managed by coordinator)
        
        // 10. Update UI
        await updateNowPlayingInfo()
        
        Self.logger.info("Playlist replaced successfully (\(tracks.count) tracks)")
    }

    /// Replace current playlist with crossfade (URL version - backward compatible)
    ///
    /// Replaces the current playlist with new tracks from URLs. If playing, performs
    /// smooth crossfade to first track of new playlist. If paused/stopped,
    /// performs silent switch.
    ///
    /// - Parameter tracks: New playlist track URLs (must not be empty)
    /// - Throws:
    ///   - `AudioPlayerError.invalidConfiguration` if tracks array is empty
    ///   - Other errors from audio engine
    ///
    /// - Note: Uses `configuration.crossfadeDuration` for crossfade
    /// - Note: For initial playlist load before playback, use `loadPlaylist(_:)`
    /// - Note: Resets playlist index to 0 and repeat count to 0
    /// - Note: If crossfade in progress, performs rollback and retries after 1.5s delay
    ///
    /// **Example:**
    /// ```swift
    /// try await player.replacePlaylist([url1, url2, url3])
    /// ```
    public func replacePlaylist(_ tracks: [URL]) async throws {
        
        // 1. Validation
        guard !tracks.isEmpty else {
            throw AudioPlayerError.invalidConfiguration(
                reason: "Cannot swap to empty playlist"
            )
        }

        // Use crossfade duration from configuration
        let validDuration = configuration.crossfadeDuration

        // Clear paused crossfade state (starting new operation)
        await crossfadeOrchestrator.clearPausedCrossfade()

        // Rollback if crossfade in progress
        if await crossfadeOrchestrator.hasActiveCrossfade() {
            await rollbackCrossfade()
            try await Task.sleep(nanoseconds: 1_500_000_000) // 1.5s delay
        }

        // State preservation (BEFORE async operations!)
        let wasPlaying = await state == .playing

        // Load first track of new playlist on secondary player
        let firstTrackURL = tracks[0]
        guard let firstTrack = Track(url: firstTrackURL) else {
            throw AudioPlayerError.fileLoadFailed(reason: "File not found: \(firstTrackURL.lastPathComponent)")
        }
        let firstTrackWithMetadata = try await audioEngine.loadAudioFileOnSecondaryPlayer(track: firstTrack)

        // Recheck state after async (actor reentrancy protection)
        let isStillPlaying = await state == .playing

        // Decision: crossfade or silent switch
        if wasPlaying && isStillPlaying {
            // Prepare secondary player
            await audioEngine.prepareSecondaryPlayer()

            // Execute crossfade with automatic pause handling
            let result = try await crossfadeOrchestrator.startCrossfade(
                to: firstTrackWithMetadata,
                duration: validDuration,
                curve: configuration.fadeCurve,
                operation: .manualChange
            )

            // If paused, cleanup will be done on resume
            // State is NOT forced here - respect user actions during crossfade
            if result == .paused {
                return
            }
        } else {
            // Paused or stopped - prepare player and switch without playback
            await audioEngine.prepareSecondaryPlayer()
            await audioEngine.switchActivePlayerWithVolume()
            await audioEngine.stopInactivePlayer()
        }
        
        // 7. Update PlaylistManager
        await playlistManager.replacePlaylist(tracks)
        
        // 8. Update current track state via coordinator
        await playbackStateCoordinator.atomicSwitch(newTrack: firstTrackWithMetadata)
        await syncCachedState()  // ✅ Sync state (activePlayer, playbackMode)
        await syncCachedTrackInfo()
        
        // 9. Reset counters
        currentRepeatCount = 0
        // Removed: activeCrossfadeOperation = nil (managed by coordinator)
        
        // 10. Update UI
        await updateNowPlayingInfo()
        
        Self.logger.info("Playlist replaced successfully (\(tracks.count) tracks)")
    }
    
    /// Current playlist tracks
    /// - Returns: Array of Track objects in playback order
    /// - Note: Returns empty array if no playlist loaded
    public var playlist: [Track] {
        get async { await playlistManager.getTracks() }
    }
    
    // MARK: - Playlist Navigation
    
    /// Skip to next track in playlist
    /// - Returns: Next track metadata (returned instantly before audio transition)
    /// - Throws: AudioPlayerError.noNextTrack if no next track available
    /// - Note: Uses configuration.crossfadeDuration for crossfade
    /// - Note: Operations are queued (no concurrent execution)
    /// - Note: Metadata returned immediately (<20ms), audio transition happens in background
    public func skipToNext() async throws -> Track.Metadata? {
        // 1. Get metadata BEFORE queueing (instant)
        let nextMetadata = await peekNextTrack()
        
        // 2. Queue audio operation (background)
        try await operationQueue.enqueue(
            priority: .normal,
            description: "skipToNext"
        ) {
            try await self._skipToNextImpl()
        }
        
        // 3. Return metadata (UI can use immediately)
        return nextMetadata
    }
    
    private func _skipToNextImpl() async throws {
        guard let nextTrack = await playlistManager.skipToNext() else {
            throw AudioPlayerError.noNextTrack
        }
        try await replaceCurrentTrack(
            track: nextTrack,
            crossfadeDuration: configuration.crossfadeDuration
        )
    }
    
    /// Skip to previous track in playlist
    /// - Returns: Previous track metadata (returned instantly before audio transition)
    /// - Throws: AudioPlayerError.noPreviousTrack if no previous track available
    /// - Note: Uses configuration.crossfadeDuration for crossfade
    /// - Note: Operations are queued (no concurrent execution)
    /// - Note: Metadata returned immediately (<20ms), audio transition happens in background
    public func skipToPrevious() async throws -> Track.Metadata? {
        // 1. Get metadata BEFORE queueing (instant)
        let prevMetadata = await peekPreviousTrack()
        
        // 2. Queue audio operation (background)
        try await operationQueue.enqueue(
            priority: .normal,
            description: "skipToPrevious"
        ) {
            try await self._skipToPreviousImpl()
        }
        
        // 3. Return metadata (UI can use immediately)
        return prevMetadata
    }
    
    private func _skipToPreviousImpl() async throws {
        guard let prevTrack = await playlistManager.skipToPrevious() else {
            throw AudioPlayerError.noPreviousTrack
        }
        try await replaceCurrentTrack(
            track: prevTrack,
            crossfadeDuration: configuration.crossfadeDuration
        )
    }
    
    // MARK: - Peek Methods (Instant UI)
    
    /// Peek at next track for instant UI update
    ///
    /// Returns immediately without queuing operation.
    /// UI can show next track info while skipToNext() executes in background.
    ///
    /// - Returns: Next track metadata, nil if no next track available
    /// - Note: Does NOT modify playback state
    /// - Note: Response time: <20ms (no queue wait)
    public func peekNextTrack() async -> Track.Metadata? {
        guard let track = await playlistManager.peekNext() else {
            return nil
        }
        return track.metadata
    }
    
    /// Peek at previous track for instant UI update
    ///
    /// Returns immediately without queuing operation.
    /// UI can show previous track info while skipToPrevious() executes in background.
    ///
    /// - Returns: Previous track metadata, nil if no previous track available
    /// - Note: Does NOT modify playback state
    /// - Note: Response time: <20ms (no queue wait)
    public func peekPreviousTrack() async -> Track.Metadata? {
        guard let track = await playlistManager.peekPrevious() else {
            return nil
        }
        return track.metadata
    }

    
    // MARK: - Internal Track Replacement
    
    /// Internal method for replacing current track with crossfade (used by skipToNext/skipToPrevious)
    /// - Parameters:
    ///   - track: New track to play
    ///   - crossfadeDuration: Crossfade duration in seconds
    ///   - retryDelay: Delay before retry if crossfade already in progress
    internal func replaceCurrentTrack(track: Track, crossfadeDuration: TimeInterval, retryDelay: TimeInterval = 1.5) async throws {
        Self.logger.debug("[SERVICE] replaceCurrentTrack → coordinator")
        
        // Validate and clamp crossfade duration
        let validatedDuration = max(1.0, min(30.0, crossfadeDuration))
        
        // CRITICAL: Remember state BEFORE any async operations
        let wasPlaying = await playbackStateCoordinator.getPlaybackMode() == .playing
        
        // Decision: crossfade only if playing
        if wasPlaying {
            // Delegate crossfade to coordinator
            let result = try await crossfadeOrchestrator.startCrossfade(
                to: track,
                duration: validatedDuration,
                curve: configuration.fadeCurve,
                operation: .manualChange
            )
            
            // Update now playing info
            if result == .completed {
                await updateNowPlayingInfo()
            }
            
            // If paused during crossfade, nothing else to do
            if result == .paused {
                return
            }
        } else {
            // Paused or stopped - load track without crossfade
            Self.logger.debug("[SERVICE] Not playing, switching without crossfade")
            
            // Load on inactive and switch
            let trackWithMetadata = try await audioEngine.loadAudioFileOnSecondaryPlayer(track: track)
            await playbackStateCoordinator.atomicSwitch(newTrack: trackWithMetadata)
            await syncCachedState()  // ✅ Sync state (activePlayer switch!)
            await syncCachedTrackInfo()
            
            // Switch engine players
            await audioEngine.switchActivePlayerWithVolume()
            await audioEngine.stopInactivePlayer()
        }
    }

    
    // MARK: - Observer API Removed (v3.1)
    // The observer pattern has been removed in favor of AsyncStream.
    // Use stateUpdates, positionUpdates, and events AsyncStream properties.
    //
    // Migration:
    //   OLD: player.addObserver(self)
    //   NEW: Task { for await state in player.stateUpdates { ... } }
    
    // MARK: - AsyncStream API (SwiftUI-friendly)
    
    /// Stream of state changes for SwiftUI observation
    ///
    /// ## Example:
    /// ```swift
    /// .task {
    ///     for await state in service.stateUpdates {
    ///         playerState = state
    ///     }
    /// }
    /// ```
    public var stateUpdates: AsyncStream<PlayerState> {
        stateStream  // ✅ FIXED: Return stored stream (no race condition!)
    }
    
    /// Stream of track changes for SwiftUI observation
    ///
    /// ## Example:
    /// ```swift
    /// .task {
    ///     for await track in service.trackUpdates {
    ///         currentTrack = track
    ///     }
    /// }
    /// ```
    public var trackUpdates: AsyncStream<Track.Metadata?> {
        trackStream  // ✅ FIXED: Return stored stream (no race condition!)
    }
    
    /// Stream of playback position updates for SwiftUI observation
    ///
    /// Updates every 0.5 seconds during playback.
    ///
    /// ## Example:
    /// ```swift
    /// .task {
    ///     for await position in service.positionUpdates {
    ///         currentPosition = position
    ///     }
    /// }
    /// ```
    public var positionUpdates: AsyncStream<PlaybackPosition> {
        positionStream  // ✅ FIXED: Return stored stream (no race condition!)
    }
    
    /// Stream of player events (file loading, crossfade progress, etc.)
    ///
    /// Provides real-time feedback for long-running operations.
    ///
    /// ## Example:
    /// ```swift
    /// .task {
    ///     for await event in player.events {
    ///         switch event {
    ///         case .fileLoadStarted(let url):
    ///             showLoadingIndicator(url)
    ///         case .fileLoadProgress(_, let progress):
    ///             updateProgressBar(progress)
    ///         case .crossfadeProgress(let progress):
    ///             updateCrossfadeBar(progress)
    ///         case .fileLoadCompleted(let url, let duration):
    ///             hideLoadingIndicator()
    ///             logMetric("fileLoad", duration)
    ///         }
    ///     }
    /// }
    /// ```
    public var events: AsyncStream<PlayerEvent> {
        eventStream  // ✅ FIXED: Return stored stream (no race condition!)
    }

    
    
    private func notifyObservers(positionUpdate position: PlaybackPosition) {
        // Yield to AsyncStream (observers removed in v3.1)
        positionContinuation.yield(position)  // ✅ Non-optional continuation
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
        
        // Check for track end (auto-advance to next track or stop)
        if await shouldTriggerTrackEnd(position) {
            await handleTrackEnd()
            return  // Don't check loop crossfade if track ended
        }
        
        // Check for loop crossfade trigger (with race condition protection)
        let hasActiveCrossfade = await crossfadeOrchestrator.hasActiveCrossfade()
        if await shouldTriggerLoopCrossfade(position) && !hasActiveCrossfade {
            await startLoopCrossfade()
        }
    }
    
    private func stopPlaybackTimer() {
        playbackTimer?.cancel()
        playbackTimer = nil
    }
    
    // MARK: - Now Playing Updates
    
    internal func updateNowPlayingInfo() async {
        guard let trackInfo = await playbackStateCoordinator.getActiveTrackInfo() else { return }
        
        // Read actor-isolated properties before MainActor hop
        let currentTime = playbackPosition?.currentTime ?? 0
        let playbackRate: Double = await state == .playing ? 1.0 : 0.0
        let manager = remoteCommandManager!  // Capture before MainActor hop
        
        await MainActor.run {
            manager.updateNowPlayingInfo(
                title: trackInfo.title,
                artist: trackInfo.artist,
                duration: trackInfo.duration,
                elapsedTime: currentTime,
                playbackRate: playbackRate
            )
        }
    }
    
    private func updateNowPlayingPosition() async {
        guard let position = playbackPosition else { return }
        
        // Read actor-isolated state before MainActor hop
        let playbackRate: Double = await state == .playing ? 1.0 : 0.0
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
    
    /// Ensure audio session is active before critical operations
    /// Protects against external AVAudioPlayer interference
    private func ensureSessionActive() async throws {
        do {
            try await sessionManager.activate()
        } catch {
            Self.logger.error("[SESSION] Failed to ensure session active: \(error.localizedDescription)")
            throw error
        }
    }
    
    private func handleInterruption(shouldResume: Bool) async {
        if shouldResume {
            // Reactivate audio session after interruption (critical for phone calls)
            // iOS deactivates session during interruption - must reactivate before resume
            do {
                try await sessionManager.activate()
                Self.logger.debug("[INTERRUPTION] Audio session reactivated")
            } catch {
                Self.logger.error("[INTERRUPTION] Failed to reactivate session: \(error.localizedDescription)")
                return
            }
            
            // Try to resume playback
            try? await resume()
        } else {
            // Pause playback
            try? await pause()
        }
    }
    
    private func handleRouteChange(reason: AVAudioSession.RouteChangeReason) async {
        let currentRoute = await sessionManager.getCurrentRoute()
        Self.logger.info("[ROUTE_CHANGE] Reason: \(reason.rawValue), New route: \(currentRoute)")
        
        switch reason {
        case .oldDeviceUnavailable:
            // Headphones unplugged - handle IMMEDIATELY (no debounce)
            // User expects instant pause when unplugging
            Self.logger.debug("[ROUTE_CHANGE] Device unplugged - pausing immediately")
            
            // Cancel any pending route change activations
            routeChangeDebounceTask?.cancel()
            routeChangeDebounceTask = nil
            
            try? await pause()
            
        case .newDeviceAvailable, .categoryChange, .override:
            // Device connected/changed - DEBOUNCE to prevent rapid-fire iOS events
            // Bluetooth devices often trigger multiple events in quick succession
            Self.logger.debug("[ROUTE_CHANGE] Event \(reason.rawValue) - debouncing (300ms)")
            
            // Cancel previous debounce task
            routeChangeDebounceTask?.cancel()
            
            // Create new debounced task
            routeChangeDebounceTask = Task {
                // Wait 300ms for event storm to settle
                try? await Task.sleep(nanoseconds: 300_000_000)
                
                // Check if cancelled during sleep
                guard !Task.isCancelled else {
                    Self.logger.debug("[ROUTE_CHANGE] Debounce cancelled")
                    return
                }
                
                // Guard against concurrent execution
                guard !isHandlingRouteChange else {
                    Self.logger.warning("[ROUTE_CHANGE] Already handling route change, skipping")
                    return
                }
                
                isHandlingRouteChange = true
                defer { isHandlingRouteChange = false }
                
                Self.logger.debug("[ROUTE_CHANGE] Debounce complete - reactivating session")
                
                do {
                    try await sessionManager.activate()
                    Self.logger.info("[ROUTE_CHANGE] Session reactivated successfully on route: \(await sessionManager.getCurrentRoute())")
                    // Audio continues automatically if playing
                } catch {
                    Self.logger.error("[ROUTE_CHANGE] Failed to reactivate session: \(error.localizedDescription)")
                }
            }
            
        default:
            Self.logger.debug("[ROUTE_CHANGE] Unhandled reason: \(reason.rawValue)")
            break
        }
    }
    
    private func handleMediaServicesReset() async {
        Self.logger.error("[MEDIA_SERVICES] ⚠️ CRITICAL: Media services were reset!")
        Self.logger.info("[MEDIA_SERVICES] Attempting to recover audio session and engine...")
        
        // Step 1: Save current playback state BEFORE any recovery
        let wasPlaying = await state == .playing
        let currentPosition = wasPlaying ? await audioEngine.getCurrentPosition()?.currentTime : nil
        if let pos = currentPosition {
            Self.logger.debug("[MEDIA_SERVICES] Saved playback position: \(pos)s")
        }
        
        // Step 2: Reconfigure audio session from scratch with user's options
        do {
            try await sessionManager.configure(options: configuration.audioSessionOptions, force: true)
            Self.logger.debug("[MEDIA_SERVICES] Session reconfigured successfully (force)")
        } catch {
            Self.logger.error("[MEDIA_SERVICES] Failed to reconfigure session: \(error.localizedDescription)")
            // Enter failed state if we can't recover
            await updateState(.failed(.sessionConfigurationFailed(
                reason: "Media services reset - reconfiguration failed: \(error.localizedDescription)"
            )))
            return
        }
        
        // Step 3: Reactivate session
        do {
            try await sessionManager.activate()
            Self.logger.debug("[MEDIA_SERVICES] Session reactivated successfully")
        } catch {
            Self.logger.error("[MEDIA_SERVICES] Failed to reactivate session: \(error.localizedDescription)")
            await updateState(.failed(.sessionConfigurationFailed(
                reason: "Media services reset - reactivation failed: \(error.localizedDescription)"
            )))
            return
        }
        
        // Step 4: Reset and restart audio engine
        // Media services reset means engine crashed - need full restart
        // IMPORTANT: Don't use stop() - it doesn't save position!
        do {
            // Force engine state reset (media services crashed, flags may be stale)
            await audioEngine.resetEngineRunningState()
            
            // Prepare and start fresh
            try await audioEngine.prepare()
            try await audioEngine.start()
            Self.logger.debug("[MEDIA_SERVICES] Audio engine restarted successfully")
        } catch {
            Self.logger.error("[MEDIA_SERVICES] Failed to restart engine: \(error.localizedDescription)")
            await updateState(.failed(.engineStartFailed(
                reason: "Media services reset - engine restart failed: \(error.localizedDescription)"
            )))
            return
        }
        
        // Step 5: Restore playback with saved position
        if wasPlaying {
            Self.logger.info("[MEDIA_SERVICES] Restoring playback after recovery")
            
            // Restore position if we had one
            if let position = currentPosition {
                Self.logger.debug("[MEDIA_SERVICES] Seeking to saved position: \(position)s")
                try? await seek(to: position, fadeDuration: 0.0)
            }
            
            // Resume playback
            try? await resume()
        }
        
        Self.logger.info("[MEDIA_SERVICES] ✅ Recovery complete - audio session restored")
    }
    
    // MARK: - Loop Crossfade Logic (UPDATED - Phase 3)
    
    /// Epsilon tolerance for floating-point comparison (100ms)
    /// Prevents precision errors in IEEE 754 arithmetic (e.g., 49.999999999 ≠ 50.0)
    private let triggerTolerance: TimeInterval = 0.1
    
    /// Calculate adapted crossfade duration for single track loop
    /// - Parameter trackDuration: Total track duration in seconds
    /// - Returns: Adapted crossfade duration (max 40% each fade, 80% total)
    /// - Note: Uses same adaptation logic as loopCurrentTrackWithFade() to ensure trigger point matches actual crossfade duration
    private func calculateAdaptedCrossfadeDuration(trackDuration: TimeInterval) -> TimeInterval {
        // v4.0: Use full crossfadeDuration for loop
        let configuredCrossfade = configuration.crossfadeDuration
        let maxCrossfade = trackDuration * 0.4
        let adaptedCrossfade = min(configuredCrossfade, maxCrossfade)
        
        Self.logger.debug("Adapted loop crossfade: configured=\(configuredCrossfade)s, track=\(trackDuration)s, adapted=\(adaptedCrossfade)s")
        
        return adaptedCrossfade
    }
    
    // MARK: - Track End Handling (Auto-advance)
    
    /// Check if track has ended (needs auto-advance or stop)
    /// - Parameter position: Current playback position
    /// - Returns: True if track ended
    private func shouldTriggerTrackEnd(_ position: PlaybackPosition) async -> Bool {
        // Only for .off or .playlist modes (not .singleTrack - it loops)
        guard configuration.repeatMode != .singleTrack else { return false }
        
        // Don't trigger if already replacing track
        let hasActiveCrossfade = await crossfadeOrchestrator.hasActiveCrossfade()
        guard !hasActiveCrossfade else { return false }
        
        // Only trigger when playing
        guard await state == .playing else { return false }
        
        // Track ended if we're within 0.5s of the end
        let epsilon: TimeInterval = 0.5
        return position.currentTime >= (position.duration - epsilon)
    }
    
    /// Handle track end - either advance to next track or stop
    private func handleTrackEnd() async {
        Self.logger.debug("[AUTO-ADVANCE] Track ended, repeatMode: \\(configuration.repeatMode)")
        
        switch configuration.repeatMode {
        case .off:
            // Stop playback
            Self.logger.debug("[AUTO-ADVANCE] Stopping (repeatMode = .off)")
            await stop()
            
        case .playlist:
            // Try to advance to next track
            Self.logger.debug("[AUTO-ADVANCE] Advancing to next track (repeatMode = .playlist)")
            do {
                // Use existing skipToNext which has crossfade logic
                try await skipToNext()
            } catch AudioPlayerError.noNextTrack {
                // No more tracks - loop back to first or stop
                Self.logger.debug("[AUTO-ADVANCE] End of playlist, stopping playback")
                await stop()
            } catch {
                Self.logger.error("[AUTO-ADVANCE] Failed to advance: \\(error)")
                await stop()
            }
            
        case .singleTrack:
            // Should not reach here - handled by loop crossfade
            break
        }
    }


    
    /// Check if we should trigger loop crossfade
    /// - Parameter position: Current playback position
    /// - Returns: True if crossfade should be triggered
    /// - Note: Uses epsilon tolerance to handle floating-point precision errors
    /// - Note: Now checks repeatMode instead of enableLooping (Phase 3)
    /// - Note: For .singleTrack mode, uses adapted crossfade duration to match actual execution
    private func shouldTriggerLoopCrossfade(_ position: PlaybackPosition) async -> Bool {
        // Only loop if repeat mode is not .off
        guard configuration.repeatMode != .off else { return false }
        
        // Don't trigger if already in progress
        let hasActiveCrossfade = await crossfadeOrchestrator.hasActiveCrossfade()
        guard !hasActiveCrossfade else { return false }
        
        // Only trigger when playing
        guard await state == .playing else { return false }
        
        // Calculate trigger point (crossfade duration before end)
        // For .singleTrack mode, use ADAPTED values to match loopCurrentTrackWithFade()
        let crossfadeDuration: TimeInterval
        if configuration.repeatMode == .singleTrack {
            // ✅ FIX: Use adapted duration (same as loopCurrentTrackWithFade)
            crossfadeDuration = calculateAdaptedCrossfadeDuration(trackDuration: position.duration)
        } else {
            crossfadeDuration = configuration.crossfadeDuration
        }
        
        let triggerPoint = position.duration - crossfadeDuration
        
        // Check if should trigger (with epsilon tolerance)
        let willTrigger = position.currentTime >= (triggerPoint - triggerTolerance) && 
                         position.currentTime < position.duration
        
        // 🔍 DEBUG: Log only when actually triggering
        if willTrigger {
            Self.logger.info("[LOOP_TRIGGER] Triggering at \(position.currentTime)s (trigger: \(triggerPoint)s, crossfade: \(crossfadeDuration)s, mode: \(configuration.repeatMode))")
        }
        
        // FIXED Issue #8: Use epsilon tolerance for float precision
        // Trigger when: triggerPoint - tolerance ≤ currentTime < duration
        return willTrigger
    }
    
    /// Start the loop crossfade process with support for all repeat modes
    /// - Note: Handles .off (finish), .singleTrack (loop current), .playlist (advance)
    private func startLoopCrossfade() async {
        // Mark as in progress BEFORE any async operations
        // Removed: activeCrossfadeOperation = .automaticLoop (coordinator manages internally)
        
        // Determine action based on repeat mode
        switch configuration.repeatMode {
        case .off:
            // Finish playback with fade out
            try? await finish(fadeDuration: 3.0)
            
        case .singleTrack:
            // Loop current track with fade
            await loopCurrentTrackWithFade()
            
        case .playlist:
            // Advance to next playlist track
            await advanceToNextPlaylistTrack()
        }
    }
    
    /// Loop current track with crossfade between iterations
    /// - Note: Used only when repeatMode = .singleTrack
    /// - Note: Uses Spotify-style crossfade (both tracks fade simultaneously over full duration)
    /// - Note: Dynamically adapts crossfade duration to track duration (max 40% of track)
    private func loopCurrentTrackWithFade() async {
        // 1. Validation
        guard let currentURL = await playbackStateCoordinator.getCurrentTrack()?.url,
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
        
        // 3. ✅ FIX: Use shared adaptation logic
        let crossfadeDuration = calculateAdaptedCrossfadeDuration(trackDuration: trackDuration)
        
        // 🔍 DEBUG: Log configuration
        let configuredCrossfade = configuration.crossfadeDuration
        Self.logger.info("[LOOP_CROSSFADE] Starting loop crossfade: track=\(trackDuration)s, configured=\(configuredCrossfade)s, adapted=\(crossfadeDuration)s")
        Self.logger.info("[LOOP_CROSSFADE] Repeat count: \(currentRepeatCount + 1)")
        
        // 7. Send .preparing state for instant UI feedback
        let prepareProgress = CrossfadeProgress(
            phase: .preparing,
            duration: crossfadeDuration,
            elapsed: 0
        )
        // Removed: updateCrossfadeProgress (coordinator handles progress reporting)
        
        // Load same file on secondary player
        do {
            guard let activeTrack = await playbackStateCoordinator.getCurrentTrack() else { return }
            let loopTrackWithMetadata = try await audioEngine.loadAudioFileOnSecondaryPlayer(track: activeTrack)

            // Prepare secondary player
            await audioEngine.prepareSecondaryPlayer()

            // Execute crossfade with automatic pause handling
            // Note: Loop uses .automaticLoop operation type
            let result = try await crossfadeOrchestrator.startCrossfade(
                to: loopTrackWithMetadata,
                duration: crossfadeDuration,
                curve: configuration.fadeCurve,
                operation: .automaticLoop
            )

            // If paused, cleanup will be done on resume
            if result == .paused {
                return
            }

            // Track is already set in coordinator by startCrossfade
            // currentTrackURL stays the same

            // Increment repeat count
            currentRepeatCount += 1

            // Update now playing
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
        // Removed: updateCrossfadeProgress (coordinator handles progress reporting)
        
        // 1. Get next track from playlist manager
        guard let nextTrack = await playlistManager.getNextTrack() else {
            // No more tracks - finish playback
            try? await finish(fadeDuration: 3.0)
            return
        }
        let nextURL = nextTrack.url
        
        // Load next track on secondary player
        do {
            let nextTrackWithMetadata = try await audioEngine.loadAudioFileOnSecondaryPlayer(track: nextTrack)

            // Prepare secondary player
            await audioEngine.prepareSecondaryPlayer()

            // Execute crossfade with automatic pause handling
            let result = try await crossfadeOrchestrator.startCrossfade(
                to: nextTrackWithMetadata,
                duration: configuration.crossfadeDuration,
                curve: configuration.fadeCurve,
                operation: .automaticLoop
            )

            // If paused, cleanup will be done on resume
            if result == .paused {
                return
            }

            // Track is already set in coordinator by startCrossfade
            // currentTrackURL removed - coordinator manages active track

            // Update now playing
            await updateNowPlayingInfo()

            Self.logger.info("Playlist auto-advance completed")

        } catch {
            // Failed to load next track
            Self.logger.error("Auto-advance failed: \(error)")
        }
    }
    
    /// Sync current configuration to playlist manager
    private func syncConfigurationToPlaylistManager() async {
        await playlistManager.updateConfiguration(configuration)
    }
    
    // MARK: - Overlay Player Control
    
    /// Play overlay audio with current configuration
    /// 
    /// Overlay player provides an independent audio layer for ambient sounds, background music,
    /// or atmospheric effects that play alongside the main audio track. The overlay player
    /// has its own volume control and can loop independently.
    ///
    /// **Use Cases:**
    /// - Meditation apps: Rain sounds while playing guided meditation
    /// - Fitness apps: Background music during workout instructions
    /// - Sleep apps: White noise alongside sleep stories
    /// - Games: Ambient soundscapes with dialogue/effects
    ///
    /// **Configuration:**
    /// - Set configuration via `setOverlayConfiguration()` before first play
    /// - Default configuration is `.default` (Spotify-inspired balanced settings)
    /// - Configuration persists across multiple playOverlay() calls
    ///
    /// **Important Notes:**
    /// - Overlay player is independent of main player state
    /// - Main track crossfades do NOT affect overlay playback
    /// - Playlist swaps do NOT affect overlay playback
    /// - Use global control methods (pauseAll/resumeAll/stopAll) to control both systems
    ///
    /// **Example:**
    /// ```swift
    /// // Configure once
    /// try await player.setOverlayConfiguration(.ambient)
    ///
    /// // Play rain sounds
    /// try await player.playOverlay(rainURL)
    ///
    /// // Later, switch to ocean (same config)
    /// try await player.playOverlay(oceanURL)
    /// ```
    ///
    /// - Parameter url: Local file URL for overlay audio (remote URLs not supported)
    /// - Throws: 
    ///   - `AudioPlayerError.fileNotFound` if file doesn't exist
    ///   - `AudioPlayerError.invalidAudioFile` if file format is unsupported
    ///   - `AudioPlayerError.audioSessionError` if audio session setup fails
    public func playOverlay(_ url: URL) async throws {
        
        // Ensure session is active before starting overlay (critical for coexistence)
        try await ensureSessionActive()
        
        // Use current configuration from overlay player (set via setOverlayConfiguration)
        try await audioEngine.startOverlay(url: url, configuration: await audioEngine.getOverlayConfiguration() ?? .default)
    }
    
    /// Play overlay audio with Track (validated file)
    ///
    /// Same as playOverlay(URL) but uses validated Track object.
    ///
    /// **Example:**
    /// ```swift
    /// let rainTrack = Track(url: rainURL)!
    /// try await player.playOverlay(rainTrack)
    /// ```
    ///
    /// - Parameter track: Validated track to play
    /// - Throws: Same errors as playOverlay(URL)
    public func playOverlay(_ track: Track) async throws {
        try await playOverlay(track.url)
    }
    
    /// Set overlay configuration (stops current overlay)
    ///
    /// Updates overlay playback behavior. Stops any currently playing overlay
    /// to apply new settings cleanly.
    ///
    /// **Configuration Changes:**
    /// - Volume levels
    /// - Loop mode (once, count, infinite)
    /// - Loop delay between iterations
    /// - Fade in/out durations
    /// - Fade curve type
    ///
    /// **Example:**
    /// ```swift
    /// // Switch to ambient preset
    /// try await player.setOverlayConfiguration(.ambient)
    ///
    /// // Custom configuration
    /// var config = OverlayConfiguration.default
    /// config.volume = 0.5
    /// config.loopMode = .infinite
    /// try await player.setOverlayConfiguration(config)
    /// ```
    ///
    /// - Parameter configuration: New overlay configuration
    /// - Note: Stops current overlay playback before applying changes
    public func setOverlayConfiguration(_ configuration: OverlayConfiguration) async throws {
        // Stop current overlay before changing config
        await audioEngine.stopOverlay()
        
        // Set new configuration
        await audioEngine.setOverlayConfiguration(configuration)
    }
    
    /// Get current overlay configuration
    ///
    /// Returns the current overlay player configuration, or nil if not set.
    ///
    /// **Example:**
    /// ```swift
    /// if let config = await player.getOverlayConfiguration() {
    ///     print("Overlay volume: \(config.volume)")
    /// }
    /// ```
    public func getOverlayConfiguration() async -> OverlayConfiguration? {
        return await audioEngine.getOverlayConfiguration()
    }
    
    /// Stop overlay playback with fade-out
    ///
    /// Stops the overlay player using the fade-out duration specified in its configuration.
    /// If no overlay is currently playing, this method does nothing.
    ///
    /// **Example:**
    /// ```swift
    /// await player.stopOverlay()
    /// ```
    public func stopOverlay() async {
        await audioEngine.stopOverlay()
    }
    
    /// Pause overlay playback
    ///
    /// Pauses the overlay player at its current position. Use `resumeOverlay()` to continue.
    /// If no overlay is playing, this method does nothing.
    ///
    /// **Note:** This only affects the overlay player. To pause both main and overlay,
    /// use `pauseAll()` instead.
    ///
    /// **Example:**
    /// ```swift
    /// await player.pauseOverlay()
    /// ```
    public func pauseOverlay() async {
        await audioEngine.pauseOverlay()
    }
    
    /// Resume overlay playback
    ///
    /// Resumes overlay playback from the paused position. If overlay is not paused
    /// or no overlay is loaded, this method does nothing.
    ///
    /// **Example:**
    /// ```swift
    /// await player.resumeOverlay()
    /// ```
    public func resumeOverlay() async {
        await audioEngine.resumeOverlay()
    }
    
    /// Set overlay volume independently
    ///
    /// Adjusts the overlay player's volume without affecting the main player.
    /// Volume changes are applied immediately without fading.
    ///
    /// **Example:**
    /// ```swift
    /// // Reduce overlay volume to 20%
    /// await player.setOverlayVolume(0.2)
    /// ```
    ///
    /// - Parameter volume: Volume level (0.0 = silent, 1.0 = full volume)
    public func setOverlayVolume(_ volume: Float) async {
        await audioEngine.setOverlayVolume(volume)
    }
    
    /// Set overlay loop mode dynamically during playback
    ///
    /// Changes the loop behavior of the overlay player in real-time. The new mode takes effect
    /// on the next loop iteration (current iteration completes first).
    ///
    /// **Example:**
    /// ```swift
    /// // User toggles "infinite loop" in UI
    /// await player.setOverlayLoopMode(.infinite)
    ///
    /// // User changes to play 5 times
    /// await player.setOverlayLoopMode(.count(5))
    /// ```
    ///
    /// - Parameter mode: New loop mode (`.once`, `.count(n)`, `.infinite`)
    /// - Throws: `AudioPlayerError.invalidState` if no overlay is active
    public func setOverlayLoopMode(_ mode: OverlayConfiguration.LoopMode) async throws {
        guard let overlay = await audioEngine.overlayPlayer else {
            throw AudioPlayerError.invalidState(
                current: "no overlay",
                attempted: "set loop mode"
            )
        }
        await overlay.setLoopMode(mode)
    }
    
    /// Set overlay loop delay dynamically during playback
    ///
    /// Changes the delay between loop iterations in real-time. The new delay takes effect
    /// on the next loop iteration (current delay completes if active).
    ///
    /// **Example:**
    /// ```swift
    /// // User adjusts "delay between sounds" slider to 10 seconds
    /// try await player.setOverlayLoopDelay(10.0)
    ///
    /// // Remove delay for continuous playback
    /// try await player.setOverlayLoopDelay(0.0)
    /// ```
    ///
    /// - Parameter delay: Delay in seconds between iterations (must be >= 0.0)
    /// - Throws: 
    ///   - `AudioPlayerError.invalidState` if no overlay is active
    ///   - `AudioPlayerError.invalidConfiguration` if delay < 0.0
    public func setOverlayLoopDelay(_ delay: TimeInterval) async throws {
        // Validate delay
        guard delay >= 0.0 else {
            throw AudioPlayerError.invalidConfiguration(
                reason: "Loop delay must be >= 0.0 (got: \(delay))"
            )
        }
        
        guard let overlay = await audioEngine.overlayPlayer else {
            throw AudioPlayerError.invalidState(
                current: "no overlay",
                attempted: "set loop delay"
            )
        }
        await overlay.setLoopDelay(delay)
    }

    
    /// Current overlay player state
    ///
    /// Returns the current state of the overlay player for UI updates and state tracking.
    ///
    /// **Example:**
    /// ```swift
    /// let state = await player.overlayState
    /// if state.isPlaying {
    ///     print("Overlay is playing")
    /// }
    /// ```
    ///
    /// - Returns: Current overlay state, or `.idle` if no overlay is loaded
    public var overlayState: OverlayState {
        get async { await audioEngine.getOverlayState() }
    }
    
    // MARK: - Global Control
    
    /// Pause all audio (main player + overlay + sound effects)
    ///
    /// Pauses main player and overlay, stops any playing sound effect.
    /// Useful for handling interruptions (phone calls, alarms) or user pause action.
    ///
    /// **Example:**
    /// ```swift
    /// // Handle phone call interruption
    /// await player.pauseAll()
    /// ```
    public func pauseAll() async {
        // Cancel any active crossfade (without rollback)
        if await crossfadeOrchestrator.hasActiveCrossfade() {
            await audioEngine.cancelCrossfadeAndStopInactive()
            
            // Removed: activeCrossfadeOperation = nil (managed by coordinator)
            
            // Removed: crossfadeProgressTask cancel (managed by coordinator)
            // Removed: currentCrossfadeProgress = .idle (managed by coordinator)
        }
        
        // Guard: only pause if playing or preparing
        let currentState = await state
        guard currentState == .playing || currentState == .preparing else {
            // If already paused or finished, just pause overlay and return
            if currentState == .paused || currentState == .finished {
                await audioEngine.pauseOverlay()
                return
            }
            // Invalid state - still pause overlay for consistency
            await audioEngine.pauseOverlay()
            return
        }
        
        // Pause main player via state machine
        await updateState(.paused)
        
        // Pause overlay separately
        await audioEngine.pauseOverlay()
        
        // Stop sound effects (no pause, only stop)
        await soundEffectsPlayer.stop(fadeDuration: 0.0)
        
        // ✅ BUG FIX #5: Stop playback timer (prevent crossfade during pause!)
        stopPlaybackTimer()

        
        // Update Now Playing
        await updateNowPlayingPlaybackRate(0.0)
    }
    
    /// Resume all audio (main player + overlay)
    ///
    /// Resumes playback of main player and overlay after a pause.
    /// Sound effects are not resumed (they were stopped, not paused).
    ///
    /// **Example:**
    /// ```swift
    /// // Resume after interruption
    /// await player.resumeAll()
    /// ```
    public func resumeAll() async {
        // Guard: only resume if paused
        guard await state == .paused else {
            // If already playing, just resume overlay and return
            if await state == .playing {
                await audioEngine.resumeOverlay()
                return
            }
            // If finished - can't resume, but still try overlay
            if await state == .finished {
                await audioEngine.resumeOverlay()
                return
            }
            // Invalid state - still resume overlay for consistency
            await audioEngine.resumeOverlay()
            return
        }
        
        // Resume main player via state machine
        await updateState(.playing)
        
        // Resume overlay separately
        await audioEngine.resumeOverlay()
        
        // ✅ BUG FIX #6: Restart playback timer (restore crossfade monitoring!)
        startPlaybackTimer()

        
        // Update Now Playing
        await updateNowPlayingPlaybackRate(1.0)
    }
    
    /// Stop all audio (main player + overlay + sound effects)
    ///
    /// Emergency stop that halts all audio playback immediately.
    /// All players are stopped and reset to idle state.
    ///
    /// **Example:**
    /// ```swift
    /// // Emergency stop
    /// await player.stopAll()
    /// ```
    public func stopAll() async {
        // Cancel any active crossfade
        if await crossfadeOrchestrator.hasActiveCrossfade() {
            await audioEngine.cancelCrossfadeAndStopInactive()
            
            // Removed: activeCrossfadeOperation = nil (managed by coordinator)
            
            // Removed: crossfadeProgressTask cancel (managed by coordinator)
            // Removed: currentCrossfadeProgress = .idle (managed by coordinator)
        }
        
        // Stop playback timer
        stopPlaybackTimer()
        
        // Stop main player via state machine (transition to finished)
        await updateState(.finished)
        
        // Stop overlay separately
        await audioEngine.stopOverlay()
        
        // Stop sound effects
        await soundEffectsPlayer.stop(fadeDuration: 0.0)
        
        // Update Now Playing
        await updateNowPlayingPlaybackRate(0.0)
    }
    
    // MARK: - Crossfade Progress
    
    /// Rollback active crossfade transaction to stable state
    /// - Parameter rollbackDuration: Duration to restore active volume (default: 0.5s)
    /// - Note: Clears both loop and replacement flags (works for all repeat modes)
    private func rollbackCrossfade(rollbackDuration: TimeInterval = 0.5) async {
        Self.logger.debug("[ROLLBACK] 🔄 Starting crossfade rollback")
        
        // Perform rollback on audio engine
        _ = await audioEngine.rollbackCrossfade(rollbackDuration: rollbackDuration)
        
        // Clear crossfade flags (handles all repeat modes)
        // Removed: activeCrossfadeOperation = nil (managed by coordinator)
        
        // ✅ FIX: Clear paused crossfade state to prevent stale resume
        if await crossfadeOrchestrator.hasPausedCrossfade() {
            Self.logger.debug("[ROLLBACK] Clearing stale paused crossfade")
            await crossfadeOrchestrator.clearPausedCrossfade()
        }
        
        // Cancel progress observation
        // Removed: crossfadeProgressTask cancel (managed by coordinator)
        
        // Update progress state
        // Removed: currentCrossfadeProgress = .idle (managed by coordinator)
        
        // Observer notification removed in v3.1 - crossfade progress via coordinator
        
        Self.logger.debug("[ROLLBACK] ✅ Crossfade rollback completed")
    }

// MARK: - Engine Control (Internal)

    func startEngine() async throws {
        Self.logger.debug("[SERVICE] startEngine → engine (Phase 3)")

        // Start engine (prepare + start)
        try await audioEngine.start()

        // Use pending fade-in if set, otherwise no fade (instant start)
        let fadeInDuration = pendingFadeInDuration
        let shouldFadeIn = fadeInDuration > 0

        await audioEngine.scheduleFile(
            fadeIn: shouldFadeIn,
            fadeInDuration: fadeInDuration,
            fadeCurve: configuration.fadeCurve
        )

        // ✅ PHASE 3: Start playback directly via engine
        // Coordinator no longer has engine control methods
        await audioEngine.play()

        // Update state after starting
        await updateState(.playing)

        // Clear pending fade after use
        pendingFadeInDuration = 0.0
    }
    
    func stopEngine() async {
        await audioEngine.stop()
        stopPlaybackTimer()
    }
    
    func pausePlayback() async {
        Self.logger.debug("[SERVICE] pausePlayback → engine (Phase 3)")

        // Stop playback timer BEFORE pausing
        stopPlaybackTimer()

        // ✅ PHASE 3: Pause directly via engine
        await audioEngine.pause()

        // Capture position
        playbackPosition = await audioEngine.getCurrentPosition()
    }

    func resumePlayback() async throws {
        Self.logger.debug("[SERVICE] resumePlayback → engine (Phase 3)")

        // Ensure session is active before resuming
        try await ensureSessionActive()

        // ✅ PHASE 3: Resume directly via engine
        await audioEngine.play()

        // Restart playback timer
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
        await updateState(.playing)
    }
    
    func transitionToFailed(error: AudioPlayerError) async {
        await updateState(.failed(error))
    }
    
    // MARK: - Sound Effects API
    
    /// Preload multiple sound effects into memory (batch operation)
    ///
    /// Preloads sound effects into LRU cache for instant playback.
    /// Best practice: Call during app initialization with all effects you'll need.
    ///
    /// **LRU Cache:**
    /// - Default limit: 10 effects
    /// - Auto-eviction of least recently used when full
    /// - Currently playing effects are never evicted
    ///
    /// **Example:**
    /// ```swift
    /// let gong = try await SoundEffect(url: gongURL, volume: 0.9)
    /// let bell = try await SoundEffect(url: bellURL, volume: 0.8)
    /// let click = try await SoundEffect(url: clickURL, volume: 1.0)
    ///
    /// await player.preloadSoundEffects([gong, bell, click])
    /// ```
    ///
    /// - Parameter effects: Array of sound effects to preload
    /// - Note: This is optional - playSoundEffect() auto-preloads if needed
    public func preloadSoundEffects(_ effects: [SoundEffect]) async {
        await soundEffectsPlayer.preloadEffects(effects)
    }
    
    /// Play sound effect with auto-preload and optional fade-in
    ///
    /// Plays sound effect independently from main player and overlay.
    /// Only one sound effect can play at a time - new trigger cancels previous.
    ///
    /// **Auto-preload:**
    /// If effect not in cache, it's automatically preloaded (with console warning).
    /// For best performance, use `preloadSoundEffects()` upfront.
    ///
    /// **Volume:**
    /// Uses volume from SoundEffect initialization (0.0-1.0).
    /// To change volume, create new SoundEffect with different volume.
    ///
    /// **Example:**
    /// ```swift
    /// // Instant playback (no fade)
    /// try await player.playSoundEffect(gong)
    ///
    /// // With fade-in
    /// try await player.playSoundEffect(bell, fadeDuration: 0.2)
    /// ```
    ///
    /// - Parameters:
    ///   - effect: Sound effect to play
    ///   - fadeDuration: Fade-in duration in seconds (default: 0.0 = instant)
    public func playSoundEffect(_ effect: SoundEffect, fadeDuration: TimeInterval = 0.0) async {
        // Ensure audio session is active and engine is running
        do {
            try await ensureSessionActive()
            try await audioEngine.start()
        } catch {
            Self.logger.error("[SoundEffects] Failed to start engine: \(error.localizedDescription)")
            return
        }
        
        await soundEffectsPlayer.play(effect, fadeDuration: fadeDuration)
    }
    
    /// Stop current sound effect with optional fade-out
    ///
    /// **Example:**
    /// ```swift
    /// // Instant stop
    /// await player.stopSoundEffect()
    ///
    /// // Fade out
    /// await player.stopSoundEffect(fadeDuration: 0.5)
    /// ```
    ///
    /// - Parameter fadeDuration: Fade-out duration in seconds (default: 0.0 = instant)
    public func stopSoundEffect(fadeDuration: TimeInterval = 0.0) async {
        await soundEffectsPlayer.stop(fadeDuration: fadeDuration)
    }
    
    /// Set master volume for all sound effects
    ///
    /// Sets the master volume level that applies to all sound effects.
    /// Final volume = effect's individual volume × master volume.
    ///
    /// **Example:**
    /// ```swift
    /// // Effect created with volume 0.8
    /// let bell = try await SoundEffect(url: bellURL, volume: 0.8)
    ///
    /// // Set master to 50%
    /// await player.setSoundEffectVolume(0.5)
    ///
    /// // Final volume = 0.8 × 0.5 = 0.4 (40%)
    /// await player.playSoundEffect(bell)
    /// ```
    ///
    /// - Parameter volume: Volume level (0.0 - 1.0)
    /// - Note: Clamped to 0.0-1.0 range
    /// - Note: No need to reload effects - applies immediately
    public func setSoundEffectVolume(_ volume: Float) async {
        await soundEffectsPlayer.setVolume(volume)
    }
    
    /// Unload specific sound effects from memory (manual cleanup)
    ///
    /// Use this for high-performance scenarios where you want explicit control
    /// over cache. Normally, LRU cache handles cleanup automatically.
    ///
    /// **Example:**
    /// ```swift
    /// // Done with these effects - free memory
    /// await player.unloadSoundEffects([tutorialGong, tutorialBell])
    /// ```
    ///
    /// - Parameter effects: Array of effects to unload
    /// - Note: Currently playing effects are stopped before unloading
    public func unloadSoundEffects(_ effects: [SoundEffect]) async {
        await soundEffectsPlayer.unloadEffects(effects)
    }
    
    /// Check if sound effect is currently playing
    public var isSoundEffectPlaying: Bool {
        get async { await soundEffectsPlayer.isPlaying }
    }
    
    /// Currently playing sound effect
    /// - Returns: Sound effect object or nil if nothing playing
    /// - Note: Use for UI updates (e.g., highlighting active button)
    public var currentSoundEffect: SoundEffect? {
        get async { await soundEffectsPlayer.currentEffect }
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
