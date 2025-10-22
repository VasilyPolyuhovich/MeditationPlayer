//
//  AudioEngineControl.swift
//  AudioServiceKit
//
//  Protocol abstraction for audio engine operations
//

import Foundation
import AudioServiceCore

/// Protocol for audio engine lifecycle and playback control
///
/// Abstracts AVFoundation engine operations to enable dependency injection
/// and unit testing with mock implementations.
///
/// **Responsibility:** Hardware control only (no business logic)
protocol AudioEngineControl: Actor {
    // MARK: - Lifecycle

    /// Prepare audio engine (allocate resources)
    /// - Throws: AudioPlayerError if preparation fails
    func prepare() throws

    /// Start audio engine
    /// - Throws: AudioPlayerError if engine start fails
    func start() throws

    /// Stop audio engine
    func stop()

    // MARK: - Playback Control

    /// Pause both players (preserves position)
    func pause()

    /// Resume/start playback
    func play()

    /// Stop both players and reset
    func stopBothPlayers()

    /// Stop active player only
    func stopActivePlayer()

    /// Stop inactive player and clean up resources
    func stopInactivePlayer() async

    // MARK: - File Operations

    /// Load audio file on active player
    /// - Parameter url: Local file URL
    /// - Returns: Track information
    /// - Throws: AudioPlayerError if file cannot be loaded
    func loadAudioFile(url: URL) throws -> TrackInfo

    /// Load audio file on secondary (inactive) player
    /// - Parameter url: Local file URL
    /// - Returns: Track information
    /// - Throws: AudioPlayerError if file cannot be loaded
    func loadAudioFileOnSecondaryPlayer(url: URL) throws -> TrackInfo

    /// Schedule active file for playback with optional fade-in
    /// - Parameters:
    ///   - fadeIn: Whether to fade in from 0 volume
    ///   - fadeInDuration: Duration of fade-in
    ///   - fadeCurve: Curve type for fade
    func scheduleFile(fadeIn: Bool, fadeInDuration: TimeInterval, fadeCurve: FadeCurve)

    /// Prepare secondary player without starting playback
    func prepareSecondaryPlayer()

    /// Prepare loop on secondary player without starting playback
    func prepareLoopOnSecondaryPlayer()

    // MARK: - Position & Seeking

    /// Get current playback position
    /// - Returns: PlaybackPosition with current time and duration, or nil if no file loaded
    func getCurrentPosition() -> PlaybackPosition?

    /// Seek to specific time
    /// - Parameter time: Target time in seconds
    /// - Throws: AudioPlayerError if seek fails or no file loaded
    func seek(to time: TimeInterval) throws

    // MARK: - Volume Control

    /// Set global volume (target volume for all operations)
    /// - Parameter volume: Volume level (0.0-1.0)
    func setVolume(_ volume: Float)

    /// Get target volume level
    /// - Returns: Current target volume (0.0-1.0)
    func getTargetVolume() -> Float

    /// Get active mixer current volume
    /// - Returns: Active mixer volume (0.0-1.0)
    func getActiveMixerVolume() -> Float

    /// Fade active mixer volume
    /// - Parameters:
    ///   - from: Start volume (0.0-1.0)
    ///   - to: End volume (0.0-1.0)
    ///   - duration: Fade duration in seconds
    ///   - curve: Fade curve type
    func fadeActiveMixer(from: Float, to: Float, duration: TimeInterval, curve: FadeCurve) async

    /// Reset inactive mixer volume to 0
    func resetInactiveMixer()

    // MARK: - Player Switching

    /// Switch active/inactive players (after crossfade)
    func switchActivePlayer()

    /// Switch players and set new active mixer to full volume
    /// Use for non-crossfade scenarios (pause + skip)
    func switchActivePlayerWithVolume()

    // MARK: - Crossfade Operations

    /// Perform synchronized crossfade between players
    /// - Parameters:
    ///   - duration: Crossfade duration in seconds
    ///   - curve: Fade curve type
    /// - Returns: AsyncStream with progress updates
    func performSynchronizedCrossfade(duration: TimeInterval, curve: FadeCurve) async -> AsyncStream<CrossfadeProgress>

    /// Cancel active crossfade operation
    func cancelActiveCrossfade()

    /// Cancel crossfade and stop inactive player
    func cancelCrossfadeAndStopInactive() async

    /// Rollback crossfade transaction
    /// - Parameter rollbackDuration: Duration to restore active volume
    /// - Returns: Current active mixer volume before rollback
    func rollbackCrossfade(rollbackDuration: TimeInterval) async -> Float

    /// Check if crossfade is active
    var isCrossfading: Bool { get }

    // MARK: - Crossfade Pause/Resume

    /// Get current crossfade state for pausing
    /// - Returns: CrossfadeState snapshot or nil if not crossfading
    func getCrossfadeState() -> AudioEngineActor.CrossfadeState?

    /// Pause both players during crossfade
    func pauseBothPlayersDuringCrossfade()

    /// Resume crossfade from paused state
    /// - Parameters:
    ///   - duration: Remaining crossfade duration
    ///   - curve: Fade curve
    ///   - startVolumes: Starting volumes for resume
    /// - Returns: AsyncStream with progress updates
    func resumeCrossfadeFromState(
        duration: TimeInterval,
        curve: FadeCurve,
        startVolumes: (active: Float, inactive: Float)
    ) async -> AsyncStream<CrossfadeProgress>

    // MARK: - State Queries

    /// Check if active player is playing
    /// - Returns: true if active player is playing
    func isActivePlayerPlaying() -> Bool

    /// Clear inactive file reference (free memory)
    func clearInactiveFile()

    // MARK: - Reset

    /// Full reset - clear all state
    func fullReset() async

    /// Reset engine running state after media services crash
    func resetEngineRunningState()
}
