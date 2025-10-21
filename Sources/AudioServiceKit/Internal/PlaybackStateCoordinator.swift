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
    
    /// Player node identifier
    enum PlayerNode {
        case a
        case b
        
        var opposite: PlayerNode {
            return self == .a ? .b : .a
        }
    }
    
    /// Playback mode
    enum PlaybackMode {
        case playing
        case paused
        case stopped
    }
    
    /// Complete player state - immutable snapshot
    struct PlayerState {
        let activePlayer: PlayerNode
        let playbackMode: PlaybackMode
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
        
        func withMode(_ mode: PlaybackMode) -> PlayerState {
            PlayerState(
                activePlayer: activePlayer,
                playbackMode: mode,
                activeTrack: activeTrack,
                inactiveTrack: inactiveTrack,
                activeMixerVolume: activeMixerVolume,
                inactiveMixerVolume: inactiveMixerVolume,
                isCrossfading: isCrossfading
            )
        }
        
        func withActiveTrack(_ track: Track?) -> PlayerState {
            PlayerState(
                activePlayer: activePlayer,
                playbackMode: playbackMode,
                activeTrack: track,
                inactiveTrack: inactiveTrack,
                activeMixerVolume: activeMixerVolume,
                inactiveMixerVolume: inactiveMixerVolume,
                isCrossfading: isCrossfading
            )
        }
        
        func withInactiveTrack(_ track: Track?) -> PlayerState {
            PlayerState(
                activePlayer: activePlayer,
                playbackMode: playbackMode,
                activeTrack: activeTrack,
                inactiveTrack: track,
                activeMixerVolume: activeMixerVolume,
                inactiveMixerVolume: inactiveMixerVolume,
                isCrossfading: isCrossfading
            )
        }
        
        func withMixerVolumes(active: Float, inactive: Float) -> PlayerState {
            PlayerState(
                activePlayer: activePlayer,
                playbackMode: playbackMode,
                activeTrack: activeTrack,
                inactiveTrack: inactiveTrack,
                activeMixerVolume: active,
                inactiveMixerVolume: inactive,
                isCrossfading: isCrossfading
            )
        }
        
        func withCrossfading(_ crossfading: Bool) -> PlayerState {
            PlayerState(
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
    
    // MARK: - State (SINGLE SOURCE OF TRUTH)
    
    /// Current player state - READ ONLY from outside
    private(set) var state: PlayerState
    
    // MARK: - Dependencies
    
    private let audioEngine: AudioEngineActor
    
    // MARK: - Logging
    
    private static let logger = Logger.audio
    
    // MARK: - Init
    
    init(audioEngine: AudioEngineActor) {
        self.audioEngine = audioEngine
        self.state = PlayerState(
            activePlayer: .a,
            playbackMode: .stopped,
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
        let newState = PlayerState(
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
    func updateMode(_ mode: PlaybackMode) {
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
    func atomicSwitch(newTrack: Track, preserveMode: Bool = true) {
        Self.logger.debug("[StateCoordinator] → atomicSwitch(\(newTrack.url.lastPathComponent))")
        
        let mode = preserveMode ? state.playbackMode : .playing
        
        // Create new state with switched player and new track
        let newState = PlayerState(
            activePlayer: state.activePlayer.opposite,
            playbackMode: mode,
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
    
    func getPlaybackMode() -> PlaybackMode {
        return state.playbackMode
    }
    
    func getActivePlayer() -> PlayerNode {
        return state.activePlayer
    }
    
    func isCrossfading() -> Bool {
        return state.isCrossfading
    }
    
    /// Capture complete state snapshot (for crossfade pause/resume)
    func captureSnapshot() -> PlayerState {
        return state
    }
    
    /// Restore state snapshot (for crossfade resume)
    func restoreSnapshot(_ snapshot: PlayerState) {
        Self.logger.debug("[StateCoordinator] → restoreSnapshot()")
        
        guard snapshot.isConsistent else {
            Self.logger.error("[StateCoordinator] ❌ Cannot restore invalid snapshot")
            return
        }
        
        state = snapshot
        Self.logger.info("[StateCoordinator] ✅ Snapshot restored")
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
