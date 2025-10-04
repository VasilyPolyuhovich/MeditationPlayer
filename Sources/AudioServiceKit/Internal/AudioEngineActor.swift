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
        
        // Schedule the file for playback
        player.scheduleFile(file, at: nil) {
            // Completion handler - will be called on audio thread
            // Keep it minimal - no heavy operations here
        }
        
        // Set initial volume for fade in
        if fadeIn {
            mixer.volume = 0.0
            Task {
                await self.fadeVolume(
                    mixer: mixer,
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
    
    // MARK: - Seeking
    
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
        let targetFrame = AVAudioFramePosition(time * sampleRate)
        
        // Clamp to valid range
        let maxFrame = file.length - 1
        let clampedFrame = max(0, min(targetFrame, maxFrame))
        
        // Check if player is currently playing
        let wasPlaying = player.isPlaying
        let currentVolume = mixer.volume
        
        // Stop current playback
        player.stop()
        
        // Schedule from new position
        player.scheduleSegment(
            file,
            startingFrame: clampedFrame,
            frameCount: AVAudioFrameCount(file.length - clampedFrame),
            at: nil
        )
        
        // Resume playback if it was playing before
        if wasPlaying {
            mixer.volume = currentVolume  // Restore volume
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
        let stepTime: TimeInterval = 0.01 // 10ms steps
        let steps = Int(duration / stepTime)
        
        for i in 0...steps {
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
        
        // Ensure final volume is exact
        mixer.volume = to
    }
    
    // MARK: - Playback Position
    
    func getCurrentPosition() -> PlaybackPosition? {
        guard let file = getActiveAudioFile() else { return nil }
        
        let player = getActivePlayerNode()
        
        // Get player time
        guard let nodeTime = player.lastRenderTime,
              let playerTime = player.playerTime(forNodeTime: nodeTime) else {
            return nil
        }
        
        let sampleRate = file.fileFormat.sampleRate
        let currentTime = Double(playerTime.sampleTime) / sampleRate
        let duration = Double(file.length) / sampleRate
        
        return PlaybackPosition(currentTime: currentTime, duration: duration)
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
    
    /// Schedule the current audio file on the secondary player for loop crossfade
    func scheduleLoopOnSecondaryPlayer() {
        guard let file = getActiveAudioFile() else { return }
        
        let player = getInactivePlayerNode()
        let mixer = getInactiveMixerNode()
        
        // Set mixer volume to 0 (will be faded in)
        mixer.volume = 0.0
        
        // Schedule the same file from the beginning
        player.scheduleFile(file, at: nil)
        
        // Start playback
        player.play()
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
    
    /// Schedule file on secondary player and start playback
    func scheduleFileOnSecondaryPlayer() {
        guard let file = getInactiveAudioFile() else { return }
        
        let player = getInactivePlayerNode()
        let mixer = getInactiveMixerNode()
        
        // Set mixer volume to 0 (will be faded in)
        mixer.volume = 0.0
        
        // Schedule the file from the beginning
        player.scheduleFile(file, at: nil)
        
        // Start playback
        player.play()
    }
    
    /// Stop the currently active player
    func stopActivePlayer() {
        let player = getActivePlayerNode()
        player.stop()
    }
    
    /// Get inactive audio file
    private func getInactiveAudioFile() -> AVAudioFile? {
        return activePlayer == .a ? audioFileB : audioFileA
    }
    
    // MARK: - Private Helper Methods (for inactive player)
    
    private func getInactivePlayerNode() -> AVAudioPlayerNode {
        return activePlayer == .a ? playerNodeB : playerNodeA
    }
    
    private func getInactiveMixerNode() -> AVAudioMixerNode {
        return activePlayer == .a ? mixerNodeB : mixerNodeA
    }
}

// MARK: - Player Node Enum

private enum PlayerNode {
    case a
    case b
}
