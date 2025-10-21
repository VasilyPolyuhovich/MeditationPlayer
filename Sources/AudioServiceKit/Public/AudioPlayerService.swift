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
    
    // SSOT: State managed exclusively by state machine
    private var _state: PlayerState
    public var state: PlayerState { _state }
    public private(set) var configuration: PlayerConfiguration  // Public read, private write (use updateConfiguration)
    public internal(set) var currentTrack: TrackInfo?  // Public read, internal write for playlist API
    public private(set) var playbackPosition: PlaybackPosition?
    
    // Internal components
    internal let audioEngine: AudioEngineActor  // Allow internal access for playlist API
    private let playbackStateCoordinator: PlaybackStateCoordinator  // SSOT for player state
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
    
    // Crossfade operation tracking (unified lock)
    private enum CrossfadeOperation {
        case automaticLoop   // Triggered by playback position reaching near-end
        case manualChange    // Triggered by user API calls (replaceTrack, skipTo*, etc.)
    }
    private var activeCrossfadeOperation: CrossfadeOperation? = nil
    
    // Paused crossfade state
    private struct PausedCrossfadeState {
        let progress: Float           // 0.0...1.0
        let originalDuration: TimeInterval
        let curve: FadeCurve
        
        // Current volume levels
        let activeMixerVolume: Float
        let inactiveMixerVolume: Float
        
        // Playback positions
        let activePlayerPosition: TimeInterval
        let inactivePlayerPosition: TimeInterval
        
        // Which player is active (.a or .b)
        let activePlayer: PlayerNode
        
        // Resume strategy based on progress
        enum ResumeStrategy {
            case continueFromProgress  // <50%: continue with remaining duration
            case quickFinish           // >=50%: quick finish in 1 second
        }
        let resumeStrategy: ResumeStrategy
        
        // Operation type
        let operation: CrossfadeOperation
        
        init(
            progress: Float,
            originalDuration: TimeInterval,
            curve: FadeCurve,
            activeMixerVolume: Float,
            inactiveMixerVolume: Float,
            activePlayerPosition: TimeInterval,
            inactivePlayerPosition: TimeInterval,
            activePlayer: PlayerNode,
            operation: CrossfadeOperation
        ) {
            self.progress = progress
            self.originalDuration = originalDuration
            self.curve = curve
            self.activeMixerVolume = activeMixerVolume
            self.inactiveMixerVolume = inactiveMixerVolume
            self.activePlayerPosition = activePlayerPosition
            self.inactivePlayerPosition = inactivePlayerPosition
            self.activePlayer = activePlayer
            self.operation = operation
            
            // Determine strategy based on progress threshold
            self.resumeStrategy = progress < 0.5 ? .continueFromProgress : .quickFinish
            
            // Log strategy selection for debugging
            let strategyName = self.resumeStrategy == .continueFromProgress ? "continueFromProgress" : "quickFinish"
            AudioPlayerService.logger.debug("[CROSSFADE_PAUSE] Strategy selected: \(strategyName) (progress=\(progress * 100)%)")
        }
    }
    private var pausedCrossfadeState: PausedCrossfadeState? = nil

    // Crossfade progress observation
    private var crossfadeProgressTask: Task<Void, Never>?
    private var crossfadeCleanupTask: Task<Void, Never>?
    public private(set) var currentCrossfadeProgress: CrossfadeProgress = .idle
    
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
        self._state = .finished
        self.configuration = configuration
        self.audioEngine = AudioEngineActor()
        self.playbackStateCoordinator = PlaybackStateCoordinator(audioEngine: audioEngine)
        self.sessionManager = AudioSessionManager.shared  // Use singleton
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
        
        // Initialize state machine
        initializeStateMachine()
        await setupSessionHandlers()
        await setupRemoteCommands()
    }
    
    private func initializeStateMachine() {
        self.stateMachine = AudioStateMachine(context: self)
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
        
        // Get current track from playlist
        guard let track = await playlistManager.getCurrentTrack() else {
            throw AudioPlayerError.emptyPlaylist
        }
        let url = track.url
        
        // Store fade-in duration for startEngine()
        pendingFadeInDuration = fadeDuration
        
        // Validate configuration
        try configuration.validate()
        
        // Sync configuration with playlist manager
        await syncConfigurationToPlaylistManager()
        
        // Reset loop tracking
        self.currentTrackURL = url
        self.currentRepeatCount = 0
        self.activeCrossfadeOperation = nil
        
        // Audio session already configured in setup()
        // Just ensure it's activated (idempotent operation)
        do {
            try await sessionManager.activate()
            Self.logger.debug("Audio session activated successfully")
        } catch {
            Self.logger.error("Failed to activate audio session: \(error.localizedDescription)")
            throw AudioPlayerError.sessionConfigurationFailed(
                reason: "Failed to activate: \(error.localizedDescription)"
            )
        }
        
        // Prepare audio engine (MUST be after session activation)
        do {
            try await audioEngine.prepare()
            Self.logger.debug("Audio engine prepared successfully")
        } catch {
            Self.logger.error("Failed to prepare audio engine: \(error.localizedDescription)")
            throw AudioPlayerError.engineStartFailed(
                reason: "Failed to prepare engine: \(error.localizedDescription)"
            )
        }
        
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
        let hasCleanupTask = crossfadeCleanupTask != nil
        Self.logger.debug("[PAUSE] ⏸️ pause() called")
        Self.logger.debug("[PAUSE] State: \(state) | Crossfade active: \(activeCrossfadeOperation != nil) | Already paused: \(pausedCrossfadeState != nil) | Cleanup task running: \(hasCleanupTask)")
        
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
        
        // Save crossfade state if active (for resume)
        // Check both activeCrossfadeOperation and pausedCrossfadeState (for repeated pause)
        if activeCrossfadeOperation != nil || pausedCrossfadeState != nil {
            // Only save state if not already paused
            if pausedCrossfadeState == nil {
                // Get current crossfade state from engine
                if let engineState = await audioEngine.getCrossfadeState() {
                    // Calculate progress from currentCrossfadeProgress
                    let progress = Float(currentCrossfadeProgress.progress)
                    
                    // Create paused state snapshot
                    pausedCrossfadeState = PausedCrossfadeState(
                        progress: progress,
                        originalDuration: configuration.crossfadeDuration,
                        curve: configuration.fadeCurve,
                        activeMixerVolume: engineState.activeMixerVolume,
                        inactiveMixerVolume: engineState.inactiveMixerVolume,
                        activePlayerPosition: engineState.activePlayerPosition,
                        inactivePlayerPosition: engineState.inactivePlayerPosition,
                        activePlayer: engineState.activePlayer,
                        operation: activeCrossfadeOperation!
                    )
                    
                    Self.logger.debug("[CROSSFADE_PAUSE] Saved state: progress=\(progress), strategy=\(pausedCrossfadeState!.resumeStrategy)")
                }
                
                // Check if state was successfully saved
                guard pausedCrossfadeState != nil else {
                    // State save failed - log error and use normal pause
                    Self.logger.error("[CROSSFADE_PAUSE] ❌ FAILED to get crossfade state from engine!")
                    Self.logger.error("[CROSSFADE_PAUSE] ⚠️ This may happen during playlist replacement or if players are not ready")
                    Self.logger.error("[CROSSFADE_PAUSE] ⚠️ Cancelling all crossfade tasks and using normal pause to avoid issues")
                    
                    // Cancel active crossfade task in AudioEngineActor
                    Self.logger.debug("[CROSSFADE_PAUSE] ❌ Cancelling active crossfade task...")
                    await audioEngine.cancelActiveCrossfade()
                    
                    // Cancel progress observation task
                    Self.logger.debug("[CROSSFADE_PAUSE] ❌ Cancelling progress observation task...")
                    crossfadeProgressTask?.cancel()
                    crossfadeProgressTask = nil
                    updateCrossfadeProgress(.idle)  // Notify observers that crossfade is cancelled
                    
                    // Cancel cleanup task to prevent it from running after crossfade completes
                    if crossfadeCleanupTask != nil {
                        Self.logger.debug("[CROSSFADE_PAUSE] ⚠️ CLEANUP TASK IS RUNNING - cancelling to prevent issues!")
                        crossfadeCleanupTask?.cancel()
                        crossfadeCleanupTask = nil
                        Self.logger.debug("[CROSSFADE_PAUSE] ✅ Cleanup task cancelled successfully")
                    } else {
                        Self.logger.debug("[CROSSFADE_PAUSE] ✓ No cleanup task running")
                    }
                    
                    // Clear crossfade operation
                    activeCrossfadeOperation = nil
                    
                    // Use normal pause instead
                    await stateMachine.enterPaused()
                    await updateNowPlayingPlaybackRate(0.0)
                    return
                }
                
                // Pause both players (don't stop inactive player)
                Self.logger.debug("[CROSSFADE_PAUSE] ⏸️ Pausing both players...")
                await audioEngine.pauseBothPlayersDuringCrossfade()

                // Cancel active crossfade task in AudioEngineActor
                Self.logger.debug("[CROSSFADE_PAUSE] ❌ Cancelling active crossfade task...")
                await audioEngine.cancelActiveCrossfade()

                // Cancel progress observation task
                Self.logger.debug("[CROSSFADE_PAUSE] ❌ Cancelling progress observation task...")
                crossfadeProgressTask?.cancel()
                crossfadeProgressTask = nil
                updateCrossfadeProgress(.idle)  // Notify observers that crossfade is paused
                
                // Cancel cleanup task to prevent race condition
                if crossfadeCleanupTask != nil {
                    Self.logger.debug("[CROSSFADE_PAUSE] ⚠️ CLEANUP TASK IS RUNNING - cancelling to prevent race condition!")
                    crossfadeCleanupTask?.cancel()
                    crossfadeCleanupTask = nil
                    Self.logger.debug("[CROSSFADE_PAUSE] ✅ Cleanup task cancelled successfully")
                } else {
                    Self.logger.debug("[CROSSFADE_PAUSE] ✓ No cleanup task running (already completed or not started)")
                }
                
                // Don't clear activeCrossfadeOperation - keep it for repeated pause detection
            } else {
                Self.logger.debug("[CROSSFADE_PAUSE] ➡️ Repeated pause detected - state already saved, skipping")
            }

            // Use state machine (pausePlayback will check pausedCrossfadeState)
            Self.logger.debug("[CROSSFADE_PAUSE] ✅ Entering paused state...")
            await stateMachine.enterPaused()
            Self.logger.debug("[CROSSFADE_PAUSE] ✓ Pause completed successfully")
            
            Self.logger.debug("[CROSSFADE_PAUSE] Paused during crossfade, players frozen at current volumes")
        } else {
            // Normal pause - use state machine
            // ✅ FIX: Delegate to state machine (removes duplicate call)
            // State machine will call context.pausePlayback() which handles:
            // - Capturing position ONCE
            // - Pausing audio engine
            // - Stopping playback timer
            await stateMachine.enterPaused()
        }
        
        // Update UI
        await updateNowPlayingPlaybackRate(0.0)
    }
    
    public func resume() async throws {
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
        
        // Check if we need to resume crossfade
        if let pausedState = pausedCrossfadeState {
            Self.logger.debug("[CROSSFADE_RESUME] ▶️ RESUMING CROSSFADE: strategy=\(pausedState.resumeStrategy), progress=\(pausedState.progress * 100)%")
            Self.logger.debug("[CROSSFADE_RESUME] State snapshot: activeMixer=\(pausedState.activeMixerVolume), inactiveMixer=\(pausedState.inactiveMixerVolume)")
            
            // Determine resume parameters based on strategy
            let resumeDuration: TimeInterval
            let startVolumes: (active: Float, inactive: Float)
            
            switch pausedState.resumeStrategy {
            case .continueFromProgress:
                // Progress <50%: continue with remaining duration
                resumeDuration = pausedState.originalDuration * TimeInterval(1.0 - pausedState.progress)
                startVolumes = (pausedState.activeMixerVolume, pausedState.inactiveMixerVolume)
                Self.logger.debug("[CROSSFADE_RESUME] Continue from progress: remaining=\(resumeDuration)s, volumes=(\(startVolumes.active), \(startVolumes.inactive))")
                
            case .quickFinish:
                // Progress >=50%: quick finish in 1 second
                resumeDuration = 1.0
                startVolumes = (pausedState.activeMixerVolume, pausedState.inactiveMixerVolume)
                Self.logger.debug("[CROSSFADE_RESUME] Quick finish: duration=1.0s, volumes=(\(startVolumes.active), \(startVolumes.inactive))")
            }
            
            // Restore operation state
            activeCrossfadeOperation = pausedState.operation

            // Use state machine but it will skip reschedule due to flag
            await stateMachine.enterPlaying()

            // Start resumed crossfade
            let progressStream = await audioEngine.resumeCrossfadeFromState(
                duration: resumeDuration,
                curve: pausedState.curve,
                startVolumes: startVolumes
            )

            // Observe progress
            crossfadeProgressTask = Task { [weak self] in
                for await progress in progressStream {
                    await self?.updateCrossfadeProgress(progress)
                }
            }

            // CRITICAL: Clear paused state IMMEDIATELY (don't wait for completion)
            // This allows new track changes to work correctly
            pausedCrossfadeState = nil

            // Cleanup asynchronously after crossfade completes (don't block resume())
            // Store task reference so it can be cancelled on pause
            Self.logger.debug("[CLEANUP_TASK] ▶️ Starting async cleanup task (will run after crossfade completes)")
            crossfadeCleanupTask = Task { [weak self] in
                Self.logger.debug("[CLEANUP_TASK] ⏳ Waiting for crossfade progress task to complete...")
                await self?.crossfadeProgressTask?.value
                Self.logger.debug("[CLEANUP_TASK] ✓ Crossfade progress task completed")
                
                // Check if task was cancelled before cleanup
                if Task.isCancelled {
                    Self.logger.debug("[CLEANUP_TASK] ❌ CANCELLED - cleanup will NOT run (race condition avoided!)")
                    return
                }
                
                Self.logger.debug("[CLEANUP_TASK] ✅ Not cancelled - proceeding with cleanup")
                await self?.cleanupResumedCrossfade()
                Self.logger.debug("[CLEANUP_TASK] ✓ Cleanup task finished successfully")
            }
            
            Self.logger.debug("[CROSSFADE_RESUME] ✅ Resume completed - crossfade is running, cleanup scheduled")
            
        } else {
            // Normal resume without crossfade
            // ✅ FIX: Delegate to state machine (removes duplicate call)
            // State machine will call context.resumePlayback() which handles:
            // - Rescheduling buffer from saved position
            // - Playing audio engine
            // - Restarting playback timer
            Self.logger.debug("[RESUME] Normal resume (no crossfade)")
            await stateMachine.enterPlaying()
        }
        
        // Update UI
        await updateNowPlayingPlaybackRate(1.0)
    }
    
    /// Stop playback with optional fade out
    /// - Parameter fadeDuration: Duration of fade out in seconds (0.0 = instant stop, clamped to 0.0-10.0)
    /// - Note: Default is instant stop (fadeDuration = 0.0)
    /// - Note: If stop called during crossfade, crossfade is cancelled and fadeout is performed on active track
    public func stop(fadeDuration: TimeInterval = 0.0) async {
        // 🔍 DIAGNOSTIC: Log stop entry
        let playerIsPlaying = await audioEngine.isActivePlayerPlaying()
        let mixerVolume = await audioEngine.getActiveMixerVolume()
        let targetVol = await audioEngine.getTargetVolume()
        Self.logger.debug("[STOP_DIAGNOSTIC] Entry: fadeDuration=\(fadeDuration), isPlaying=\(playerIsPlaying), mixerVol=\(mixerVolume), targetVol=\(targetVol), state=\(self.state)")

        // Clear paused crossfade state (stop invalidates saved state)
        clearPausedCrossfadeIfNeeded()

        // ✅ FIX: If crossfade in progress, cancel it and stop inactive player
        // Active player will fade out naturally
        if activeCrossfadeOperation != nil {
            Self.logger.debug("[STOP] Cancel crossfade in progress")
            await audioEngine.cancelCrossfadeAndStopInactive()

            activeCrossfadeOperation = nil

            // Cancel progress observation
            crossfadeProgressTask?.cancel()
            crossfadeProgressTask = nil
            currentCrossfadeProgress = .idle
        }
        
        if fadeDuration > 0 {
            // Stop with fade
            await stopWithFade(duration: fadeDuration)
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
        
        // 🔍 DIAGNOSTIC: Check player state BEFORE getting volume
        let playerIsPlayingBefore = await audioEngine.isActivePlayerPlaying()
        Self.logger.debug("[STOP_DIAGNOSTIC] Before fade: playerIsPlaying=\(playerIsPlayingBefore)")
        
        // ✅ FIX #2: Get ACTUAL mixer volume, not target volume
        // targetVolume is for mainMixer (global), we need activeMixer volume
        let currentVolume = await audioEngine.getActiveMixerVolume()
        
        Self.logger.debug("[STOP_FADE] Starting fade: volume=\(currentVolume) → 0.0, duration=\(clampedDuration)s")
        Self.logger.debug("[STOP_DIAGNOSTIC] Fade params: from=\(currentVolume), to=0.0, duration=\(clampedDuration)s")
        
        // Fade out active mixer
        await audioEngine.fadeActiveMixer(
            from: currentVolume,
            to: 0.0,
            duration: clampedDuration,
            curve: configuration.fadeCurve
        )
        
        // 🔍 DIAGNOSTIC: Check state AFTER fade
        let playerIsPlayingAfter = await audioEngine.isActivePlayerPlaying()
        let mixerVolumeAfter = await audioEngine.getActiveMixerVolume()
        Self.logger.debug("[STOP_DIAGNOSTIC] After fade: playerIsPlaying=\(playerIsPlayingAfter), mixerVol=\(mixerVolumeAfter)")
        
        Self.logger.debug("[STOP_FADE] Fade complete, performing instant stop")
        
        // Then perform instant stop
        await stopImmediately()
    }
    
    /// Stop playback immediately without fade
    /// - Note: This is the original stop() behavior
    private func stopImmediately() async {
        // 🔍 DIAGNOSTIC: Log immediate stop
        Self.logger.debug("[STOP_DIAGNOSTIC] stopImmediately START")
        
        // Stop playback components
        stopPlaybackTimer()
        await audioEngine.stopBothPlayers()
        
        Self.logger.debug("[STOP_DIAGNOSTIC] stopImmediately: players stopped")
        
        // Session stays active - following Apple's AVAudioPlayer pattern
        // iOS manages session lifecycle automatically
        
        // Reset ALL state for clean restart (including crossfade flags)
        playbackPosition = nil
        currentTrack = nil
        currentTrackURL = nil
        currentRepeatCount = 0
        activeCrossfadeOperation = nil
        
        // State change via state machine
        await stateMachine.enterFinished()
        
        // Clear UI
        let manager = remoteCommandManager!  // Capture before MainActor hop
        Task { @MainActor in
            manager.clearNowPlayingInfo()
        }
    }

    
    public func finish(fadeDuration: TimeInterval?) async throws {
        let duration = fadeDuration ?? 3.0
        
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
    
    public func skip(forward interval: TimeInterval = 15.0) async throws {
        // Cancel any active crossfade (without rollback)
        if activeCrossfadeOperation != nil {
            await audioEngine.cancelCrossfadeAndStopInactive()
            
            activeCrossfadeOperation = nil
            
            crossfadeProgressTask?.cancel()
            crossfadeProgressTask = nil
            currentCrossfadeProgress = .idle
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
    
    public func skip(backward interval: TimeInterval = 15.0) async throws {
        // Cancel any active crossfade (without rollback)
        if activeCrossfadeOperation != nil {
            await audioEngine.cancelCrossfadeAndStopInactive()
            
            activeCrossfadeOperation = nil
            
            crossfadeProgressTask?.cancel()
            crossfadeProgressTask = nil
            currentCrossfadeProgress = .idle
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
    /// - Note: Automatically cancels any active crossfade before seeking
    public func seek(to time: TimeInterval, fadeDuration: TimeInterval = 0.1) async throws {
        // Clear paused crossfade state (new position invalidates saved state)
        clearPausedCrossfadeIfNeeded()
        
        Self.logger.debug("[SEEK] Seeking to \(time)s, crossfadeActive=\(activeCrossfadeOperation != nil)")

        // Cancel any active crossfade (without rollback)
        if activeCrossfadeOperation != nil {
            await audioEngine.cancelCrossfadeAndStopInactive()

            activeCrossfadeOperation = nil

            crossfadeProgressTask?.cancel()
            crossfadeProgressTask = nil
            currentCrossfadeProgress = .idle
        }
        
        let wasPlaying = state == .playing
        
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
        currentTrack = nil
        currentTrackURL = nil
        playbackPosition = nil
        currentRepeatCount = 0
        activeCrossfadeOperation = nil
        
        // CRITICAL: Reinitialize state machine to FinishedState
        // This prevents Error 4 (invalidState) on next play()
        initializeStateMachine()
        
        // Re-setup engine for fresh start
        try? await audioEngine.setup()
        
        // Notify observers
        notifyObservers(stateChange: .finished)
        
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
        currentTrack = nil
        currentTrackURL = nil
        playbackPosition = nil
        currentRepeatCount = 0
        activeCrossfadeOperation = nil
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
        clearPausedCrossfadeIfNeeded()

        // Rollback if crossfade in progress
        if activeCrossfadeOperation != nil {
            await rollbackCrossfade()
            try await Task.sleep(nanoseconds: 1_500_000_000) // 1.5s delay
        }

        // State preservation (BEFORE async operations!)
        let wasPlaying = state == .playing

        // Load first track of new playlist on secondary player
        let firstTrack = tracks[0]
        let newTrack = try await audioEngine.loadAudioFileOnSecondaryPlayer(url: firstTrack.url)

        // Recheck state after async (actor reentrancy protection)
        let isStillPlaying = state == .playing

        // Decision: crossfade or silent switch
        if wasPlaying && isStillPlaying {
            // Prepare secondary player
            await audioEngine.prepareSecondaryPlayer()

            // Execute crossfade with automatic pause handling
            let result = await executeCrossfade(
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

        // 7. Update PlaylistManager (URL version)
        await playlistManager.replacePlaylist(tracks)
        
        // 8. Update current track state
        currentTrack = newTrack
        currentTrackURL = firstTrack.url
        
        // 9. Reset counters
        currentRepeatCount = 0
        activeCrossfadeOperation = nil
        
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
        clearPausedCrossfadeIfNeeded()

        // Rollback if crossfade in progress
        if activeCrossfadeOperation != nil {
            await rollbackCrossfade()
            try await Task.sleep(nanoseconds: 1_500_000_000) // 1.5s delay
        }

        // State preservation (BEFORE async operations!)
        let wasPlaying = state == .playing

        // Load first track of new playlist on secondary player
        let firstTrackURL = tracks[0]
        let newTrack = try await audioEngine.loadAudioFileOnSecondaryPlayer(url: firstTrackURL)

        // Recheck state after async (actor reentrancy protection)
        let isStillPlaying = state == .playing

        // Decision: crossfade or silent switch
        if wasPlaying && isStillPlaying {
            // Prepare secondary player
            await audioEngine.prepareSecondaryPlayer()

            // Execute crossfade with automatic pause handling
            let result = await executeCrossfade(
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
        
        // 7. Update PlaylistManager (URL version)
        await playlistManager.replacePlaylist(tracks)
        
        // 8. Update current track state
        currentTrack = newTrack
        currentTrackURL = firstTrackURL
        
        // 9. Reset counters
        currentRepeatCount = 0
        activeCrossfadeOperation = nil
        
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
    /// - Throws: AudioPlayerError.noNextTrack if no next track available
    /// - Note: Uses configuration.crossfadeDuration for crossfade
    /// - Note: If crossfade in progress, performs rollback and retries
    public func skipToNext() async throws {
        guard let nextTrack = await playlistManager.skipToNext() else {
            throw AudioPlayerError.noNextTrack
        }
        try await replaceCurrentTrack(
            track: nextTrack,
            crossfadeDuration: configuration.crossfadeDuration
        )
    }
    
    /// Skip to previous track in playlist
    /// - Throws: AudioPlayerError.noPreviousTrack if no previous track available
    /// - Note: Uses configuration.crossfadeDuration for crossfade
    /// - Note: If crossfade in progress, performs rollback and retries
    public func skipToPrevious() async throws {
        guard let prevTrack = await playlistManager.skipToPrevious() else {
            throw AudioPlayerError.noPreviousTrack
        }
        try await replaceCurrentTrack(
            track: prevTrack,
            crossfadeDuration: configuration.crossfadeDuration
        )
    }
    
    // MARK: - Internal Track Replacement
    
    /// Internal method for replacing current track with crossfade (used by skipToNext/skipToPrevious)
    /// - Parameters:
    ///   - track: New track to play
    ///   - crossfadeDuration: Crossfade duration in seconds
    ///   - retryDelay: Delay before retry if crossfade already in progress
    internal func replaceCurrentTrack(track: Track, crossfadeDuration: TimeInterval, retryDelay: TimeInterval = 1.5) async throws {
        let url = track.url

        // Validate and clamp crossfade duration
        let validatedDuration = max(1.0, min(30.0, crossfadeDuration))

        // Clear any paused crossfade state (starting new operation)
        clearPausedCrossfadeIfNeeded()

        // If crossfade in progress - rollback and retry
        if activeCrossfadeOperation != nil {
            // 1. Rollback current transition
            await audioEngine.cancelCrossfadeAndStopInactive()
            activeCrossfadeOperation = nil
            crossfadeProgressTask?.cancel()
            crossfadeProgressTask = nil
            currentCrossfadeProgress = .idle

            // 2. Short delay before retry
            try await Task.sleep(nanoseconds: UInt64(retryDelay * 1_000_000_000))
        }
        
        // CRITICAL: Remember state BEFORE any async operations
        let wasPlaying = state == .playing
        
        // Load new file on secondary player (suspension point)
        _ = try await audioEngine.loadAudioFileOnSecondaryPlayer(url: url)
        
        // CRITICAL: Recheck state after async operation (actor reentrancy protection)
        let isStillPlaying = state == .playing
        
        // Decision: crossfade only if BOTH conditions true
        if wasPlaying && isStillPlaying {
            // Still playing - do crossfade
            await audioEngine.prepareSecondaryPlayer()

            // Execute crossfade with automatic pause handling
            let result = await executeCrossfade(
                duration: validatedDuration,
                curve: configuration.fadeCurve,
                operation: .manualChange
            )

            // If paused, cleanup will be done on resume
            if result == .paused {
                return
            }

            // CRITICAL FIX: Ensure state=.playing after crossfade
            if state != .playing {
                await stateMachine.enterPlaying()
            }
        } else {
            // Paused or stopped during load - switch files without starting
            await audioEngine.switchActivePlayerWithVolume()
            await audioEngine.stopInactivePlayer()
            // Note: New active player will be scheduled on resume via play()
        }
    }

    
    // MARK: - Observers (Public for Demo App)
    
    public func addObserver(_ observer: AudioPlayerObserver) {
        observers.append(observer)
    }
    
    public func removeObserver(_ observer: AudioPlayerObserver) {
        // Remove by identity (assuming observers are classes)
        observers.removeAll { existingObserver in
            existingObserver === observer
        }
    }
    
    internal func removeAllObservers() {
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
        
        // Check for track end (auto-advance to next track or stop)
        if shouldTriggerTrackEnd(position) {
            await handleTrackEnd()
            return  // Don't check loop crossfade if track ended
        }
        
        // Check for loop crossfade trigger (with race condition protection)
        if shouldTriggerLoopCrossfade(position) && activeCrossfadeOperation != .automaticLoop {
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
        let wasPlaying = state == .playing
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
            await stateMachine.enterFailed(error: .sessionConfigurationFailed(
                reason: "Media services reset - reconfiguration failed: \(error.localizedDescription)"
            ))
            return
        }
        
        // Step 3: Reactivate session
        do {
            try await sessionManager.activate()
            Self.logger.debug("[MEDIA_SERVICES] Session reactivated successfully")
        } catch {
            Self.logger.error("[MEDIA_SERVICES] Failed to reactivate session: \(error.localizedDescription)")
            await stateMachine.enterFailed(error: .sessionConfigurationFailed(
                reason: "Media services reset - reactivation failed: \(error.localizedDescription)"
            ))
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
            await stateMachine.enterFailed(error: .engineStartFailed(
                reason: "Media services reset - engine restart failed: \(error.localizedDescription)"
            ))
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
    private func shouldTriggerTrackEnd(_ position: PlaybackPosition) -> Bool {
        // Only for .off or .playlist modes (not .singleTrack - it loops)
        guard configuration.repeatMode != .singleTrack else { return false }
        
        // Don't trigger if already replacing track
        guard activeCrossfadeOperation != .manualChange else { return false }
        
        // Only trigger when playing
        guard state == .playing else { return false }
        
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
    private func shouldTriggerLoopCrossfade(_ position: PlaybackPosition) -> Bool {
        // Only loop if repeat mode is not .off
        guard configuration.repeatMode != .off else { return false }
        
        // Don't trigger if already in progress
        guard activeCrossfadeOperation != .automaticLoop else { return false }
        
        // Only trigger when playing
        guard state == .playing else { return false }
        
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
        activeCrossfadeOperation = .automaticLoop
        defer { activeCrossfadeOperation = nil }
        
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
        updateCrossfadeProgress(prepareProgress)
        
        // Load same file on secondary player
        do {
            let trackInfo = try await audioEngine.loadAudioFileOnSecondaryPlayer(url: currentURL)

            // Prepare secondary player
            await audioEngine.prepareSecondaryPlayer()

            // Execute crossfade with automatic pause handling
            // Note: Loop uses .automaticLoop operation type
            let result = await executeCrossfade(
                duration: crossfadeDuration,
                curve: configuration.fadeCurve,
                operation: .automaticLoop
            )

            // If paused, cleanup will be done on resume
            if result == .paused {
                return
            }

            // Update track info (same URL, but refreshed)
            currentTrack = trackInfo
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
        updateCrossfadeProgress(prepareProgress)
        
        // 1. Get next track from playlist manager
        guard let nextTrack = await playlistManager.getNextTrack() else {
            // No more tracks - finish playback
            try? await finish(fadeDuration: 3.0)
            return
        }
        let nextURL = nextTrack.url
        
        // Load next track on secondary player
        do {
            let nextTrack = try await audioEngine.loadAudioFileOnSecondaryPlayer(url: nextURL)

            // Prepare secondary player
            await audioEngine.prepareSecondaryPlayer()

            // Execute crossfade with automatic pause handling
            let result = await executeCrossfade(
                duration: configuration.crossfadeDuration,
                curve: configuration.fadeCurve,
                operation: .automaticLoop
            )

            // If paused, cleanup will be done on resume
            if result == .paused {
                return
            }

            // Update current track info
            currentTrack = nextTrack
            currentTrackURL = nextURL

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
        if activeCrossfadeOperation != nil {
            await audioEngine.cancelCrossfadeAndStopInactive()
            
            activeCrossfadeOperation = nil
            
            crossfadeProgressTask?.cancel()
            crossfadeProgressTask = nil
            currentCrossfadeProgress = .idle
        }
        
        // Guard: only pause if playing or preparing
        guard state == .playing || state == .preparing else {
            // If already paused or finished, just pause overlay and return
            if state == .paused || state == .finished {
                await audioEngine.pauseOverlay()
                return
            }
            // Invalid state - still pause overlay for consistency
            await audioEngine.pauseOverlay()
            return
        }
        
        // Pause main player via state machine
        await stateMachine.enterPaused()
        
        // Pause overlay separately
        await audioEngine.pauseOverlay()
        
        // Stop sound effects (no pause, only stop)
        await soundEffectsPlayer.stop(fadeDuration: 0.0)
        
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
        guard state == .paused else {
            // If already playing, just resume overlay and return
            if state == .playing {
                await audioEngine.resumeOverlay()
                return
            }
            // If finished - can't resume, but still try overlay
            if state == .finished {
                await audioEngine.resumeOverlay()
                return
            }
            // Invalid state - still resume overlay for consistency
            await audioEngine.resumeOverlay()
            return
        }
        
        // Resume main player via state machine
        await stateMachine.enterPlaying()
        
        // Resume overlay separately
        await audioEngine.resumeOverlay()
        
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
        if activeCrossfadeOperation != nil {
            await audioEngine.cancelCrossfadeAndStopInactive()
            
            activeCrossfadeOperation = nil
            
            crossfadeProgressTask?.cancel()
            crossfadeProgressTask = nil
            currentCrossfadeProgress = .idle
        }
        
        // Stop playback timer
        stopPlaybackTimer()
        
        // Stop main player via state machine (transition to finished)
        await stateMachine.enterFinished()
        
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
        activeCrossfadeOperation = nil
        
        // ✅ FIX: Clear paused crossfade state to prevent stale resume
        if pausedCrossfadeState != nil {
            Self.logger.debug("[ROLLBACK] Clearing stale pausedCrossfadeState")
            pausedCrossfadeState = nil
        }
        
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
        
        Self.logger.debug("[ROLLBACK] ✅ Crossfade rollback completed")
    }

    // MARK: - Crossfade Lifecycle Helpers

    /// Result of crossfade execution
    private enum CrossfadeResult {
        case completed  // Crossfade finished normally
        case paused    // Crossfade was paused mid-execution
    }

    /// Execute crossfade with automatic pause handling and cleanup
    /// - Parameters:
    ///   - duration: Crossfade duration
    ///   - curve: Fade curve
    ///   - operation: Type of crossfade operation
    /// - Returns: Result indicating if crossfade completed or was paused
    private func executeCrossfade(
        duration: TimeInterval,
        curve: FadeCurve,
        operation: CrossfadeOperation
    ) async -> CrossfadeResult {
        // Mark operation as active
        activeCrossfadeOperation = operation
        
        Self.logger.debug("[CROSSFADE] Starting: operation=\(operation), duration=\(duration)s")

        // Start crossfade
        let progressStream = await audioEngine.performSynchronizedCrossfade(
            duration: duration,
            curve: curve
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
        currentCrossfadeProgress = .idle

        // Check if paused during crossfade
        if pausedCrossfadeState != nil {
            Self.logger.debug("[CROSSFADE] Paused during execution, skipping cleanup")
            return .paused
        }

        // Perform cleanup
        await performCrossfadeCleanup()

        // Clear operation
        activeCrossfadeOperation = nil

        return .completed
    }

    /// Perform post-crossfade cleanup (switch players, stop inactive, reset mixer)
    private func performCrossfadeCleanup() async {
        await audioEngine.switchActivePlayer()
        await audioEngine.stopInactivePlayer()
        await audioEngine.resetInactiveMixer()
        await audioEngine.clearInactiveFile()
        Self.logger.debug("[CROSSFADE] Cleanup complete (players switched)")
    }

    /// Clear paused crossfade state if starting new operation
    private func clearPausedCrossfadeIfNeeded() {
        if pausedCrossfadeState != nil {
            Self.logger.debug("[CROSSFADE] Clearing paused state (new operation)")
            pausedCrossfadeState = nil
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

    /// Cleanup after resumed crossfade completes
    /// - Note: Called asynchronously from Task in resume() to avoid blocking
    private func cleanupResumedCrossfade() async {
        Self.logger.debug("[CLEANUP] ⚙️ cleanupResumedCrossfade() STARTED")
        Self.logger.debug("[CLEANUP] Current state: \(await stateMachine.currentState), pausedCrossfadeState: \(pausedCrossfadeState != nil ? "EXISTS" : "nil")")
        
        // CRITICAL: Check if paused during cleanup execution
        // Task.isCancelled is NOT reliable in Swift - must check state manually!
        if pausedCrossfadeState != nil {
            Self.logger.debug("[CLEANUP] ❌ ABORTED - crossfade is paused (pausedCrossfadeState exists)")
            Self.logger.debug("[CLEANUP] ⚠️ This prevents stopInactivePlayer() from being called during pause")
            return
        }
        
        // Switch players after crossfade
        Self.logger.debug("[CLEANUP] → Switching active player...")
        await audioEngine.switchActivePlayer()
        
        Self.logger.debug("[CLEANUP] → Stopping inactive player...")
        await audioEngine.stopInactivePlayer()

        Self.logger.debug("[CLEANUP] ✅ Crossfade cleanup COMPLETED successfully")

        // Clear operation state
        activeCrossfadeOperation = nil
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
        
        // Use pending fade-in if set, otherwise no fade (instant start)
        let fadeInDuration = pendingFadeInDuration
        let shouldFadeIn = fadeInDuration > 0
        
        await audioEngine.scheduleFile(
            fadeIn: shouldFadeIn,
            fadeInDuration: fadeInDuration,
            fadeCurve: configuration.fadeCurve
        )
        
        // Clear pending fade after use
        pendingFadeInDuration = 0.0
    }
    
    func stopEngine() async {
        await audioEngine.stop()
        stopPlaybackTimer()
    }
    
    func pausePlayback() async {
        // Stop playback timer BEFORE pausing
        // This prevents position updates during pause
        stopPlaybackTimer()
        
        // During crossfade pause: just pause both players without fade
        if pausedCrossfadeState != nil {
            Self.logger.debug("[CROSSFADE_PAUSE] pausePlayback: skipping normal pause (crossfade mode)")
            // Players already paused by pauseBothPlayersDuringCrossfade()
            // Just capture position
            playbackPosition = await audioEngine.getCurrentPosition()
            return
        }

        Self.logger.debug("[PAUSE] pausePlayback: normal pause")
        // Normal pause: pause audio engine (captures position accurately)
        await audioEngine.pause()
    }

    func resumePlayback() async throws {
        // Ensure session is active before resuming (protects against external interference)
        try await ensureSessionActive()

        // During crossfade resume: skip normal play (crossfade will handle it)
        if pausedCrossfadeState != nil {
            // Just restart timer, players will be resumed by crossfade
            startPlaybackTimer()
            return
        }
        
        // Normal resume: play audio engine
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
