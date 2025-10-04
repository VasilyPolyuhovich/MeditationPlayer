import Foundation
import AVFoundation
import AudioServiceCore

/// Main audio player service implementing the AudioPlayerProtocol
public actor AudioPlayerService: AudioPlayerProtocol {
    // MARK: - Properties
    
    public private(set) var state: PlayerState
    public private(set) var configuration: AudioConfiguration
    public private(set) var currentTrack: TrackInfo?
    public private(set) var playbackPosition: PlaybackPosition?
    
    // Internal components
    private let audioEngine: AudioEngineActor
    private let sessionManager: AudioSessionManager
    private nonisolated let remoteCommandManager: RemoteCommandManager
    private var stateMachine: AudioStateMachine!
    
    // Playback timer for position updates
    private var playbackTimer: Task<Void, Never>?
    
    // Observers
    private var observers: [AudioPlayerObserver] = []
    
    // MARK: - Initialization
    
    public init(configuration: AudioConfiguration = AudioConfiguration()) {
        self.state = .finished
        self.configuration = configuration
        self.audioEngine = AudioEngineActor()
        self.sessionManager = AudioSessionManager()
        self.remoteCommandManager = RemoteCommandManager()
    }
    
    /// Setup the service (must be called after initialization)
    public func setup() async {
        // Initialize components
        await audioEngine.setup()
        await sessionManager.setup()
        
        // Initialize state machine
        initializeStateMachine()
        await setupSessionHandlers()
        await setupRemoteCommands()
    }
    
    private func initializeStateMachine() {
        self.stateMachine = AudioStateMachine(context: self)
    }
    
    // MARK: - Setup
    
    private func setupSessionHandlers() async {
        // Handle interruptions
        await sessionManager.setInterruptionHandler { [weak self] shouldResume in
            guard let self = self else { return }
            Task {
                await self.handleInterruption(shouldResume: shouldResume)
            }
        }
        
        // Handle route changes
        await sessionManager.setRouteChangeHandler { [weak self] reason in
            guard let self = self else { return }
            Task {
                await self.handleRouteChange(reason: reason)
            }
        }
    }
    
    private func setupRemoteCommands() {
        Task { @MainActor in
            remoteCommandManager.setupCommands(
                playHandler: { [weak self] in
                    try? await self?.resume()
                },
                pauseHandler: { [weak self] in
                    try? await self?.pause()
                },
                skipForwardHandler: { [weak self] interval in
                    try? await self?.skipForward(by: interval)
                },
                skipBackwardHandler: { [weak self] interval in
                    try? await self?.skipBackward(by: interval)
                }
            )
        }
    }
    
    // MARK: - AudioPlayerProtocol Implementation
    
    public func startPlaying(url: URL, configuration: AudioConfiguration) async throws {
        // Validate configuration
        try configuration.validate()
        self.configuration = configuration
        
        // Configure audio session
        try await sessionManager.configure()
        try await sessionManager.activate()
        
        // Prepare audio engine
        try await audioEngine.prepare()
        
        // Load audio file
        let trackInfo = try await audioEngine.loadAudioFile(url: url)
        self.currentTrack = trackInfo
        
        // Enter preparing state
        guard await stateMachine.enterPreparing() else {
            throw AudioPlayerError.invalidState(
                current: state.description,
                attempted: "start playing"
            )
        }
        
        // Update now playing info
        await updateNowPlayingInfo()
        
        // Start playback timer
        startPlaybackTimer()
    }
    
    public func pause() async throws {
        guard await stateMachine.enterPaused() else {
            throw AudioPlayerError.invalidState(
                current: state.description,
                attempted: "pause"
            )
        }
        
        await audioEngine.pause()
        await updateNowPlayingPlaybackRate(0.0)
    }
    
    public func resume() async throws {
        guard await stateMachine.enterPlaying() else {
            throw AudioPlayerError.invalidState(
                current: state.description,
                attempted: "resume"
            )
        }
        
        await updateNowPlayingPlaybackRate(1.0)
    }
    
    public func stop() async {
        stopPlaybackTimer()
        await audioEngine.stop()
        _ = await stateMachine.enterFinished()
        
        Task { @MainActor in
            remoteCommandManager.clearNowPlayingInfo()
        }
    }
    
    public func finish(fadeDuration: TimeInterval?) async throws {
        let duration = fadeDuration ?? configuration.fadeOutDuration
        
        guard await stateMachine.enterFadingOut(duration: duration) else {
            throw AudioPlayerError.invalidState(
                current: state.description,
                attempted: "finish"
            )
        }
    }
    
    public func skipForward(by interval: TimeInterval = 15.0) async throws {
        guard let position = playbackPosition else {
            throw AudioPlayerError.invalidState(
                current: "no playback position",
                attempted: "skip forward"
            )
        }
        
        let newTime = min(position.currentTime + interval, position.duration)
        try await audioEngine.seek(to: newTime)
    }
    
    public func skipBackward(by interval: TimeInterval = 15.0) async throws {
        guard let position = playbackPosition else {
            throw AudioPlayerError.invalidState(
                current: "no playback position",
                attempted: "skip backward"
            )
        }
        
        let newTime = max(position.currentTime - interval, 0)
        try await audioEngine.seek(to: newTime)
    }
    
    public func setVolume(_ volume: Float) async {
        let clampedVolume = max(0.0, min(1.0, volume))
        await audioEngine.setVolume(clampedVolume)
    }
    
    // MARK: - Observers
    
    public func addObserver(_ observer: AudioPlayerObserver) {
        observers.append(observer)
    }
    
    public func removeAllObservers() {
        observers.removeAll()
    }
    
    private func notifyObservers(stateChange state: PlayerState) {
        for observer in observers {
            Task {
                await observer.playerStateDidChange(state)
            }
        }
    }
    
    private func notifyObservers(positionUpdate position: PlaybackPosition) {
        for observer in observers {
            Task {
                await observer.playbackPositionDidUpdate(position)
            }
        }
    }
    
    private func notifyObservers(error: AudioPlayerError) {
        for observer in observers {
            Task {
                await observer.playerDidEncounterError(error)
            }
        }
    }
    
    // MARK: - Playback Timer
    
    private func startPlaybackTimer() {
        stopPlaybackTimer()
        
        playbackTimer = Task {
            while !Task.isCancelled {
                // Update position every 0.5 seconds
                try? await Task.sleep(nanoseconds: 500_000_000)
                
                if let position = await audioEngine.getCurrentPosition() {
                    self.playbackPosition = position
                    notifyObservers(positionUpdate: position)
                    await updateNowPlayingPosition()
                }
            }
        }
    }
    
    private func stopPlaybackTimer() {
        playbackTimer?.cancel()
        playbackTimer = nil
    }
    
    // MARK: - Now Playing Updates
    
    private func updateNowPlayingInfo() async {
        guard let track = currentTrack else { return }
        
        // Read actor-isolated properties before MainActor hop
        let currentTime = playbackPosition?.currentTime ?? 0
        let playbackRate: Double = state == .playing ? 1.0 : 0.0
        
        await MainActor.run {
            remoteCommandManager.updateNowPlayingInfo(
                title: track.title,
                artist: track.artist,
                duration: track.duration,
                elapsedTime: currentTime,
                playbackRate: playbackRate
            )
        }
    }
    
    private func updateNowPlayingPosition() async {
        guard let position = playbackPosition else { return }
        
        // Read actor-isolated state before MainActor hop
        let playbackRate: Double = state == .playing ? 1.0 : 0.0
        
        await MainActor.run {
            remoteCommandManager.updatePlaybackPosition(
                elapsedTime: position.currentTime,
                playbackRate: playbackRate
            )
        }
    }
    
    private func updateNowPlayingPlaybackRate(_ rate: Double) async {
        // Read actor-isolated property before MainActor hop
        let currentTime = playbackPosition?.currentTime ?? 0
        
        await MainActor.run {
            remoteCommandManager.updatePlaybackPosition(
                elapsedTime: currentTime,
                playbackRate: rate
            )
        }
    }
    
    // MARK: - Session Event Handlers
    
    private func handleInterruption(shouldResume: Bool) async {
        if shouldResume {
            // Try to resume playback
            try? await resume()
        } else {
            // Pause playback
            try? await pause()
        }
    }
    
    private func handleRouteChange(reason: AVAudioSession.RouteChangeReason) async {
        switch reason {
        case .oldDeviceUnavailable:
            // Headphones unplugged - pause immediately
            try? await pause()
            
        case .newDeviceAvailable:
            // Headphones plugged in - don't auto-resume, let user decide
            break
            
        case .categoryChange, .override:
            // Route changed - continue playback
            break
            
        default:
            break
        }
    }
}

