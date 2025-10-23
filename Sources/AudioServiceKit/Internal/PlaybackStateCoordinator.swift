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
    // Note: CrossfadeOperation, CrossfadeResult moved to CrossfadeOrchestrating protocol
    
    /// Player node identifier
    enum PlayerNode {
        case a
        case b
        
        var opposite: PlayerNode {
            return self == .a ? .b : .a
        }
    }
    
    // Use PlayerState from AudioServiceCore instead of custom enum
    
    /// Complete coordinator state - value type for atomic updates
    ///
    /// **Design Decision (Phase 2C):**
    /// Originally used `let` fields + verbose `withMode()`/`withActiveTrack()` helpers (150+ LOC boilerplate).
    /// This created maintenance burden (9 fields × 5 helpers = 45 field copies to maintain).
    ///
    /// **Why the pattern existed:**
    /// - Transaction-style updates: `let newState = state.withMode(mode)` → validate → `state = newState`
    /// - Rollback safety: if validation fails, old state stays unchanged
    /// - Actor isolation: `state = newState` is atomic reassignment
    ///
    /// **Simplified approach (Variant C - Hybrid):**
    /// - Changed to `var` fields (still value type, still immutable from outside)
    /// - Use Swift idiomatic pattern: `var newState = state; newState.field = value`
    /// - **Same safety guarantees** (transaction/validation/rollback)
    /// - **-150 LOC** (removed all verbose helpers)
    ///
    struct CoordinatorState {
        var activePlayer: PlayerNode
        var playbackMode: PlayerState
        var activeTrack: Track?
        var activeTrackInfo: TrackInfo?
        var inactiveTrack: Track?
        var inactiveTrackInfo: TrackInfo?
        var activeMixerVolume: Float
        var inactiveMixerVolume: Float
        var isCrossfading: Bool
        
        /// Validate state consistency
        /// VALIDATION RULES:
        /// 1. Playing mode requires active track
        /// 2. Mixer volumes in range [0.0...1.0]
        var isConsistent: Bool {
            // Rule 1: Playing mode requires active track
            if playbackMode == .playing && activeTrack == nil {
                Logger.audio.error("[StateCoordinator] Invalid: playing mode but no track")
                return false
            }
            
            // Rule 2: Mixer volumes must be in valid range [0.0...1.0]
            guard (0.0...1.0).contains(activeMixerVolume) else {
                Logger.audio.error("[StateCoordinator] Invalid active mixer volume: \(activeMixerVolume)")
                return false
            }
            
            guard (0.0...1.0).contains(inactiveMixerVolume) else {
                Logger.audio.error("[StateCoordinator] Invalid inactive mixer volume: \(inactiveMixerVolume)")
                return false
            }
            
            // Note: Rule 3 ("inactive mixer = 0 when not crossfading") REMOVED
            // Reason: False assumption - inactive can have volume when preparing for crossfade
            // Example: skip backward loads previous track on inactive with non-zero volume
            
            return true
        }
        
        // MARK: - Historical Note: Verbose Helpers Removed
        //
        // **Original Pattern (150+ LOC):**
        // func withMode(_ mode: PlayerState) -> CoordinatorState {
        //     CoordinatorState(
        //         activePlayer: activePlayer,        // copy
        //         playbackMode: mode,                // NEW
        //         activeTrack: activeTrack,          // copy
        //         activeTrackInfo: activeTrackInfo,  // copy
        //         inactiveTrack: inactiveTrack,      // copy
        //         inactiveTrackInfo: inactiveTrackInfo, // copy
        //         activeMixerVolume: activeMixerVolume, // copy
        //         inactiveMixerVolume: inactiveMixerVolume, // copy
        //         isCrossfading: isCrossfading       // copy
        //     )
        // }
        // ... + 4 more identical helpers (withActiveTrack, withInactiveTrack, etc.)
        //
        // **Why removed:**
        // - Maintenance burden: adding new field → update ALL 5 helpers
        // - Verbose: 9 fields × 5 helpers = 45 manual copies
        // - Unnecessary: Swift idiom is simpler: `var newState = state; newState.field = value`
        //
        // **Current Pattern (Phase 2C - Variant C):**
        // Use direct mutation on copied struct:
        //   var newState = state
        //   newState.playbackMode = mode
        //   guard newState.isConsistent else { return }
        //   state = newState
        //
        // Same safety (transaction/validation/rollback), -150 LOC, easier maintenance.
    }
    
    // MARK: - Crossfade State
    // Note: ActiveCrossfadeState, PausedCrossfadeState moved to CrossfadeOrchestrator
    
    // MARK: - State (SINGLE SOURCE OF TRUTH)
    
    /// Current coordinator state - READ ONLY from outside
    private(set) var state: CoordinatorState
    
    // Note: Crossfade state moved to CrossfadeOrchestrator
    
    // MARK: - Dependencies
    // Note: audioEngine removed - crossfade logic moved to CrossfadeOrchestrator
    
    // MARK: - Logging
    
    private static let logger = Logger.audio
    
    // MARK: - Init
    
    init() {
        // Note: audioEngine parameter removed
        self.state = CoordinatorState(
            activePlayer: .a,
            playbackMode: .finished,
            activeTrack: nil,
            activeTrackInfo: nil,
            inactiveTrack: nil,
            inactiveTrackInfo: nil,
            activeMixerVolume: 1.0,
            inactiveMixerVolume: 0.0,
            isCrossfading: false
        )
        
        Self.logger.info("[StateCoordinator] ✅ Initialized with default state")
    }
    
    // MARK: - Atomic Operations
    
    /// Atomically switch active player (no suspend points)
    /// USE CASE: After crossfade completes (REQUIREMENTS_ANSWERS.md: 3-stage meditation)
    func switchActivePlayer() {
        Self.logger.debug("[StateCoordinator] → switchActivePlayer()")
        
        // Create new state with swapped players (Variant C pattern)
        var newState = state
        newState.activePlayer = state.activePlayer.opposite
        newState.activeTrack = state.inactiveTrack
        newState.activeTrackInfo = state.inactiveTrackInfo
        newState.inactiveTrack = state.activeTrack
        newState.inactiveTrackInfo = state.activeTrackInfo
        newState.activeMixerVolume = state.inactiveMixerVolume
        newState.inactiveMixerVolume = state.activeMixerVolume
        
        // Validate and apply
        guard newState.isConsistent else {
            Self.logger.error("[StateCoordinator] ❌ Invalid state after switch - rollback")
            return
        }
        
        state = newState
        Self.logger.debug("[StateCoordinator] ✅ Switched to player \(state.activePlayer)")
    }
    
    /// Atomically update playback mode
    /// USE CASE: play/pause/stop transitions (REQUIREMENTS: daily morning pauses)
    func updateMode(_ mode: PlayerState) {
        Self.logger.debug("[StateCoordinator] → updateMode(\(mode))")
        
        // Update mode (Variant C pattern)
        var newState = state
        newState.playbackMode = mode
        
        // Validate and apply
        guard newState.isConsistent else {
            Self.logger.error("[StateCoordinator] ❌ Invalid state for mode \(mode) - rollback")
            return
        }
        
        state = newState
        Self.logger.debug("[StateCoordinator] ✅ Mode updated to \(mode)")
    }
    
    /// Atomically load track on inactive player
    /// USE CASE: Prepare next track during crossfade (REQUIREMENTS: seamless loops)
    func loadTrackOnInactive(_ track: Track, info: TrackInfo? = nil) {
        Self.logger.debug("[StateCoordinator] → loadTrackOnInactive(\(track.url.lastPathComponent))")
        
        // Update inactive track (Variant C pattern)
        var newState = state
        newState.inactiveTrack = track
        newState.inactiveTrackInfo = info
        
        // Validate and apply
        guard newState.isConsistent else {
            Self.logger.error("[StateCoordinator] ❌ Invalid state after loading track - rollback")
            return
        }
        
        state = newState
        Self.logger.debug("[StateCoordinator] ✅ Track loaded on inactive player")
    }
    
    /// Atomically update mixer volumes
    /// USE CASE: Crossfade progress (REQUIREMENTS: 5-15s crossfade duration)
    func updateMixerVolumes(active: Float, inactive: Float) {
        // Update volumes (Variant C pattern)
        var newState = state
        newState.activeMixerVolume = active
        newState.inactiveMixerVolume = inactive
        
        // Validate and apply
        guard newState.isConsistent else {
            Self.logger.error("[StateCoordinator] ❌ Invalid mixer volumes - rollback")
            return
        }
        
        state = newState
    }
    
    /// Atomically update crossfading flag
    /// USE CASE: Mark crossfade start/end (REQUIREMENTS: pause during crossfade ~10%)
    func updateCrossfading(_ crossfading: Bool) {
        // Update crossfading flag (Variant C pattern)
        var newState = state
        newState.isCrossfading = crossfading
        
        // Validate and apply
        guard newState.isConsistent else {
            Self.logger.error("[StateCoordinator] ❌ Invalid crossfading state - rollback")
            return
        }
        
        state = newState
        Self.logger.debug("[StateCoordinator] ✅ Crossfading = \(crossfading)")
    }
    
    /// Atomically switch to new track (combines load + switch)
    /// USE CASE: Pause + skip scenario (REQUIREMENTS: skip during pause without crossfade)
    func atomicSwitch(newTrack: Track, trackInfo: TrackInfo? = nil, mode: PlayerState? = nil) {
        Self.logger.debug("[StateCoordinator] → atomicSwitch(\(newTrack.url.lastPathComponent))")
        
        // Create new state with immediate track switch (Variant C pattern)
        var newState = state
        newState.activePlayer = state.activePlayer.opposite
        newState.activeTrack = newTrack
        newState.activeTrackInfo = trackInfo
        newState.inactiveTrack = state.activeTrack
        newState.inactiveTrackInfo = state.activeTrackInfo
        
        // Update mode if specified
        if let mode = mode {
            newState.playbackMode = mode
        }
        
        // Reset volumes for new track
        newState.activeMixerVolume = 1.0
        newState.inactiveMixerVolume = 0.0
        newState.isCrossfading = false
        
        // Validate and apply
        guard newState.isConsistent else {
            Self.logger.error("[StateCoordinator] ❌ Invalid state after atomic switch - rollback")
            return
        }
        
        state = newState
        Self.logger.info("[StateCoordinator] ✅ Atomic switch to \(newTrack.url.lastPathComponent) on player \(state.activePlayer)")
    }
    
    // MARK: - State Queries
    
    /// Get current active track
    /// USE CASE: Display current track in UI (all stages)
    func getCurrentTrack() -> Track? {
        return state.activeTrack
    }
    
    /// Get current playback mode
    /// USE CASE: UI state sync, validation before operations
    func getPlaybackMode() -> PlayerState {
        return state.playbackMode
    }
    
    /// Get active player node (A or B)
    /// USE CASE: Engine queries which player is active
    func getActivePlayer() -> PlayerNode {
        return state.activePlayer
    }
    
    /// Check if crossfade is in progress
    /// USE CASE: Prevent operations during crossfade
    func isCrossfading() -> Bool {
        return state.isCrossfading
    }
    
    /// Check if there's an active crossfade operation
    /// Note: Delegated to CrossfadeOrchestrator (temporary stub)
    func hasActiveCrossfade() -> Bool {
        return false // TODO: Delegate to CrossfadeOrchestrator
    }
    
    /// Get current active track (duplicate of getCurrentTrack?)
    /// ⚠️ NOTE: This is duplicate of getCurrentTrack() - see SKELETON_VALIDATION_REPORT.md
    /// Keeping for backward compatibility, consider removing in future cleanup
    func getActiveTrack() -> Track? {
        return state.activeTrack
    }
    
    /// Get current active track metadata
    /// USE CASE: Display duration, title in UI
    func getActiveTrackInfo() -> TrackInfo? {
        return state.activeTrackInfo
    }
    
    /// Check if there's a paused crossfade
    /// Note: Delegated to CrossfadeOrchestrator (temporary stub)
    func hasPausedCrossfade() -> Bool {
        return false // TODO: Delegate to CrossfadeOrchestrator
    }
    
    // Note: getActiveCrossfadeOperation removed - moved to CrossfadeOrchestrator
    
    /// Cancel active crossfade and cleanup
    /// Note: Delegated to CrossfadeOrchestrator (temporary stub)
    func cancelActiveCrossfade() async {
        // TODO: Delegate to CrossfadeOrchestrator
    }
    
    /// Clear paused crossfade state
    /// Note: Delegated to CrossfadeOrchestrator (temporary stub)
    /// This is a placeholder - actual logic is in CrossfadeOrchestrator
    func clearPausedCrossfade() {
        // Nothing to do here - CrossfadeOrchestrator owns paused state
        Self.logger.debug("[StateCoordinator] clearPausedCrossfade() - delegated to CrossfadeOrchestrator")
    }
    
    /// Capture complete state snapshot
    /// USE CASE: Save state before risky operation (rollback capability)
    func captureSnapshot() -> CoordinatorState {
        // Return copy of current state (struct = value type = automatic copy)
        return state
    }
    
    /// Restore state snapshot
    /// USE CASE: Rollback after failed operation
    func restoreSnapshot(_ snapshot: CoordinatorState) {
        Self.logger.debug("[StateCoordinator] → restoreSnapshot()")
        
        // Validate snapshot before restoring
        guard snapshot.isConsistent else {
            Self.logger.error("[StateCoordinator] ❌ Cannot restore inconsistent snapshot")
            return
        }
        
        // Restore state (atomic reassignment)
        state = snapshot
        Self.logger.info("[StateCoordinator] ✅ State restored from snapshot")
    }
    
    // MARK: - Crossfade Operations

    // MARK: - Crossfade Operations (Moved to CrossfadeOrchestrator)
    //
    // All crossfade logic has been extracted to CrossfadeOrchestrator actor:
    // - startCrossfade() → CrossfadeOrchestrator.startCrossfade()
    // - pauseCrossfade() → CrossfadeOrchestrator.pauseCrossfade()
    // - resumeCrossfade() → CrossfadeOrchestrator.resumeCrossfade()
    // - rollbackCurrentCrossfade() → CrossfadeOrchestrator (private)
    // - updateCrossfadeProgress() → CrossfadeOrchestrator (private)
    // - cleanupResumedCrossfade() → CrossfadeOrchestrator.quickFinishCrossfade()
    //
    // PlaybackStateCoordinator is now pure state storage (PlaybackStateStore)
    // and no longer depends on AudioEngineActor

    
    // MARK: - Engine Control (Phase 2.5)
    
    /// Start playback engine
    /// - Returns: true if successfully started
    // REMOVED: Engine control methods moved to PlaybackOrchestrator
    // - startPlayback() → orchestrator handles engine.play() + state update
    // - pausePlayback() → orchestrator handles engine.pause()
    // - resumePlayback() → orchestrator handles engine.play()
    // - stopPlayback() → orchestrator handles engine.stop()
    //
    // StateStore responsibility: ONLY state storage, NO engine control
    
    // MARK: - Debug
    
    /// Debug: Log complete state
    /// USE CASE: Debugging state issues
    func logCurrentState() {
        Self.logger.debug("""
        [StateCoordinator] Current State:
          - Active Player: \(state.activePlayer)
          - Playback Mode: \(state.playbackMode)
          - Active Track: \(state.activeTrack?.url.lastPathComponent ?? "none")
          - Inactive Track: \(state.inactiveTrack?.url.lastPathComponent ?? "none")
          - Active Volume: \(state.activeMixerVolume)
          - Inactive Volume: \(state.inactiveMixerVolume)
          - Crossfading: \(state.isCrossfading)
        """)
    }
}

// MARK: - PlaybackStateStore Conformance

extension PlaybackStateCoordinator: PlaybackStateStore {
    // ✅ Already conforms to all protocol requirements
    // All query and mutation methods are implemented in the main actor body
    // Note: captureSnapshot/restoreSnapshot removed from protocol (internal detail)

    /// Validate state consistency
    /// USE CASE: Post-operation validation (PlaybackStateStore protocol)
    func isStateConsistent() -> Bool {
        return state.isConsistent
    }
}
