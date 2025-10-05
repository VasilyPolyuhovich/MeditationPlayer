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
        getActivePlayerNode().pause()
    }
    
    func play() {
        getActivePlayerNode().play()
    }
    
    /// Stop both players completely and reset volumes
    func stopBothPlayers() {
        playerNodeA.stop()
        playerNodeB.stop()
        mixerNodeA.volume = 0.0
        mixerNodeB.volume = 0.0
        
        if isEngineRunning {
            engine.stop()
            isEngineRunning = false
        }
    }
    
    /// Complete reset - clears all state and files
    func fullReset() {
        // Stop everything
        stopBothPlayers()
        
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
                await self.fadeActiveMixer(
                    from: 0.0,
                    to: 1.0,
                    duration: fadeInDuration,
                    curve: fadeCurve
                )
            }
        } else {
            mixer.volume = 1.0
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
        engine.mainMixerNode.volume = volume
    }
    
    func fadeVolume(
        mixer: AVAudioMixerNode,
        from: Float,
        to: Float,
        duration: TimeInterval,
        curve: FadeCurve = .equalPower
    ) async {
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
        
        for i in 0...steps {
            // FIXED Issue #10A: Check for task cancellation on every step
            // If fade is interrupted (pause/stop) → abort gracefully
            guard !Task.isCancelled else {
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
            
            try? await Task.sleep(nanoseconds: UInt64(stepTime * 1_000_000_000))
        }
        
        // Ensure final volume is exact (only if not cancelled)
        if !Task.isCancelled {
            mixer.volume = to
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
        
        // Add buffer for scheduling (2048 samples ≈ 46ms at 44.1kHz)
        let bufferSamples: AVAudioFramePosition = 2048
        let startSampleTime = lastRenderTime.sampleTime + bufferSamples
        
        return AVAudioTime(
            sampleTime: startSampleTime,
            atRate: lastRenderTime.sampleRate
        )
    }
    
    /// Perform synchronized crossfade between active and inactive players
    /// FIXED Issue #10A: Added graceful interruption handling
    func performSynchronizedCrossfade(
        duration: TimeInterval,
        curve: FadeCurve
    ) async {
        let inactivePlayer = getInactivePlayerNode()
        
        // FIXED Issue #10A: Early exit if task already cancelled
        guard !Task.isCancelled else { return }
        
        // Get synchronized start time
        let syncTime = getSyncedStartTime()
        
        // Start inactive player at exact time for sample-accurate sync
        if let syncTime = syncTime {
            inactivePlayer.play(at: syncTime)
            // Small delay to ensure player has started
            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
        } else {
            // Fallback: start immediately
            inactivePlayer.play()
        }
        
        // FIXED Issue #10A: Check again after suspension point
        guard !Task.isCancelled else {
            // Interrupted during startup - stop inactive player
            inactivePlayer.stop()
            return
        }
        
        // Perform volume fades while BOTH players are running
        // fadeVolume() now checks Task.isCancelled internally
        async let fadeOut: () = fadeActiveMixer(
            from: 1.0,
            to: 0.0,
            duration: duration,
            curve: curve
        )
        
        async let fadeIn: () = fadeInactiveMixer(
            from: 0.0,
            to: 1.0,
            duration: duration,
            curve: curve
        )
        
        // Wait for both fades to complete (may abort early if cancelled)
        await fadeOut
        await fadeIn
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
    
    /// Fade the active mixer volume (actor-isolated)
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
    
    /// Fade the inactive mixer volume (actor-isolated)
    func fadeInactiveMixer(
        from: Float,
        to: Float,
        duration: TimeInterval,
        curve: FadeCurve = .equalPower
    ) async {
        let mixer = getInactiveMixerNode()
        await fadeVolume(
            mixer: mixer,
            from: from,
            to: to,
            duration: duration,
            curve: curve
        )
    }
    

    
    /// Switch the active player (used after crossfade completes)
    func switchActivePlayer() {
        // Store the file reference before switch
        let currentFile = getActiveAudioFile()
        
        // Switch active player
        activePlayer = activePlayer == .a ? .b : .a
        
        // Update the new active player's file reference
        switch activePlayer {
        case .a:
            audioFileA = currentFile
        case .b:
            audioFileB = currentFile
        }
    }
    
    /// Load audio file on the secondary player (for replace/next track)
    func loadAudioFileOnSecondaryPlayer(url: URL) throws -> TrackInfo {
        let file = try AVAudioFile(forReading: url)
        
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
}

// MARK: - Player Node Enum

private enum PlayerNode {
    case a
    case b
}