// MARK: - AudioStateMachineContext

extension AudioPlayerService: AudioStateMachineContext {
    func stateDidChange(to state: PlayerState) async {
        self.state = state
        notifyObservers(stateChange: state)
    }
    
    func startEngine() async throws {
        try await audioEngine.start()
        await audioEngine.scheduleFile(
            fadeIn: true,
            fadeInDuration: configuration.fadeInDuration,
            fadeCurve: configuration.fadeCurve
        )
    }
    
    func stopEngine() async {
        await audioEngine.stop()
        stopPlaybackTimer()
    }
    
    func pausePlayback() async {
        await audioEngine.pause()
    }
    
    func resumePlayback() async throws {
        await audioEngine.play()
    }
    
    func startFadeOut(duration: TimeInterval) async {
        // Fade out directly within actor context
        await audioEngine.fadeActiveMixer(
            from: 1.0,
            to: 0.0,
            duration: duration,
            curve: configuration.fadeCurve
        )
    }
}

// MARK: - PlayerState Description

private extension PlayerState {
    var description: String {
        switch self {
        case .preparing: return "preparing"
        case .playing: return "playing"
        case .paused: return "paused"
        case .fadingOut: return "fading out"
        case .finished: return "finished"
        case .failed: return "failed"
        }
    }
}
