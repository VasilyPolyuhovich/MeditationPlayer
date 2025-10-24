//
//  CrossfadeOrchestrator.swift
//  AudioServiceKit
//
//  Orchestrates crossfade operations between tracks
//

import Foundation
import OSLog
import AudioServiceCore

/// Actor orchestrating crossfade business logic
///
/// **Responsibility:** Crossfade flow orchestration ONLY
/// - Coordinates dual-player crossfade execution
/// - Manages active/paused crossfade state
/// - Handles pause/resume/cancel scenarios
///
/// **Dependencies:**
/// - AudioEngineControl: For dual-player operations
/// - PlaybackStateStore: For player switching and state queries
actor CrossfadeOrchestrator: CrossfadeOrchestrating {
    // MARK: - Dependencies

    private let audioEngine: AudioEngineActor  // ✅ PHASE 2: Direct usage (no protocol)
    private let stateStore: PlaybackStateStore
    private let timeoutManager = AdaptiveTimeoutManager()  // Adaptive timeout for file I/O

    // MARK: - Active Crossfade State

    /// Currently active crossfade operation
    private var activeCrossfade: ActiveCrossfadeState?

    /// Task monitoring crossfade progress
    private var crossfadeProgressTask: Task<Void, Never>?

    // MARK: - Paused Crossfade State

    /// Saved state for pause/resume
    private var pausedCrossfade: PausedCrossfadeState?

    // MARK: - Logging

    private static let logger = Logger(category: "CrossfadeOrchestrator")

    // MARK: - Initialization

    init(
        audioEngine: AudioEngineActor,  // ✅ PHASE 2: Direct usage
        stateStore: PlaybackStateStore
    ) {
        self.audioEngine = audioEngine
        self.stateStore = stateStore

        Self.logger.info("[CrossfadeOrch] ✅ Initialized with protocol dependencies")
    }

    // MARK: - CrossfadeOrchestrating Implementation

    func startCrossfade(
        to track: Track,
        duration: TimeInterval,
        curve: FadeCurve,
        operation: CrossfadeOperation
    ) async throws -> CrossfadeResult {
        Self.logger.debug("[CrossfadeOrch] → startCrossfade(to: \(track.url.lastPathComponent))")

        // 1. Rollback existing crossfade if any
        if activeCrossfade != nil {
            Self.logger.debug("[CrossfadeOrch] Active crossfade exists, rolling back...")
            await rollbackCurrentCrossfade()
        }

        // 2. Validate we have active track
        guard let fromTrack = await stateStore.getCurrentTrack() else {
            Self.logger.error("[CrossfadeOrch] ❌ No active track to crossfade from")
            throw AudioPlayerError.invalidState(
                current: "no active track",
                attempted: "start crossfade"
            )
        }
        
        // 2a. Time Remaining Check - decide strategy
        let position = await audioEngine.getCurrentPosition()
        let currentTime = position?.currentTime ?? 0.0
        let trackDuration = position?.duration ?? (fromTrack.metadata?.duration ?? 0.0)
        
        let strategy = TimeRemainingHelper.decideStrategy(
            trackPosition: currentTime,
            trackDuration: trackDuration,
            requestedDuration: duration
        )
        
        Self.logger.info("[CrossfadeOrch] Time check: position=\(String(format: "%.1f", currentTime))s, duration=\(String(format: "%.1f", trackDuration))s, strategy=\(strategy)")
        
        // Adapt duration based on strategy
        let actualDuration: TimeInterval
        switch strategy {
        case .fullCrossfade(let d):
            actualDuration = d
            
        case .reducedCrossfade(let d):
            actualDuration = d
            Self.logger.warning("[CrossfadeOrch] ⚠️ Not enough time for full crossfade, using \(String(format: "%.1f", d))s")
            
        case .separateFades(let fadeOut, let fadeIn):
            // Not enough time for crossfade - use separate fades
            Self.logger.info("[CrossfadeOrch] Using separate fades strategy (fadeOut: \(String(format: "%.1f", fadeOut))s, fadeIn: \(String(format: "%.1f", fadeIn))s)")
            return try await performSeparateFades(
                to: track,
                fadeOutDuration: fadeOut,
                fadeInDuration: fadeIn,
                curve: curve,
                operation: operation
            )
        }

        // 3. Clear any paused crossfade
        if pausedCrossfade != nil {
            Self.logger.debug("[CrossfadeOrch] Clearing paused crossfade (new operation)")
            pausedCrossfade = nil
        }
        
        // 4. Capture position snapshot BEFORE crossfade starts (for rollback)
        let snapshotActivePos = await audioEngine.getCurrentPosition()?.currentTime ?? 0.0
        let snapshotInactivePos: TimeInterval = 0.0  // Inactive not yet loaded
        
        Self.logger.debug("[CrossfadeOrch] Position snapshot: active=\(String(format: "%.2f", snapshotActivePos))s")

        // 5. Create active crossfade state with snapshots (using actualDuration)
        activeCrossfade = ActiveCrossfadeState(
            operation: operation,
            startTime: Date(),
            duration: actualDuration,  // ✅ Use adapted duration from strategy
            curve: curve,
            fromTrack: fromTrack,
            toTrack: track,
            snapshotActivePosition: snapshotActivePos,
            snapshotInactivePosition: snapshotInactivePos
        )

        // 5. Load track on inactive player and fill metadata (CRITICAL I/O with timeout)
        Self.logger.debug("[CrossfadeOrch] Loading track on inactive player...")
        let trackWithMetadata: Track
        do {
            // Calculate adaptive timeout based on past performance
            let expectedLoad = Duration.milliseconds(500)  // Expected file I/O time
            let adaptiveTimeout = await timeoutManager.adaptiveTimeout(
                for: expectedLoad,
                operation: "fileLoad"
            )
            
            let loadStart = ContinuousClock.now
            
            // Load with timeout protection
            trackWithMetadata = try await audioEngine.loadAudioFileOnSecondaryPlayerWithTimeout(
                track: track,
                timeout: adaptiveTimeout,
                onProgress: { event in
                    // Log progress events
                    Self.logger.debug("[CrossfadeOrch] File I/O: \(event)")
                    // Note: Events logged here, can be forwarded via callback in future
                }
            )
            
            let loadDuration = ContinuousClock.now - loadStart
            
            // Record actual duration for future adaptation
            await timeoutManager.recordDuration(
                operation: "fileLoad",
                expected: expectedLoad,
                actual: loadDuration
            )
        } catch {
            // ✅ PRIORITY 2: Cleanup state on file load error
            Self.logger.error("[CrossfadeOrch] ❌ File load failed: \(error)")
            activeCrossfade = nil
            throw error
        }
        await stateStore.loadTrackOnInactive(trackWithMetadata)

        // 6. Mark as crossfading
        await stateStore.updateCrossfading(true)

        // 7. Prepare and start crossfade
        await audioEngine.prepareSecondaryPlayer()

        Self.logger.info("[CrossfadeOrch] ✅ Starting engine crossfade (duration=\(actualDuration)s)")

        let progressStream = await audioEngine.performSynchronizedCrossfade(
            duration: actualDuration,  // ✅ Use adapted duration
            curve: curve
        )

        // 8. Save crossfade ID for race detection
        let crossfadeId = activeCrossfade!.id
        
        // 9. Monitor progress
        crossfadeProgressTask = Task { [weak self] in
            for await progress in progressStream {
                await self?.updateCrossfadeProgress(progress)
            }
        }

        // 10. Wait for completion
        await crossfadeProgressTask?.value
        crossfadeProgressTask = nil

        // 11. Identity check: cancelled if ID changed or nil (race condition protection)
        if activeCrossfade?.id != crossfadeId {
            Self.logger.debug("[CrossfadeOrch] Crossfade was cancelled (identity mismatch: rolled back by new crossfade)")
            return .cancelled
        }

        // 12. Check if paused during crossfade
        if pausedCrossfade != nil {
            Self.logger.debug("[CrossfadeOrch] Crossfade paused during execution")
            activeCrossfade = nil
            return .paused
        }

        // 13. Crossfade completed - cleanup
        Self.logger.debug("[CrossfadeOrch] Crossfade completed, performing cleanup...")

        // Switch players
        await stateStore.switchActivePlayer()

        // Stop and clear inactive
        await audioEngine.stopInactivePlayer()
        await audioEngine.resetInactiveMixer()
        await audioEngine.clearInactiveFile()

        // Clear crossfade state
        activeCrossfade = nil
        await stateStore.updateCrossfading(false)

        Self.logger.info("[CrossfadeOrch] ✅ Crossfade completed successfully")

        return .completed
    }

    func pauseCrossfade() async throws -> PausedCrossfadeSnapshot? {
        Self.logger.debug("[CrossfadeOrch] → pauseCrossfade()")

        guard let active = activeCrossfade else {
            Self.logger.debug("[CrossfadeOrch] No active crossfade to pause")
            return nil
        }

        // Cancel progress monitoring
        crossfadeProgressTask?.cancel()
        crossfadeProgressTask = nil

        // Get engine crossfade state
        guard let engineState = await audioEngine.getCrossfadeState() else {
            Self.logger.error("[CrossfadeOrch] ❌ Failed to get engine crossfade state")
            throw AudioPlayerError.invalidState(
                current: "no engine crossfade state",
                attempted: "pause crossfade"
            )
        }

        // Calculate resume strategy
        let strategy: PausedCrossfadeState.ResumeStrategy = active.progress < 0.5 ? .continueFromProgress : .quickFinish

        // Create paused state
        pausedCrossfade = PausedCrossfadeState(
            progress: active.progress,
            originalDuration: active.duration,
            curve: active.curve,
            activeMixerVolume: engineState.activeMixerVolume,
            inactiveMixerVolume: engineState.inactiveMixerVolume,
            activePlayerPosition: engineState.activePlayerPosition,
            inactivePlayerPosition: engineState.inactivePlayerPosition,
            activePlayer: engineState.activePlayer == .a ? .a : .b,
            resumeStrategy: strategy,
            operation: active.operation
        )

        // Clear active crossfade
        activeCrossfade = nil

        Self.logger.info("[CrossfadeOrch] ✅ Crossfade paused (progress: \(Int(active.progress * 100))%, strategy: \(strategy))")

        // Return simplified snapshot
        return PausedCrossfadeSnapshot(
            timestamp: Date(),
            fromTrack: active.fromTrack,
            toTrack: active.toTrack,
            duration: active.duration,
            curve: active.curve
        )
    }

    func resumeCrossfade() async throws -> Bool {
        Self.logger.debug("[CrossfadeOrch] → resumeCrossfade()")

        guard let paused = pausedCrossfade else {
            Self.logger.debug("[CrossfadeOrch] No paused crossfade to resume")
            return false
        }

        // Clear paused state
        pausedCrossfade = nil

        // Resume based on strategy
        switch paused.resumeStrategy {
        case .continueFromProgress:
            Self.logger.info("[CrossfadeOrch] Resuming crossfade from \(Int(paused.progress * 100))%")
            // TODO: Implement continue from progress
            // Need engine support for resuming crossfade mid-way
            Self.logger.warning("[CrossfadeOrch] ⚠️ Continue from progress not yet implemented, using quick finish")
            fallthrough

        case .quickFinish:
            Self.logger.info("[CrossfadeOrch] Quick finish crossfade in 1s")
            try await quickFinishCrossfade(from: paused)
        }

        return true
    }

    func cancelActiveCrossfade() async {
        Self.logger.debug("[CrossfadeOrch] → cancelActiveCrossfade()")

        // Cancel progress monitoring
        crossfadeProgressTask?.cancel()
        crossfadeProgressTask = nil

        // Clear states
        activeCrossfade = nil
        pausedCrossfade = nil

        // Cancel engine crossfade
        await audioEngine.cancelActiveCrossfade()

        Self.logger.info("[CrossfadeOrch] ✅ Crossfade cancelled")
    }

    func clearPausedCrossfade() {
        pausedCrossfade = nil
        Self.logger.debug("[CrossfadeOrch] Paused crossfade cleared")
    }

    func hasActiveCrossfade() -> Bool {
        return activeCrossfade != nil
    }

    func hasPausedCrossfade() -> Bool {
        return pausedCrossfade != nil
    }

    // MARK: - Private Helpers

    /// Rollback current crossfade smoothly
    private func rollbackCurrentCrossfade() async {
        Self.logger.debug("[CrossfadeOrch] → rollbackCurrentCrossfade()")

        // Cancel progress monitoring
        crossfadeProgressTask?.cancel()
        crossfadeProgressTask = nil

        // Rollback engine crossfade (0.3s smooth rollback)
        _ = await audioEngine.rollbackCrossfade(rollbackDuration: 0.3)

        // Clear crossfade state
        activeCrossfade = nil
        pausedCrossfade = nil

        Self.logger.info("[CrossfadeOrch] ✅ Crossfade rolled back")
    }

    /// Update crossfade progress from engine
    private func updateCrossfadeProgress(_ progress: CrossfadeProgress) {
        guard activeCrossfade != nil else { return }

        // Update progress in active state
        activeCrossfade?.progress = Float(progress.progress)

        // TODO: Notify observers if needed
    }

    /// Quick finish paused crossfade
    private func quickFinishCrossfade(from paused: PausedCrossfadeState) async throws {
        Self.logger.debug("[CrossfadeOrch] → quickFinishCrossfade()")

        // Determine remaining duration (1 second for quick finish)
        let finishDuration: TimeInterval = 1.0

        // Resume crossfade from current volumes
        let progressStream = await audioEngine.performSynchronizedCrossfade(
            duration: finishDuration,
            curve: paused.curve
        )

        // Wait for completion
        for await _ in progressStream {
            // Just consume the stream
        }

        // Switch players
        await stateStore.switchActivePlayer()

        // Cleanup
        await audioEngine.stopInactivePlayer()
        await audioEngine.resetInactiveMixer()
        await audioEngine.clearInactiveFile()
        await stateStore.updateCrossfading(false)

        Self.logger.info("[CrossfadeOrch] ✅ Quick finish completed")
    }

    /// Perform separate fades: fade out active → switch → fade in new track
    /// Used when not enough time for crossfade (near end of track)
    private func performSeparateFades(
        to track: Track,
        fadeOutDuration: TimeInterval,
        fadeInDuration: TimeInterval,
        curve: FadeCurve,
        operation: CrossfadeOperation
    ) async throws -> CrossfadeResult {
        Self.logger.info("[CrossfadeOrch] → performSeparateFades(fadeOut: \(String(format: "%.1f", fadeOutDuration))s, fadeIn: \(String(format: "%.1f", fadeInDuration))s)")

        // 1. Fade out active player
        Self.logger.debug("[CrossfadeOrch] Step 1: Fade out active player")
        await audioEngine.fadeOutActivePlayer(duration: fadeOutDuration, curve: curve)

        // 2. Stop active player
        Self.logger.debug("[CrossfadeOrch] Step 2: Stop active player")
        await audioEngine.stopActivePlayer()

        // 3. Load new track on active player (reuse same player)
        Self.logger.debug("[CrossfadeOrch] Step 3: Load new track on active player")
        let trackWithMetadata = try await audioEngine.loadAudioFileOnPrimaryPlayer(track: track)
        await stateStore.atomicSwitch(newTrack: trackWithMetadata, mode: nil)

        // 4. Start playback with fade in
        Self.logger.debug("[CrossfadeOrch] Step 4: Start with fade in")
        await audioEngine.playWithFadeIn(duration: fadeInDuration, curve: curve)

        Self.logger.info("[CrossfadeOrch] ✅ Separate fades completed")
        return .completed
    }

    // MARK: - Simple Fade Operations (Pause/Resume/Skip)

    /// Perform simple fade out (for pause operations)
    func performSimpleFadeOut(duration: TimeInterval = 0.3) async {
        Self.logger.debug("[CrossfadeOrch] → performSimpleFadeOut(\(String(format: "%.1f", duration))s)")
        await audioEngine.fadeOutActivePlayer(duration: duration, curve: .linear)
        Self.logger.debug("[CrossfadeOrch] ✅ Simple fade out completed")
    }

    /// Perform simple fade in (for resume operations)
    func performSimpleFadeIn(duration: TimeInterval = 0.3) async {
        Self.logger.debug("[CrossfadeOrch] → performSimpleFadeIn(\(String(format: "%.1f", duration))s)")
        await audioEngine.fadeInActivePlayer(duration: duration, curve: .linear)
        Self.logger.debug("[CrossfadeOrch] ✅ Simple fade in completed")
    }

    /// Perform fade → seek → fade (for skip forward/backward)
    func performFadeSeekFade(
        seekTo time: TimeInterval,
        fadeOutDuration: TimeInterval = 0.3,
        fadeInDuration: TimeInterval = 0.3
    ) async throws {
        Self.logger.debug("[CrossfadeOrch] → performFadeSeekFade(to: \(String(format: "%.1f", time))s)")

        // 1. Fade out
        await audioEngine.fadeOutActivePlayer(duration: fadeOutDuration, curve: .linear)

        // 2. Seek
        try await audioEngine.seek(to: time)

        // 3. Fade in
        await audioEngine.fadeInActivePlayer(duration: fadeInDuration, curve: .linear)

        Self.logger.info("[CrossfadeOrch] ✅ Fade-seek-fade completed")
    }
}

// MARK: - Internal State Types

/// Active crossfade state
private struct ActiveCrossfadeState {
    let id: UUID = UUID()  // ✅ Identity for race condition detection
    let operation: CrossfadeOperation
    let startTime: Date
    let duration: TimeInterval
    let curve: FadeCurve
    let fromTrack: Track
    let toTrack: Track
    var progress: Float = 0.0
    
    // Position snapshots BEFORE crossfade started (for rollback)
    let snapshotActivePosition: TimeInterval
    let snapshotInactivePosition: TimeInterval

    var elapsed: TimeInterval {
        return Date().timeIntervalSince(startTime)
    }

    var remaining: TimeInterval {
        return max(0, duration - elapsed)
    }
}

/// Paused crossfade state
private struct PausedCrossfadeState {
    let progress: Float
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
        return max(0.1, remaining) // Minimum 0.1s
    }
}

// Note: PlayerNode enum is in PlaybackStateCoordinator
