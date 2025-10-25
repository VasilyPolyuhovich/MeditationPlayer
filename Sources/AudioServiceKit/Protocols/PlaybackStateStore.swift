//
//  PlaybackStateStore.swift
//  AudioServiceKit
//
//  Protocol abstraction for playback state storage
//

import Foundation
import AudioServiceCore

/// Protocol for pure playback state storage and queries
///
/// Abstracts state management to enable dependency injection
/// and unit testing with mock implementations.
///
/// **Responsibility:** State storage ONLY (no engine control, no business logic)
/// **Dependencies:** NONE (zero dependencies for maximum testability)
protocol PlaybackStateStore: Actor {
    // MARK: - Queries

    /// Get current playback mode
    /// - Returns: Current player state
    func getPlaybackMode() -> PlayerState

    /// Get current active track
    /// - Returns: Active track or nil if none
    func getCurrentTrack() -> Track?

    /// Get active track
    /// - Returns: Active track or nil if none
    func getActiveTrack() -> Track?

    /// Get active track metadata
    /// - Returns: Track.Metadata or nil if none
    func getActiveTrackInfo() -> Track.Metadata?

    // Note: getActivePlayer() removed - internal detail not needed in protocol

    /// Check if crossfade is active
    /// - Returns: true if crossfading
    func isCrossfading() -> Bool

    /// Check if there's an active crossfade operation
    /// - Returns: true if crossfade state exists
    func hasActiveCrossfade() -> Bool

    /// Check if there's a paused crossfade
    /// - Returns: true if paused crossfade exists
    func hasPausedCrossfade() -> Bool

    // Note: getActiveCrossfadeOperation() removed - internal detail not needed in protocol

    // MARK: - Mutations

    /// Update playback mode atomically
    /// - Parameter mode: New playback mode
    /// - Throws: AudioPlayerError.invalidState if new state is inconsistent
    func updateMode(_ mode: PlayerState) throws

    /// Switch active/inactive players atomically
    func switchActivePlayer()

    /// Load track on inactive player atomically
    /// - Parameters:
    ///   - track: Track to load (with metadata filled)
    func loadTrackOnInactive(_ track: Track)

    /// Update mixer volumes atomically
    /// - Parameters:
    ///   - active: Active mixer volume (0.0-1.0)
    ///   - inactive: Inactive mixer volume (0.0-1.0)
    func updateMixerVolumes(active: Float, inactive: Float)

    /// Update crossfading flag atomically
    /// - Parameter crossfading: true if crossfade active
    func updateCrossfading(_ crossfading: Bool)

    /// Atomically switch to new track (combines load + switch)
    /// Use for pause + skip scenario
    /// - Parameters:
    ///   - newTrack: New track to load (with metadata filled)
    ///   - mode: Optional playback mode to set
    func atomicSwitch(newTrack: Track, mode: PlayerState?)

    // MARK: - Crossfade State Management

    /// Cancel active crossfade and cleanup
    func cancelActiveCrossfade() async

    /// Clear paused crossfade state
    func clearPausedCrossfade()

    // MARK: - Snapshot & Restore
    // Note: captureSnapshot/restoreSnapshot removed - internal detail not needed in protocol

    // MARK: - Validation

    /// Check if current state is consistent
    /// - Returns: true if state passes validation
    func isStateConsistent() -> Bool
}
