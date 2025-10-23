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
    
    /// Complete coordinator state - immutable snapshot
    struct CoordinatorState {
        let activePlayer: PlayerNode
        let playbackMode: PlayerState
        let activeTrack: Track?
        let activeTrackInfo: TrackInfo?
        let inactiveTrack: Track?
        let inactiveTrackInfo: TrackInfo?
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
                activeTrackInfo: activeTrackInfo,
                inactiveTrack: inactiveTrack,
                inactiveTrackInfo: inactiveTrackInfo,
                activeMixerVolume: activeMixerVolume,
                inactiveMixerVolume: inactiveMixerVolume,
                isCrossfading: isCrossfading
            )
        }
        
        func withActiveTrack(_ track: Track?, info: TrackInfo? = nil) -> CoordinatorState {
            CoordinatorState(
                activePlayer: activePlayer,
                playbackMode: playbackMode,
                activeTrack: track,
                activeTrackInfo: info,
                inactiveTrack: inactiveTrack,
                inactiveTrackInfo: inactiveTrackInfo,
                activeMixerVolume: activeMixerVolume,
                inactiveMixerVolume: inactiveMixerVolume,
                isCrossfading: isCrossfading
            )
        }
        
        func withInactiveTrack(_ track: Track?, info: TrackInfo? = nil) -> CoordinatorState {
            CoordinatorState(
                activePlayer: activePlayer,
                playbackMode: playbackMode,
                activeTrack: activeTrack,
                activeTrackInfo: activeTrackInfo,
                inactiveTrack: track,
                inactiveTrackInfo: info,
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
                activeTrackInfo: activeTrackInfo,
                inactiveTrack: inactiveTrack,
                inactiveTrackInfo: inactiveTrackInfo,
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
                activeTrackInfo: activeTrackInfo,
                inactiveTrack: inactiveTrack,
                inactiveTrackInfo: inactiveTrackInfo,
                activeMixerVolume: activeMixerVolume,
                inactiveMixerVolume: inactiveMixerVolume,
                isCrossfading: crossfading
            )
        }
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
    func switchActivePlayer() {
        Self.logger.debug("[StateCoordinator] → switchActivePlayer()")
        
        // Create new state with swapped players
        let newState = CoordinatorState(
            activePlayer: state.activePlayer.opposite,
            playbackMode: state.playbackMode,
            activeTrack: state.inactiveTrack,  // Swap tracks
            activeTrackInfo: state.inactiveTrackInfo,
            inactiveTrack: state.activeTrack,
            inactiveTrackInfo: state.activeTrackInfo,
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
    func loadTrackOnInactive(_ track: Track, info: TrackInfo? = nil) {
        Self.logger.debug("[StateCoordinator] → loadTrackOnInactive(\(track.url.lastPathComponent))")
        
        let newState = state.withInactiveTrack(track, info: info)
        
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
    func atomicSwitch(newTrack: Track, trackInfo: TrackInfo? = nil, mode: PlayerState? = nil) {
        Self.logger.debug("[StateCoordinator] → atomicSwitch(\(newTrack.url.lastPathComponent))")
        
        let targetMode = mode ?? state.playbackMode
        
        // Create new state with switched player and new track
        let newState = CoordinatorState(
            activePlayer: state.activePlayer.opposite,
            playbackMode: targetMode,
            activeTrack: newTrack,  // New track becomes active
            activeTrackInfo: trackInfo,
            inactiveTrack: state.activeTrack,  // Old active becomes inactive
            inactiveTrackInfo: state.activeTrackInfo,
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
    /// Note: Delegated to CrossfadeOrchestrator (temporary stub)
    func hasActiveCrossfade() -> Bool {
        return false // TODO: Delegate to CrossfadeOrchestrator
    }
    
    /// Get current active track
    func getActiveTrack() -> Track? {
        return state.activeTrack
    }
    
    /// Get current active track info
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
    func clearPausedCrossfade() {
        // TODO: Delegate to CrossfadeOrchestrator
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

// MARK: - PlaybackStateStore Conformance

extension PlaybackStateCoordinator: PlaybackStateStore {
    // ✅ Already conforms to all protocol requirements
    // All query and mutation methods are implemented in the main actor body
    // Note: captureSnapshot/restoreSnapshot removed from protocol (internal detail)

    func isStateConsistent() -> Bool {
        return state.isConsistent
    }
}
