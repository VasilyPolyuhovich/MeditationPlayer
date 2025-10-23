//
//  CrossfadeOrchestrating.swift
//  AudioServiceKit
//
//  Protocol abstraction for crossfade orchestration
//

import Foundation
import AudioServiceCore

/// Result of crossfade operation
public enum CrossfadeResult: Sendable {
    case completed  // Crossfade finished successfully
    case paused     // Crossfade was paused mid-execution
    case cancelled  // Crossfade was cancelled
}

/// Crossfade operation type
public enum CrossfadeOperation: Sendable {
    case automaticLoop   // Triggered by playback position reaching near-end
    case manualChange    // Triggered by user API calls (replaceTrack, skipTo*, etc.)
}

/// Protocol for crossfade orchestration
///
/// Defines high-level crossfade operations that coordinate audio engine
/// and state management for seamless track transitions.
///
/// **Responsibility:** Crossfade logic ONLY
/// - Coordinates engine dual-player crossfade
/// - Manages crossfade state (active/paused)
/// - Handles pause/resume/cancel scenarios
protocol CrossfadeOrchestrating: Actor {
    /// Start crossfade from active track to new track
    /// - Parameters:
    ///   - track: Target track to crossfade to (metadata will be filled during load)
    ///   - duration: Crossfade duration in seconds
    ///   - curve: Fade curve (equalPower, linear, etc.)
    ///   - operation: Operation type (automatic loop or manual change)
    /// - Returns: CrossfadeResult indicating completion status
    /// - Throws: AudioPlayerError if crossfade fails
    func startCrossfade(
        to track: Track,
        duration: TimeInterval,
        curve: FadeCurve,
        operation: CrossfadeOperation
    ) async throws -> CrossfadeResult

    /// Pause active crossfade (captures current state)
    /// - Returns: Paused state snapshot or nil if no active crossfade
    /// - Throws: AudioPlayerError if pause fails
    func pauseCrossfade() async throws -> PausedCrossfadeSnapshot?

    /// Resume paused crossfade (restores captured state)
    /// - Returns: true if resumed, false if no paused crossfade
    /// - Throws: AudioPlayerError if resume fails
    func resumeCrossfade() async throws -> Bool

    /// Cancel active crossfade and rollback smoothly
    func cancelActiveCrossfade() async

    /// Clear paused crossfade state
    func clearPausedCrossfade()

    /// Check if crossfade is currently active
    /// - Returns: true if crossfade in progress
    func hasActiveCrossfade() -> Bool

    /// Check if crossfade is paused
    /// - Returns: true if paused crossfade exists
    func hasPausedCrossfade() -> Bool
}

/// Paused crossfade snapshot (simplified for protocol)
public struct PausedCrossfadeSnapshot: Sendable {
    public let timestamp: Date
    public let fromTrack: Track
    public let toTrack: Track
    public let duration: TimeInterval
    public let curve: FadeCurve
}
