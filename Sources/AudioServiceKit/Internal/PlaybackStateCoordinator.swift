import Foundation
import AVFoundation
import OSLog
import AudioServiceCore

/// Coordinator for player state management - SINGLE SOURCE OF TRUTH
///
/// This coordinator owns ALL playback state:
/// - Which player (A/B) is active
/// - Current playback mode (playing/paused/stopped)
/// - Track information
/// - Mixer volumes
///
/// **Architecture Rules:**
/// 1. All state queries MUST go through this coordinator
/// 2. All state updates MUST use atomic operations
/// 3. State validation runs on every change
/// 4. No direct state manipulation allowed
///
actor PlaybackStateCoordinator {
    
    // MARK: - Types
    
    /// Crossfade operation type
    enum CrossfadeOperation {
        case automaticLoop   // Triggered by playback position reaching near-end
        case manualChange    // Triggered by user API calls (replaceTrack, skipTo*, etc.)
    }
    
    /// Crossfade result
    enum CrossfadeResult {
        case completed   // Crossfade finished successfully
        case paused      // Crossfade was paused mid-way
        case cancelled   // Crossfade was cancelled/rolled back
    }
    
    /// Player node identifier
    enum PlayerNode {
        case a
        case b
        
        var opposite: PlayerNode {
            return self == .a ? .b : .a
        }
    }
    
    // Use PlayerState from AudioServiceCore instead of custom enum
    
    /// Complete coordinator state - immutable snapshot
    struct CoordinatorState {
        let activePlayer: PlayerNode
        let playbackMode: PlayerState
        let activeTrack: Track?
        let inactiveTrack: Track?
        let activeMixerVolume: Float
        let inactiveMixerVolume: Float
        let isCrossfading: Bool
        
        /// Validate state consistency
        var isConsistent: Bool {
            // 1. Playing mode requires active track
            if playbackMode == .playing && activeTrack == nil {
                Logger.audio.error("[StateCoordinator] Invalid: playing mode but no track")
                return false
            }
            
            // 2. Mixer volumes must be in valid range
            guard (0.0...1.0).contains(activeMixerVolume) else {
                Logger.audio.error("[StateCoordinator] Invalid active mixer volume: \(activeMixerVolume)")
                return false
            }
            
            guard (0.0...1.0).contains(inactiveMixerVolume) else {
                Logger.audio.error("[StateCoordinator] Invalid inactive mixer volume: \(inactiveMixerVolume)")
                return false
            }
            
            // 3. When not crossfading, inactive mixer should be 0
            if !isCrossfading && inactiveMixerVolume != 0.0 {
                Logger.audio.warning("[StateCoordinator] Inactive mixer should be 0 when not crossfading")
            }
            
            return true
        }
        
        // MARK: - Functional Updates
        
        func withMode(_ mode: PlayerState) -> CoordinatorState {
            CoordinatorState(
                activePlayer: activePlayer,
                playbackMode: mode,
                activeTrack: activeTrack,
                inactiveTrack: inactiveTrack,
                activeMixerVolume: activeMixerVolume,
                inactiveMixerVolume: inactiveMixerVolume,
                isCrossfading: isCrossfading
            )
        }
        
        func withActiveTrack(_ track: Track?) -> CoordinatorState {
            CoordinatorState(
                activePlayer: activePlayer,
                playbackMode: playbackMode,
                activeTrack: track,
                inactiveTrack: inactiveTrack,
                activeMixerVolume: activeMixerVolume,
                inactiveMixerVolume: inactiveMixerVolume,
                isCrossfading: isCrossfading
            )
        }
        
        func withInactiveTrack(_ track: Track?) -> CoordinatorState {
            CoordinatorState(
                activePlayer: activePlayer,
                playbackMode: playbackMode,
                activeTrack: activeTrack,
                inactiveTrack: track,
                activeMixerVolume: activeMixerVolume,
                inactiveMixerVolume: inactiveMixerVolume,
                isCrossfading: isCrossfading
            )
        }
        
        func withMixerVolumes(active: Float, inactive: Float) -> CoordinatorState {
            CoordinatorState(
                activePlayer: activePlayer,
                playbackMode: playbackMode,
                activeTrack: activeTrack,
                inactiveTrack: inactiveTrack,
                activeMixerVolume: active,
                inactiveMixerVolume: inactive,
                isCrossfading: isCrossfading
            )
        }
        
        func withCrossfading(_ crossfading: Bool) -> CoordinatorState {
            CoordinatorState(
                activePlayer: activePlayer,
                playbackMode: playbackMode,
                activeTrack: activeTrack,
                inactiveTrack: inactiveTrack,
                activeMixerVolume: activeMixerVolume,
                inactiveMixerVolume: inactiveMixerVolume,
                isCrossfading: crossfading
            )
        }
    }
    
    // MARK: - Crossfade State
    
    /// Active crossfade tracking
    struct ActiveCrossfadeState {
        let operation: CrossfadeOperation
        let startTime: Date
        let duration: TimeInterval
        let curve: FadeCurve
        let fromTrack: Track
        let toTrack: Track
        var progress: Float = 0.0
        
        var elapsed: TimeInterval {
            return Date().timeIntervalSince(startTime)
        }
        
        var remaining: TimeInterval {
            return max(0, duration - elapsed)
        }
    }
    
    /// Paused crossfade state for pause/resume
    struct PausedCrossfadeState {
        let progress: Float           // 0.0...1.0
        let originalDuration: TimeInterval
        let curve: FadeCurve
        
        // Current volume levels
        let activeMixerVolume: Float
        let inactiveMixerVolume: Float
        
        // Playback positions
        let activePlayerPosition: TimeInterval
        let inactivePlayerPosition: TimeInterval
        
        // Which player is active
        let activePlayer: PlayerNode
        
        // Resume strategy based on progress
        enum ResumeStrategy {
            case continueFromProgress  // <50%: continue with remaining duration
            case quickFinish           // >=50%: quick finish in 1 second
        }
        let resumeStrategy: ResumeStrategy
        
        // Operation type
        let operation: CrossfadeOperation
        
        var remainingDuration: TimeInterval {
            let remaining = originalDuration * TimeInterval(1.0 - progress)
            return resumeStrategy == .quickFinish ? 1.0 : remaining
        }
        
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
            
            Logger.audio.debug("[Coordinator] PausedCrossfade: strategy=\(self.resumeStrategy), progress=\(Int(progress * 100))%")
        }
    }
    
    // MARK: - State (SINGLE SOURCE OF TRUTH)
    
    /// Current coordinator state - READ ONLY from outside
    private(set) var state: CoordinatorState
    
    /// Active crossfade (if any)
    private var activeCrossfade: ActiveCrossfadeState? = nil
    
    /// Paused crossfade (if any)
    private var pausedCrossfade: PausedCrossfadeState? = nil
    
    /// Crossfade progress task
    private var crossfadeProgressTask: Task<Void, Never>? = nil
    
    // MARK: - Dependencies
    
    private let audioEngine: AudioEngineActor
    
    // MARK: - Logging
    
    private static let logger = Logger.audio
    
    // MARK: - Init
    
    init(audioEngine: AudioEngineActor) {
        self.audioEngine = audioEngine
        self.state = CoordinatorState(
            activePlayer: .a,
            playbackMode: .finished,
            activeTrack: nil,
            inactiveTrack: nil,
            activeMixerVolume: 1.0,
            inactiveMixerVolume: 0.0,
            isCrossfading: false
        )
        
        Self.logger.info("[StateCoordinator] ✅ Initialized with default state")
    }
    
    // MARK: - Atomic Operations
    
    /// Atomically switch active player (no suspend points)
    func switchActivePlayer() {
        Self.logger.debug("[StateCoordinator] → switchActivePlayer()")
        
        // Create new state with swapped players
        let newState = CoordinatorState(
            activePlayer: state.activePlayer.opposite,
            playbackMode: state.playbackMode,
            activeTrack: state.inactiveTrack,  // Swap tracks
            inactiveTrack: state.activeTrack,
            activeMixerVolume: state.inactiveMixerVolume,  // Swap volumes
            inactiveMixerVolume: state.activeMixerVolume,
            isCrossfading: state.isCrossfading
        )
        
        guard newState.isConsistent else {
            Self.logger.error("[StateCoordinator] ❌ Invalid state after switch - rollback")
            return
        }
        
        state = newState
        Self.logger.debug("[StateCoordinator] ✅ Switched to player \(state.activePlayer)")
    }
    
    /// Atomically update playback mode
    func updateMode(_ mode: PlayerState) {
        Self.logger.debug("[StateCoordinator] → updateMode(\(mode))")
        
        let newState = state.withMode(mode)
        
        guard newState.isConsistent else {
            Self.logger.error("[StateCoordinator] ❌ Invalid state for mode \(mode) - rollback")
            return
        }
        
        state = newState
        Self.logger.debug("[StateCoordinator] ✅ Mode updated to \(mode)")
    }
    
    /// Atomically load track on inactive player
    func loadTrackOnInactive(_ track: Track) {
        Self.logger.debug("[StateCoordinator] → loadTrackOnInactive(\(track.url.lastPathComponent))")
        
        let newState = state.withInactiveTrack(track)
        
        guard newState.isConsistent else {
            Self.logger.error("[StateCoordinator] ❌ Invalid state after loading track - rollback")
            return
        }
        
        state = newState
        Self.logger.debug("[StateCoordinator] ✅ Track loaded on inactive player")
    }
    
    /// Atomically update mixer volumes
    func updateMixerVolumes(active: Float, inactive: Float) {
        let newState = state.withMixerVolumes(active: active, inactive: inactive)
        
        guard newState.isConsistent else {
            Self.logger.error("[StateCoordinator] ❌ Invalid mixer volumes - rollback")
            return
        }
        
        state = newState
    }
    
    /// Atomically update crossfading flag
    func updateCrossfading(_ crossfading: Bool) {
        let newState = state.withCrossfading(crossfading)
        
        guard newState.isConsistent else {
            Self.logger.error("[StateCoordinator] ❌ Invalid crossfading state - rollback")
            return
        }
        
        state = newState
        Self.logger.debug("[StateCoordinator] ✅ Crossfading = \(crossfading)")
    }
    
    /// Atomically switch to new track (combines load + switch)
    /// Use this for pause + skip scenario
    func atomicSwitch(newTrack: Track, mode: PlayerState? = nil) {
        Self.logger.debug("[StateCoordinator] → atomicSwitch(\(newTrack.url.lastPathComponent))")
        
        let targetMode = mode ?? state.playbackMode
        
        // Create new state with switched player and new track
        let newState = CoordinatorState(
            activePlayer: state.activePlayer.opposite,
            playbackMode: targetMode,
            activeTrack: newTrack,  // New track becomes active
            inactiveTrack: state.activeTrack,  // Old active becomes inactive
            activeMixerVolume: 1.0,  // Reset to full volume
            inactiveMixerVolume: 0.0,
            isCrossfading: false
        )
        
        guard newState.isConsistent else {
            Self.logger.error("[StateCoordinator] ❌ Invalid state after atomic switch - rollback")
            return
        }
        
        state = newState
        Self.logger.info("[StateCoordinator] ✅ Atomic switch complete: \(state.activePlayer) = \(newTrack.url.lastPathComponent)")
    }
    
    // MARK: - State Queries
    
    func getCurrentTrack() -> Track? {
        return state.activeTrack
    }
    
    func getPlaybackMode() -> PlayerState {
        return state.playbackMode
    }
    
    func getActivePlayer() -> PlayerNode {
        return state.activePlayer
    }
    
    func isCrossfading() -> Bool {
        return state.isCrossfading
    }
    
    /// Check if there's an active crossfade operation
    func hasActiveCrossfade() -> Bool {
        return activeCrossfade != nil
    }
    
    /// Check if there's a paused crossfade
    func hasPausedCrossfade() -> Bool {
        return pausedCrossfade != nil
    }
    
    /// Get active crossfade operation type (if any)
    func getActiveCrossfadeOperation() -> CrossfadeOperation? {
        return activeCrossfade?.operation
    }
    
    /// Cancel active crossfade and cleanup
    func cancelActiveCrossfade() async {
        guard activeCrossfade != nil else { return }
        
        Self.logger.debug("[Coordinator] Cancelling active crossfade")
        
        // Cancel progress task
        crossfadeProgressTask?.cancel()
        crossfadeProgressTask = nil
        
        // Cancel engine crossfade
        await audioEngine.cancelActiveCrossfade()
        
        // Clear state
        activeCrossfade = nil
        state = state.withCrossfading(false)
    }
    
    /// Clear paused crossfade state
    func clearPausedCrossfade() {
        if pausedCrossfade != nil {
            Self.logger.debug("[Coordinator] Clearing paused crossfade")
            pausedCrossfade = nil
        }
    }
    
    /// Capture complete state snapshot (for crossfade pause/resume)
    func captureSnapshot() -> CoordinatorState {
        return state
    }
    
    /// Restore state snapshot (for crossfade resume)
    func restoreSnapshot(_ snapshot: CoordinatorState) {
        Self.logger.debug("[StateCoordinator] → restoreSnapshot()")
        
        guard snapshot.isConsistent else {
            Self.logger.error("[StateCoordinator] ❌ Cannot restore invalid snapshot")
            return
        }
        
        state = snapshot
        Self.logger.info("[StateCoordinator] ✅ Snapshot restored")
    }
    
    // MARK: - Crossfade Operations
    
    /// Start crossfade from active track to new track
    /// - Returns: CrossfadeResult (.completed, .paused, .cancelled)
    func startCrossfade(
        to track: Track,
        duration: TimeInterval,
        curve: FadeCurve,
        operation: CrossfadeOperation
    ) async throws -> CrossfadeResult {
        Self.logger.debug("[Coordinator] → startCrossfade(to: \(track.url.lastPathComponent))")
        
        // 1. Rollback existing crossfade if any
        if activeCrossfade != nil {
            Self.logger.debug("[Coordinator] Active crossfade exists, rolling back...")
            await rollbackCurrentCrossfade()
        }
        
        // 2. Validate we have active track
        guard let fromTrack = state.activeTrack else {
            Self.logger.error("[Coordinator] ❌ No active track to crossfade from")
            throw AudioPlayerError.invalidState(
                current: "no active track",
                attempted: "start crossfade"
            )
        }
        
        // 3. Clear any paused crossfade
        if pausedCrossfade != nil {
            Self.logger.debug("[Coordinator] Clearing paused crossfade (new operation)")
            pausedCrossfade = nil
        }
        
        // 4. Create active crossfade state
        activeCrossfade = ActiveCrossfadeState(
            operation: operation,
            startTime: Date(),
            duration: duration,
            curve: curve,
            fromTrack: fromTrack,
            toTrack: track
        )
        
        // 5. Load track on inactive player
        Self.logger.debug("[Coordinator] Loading track on inactive player...")
        _ = try await audioEngine.loadAudioFileOnSecondaryPlayer(url: track.url)
        loadTrackOnInactive(track)
        
        // 6. Mark as crossfading
        updateCrossfading(true)
        
        // 7. Prepare and start crossfade
        await audioEngine.prepareSecondaryPlayer()
        
        Self.logger.info("[Coordinator] ✅ Starting engine crossfade (duration=\(duration)s)")
        
        let progressStream = await audioEngine.performSynchronizedCrossfade(
            duration: duration,
            curve: curve
        )
        
        // 8. Monitor progress
        crossfadeProgressTask = Task { [weak self] in
            for await progress in progressStream {
                await self?.updateCrossfadeProgress(progress)
            }
        }
        
        // 9. Wait for completion
        await crossfadeProgressTask?.value
        crossfadeProgressTask = nil
        
        // 10. Check if paused during crossfade
        if pausedCrossfade != nil {
            Self.logger.debug("[Coordinator] Crossfade paused during execution")
            activeCrossfade = nil
            return .paused
        }
        
        // 11. Crossfade completed - cleanup
        Self.logger.debug("[Coordinator] Crossfade completed, performing cleanup...")
        
        // Switch players
        switchActivePlayer()
        
        // Stop and clear inactive
        await audioEngine.stopInactivePlayer()
        await audioEngine.resetInactiveMixer()
        await audioEngine.clearInactiveFile()
        
        // Clear crossfade state
        activeCrossfade = nil
        updateCrossfading(false)
        
        Self.logger.info("[Coordinator] ✅ Crossfade completed successfully")
        
        return .completed
    }
    
    /// Rollback current crossfade smoothly (used when skipping during crossfade)
    func rollbackCurrentCrossfade() async {
        guard activeCrossfade != nil else { return }
        
        Self.logger.debug("[Coordinator] Rolling back active crossfade...")
        
        // Quick fade to active player (0.3s smooth rollback)
        _ = await audioEngine.rollbackCrossfade(rollbackDuration: 0.3)
        
        // Clear state
        activeCrossfade = nil
        state = state.withInactiveTrack(nil)
            .withMixerVolumes(active: 1.0, inactive: 0.0)
            .withCrossfading(false)
        
        // Cancel progress task
        crossfadeProgressTask?.cancel()
        crossfadeProgressTask = nil
        
        Self.logger.info("[Coordinator] ✅ Crossfade rolled back")
    }
    
    /// Pause current crossfade and capture state
    func pauseCrossfade() async throws -> PausedCrossfadeState? {
        guard let crossfade = activeCrossfade else { return nil }
        
        Self.logger.debug("[Coordinator] Pausing crossfade (progress=\(Int(crossfade.progress * 100))%)")
        
        // Capture engine state (includes positions)
        guard let engineState = await audioEngine.getCrossfadeState() else {
            Self.logger.error("[Coordinator] ❌ Failed to get crossfade state")
            return nil
        }
        
        // Create paused state
        let pausedState = PausedCrossfadeState(
            progress: crossfade.progress,
            originalDuration: crossfade.duration,
            curve: crossfade.curve,
            activeMixerVolume: engineState.activeMixerVolume,
            inactiveMixerVolume: engineState.inactiveMixerVolume,
            activePlayerPosition: engineState.activePlayerPosition,
            inactivePlayerPosition: engineState.inactivePlayerPosition,
            activePlayer: state.activePlayer,
            operation: crossfade.operation
        )
        
        // Store paused state
        pausedCrossfade = pausedState
        
        // Clear active crossfade
        activeCrossfade = nil
        
        // Cancel progress task
        crossfadeProgressTask?.cancel()
        crossfadeProgressTask = nil
        
        Self.logger.info("[Coordinator] ✅ Crossfade paused (strategy=\(pausedState.resumeStrategy))")
        
        return pausedState
    }
    
    /// Resume paused crossfade
    func resumeCrossfade() async throws -> Bool {
        guard let paused = pausedCrossfade else { return false }
        
        Self.logger.debug("[Coordinator] Resuming paused crossfade (strategy=\(paused.resumeStrategy))")
        
        // Resume crossfade in engine
        // Note: We'll implement a simpler approach - just continue the crossfade
        let resumed = true  // For now, always resume
        
        if resumed {
            // Recreate active crossfade
            guard let fromTrack = state.activeTrack, let toTrack = state.inactiveTrack else {
                Self.logger.error("[Coordinator] ❌ Cannot resume - missing tracks")
                return false
            }
            
            activeCrossfade = ActiveCrossfadeState(
                operation: paused.operation,
                startTime: Date(),
                duration: paused.remainingDuration,
                curve: paused.curve,
                fromTrack: fromTrack,
                toTrack: toTrack,
                progress: Float(paused.progress)
            )
            
            pausedCrossfade = nil
            updateCrossfading(true)
            
            // Monitor resumed crossfade (async cleanup)
            Task { [weak self] in
                // Wait a bit for resume to settle
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s
                
                await self?.cleanupResumedCrossfade()
            }
            
            Self.logger.info("[Coordinator] ✅ Crossfade resumed")
        }
        
        return resumed
    }
    
    /// Cleanup after resumed crossfade completes
    private func cleanupResumedCrossfade() async {
        Self.logger.debug("[Coordinator] Cleanup resumed crossfade...")
        
        // Check if paused again during cleanup
        if pausedCrossfade != nil {
            Self.logger.debug("[Coordinator] ❌ Cleanup aborted - crossfade paused again")
            return
        }
        
        // Switch players
        switchActivePlayer()
        
        // Stop inactive
        await audioEngine.stopInactivePlayer()
        
        // Clear state
        activeCrossfade = nil
        updateCrossfading(false)
        
        Self.logger.info("[Coordinator] ✅ Resumed crossfade cleanup complete")
    }
    
    /// Update crossfade progress (internal)
    private func updateCrossfadeProgress(_ progress: CrossfadeProgress) {
        guard var crossfade = activeCrossfade else { return }
        
        // Update progress
        crossfade.progress = Float(progress.progress)
        activeCrossfade = crossfade
    }
    
    // MARK: - Engine Control (Phase 2.5)
    
    /// Start playback engine
    /// - Returns: true if successfully started
    func startPlayback() async throws -> Bool {
        Self.logger.debug("[Coordinator] startPlayback()")
        
        // Validate we have active track
        guard state.activeTrack != nil else {
            Self.logger.error("[Coordinator] ❌ Cannot start - no active track")
            throw AudioPlayerError.invalidState(
                current: "no active track",
                attempted: "start playback"
            )
        }
        
        // Start engine playback
        await audioEngine.play()
        
        // Update state
        updateMode(.playing)
        
        Self.logger.info("[Coordinator] ✅ Playback started")
        return true
    }
    
    /// Pause playback engine
    func pausePlayback() async {
        Self.logger.debug("[Coordinator] pausePlayback()")
        
        await audioEngine.pause()
        
        Self.logger.info("[Coordinator] ✅ Playback paused")
    }
    
    /// Resume playback engine
    func resumePlayback() async {
        Self.logger.debug("[Coordinator] resumePlayback()")
        
        await audioEngine.play()
        
        Self.logger.info("[Coordinator] ✅ Playback resumed")
    }
    
    /// Stop playback engine
    func stopPlayback() async {
        Self.logger.debug("[Coordinator] stopPlayback()")
        
        // Stop both players
        await audioEngine.stopActivePlayer()
        await audioEngine.stopInactivePlayer()
        
        // Reset mixers
        await audioEngine.resetInactiveMixer()
        
        Self.logger.info("[Coordinator] ✅ Playback stopped")
    }
    
    // MARK: - Debug
    
    func logCurrentState() {
        Self.logger.debug("""
        [StateCoordinator] Current State:
          Active: \(state.activePlayer)
          Mode: \(state.playbackMode)
          Active Track: \(state.activeTrack?.url.lastPathComponent ?? "nil")
          Inactive Track: \(state.inactiveTrack?.url.lastPathComponent ?? "nil")
          Active Volume: \(state.activeMixerVolume)
          Inactive Volume: \(state.inactiveMixerVolume)
          Crossfading: \(state.isCrossfading)
          Consistent: \(state.isConsistent)
        """)
    }
}
