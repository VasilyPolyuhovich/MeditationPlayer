//
//  PlaybackOrchestrator.swift
//  AudioServiceKit
//
//  Orchestrates multi-step playback flows with protocol dependencies
//

import Foundation
import OSLog
import AudioServiceCore

/// Protocol for playback orchestration
///
/// Defines high-level playback operations that coordinate multiple
/// subsystems (state, engine, session, playlist, etc.)
protocol PlaybackOrchestrating: Actor {
    /// Start playing with optional fade-in
    /// - Parameter fadeDuration: Fade-in duration in seconds (0 = no fade)
    /// - Throws: AudioPlayerError if operation fails
    func startPlaying(fadeDuration: TimeInterval) async throws

    /// Pause playback
    /// - Throws: AudioPlayerError if invalid state
    func pause() async throws

    /// Resume playback from pause
    /// - Throws: AudioPlayerError if invalid state
    func resume() async throws

    /// Stop playback with optional fade-out
    /// - Parameter fadeDuration: Fade-out duration in seconds (0 = no fade)
    func stop(fadeDuration: TimeInterval) async

    /// Get current playback state
    /// - Returns: Current PlayerState
    func getCurrentState() async -> PlayerState
}

/// Actor orchestrating playback business logic
///
/// **Responsibility:** Multi-step flow orchestration ONLY
/// - Coordinates: State, Engine, Session, Playlist, Timer, RemoteCommands
/// - No direct hardware access
/// - No state storage (delegates to StateStore)
///
/// **Swift Concurrency:**
/// - Uses Task for cancellable operations
/// - Task.checkCancellation() for early exit
/// - Actor isolation for thread safety
actor PlaybackOrchestrator: PlaybackOrchestrating {
    // MARK: - Dependencies (Protocol-based for DIP)

    private let stateStore: PlaybackStateStore
    private let engineControl: AudioEngineControl
    private let sessionManager: AudioSessionManaging
    // Note: PlaylistManager and TimerManager will be added later
    // For now, we'll work with what exists in AudioPlayerService

    // MARK: - Active Operation Tracking

    /// Currently running operation (for cancellation)
    private var activeOperation: Task<Void, Error>?

    // MARK: - Logging

    private static let logger = Logger(category: "PlaybackOrchestrator")

    // MARK: - Initialization

    init(
        stateStore: PlaybackStateStore,
        engineControl: AudioEngineControl,
        sessionManager: AudioSessionManaging
    ) {
        self.stateStore = stateStore
        self.engineControl = engineControl
        self.sessionManager = sessionManager

        Self.logger.info("[Orchestrator] ✅ Initialized with protocol dependencies")
    }

    // MARK: - Public API Implementation

    /// Start playing a specific track
    /// - Parameters:
    ///   - track: Track to play
    ///   - fadeDuration: Fade-in duration (0 = no fade)
    /// - Throws: AudioPlayerError if operation fails
    func startPlaying(track: Track, fadeDuration: TimeInterval) async throws {
        Self.logger.debug("[Orchestrator] → startPlaying(track: \(track.url.lastPathComponent), fade: \(fadeDuration)s)")

        // Cancel any active operation
        activeOperation?.cancel()

        // Create new cancellable operation
        activeOperation = Task {
            // 1. Activate audio session
            do {
                try await sessionManager.activate()
                Self.logger.debug("[Orchestrator] ✅ Audio session activated")
            } catch {
                Self.logger.error("[Orchestrator] ❌ Failed to activate session: \(error)")
                throw AudioPlayerError.sessionConfigurationFailed(
                    reason: "Failed to activate: \(error.localizedDescription)"
                )
            }

            // Check cancellation after async call
            try Task.checkCancellation()

            // 2. Prepare audio engine
            do {
                try await engineControl.prepare()
                Self.logger.debug("[Orchestrator] ✅ Engine prepared")
            } catch {
                Self.logger.error("[Orchestrator] ❌ Failed to prepare engine: \(error)")
                throw AudioPlayerError.engineStartFailed(
                    reason: "Failed to prepare: \(error.localizedDescription)"
                )
            }

            // Check cancellation
            try Task.checkCancellation()

            // 3. Load audio file
            let trackInfo = try await engineControl.loadAudioFile(url: track.url)
            Self.logger.debug("[Orchestrator] ✅ File loaded: \(trackInfo.title)")

            // 4. Update state BEFORE starting playback
            await stateStore.atomicSwitch(newTrack: track, trackInfo: trackInfo, mode: .preparing)
            Self.logger.debug("[Orchestrator] ✅ State: preparing")

            // Check cancellation
            try Task.checkCancellation()

            // 5. Start audio engine
            try await engineControl.start()
            Self.logger.debug("[Orchestrator] ✅ Engine started")

            // 6. Schedule file with optional fade-in
            await engineControl.scheduleFile(
                fadeIn: fadeDuration > 0,
                fadeInDuration: fadeDuration,
                fadeCurve: .equalPower
            )
            Self.logger.debug("[Orchestrator] ✅ File scheduled (fade: \(fadeDuration > 0))")

            // 7. Start playback
            await engineControl.play()
            Self.logger.debug("[Orchestrator] ✅ Playback started")

            // 8. Update state AFTER successful start
            await stateStore.updateMode(.playing)
            Self.logger.info("[Orchestrator] ✅ Playing: \(track.url.lastPathComponent)")

            // TODO: Start timer (Step 2.6 - add TimerManager dependency)
        }

        // Await operation completion (propagates any errors)
        try await activeOperation?.value
    }

    /// Convenience wrapper for existing API compatibility
    func startPlaying(fadeDuration: TimeInterval) async throws {
        // This will be implemented after we add PlaylistManager dependency
        // For now, throw an error
        throw AudioPlayerError.emptyPlaylist
    }

    func pause() async throws {
        Self.logger.debug("[Orchestrator] → pause()")

        // 1. Validate current state
        let currentState = await stateStore.getPlaybackMode()
        guard currentState == .playing || currentState == .preparing else {
            // Already paused - idempotent operation
            if currentState == .paused {
                Self.logger.debug("[Orchestrator] Already paused - no-op")
                return
            }
            Self.logger.error("[Orchestrator] ❌ Invalid state for pause: \(currentState)")
            throw AudioPlayerError.invalidState(
                current: currentState.description,
                attempted: "pause"
            )
        }

        // 2. Pause engine (captures position internally)
        await engineControl.pause()
        Self.logger.debug("[Orchestrator] ✅ Engine paused")

        // 3. Update state ONLY after success
        await stateStore.updateMode(.paused)
        Self.logger.info("[Orchestrator] ✅ Paused")

        // TODO: Stop timer (Step 2.6 - add TimerManager dependency)
    }

    func resume() async throws {
        Self.logger.debug("[Orchestrator] → resume()")

        // 1. Validate current state
        let currentState = await stateStore.getPlaybackMode()
        guard currentState == .paused else {
            // Already playing - idempotent operation
            if currentState == .playing {
                Self.logger.debug("[Orchestrator] Already playing - no-op")
                return
            }
            Self.logger.error("[Orchestrator] ❌ Invalid state for resume: \(currentState)")
            throw AudioPlayerError.invalidState(
                current: currentState.description,
                attempted: "resume"
            )
        }

        // 2. Ensure audio session is active
        do {
            try await sessionManager.ensureActive()
            Self.logger.debug("[Orchestrator] ✅ Session ensured active")
        } catch {
            Self.logger.error("[Orchestrator] ❌ Failed to ensure session active: \(error)")
            throw AudioPlayerError.sessionConfigurationFailed(
                reason: "Failed to ensure active: \(error.localizedDescription)"
            )
        }

        // 3. Resume engine playback (restores from saved position)
        await engineControl.play()
        Self.logger.debug("[Orchestrator] ✅ Engine resumed")

        // 4. Update state ONLY after success
        await stateStore.updateMode(.playing)
        Self.logger.info("[Orchestrator] ✅ Resumed")

        // TODO: Restart timer (Step 2.6 - add TimerManager dependency)
    }

    func stop(fadeDuration: TimeInterval) async {
        Self.logger.debug("[Orchestrator] → stop(fadeDuration: \(fadeDuration)s)")

        // Cancel any active operation
        activeOperation?.cancel()
        activeOperation = nil

        // TODO: Stop timer (Step 2.6 - add TimerManager dependency)

        // Apply fade-out if requested
        if fadeDuration > 0 {
            let currentVolume = await engineControl.getActiveMixerVolume()
            Self.logger.debug("[Orchestrator] Fading out from \(currentVolume) to 0")
            await engineControl.fadeActiveMixer(
                from: currentVolume,
                to: 0.0,
                duration: fadeDuration,
                curve: .equalPower
            )
        }

        // Stop both players
        await engineControl.stopBothPlayers()
        Self.logger.debug("[Orchestrator] ✅ Players stopped")

        // Update state to finished
        await stateStore.updateMode(.finished)
        Self.logger.info("[Orchestrator] ✅ Stopped")
    }

    func getCurrentState() async -> PlayerState {
        return await stateStore.getPlaybackMode()
    }
}
