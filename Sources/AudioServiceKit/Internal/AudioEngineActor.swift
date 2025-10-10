import AVFoundation
import AudioServiceCore

/// Actor that isolates AVAudioEngine for thread-safe access
actor AudioEngineActor {
    // MARK: - Audio Engine Components
    
    private let engine: AVAudioEngine
    
    // Dual player setup for crossfading
    private let playerNodeA: AVAudioPlayerNode
    private let playerNodeB: AVAudioPlayerNode
    private let mixerNodeA: AVAudioMixerNode
    private let mixerNodeB: AVAudioMixerNode
    
    // Track which player is currently active
    private var activePlayer: PlayerNode = .a
    
    // Currently loaded audio files
    private var audioFileA: AVAudioFile?
    private var audioFileB: AVAudioFile?
    
    // Playback state
    private var isEngineRunning = false
    
    // Playback offset tracking for accurate seeking
    private var playbackOffsetA: AVAudioFramePosition = 0
    private var playbackOffsetB: AVAudioFramePosition = 0
    
    // Crossfade task management
    private var activeCrossfadeTask: Task<Void, Never>?
    private var crossfadeProgressContinuation: AsyncStream<CrossfadeProgress>.Continuation?
    
    /// Is crossfade currently in progress
    var isCrossfading: Bool { activeCrossfadeTask != nil }
    
    // Volume management
    /// Target volume set by user (0.0-1.0)
    /// Crossfade curves are scaled to this target for smooth volume changes
    private var targetVolume: Float = 1.0
    
    // MARK: - Overlay Player
    
    /// Overlay player for independent ambient audio
    /// 
    /// **Architecture Note:**
    /// Overlay system follows clean actor separation (OverlayPlayerActor receives nodes from outside).
    /// Main player system (playerA/B, mixerA/B) is embedded directly in AudioEngineActor for:
    /// - Zero await overhead on position tracking (60 FPS)
    /// - Simpler state management for complex crossfade logic
    /// - Historical reasons (evolved from v1.0 monolithic design)
    /// 
    /// This creates architectural inconsistency (technical debt) but maintains performance.
    /// **Future v4.0:** Consider extracting MainPlayerActor if position tracking can tolerate async overhead.
    internal var overlayPlayer: OverlayPlayerActor?
    
    // MARK: - Initialization
    
    init() {
        self.engine = AVAudioEngine()
        self.playerNodeA = AVAudioPlayerNode()
        self.playerNodeB = AVAudioPlayerNode()
        self.mixerNodeA = AVAudioMixerNode()
        self.mixerNodeB = AVAudioMixerNode()
    }
    
    // MARK: - Setup
    
    func setup() {
        setupAudioGraph()
    }
    
    private func setupAudioGraph() {
        // Attach all nodes to engine
        engine.attach(playerNodeA)
        engine.attach(playerNodeB)
        engine.attach(mixerNodeA)
        engine.attach(mixerNodeB)
        
        // Get the standard format from output
        let format = engine.outputNode.outputFormat(forBus: 0)
        
        // 🔍 DIAGNOSTIC: Log engine format
        print("[AudioEngine] Setup format: \(format.sampleRate)Hz, \(format.channelCount)ch")
        
        // Connect player A: playerA -> mixerA -> mainMixer
        engine.connect(playerNodeA, to: mixerNodeA, format: format)
        engine.connect(mixerNodeA, to: engine.mainMixerNode, format: format)
        
        // Connect player B: playerB -> mixerB -> mainMixer
        engine.connect(playerNodeB, to: mixerNodeB, format: format)
        engine.connect(mixerNodeB, to: engine.mainMixerNode, format: format)
        
        // Set initial volumes
        mixerNodeA.volume = 0.0
        mixerNodeB.volume = 0.0
        engine.mainMixerNode.volume = 1.0
    }
    
    // MARK: - Engine Control
    
    func prepare() throws {
        engine.prepare()
    }
    
    func start() throws {
        guard !isEngineRunning else { return }
        
        try engine.start()
        isEngineRunning = true
    }
    
    func stop() {
        guard isEngineRunning else { return }
        
        playerNodeA.stop()
        playerNodeB.stop()
        engine.stop()
        isEngineRunning = false
    }
    
    func pause() {
        // 1. Capture current position in offset before pausing
        // This ensures position is preserved for accurate resume
        if let current = getCurrentPosition() {
            let sampleRate = getActiveAudioFile()?.fileFormat.sampleRate ?? 44100
            let currentFrame = AVAudioFramePosition(current.currentTime * sampleRate)
            
            if activePlayer == .a {
                playbackOffsetA = currentFrame
            } else {
                playbackOffsetB = currentFrame
            }
        }
        
        // 2. Pause BOTH players (safe during crossfade)
        playerNodeA.pause()
        playerNodeB.pause()
    }
    
    func play() {
        let player = getActivePlayerNode()
        guard let file = getActiveAudioFile() else { return }
        
        // Get saved offset
        let offset = activePlayer == .a ? playbackOffsetA : playbackOffsetB
        
        // ✅ SAFETY: Validate offset is within file bounds
        // Prevents crash when offset >= file.length (negative remainingFrames)
        guard offset < file.length else {
            Logger.audio.error("Cannot play: offset (\(offset)) >= file.length (\(file.length))")
            Logger.audio.error("This may indicate corrupted test file or invalid state")
            return
        }
        
        // ✅ FIX: Always check if we need to reschedule after pause
        // AVFoundation quirk: isPlaying may be unreliable after pause()
        // Strategy: If player is not playing AND we have an offset, it's a resume
        let needsReschedule = !player.isPlaying && offset > 0
        
        if needsReschedule {
            // Resume from saved position
            // Stop player completely to clear any stale state
            player.stop()
            
            // Reschedule from offset (like seek)
            let remainingFrames = AVAudioFrameCount(file.length - offset)
            if remainingFrames > 0 {
                player.scheduleSegment(
                    file,
                    startingFrame: offset,
                    frameCount: remainingFrames,
                    at: nil,
                    completionCallbackType: .dataPlayedBack
                ) { _ in
                    // Completion on audio thread - keep minimal
                }
            }
        }
        
        // Play (either fresh scheduled buffer or continue)
        player.play()
    }
    
    /// Stop both players completely and reset volumes
    func stopBothPlayers() {
        // Cancel active crossfade if running
        cancelActiveCrossfade()
        
        playerNodeA.stop()
        playerNodeB.stop()
        mixerNodeA.volume = 0.0
        mixerNodeB.volume = 0.0
        
        if isEngineRunning {
            engine.stop()
            isEngineRunning = false
        }
    }
    
    /// Cancel active crossfade and cleanup
    func cancelActiveCrossfade() {
        guard let task = activeCrossfadeTask else { return }
        
        // Cancel task
        task.cancel()
        activeCrossfadeTask = nil
        
        // Report idle state
        crossfadeProgressContinuation?.yield(.idle)
        crossfadeProgressContinuation?.finish()
        crossfadeProgressContinuation = nil
        
        // Quick cleanup: reset volumes
        mixerNodeA.volume = 0.0
        mixerNodeB.volume = 0.0
    }
    
    /// Cancel crossfade and stop inactive player
    /// - Note: Used when stop() is called during crossfade
    /// - Note: Leaves active mixer volume unchanged for subsequent fadeout
    func cancelCrossfadeAndStopInactive() async {
        // 1. Cancel crossfade task
        guard let task = activeCrossfadeTask else { return }
        
        task.cancel()
        activeCrossfadeTask = nil
        
        // Report cancellation
        crossfadeProgressContinuation?.yield(.idle)
        crossfadeProgressContinuation?.finish()
        crossfadeProgressContinuation = nil
        
        // 2. Stop inactive player (was fading in, no longer needed)
        let inactivePlayer = getInactivePlayerNode()
        inactivePlayer.stop()
        
        // 3. Reset inactive mixer to 0
        getInactiveMixerNode().volume = 0.0
        
        // 4. Active mixer volume is LEFT UNCHANGED
        // stopWithFade() will fade it out from current volume to 0
    }
    
    /// Rollback crossfade transaction - restore active player to normal state
    /// - Parameter rollbackDuration: Duration to restore active volume (default: 0.5s)
    /// - Returns: Current volume of active mixer before rollback (for smooth transition)
    func rollbackCrossfade(rollbackDuration: TimeInterval = 0.5) async -> Float {
        // 1. Get current volumes before cancellation
        let activeMixer = getActiveMixerNode()
        let inactiveMixer = getInactiveMixerNode()
        let currentActiveVolume = activeMixer.volume
        let currentInactiveVolume = inactiveMixer.volume
        
        // 2. Cancel crossfade task
        guard let task = activeCrossfadeTask else {
            // No active crossfade, just return current volume
            return currentActiveVolume
        }
        
        task.cancel()
        activeCrossfadeTask = nil
        
        // Report cancellation
        crossfadeProgressContinuation?.yield(.idle)
        crossfadeProgressContinuation?.finish()
        crossfadeProgressContinuation = nil
        
        // 3. Graceful rollback: restore active volume to targetVolume
        if currentActiveVolume < targetVolume {
            await fadeVolume(
                mixer: activeMixer,
                from: currentActiveVolume,
                to: targetVolume,  // Use target, not 1.0
                duration: rollbackDuration,
                curve: .linear  // Fast linear restore
            )
        }
        
        // 4. Fade out inactive player if it's playing
        if currentInactiveVolume > 0.0 {
            await fadeVolume(
                mixer: inactiveMixer,
                from: currentInactiveVolume,
                to: 0.0,
                duration: rollbackDuration,
                curve: .linear
            )
        }
        
        // 5. Stop inactive player and reset
        await stopInactivePlayer()
        inactiveMixer.volume = 0.0
        
        return currentActiveVolume
    }
    
    /// Complete reset - clears all state and files
    func fullReset() {
        // Stop everything
        stopBothPlayers()
        
        // Stop overlay
        Task {
            await stopOverlay()
        }
        
        // Clear files
        audioFileA = nil
        audioFileB = nil
        
        // Reset offsets
        playbackOffsetA = 0
        playbackOffsetB = 0
        
        // Reset to player A
        activePlayer = .a
    }
    
    // MARK: - Audio File Loading
    
    func loadAudioFile(url: URL) throws -> TrackInfo {
        let file = try AVAudioFile(forReading: url)
        
        // 🔍 DIAGNOSTIC: Log file format
        print("[AudioEngine] Load file: \(url.lastPathComponent)")
        print("  Format: \(file.fileFormat.sampleRate)Hz, \(file.fileFormat.channelCount)ch")
        
        // Store in active player's slot
        switch activePlayer {
        case .a:
            audioFileA = file
        case .b:
            audioFileB = file
        }
        
        // Get track info
        let duration = Double(file.length) / file.fileFormat.sampleRate
        let format = AudioFormat(
            sampleRate: file.fileFormat.sampleRate,
            channelCount: Int(file.fileFormat.channelCount),
            bitDepth: 32,
            isInterleaved: file.fileFormat.isInterleaved
        )
        
        return TrackInfo(
            title: url.lastPathComponent,
            artist: nil,
            duration: duration,
            format: format
        )
    }
    
    // MARK: - Playback Control
    
    func scheduleFile(fadeIn: Bool = false, fadeInDuration: TimeInterval = 3.0, fadeCurve: FadeCurve = .equalPower) {
        guard let file = getActiveAudioFile() else { return }
        
        let player = getActivePlayerNode()
        let mixer = getActiveMixerNode()
        
        // Reset offset when scheduling full file
        if activePlayer == .a {
            playbackOffsetA = 0
        } else {
            playbackOffsetB = 0
        }
        
        // Schedule the file for playback
        player.scheduleFile(file, at: nil) {
            // Completion handler - will be called on audio thread
            // Keep it minimal - no heavy operations here
        }
        
        // Set initial volume for fade in
        if fadeIn {
            mixer.volume = 0.0
            Task {
                // Use actor method to avoid data races
                // Fade to targetVolume (not 1.0) to respect user's volume setting
                await self.fadeActiveMixer(
                    from: 0.0,
                    to: targetVolume,
                    duration: fadeInDuration,
                    curve: fadeCurve
                )
            }
        } else {
            mixer.volume = targetVolume  // Use target, not 1.0
        }
        
        // Start playback
        player.play()
    }
    
    // MARK: - Seeking (REALLY FIXED)
    
    func seek(to time: TimeInterval) throws {
        guard let file = getActiveAudioFile() else {
            throw AudioPlayerError.invalidState(
                current: "no file loaded",
                attempted: "seek"
            )
        }
        
        let player = getActivePlayerNode()
        let mixer = getActiveMixerNode()
        let sampleRate = file.fileFormat.sampleRate
        
        // Calculate target frame
        let targetFrame = AVAudioFramePosition(time * sampleRate)
        let maxFrame = file.length - 1
        let clampedFrame = max(0, min(targetFrame, maxFrame))
        
        // Save state BEFORE stopping
        let wasPlaying = player.isPlaying
        let currentVolume = mixer.volume
        
        // Stop player completely (clears buffers)
        player.stop()
        
        // CRITICAL: Store playback offset for position tracking
        if activePlayer == .a {
            playbackOffsetA = clampedFrame
        } else {
            playbackOffsetB = clampedFrame
        }
        
        // Schedule from new position
        player.scheduleSegment(
            file,
            startingFrame: clampedFrame,
            frameCount: AVAudioFrameCount(file.length - clampedFrame),
            at: nil,
            completionCallbackType: .dataPlayedBack
        ) { _ in
            // Completion on audio thread - keep minimal
        }
        
        // Restore volume BEFORE playing
        mixer.volume = currentVolume
        
        // Resume playback if was playing
        if wasPlaying {
            player.play()
        }
    }
    
    // MARK: - Volume Control
    
    func setVolume(_ volume: Float) {
        // Store target volume for crossfade scaling
        targetVolume = max(0.0, min(1.0, volume))
        
        // Set volume on main mixer (global)
        engine.mainMixerNode.volume = targetVolume
        
        // If NOT crossfading, update active mixer to target volume
        // During crossfade, fadeWithProgress() handles volume scaling
        if !isCrossfading {
            getActiveMixerNode().volume = targetVolume
        }
    }
    
    /// Get current target volume
    /// - Returns: Target volume level (0.0-1.0)
    func getTargetVolume() -> Float {
        return targetVolume
    }
    
    /// Get current active mixer volume
    /// - Returns: Actual volume of active mixer node (0.0-1.0)
    /// - Note: This is different from targetVolume (mainMixer.volume)
    /// - Note: During crossfade, active mixer may have different volume than target
    func getActiveMixerVolume() -> Float {
        return getActiveMixerNode().volume
    }
    
    func fadeVolume(
        mixer: AVAudioMixerNode,
        from: Float,
        to: Float,
        duration: TimeInterval,
        curve: FadeCurve = .equalPower
    ) async {
        // ✅ DEBUG: Log fade parameters
        let mixerName = (mixer === mixerNodeA) ? "MixerA" : "MixerB"
        print("[FADE_DEBUG] \(mixerName): from=\(from) → to=\(to), duration=\(duration)s, curve=\(curve)")
        
        // FIXED Issue #9: Adaptive step sizing for efficient fading
        // Short fades need high frequency updates for smoothness
        // Long fades can use lower frequency to reduce CPU usage
        let stepsPerSecond: Int
        if duration < 1.0 {
            stepsPerSecond = 100  // 10ms - ultra smooth for quick fades
        } else if duration < 5.0 {
            stepsPerSecond = 50   // 20ms - smooth
        } else if duration < 15.0 {
            stepsPerSecond = 30   // 33ms - balanced
        } else {
            stepsPerSecond = 20   // 50ms - efficient for long fades (30s fade: 600 steps vs 3000)
        }
        
        let steps = Int(duration * Double(stepsPerSecond))
        let stepTime = duration / Double(steps)
        
        print("[FADE_DEBUG] \(mixerName): steps=\(steps), stepTime=\(stepTime*1000)ms, stepsPerSecond=\(stepsPerSecond)")
        
        // ✅ DEBUG: Log first 5 and last 5 steps
        var loggedSteps: Set<Int> = []
        for i in 0..<5 {
            loggedSteps.insert(i)
            loggedSteps.insert(steps - i)
        }
        
        for i in 0...steps {
            // FIXED Issue #10A: Check for task cancellation on every step
            // If fade is interrupted (pause/stop) → abort gracefully
            guard !Task.isCancelled else {
                print("[FADE_DEBUG] \(mixerName): CANCELLED at step \(i)/\(steps)")
                return // Exit immediately without throwing
            }
            
            let progress = Float(i) / Float(steps)
            
            // Calculate volume based on curve type
            let curveValue: Float
            if from < to {
                // Fading in (0 -> 1)
                curveValue = curve.volume(for: progress)
            } else {
                // Fading out (1 -> 0)
                curveValue = curve.inverseVolume(for: progress)
            }
            
            // Apply curve to the range [from, to]
            let newVolume = from + (to - from) * curveValue
            mixer.volume = newVolume
            
            // ✅ DEBUG: Log critical steps
            if loggedSteps.contains(i) {
                print("[FADE_DEBUG] \(mixerName): step[\(i)/\(steps)] progress=\(progress) curveValue=\(curveValue) volume=\(newVolume)")
            }
            
            try? await Task.sleep(nanoseconds: UInt64(stepTime * 1_000_000_000))
        }
        
        // Ensure final volume is exact (only if not cancelled)
        if !Task.isCancelled {
            mixer.volume = to
            print("[FADE_DEBUG] \(mixerName): COMPLETE - final volume=\(to)")
        } else {
            print("[FADE_DEBUG] \(mixerName): CANCELLED before completion")
        }
    }
    
    // MARK: - Playback Position
    
    func getCurrentPosition() -> PlaybackPosition? {
        guard let file = getActiveAudioFile() else { return nil }
        
        let player = getActivePlayerNode()
        let offset = activePlayer == .a ? playbackOffsetA : playbackOffsetB
        let sampleRate = file.fileFormat.sampleRate
        
        // ISSUE #6 FIX: Different logic for playing vs paused state
        let actualSampleTime: AVAudioFramePosition
        
        if player.isPlaying {
            // Player is playing - use offset + playerTime for accurate tracking
            guard let nodeTime = player.lastRenderTime,
                  let playerTime = player.playerTime(forNodeTime: nodeTime) else {
                // Fallback to offset if times unavailable
                actualSampleTime = offset
                let currentTime = Double(actualSampleTime) / sampleRate
                let duration = Double(file.length) / sampleRate
                return PlaybackPosition(currentTime: currentTime, duration: duration)
            }
            actualSampleTime = offset + playerTime.sampleTime
        } else {
            // Player is paused - use ONLY offset (last known position)
            // playerTime.sampleTime may be stale or reset after pause
            actualSampleTime = offset
        }
        
        let currentTime = Double(actualSampleTime) / sampleRate
        let duration = Double(file.length) / sampleRate
        
        return PlaybackPosition(currentTime: currentTime, duration: duration)
    }
    
    // MARK: - Synchronized Crossfade (NEW)
    
    /// Prepare secondary player without starting playback
    func prepareSecondaryPlayer() {
        guard let file = getInactiveAudioFile() else { return }
        
        let player = getInactivePlayerNode()
        let mixer = getInactiveMixerNode()
        
        // Reset offset for new file
        if activePlayer == .a {
            playbackOffsetB = 0
        } else {
            playbackOffsetA = 0
        }
        
        // Set volume to 0 for fade in
        mixer.volume = 0.0
        
        // Schedule file but DON'T play yet
        player.scheduleFile(file, at: nil)
    }
    
    /// Prepare loop on secondary player without starting playback
    func prepareLoopOnSecondaryPlayer() {
        guard let file = getActiveAudioFile() else { return }
        
        let player = getInactivePlayerNode()
        let mixer = getInactiveMixerNode()
        
        // Reset offset for loop (starts from beginning)
        if activePlayer == .a {
            playbackOffsetB = 0
        } else {
            playbackOffsetA = 0
        }
        
        // Set volume to 0 for fade in
        mixer.volume = 0.0
        
        // Schedule same file but DON'T play yet
        player.scheduleFile(file, at: nil)
    }
    
    /// Calculate synchronized start time for secondary player
    private func getSyncedStartTime() -> AVAudioTime? {
        let activePlayer = getActivePlayerNode()
        
        guard let lastRenderTime = activePlayer.lastRenderTime else {
            return nil
        }
        
        // ✅ FIX: Increased buffer for better synchronization (4096 samples ≈ 93ms at 44.1kHz)
        // Prevents timing glitches with complex audio files or high system load
        let bufferSamples: AVAudioFramePosition = 4096  // Was: 2048
        let startSampleTime = lastRenderTime.sampleTime + bufferSamples
        
        return AVAudioTime(
            sampleTime: startSampleTime,
            atRate: lastRenderTime.sampleRate
        )
    }
    
    /// Perform synchronized crossfade between active and inactive players
    /// Returns async stream for progress observation
    func performSynchronizedCrossfade(
        duration: TimeInterval,
        curve: FadeCurve
    ) async -> AsyncStream<CrossfadeProgress> {
        // Create progress stream with buffering to prevent loss of .idle state
        let (stream, continuation) = AsyncStream.makeStream(
            of: CrossfadeProgress.self,
            bufferingPolicy: .bufferingNewest(1)  // Keep last value if consumer is slow
        )
        crossfadeProgressContinuation = continuation
        
        // Create and store crossfade task
        // Task runs asynchronously and sends progress updates through continuation
        let task = Task {
            await self.executeCrossfade(
                duration: duration,
                curve: curve,
                progress: continuation
            )
            
            // CRITICAL: Small delay to ensure .idle state is delivered to all observers
            // Before closing the stream. Without this, race condition may prevent UI from
            // receiving the final .idle update, causing it to be stuck at "Crossfading 0%"
            try? await Task.sleep(nanoseconds: 50_000_000)  // 50ms
            
            // Cleanup after crossfade completes
            await self.cleanupCrossfade(continuation: continuation)
        }
        
        activeCrossfadeTask = task
        
        // ✅ FIX: Return stream immediately so caller can subscribe to progress updates
        // Task continues running asynchronously and generates updates
        return stream
    }
    
    /// Cleanup crossfade state after completion
    private func cleanupCrossfade(continuation: AsyncStream<CrossfadeProgress>.Continuation) {
        activeCrossfadeTask = nil
        continuation.finish()
        crossfadeProgressContinuation = nil
    }
    
    /// Execute crossfade with progress reporting
    private func executeCrossfade(
        duration: TimeInterval,
        curve: FadeCurve,
        progress: AsyncStream<CrossfadeProgress>.Continuation
    ) async {
        let startTime = Date()
        
        // Phase 1: Preparing
        progress.yield(CrossfadeProgress(
            phase: .preparing,
            duration: duration,
            elapsed: 0
        ))
        
        let inactivePlayer = getInactivePlayerNode()
        
        guard !Task.isCancelled else {
            progress.yield(.idle)
            return
        }
        
        // Get synchronized start time
        let syncTime = getSyncedStartTime()
        
        // Start inactive player
        if let syncTime = syncTime {
            inactivePlayer.play(at: syncTime)
            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
        } else {
            inactivePlayer.play()
        }
        
        guard !Task.isCancelled else {
            inactivePlayer.stop()
            progress.yield(.idle)
            return
        }
        
        // Phase 2: Fading
        let fadeTask = Task {
            await self.fadeWithProgress(
                duration: duration,
                curve: curve,
                startTime: startTime,
                progress: progress
            )
        }
        
        await fadeTask.value
        
        guard !Task.isCancelled else {
            progress.yield(.idle)
            return
        }
        
        // Phase 3: Switching (instant)
        progress.yield(CrossfadeProgress(
            phase: .switching,
            duration: duration,
            elapsed: Date().timeIntervalSince(startTime)
        ))
        
        // Phase 4: Cleanup (instant)
        progress.yield(CrossfadeProgress(
            phase: .cleanup,
            duration: duration,
            elapsed: Date().timeIntervalSince(startTime)
        ))
        
        // Phase 5: Complete
        progress.yield(.idle)
    }
    
    /// Fade with progress reporting
    private func fadeWithProgress(
        duration: TimeInterval,
        curve: FadeCurve,
        startTime: Date,
        progress: AsyncStream<CrossfadeProgress>.Continuation
    ) async {
        let activeMixer = getActiveMixerNode()
        let inactiveMixer = getInactiveMixerNode()
        
        let stepsPerSecond: Int
        if duration < 1.0 {
            stepsPerSecond = 100
        } else if duration < 5.0 {
            stepsPerSecond = 50
        } else if duration < 15.0 {
            stepsPerSecond = 30
        } else {
            stepsPerSecond = 20
        }
        
        let steps = Int(duration * Double(stepsPerSecond))
        let stepTime = duration / Double(steps)
        
        for i in 0...steps {
            guard !Task.isCancelled else { return }
            
            let stepProgress = Float(i) / Float(steps)
            let elapsed = Date().timeIntervalSince(startTime)
            
            // Report progress
            progress.yield(CrossfadeProgress(
                phase: .fading(progress: Double(stepProgress)),
                duration: duration,
                elapsed: elapsed
            ))
            
            // Calculate volumes scaled to target volume
            // This ensures crossfade respects user's volume setting
            let fadeOutValue = curve.inverseVolume(for: stepProgress) * targetVolume
            let fadeInValue = curve.volume(for: stepProgress) * targetVolume
            
            activeMixer.volume = fadeOutValue
            inactiveMixer.volume = fadeInValue
            
            try? await Task.sleep(nanoseconds: UInt64(stepTime * 1_000_000_000))
        }
        
        // Ensure final volumes (if not cancelled)
        if !Task.isCancelled {
            activeMixer.volume = 0.0
            inactiveMixer.volume = targetVolume  // Use target, not 1.0
        }
    }
    
    /// Reset inactive mixer volume to 0
    func resetInactiveMixer() {
        getInactiveMixerNode().volume = 0.0
    }
    
    // MARK: - Helper Methods
    
    private func getActivePlayerNode() -> AVAudioPlayerNode {
        return activePlayer == .a ? playerNodeA : playerNodeB
    }
    
    private func getActiveMixerNode() -> AVAudioMixerNode {
        return activePlayer == .a ? mixerNodeA : mixerNodeB
    }
    
    private func getActiveAudioFile() -> AVAudioFile? {
        return activePlayer == .a ? audioFileA : audioFileB
    }
    
    private func getInactivePlayerNode() -> AVAudioPlayerNode {
        return activePlayer == .a ? playerNodeB : playerNodeA
    }
    
    private func getInactiveMixerNode() -> AVAudioMixerNode {
        return activePlayer == .a ? mixerNodeB : mixerNodeA
    }
    
    private func getInactiveAudioFile() -> AVAudioFile? {
        return activePlayer == .a ? audioFileB : audioFileA
    }
    
    // MARK: - Public Helper Methods
    
    /// Fade the active mixer volume (for seek and fade-out)
    func fadeActiveMixer(
        from: Float,
        to: Float,
        duration: TimeInterval,
        curve: FadeCurve = .equalPower
    ) async {
        let mixer = getActiveMixerNode()
        await fadeVolume(
            mixer: mixer,
            from: from,
            to: to,
            duration: duration,
            curve: curve
        )
    }
    
    /// Switch the active player (used after crossfade completes)
    /// NOTE: For track replacement, files are already loaded correctly.
    /// For loop, both players have the same file, so no copying needed.
    func switchActivePlayer() {
        // Simply switch the active flag - files are already in correct slots
        activePlayer = activePlayer == .a ? .b : .a
    }
    
    /// Load audio file on the secondary player (for replace/next track)
    func loadAudioFileOnSecondaryPlayer(url: URL) throws -> TrackInfo {
        let file = try AVAudioFile(forReading: url)
        
        // 🔍 DIAGNOSTIC: Log secondary file format
        print("[AudioEngine] Load secondary file: \(url.lastPathComponent)")
        print("  Format: \(file.fileFormat.sampleRate)Hz, \(file.fileFormat.channelCount)ch")
        
        // 🔍 DIAGNOSTIC: Compare with active file format
        if let activeFile = getActiveAudioFile() {
            let activeSR = activeFile.fileFormat.sampleRate
            let secondarySR = file.fileFormat.sampleRate
            if activeSR != secondarySR {
                print("  ⚠️ FORMAT MISMATCH: Active=\(activeSR)Hz, Secondary=\(secondarySR)Hz")
                print("  ⚠️ Real-time conversion may cause crackling during crossfade!")
            }
        }
        
        // Store in inactive player's slot
        switch activePlayer {
        case .a:
            audioFileB = file
        case .b:
            audioFileA = file
        }
        
        // Get track info
        let duration = Double(file.length) / file.fileFormat.sampleRate
        let format = AudioFormat(
            sampleRate: file.fileFormat.sampleRate,
            channelCount: Int(file.fileFormat.channelCount),
            bitDepth: 32,
            isInterleaved: file.fileFormat.isInterleaved
        )
        
        return TrackInfo(
            title: url.lastPathComponent,
            artist: nil,
            duration: duration,
            format: format
        )
    }
    

    
    /// Stop the currently active player
    func stopActivePlayer() {
        let player = getActivePlayerNode()
        player.stop()
    }
    
    /// Stop the currently inactive player (used after crossfade)
    func stopInactivePlayer() async {
        let player = getInactivePlayerNode()
        let mixer = getInactiveMixerNode()
        
        // ✅ FIX: Add micro-fade before stop to prevent clicking
        // Even if mixer.volume is already 0.0, this ensures smooth buffer cleanup
        if mixer.volume > 0.01 {
            await fadeVolume(
                mixer: mixer,
                from: mixer.volume,
                to: 0.0,
                duration: 0.02,  // 20ms - imperceptible but eliminates clicks
                curve: .linear
            )
        }
        
        // Small delay to ensure fade completes before stop
        try? await Task.sleep(nanoseconds: 25_000_000)  // 25ms
        
        // CRITICAL: Full cleanup to prevent memory leaks
        player.stop()  // Stop playback
        player.reset()  // Clear all scheduled buffers
        mixer.volume = 0.0  // Reset volume
    }
    
    /// Clear inactive file reference to free memory
    func clearInactiveFile() {
        if activePlayer == .a {
            audioFileB = nil
        } else {
            audioFileA = nil
        }
    }
    
    // MARK: - Overlay Player Control
    
    /// Start overlay playback with specified configuration
    /// - Parameters:
    ///   - url: Local file URL for overlay audio
    ///   - configuration: Overlay playback configuration
    /// - Throws: AudioPlayerError if file invalid or playback fails
    func startOverlay(url: URL, configuration: OverlayConfiguration) async throws {
        // 1. Stop existing overlay if any
        if overlayPlayer != nil {
            await stopOverlay()
        }
        
        // 2. Create overlay player nodes
        // These nodes are created locally and immediately transferred to OverlayPlayerActor
        // where they will be actor-isolated. This is safe despite the non-Sendable types.
        nonisolated(unsafe) let playerNode = AVAudioPlayerNode()
        nonisolated(unsafe) let mixerNode = AVAudioMixerNode()
        
        // 3. Attach nodes to engine
        engine.attach(playerNode)
        engine.attach(mixerNode)
        
        // 4. Connect: PlayerC → MixerC → MainMixer
        let format = engine.outputNode.outputFormat(forBus: 0)
        engine.connect(playerNode, to: mixerNode, format: format)
        engine.connect(mixerNode, to: engine.mainMixerNode, format: format)
        
        // 5. Create overlay player actor
        overlayPlayer = OverlayPlayerActor(
            player: playerNode,
            mixer: mixerNode,
            configuration: configuration
        )
        
        // 6. Load file and start playback
        try await overlayPlayer?.load(url: url)
        try await overlayPlayer?.play()
    }
    
    /// Stop overlay playback with fade-out
    func stopOverlay() async {
        guard let player = overlayPlayer else { return }
        
        await player.stop()
        overlayPlayer = nil
    }
    
    /// Pause overlay playback
    func pauseOverlay() async {
        await overlayPlayer?.pause()
    }
    
    /// Resume overlay playback
    func resumeOverlay() async {
        guard let player = overlayPlayer else { return }
        try? await player.resume()
    }
    
    /// Replace current overlay file with crossfade
    /// - Parameter url: New audio file URL
    /// - Throws: AudioPlayerError if no overlay is active
    func replaceOverlay(url: URL) async throws {
        guard let player = overlayPlayer else {
            throw AudioPlayerError.invalidState(
                current: "no overlay",
                attempted: "replace"
            )
        }
        
        try await player.replaceFile(url: url)
    }
    
    /// Set overlay volume independently
    /// - Parameter volume: Volume level (0.0-1.0)
    func setOverlayVolume(_ volume: Float) async {
        await overlayPlayer?.setVolume(volume)
    }
    
    // MARK: - Global Control
    
    /// Pause both main player and overlay
    /// Useful for phone call interruptions or user pause action
    func pauseAll() async {
        // Pause main player (synchronous)
        pause()
        
        // Pause overlay if active
        await pauseOverlay()
    }
    
    /// Resume both main player and overlay
    /// Restore playback after interruption
    func resumeAll() async {
        // Resume main player (synchronous)
        play()
        
        // Resume overlay if active
        await resumeOverlay()
    }
    
    /// Stop both main player and overlay completely
    /// Emergency stop or full reset scenario
    func stopAll() async {
        // Stop main player system
        stopBothPlayers()
        
        // Stop overlay system
        await stopOverlay()
    }
    
    /// Get current overlay state
    /// - Returns: Current overlay state, or `.idle` if no overlay loaded
    func getOverlayState() async -> OverlayState {
        guard let player = overlayPlayer else {
            return .idle
        }
        return await player.getState()
    }
}

// MARK: - Player Node Enum

private enum PlayerNode {
    case a
    case b
}
