import MediaPlayer
import AudioServiceCore

/// Manager for handling remote control commands and Now Playing info
final class RemoteCommandManager: @unchecked Sendable {
    // MARK: - Properties
    
    private let commandCenter: MPRemoteCommandCenter
    private let nowPlayingCenter: MPNowPlayingInfoCenter
    
    // Command handlers
    private var playHandler: (@Sendable () async -> Void)?
    private var pauseHandler: (@Sendable () async -> Void)?
    private var skipForwardHandler: (@Sendable (TimeInterval) async -> Void)?
    private var skipBackwardHandler: (@Sendable (TimeInterval) async -> Void)?
    
    // MARK: - Initialization
    
    init() {
        self.commandCenter = MPRemoteCommandCenter.shared()
        self.nowPlayingCenter = MPNowPlayingInfoCenter.default()
    }
    
    // MARK: - Setup Commands
    
    @MainActor
    func setupCommands(
        playHandler: @escaping @Sendable () async -> Void,
        pauseHandler: @escaping @Sendable () async -> Void,
        skipForwardHandler: @escaping @Sendable (TimeInterval) async -> Void,
        skipBackwardHandler: @escaping @Sendable (TimeInterval) async -> Void
    ) {
        self.playHandler = playHandler
        self.pauseHandler = pauseHandler
        self.skipForwardHandler = skipForwardHandler
        self.skipBackwardHandler = skipBackwardHandler
        
        // Enable play command
        commandCenter.playCommand.isEnabled = true
        commandCenter.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                await self?.playHandler?()
            }
            return .success
        }
        
        // Enable pause command
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                await self?.pauseHandler?()
            }
            return .success
        }
        
        // Enable skip forward command (15 seconds)
        commandCenter.skipForwardCommand.isEnabled = true
        commandCenter.skipForwardCommand.preferredIntervals = [15.0]
        commandCenter.skipForwardCommand.addTarget { [weak self] event in
            if let skipEvent = event as? MPSkipIntervalCommandEvent {
                Task { @MainActor in
                    await self?.skipForwardHandler?(skipEvent.interval)
                }
            }
            return .success
        }
        
        // Enable skip backward command (15 seconds)
        commandCenter.skipBackwardCommand.isEnabled = true
        commandCenter.skipBackwardCommand.preferredIntervals = [15.0]
        commandCenter.skipBackwardCommand.addTarget { [weak self] event in
            if let skipEvent = event as? MPSkipIntervalCommandEvent {
                Task { @MainActor in
                    await self?.skipBackwardHandler?(skipEvent.interval)
                }
            }
            return .success
        }
        
        // Disable commands we don't support
        commandCenter.nextTrackCommand.isEnabled = false
        commandCenter.previousTrackCommand.isEnabled = false
        commandCenter.changePlaybackRateCommand.isEnabled = false
        commandCenter.seekBackwardCommand.isEnabled = false
        commandCenter.seekForwardCommand.isEnabled = false
    }
    
    @MainActor
    func removeCommands() {
        commandCenter.playCommand.removeTarget(nil)
        commandCenter.pauseCommand.removeTarget(nil)
        commandCenter.skipForwardCommand.removeTarget(nil)
        commandCenter.skipBackwardCommand.removeTarget(nil)
        
        commandCenter.playCommand.isEnabled = false
        commandCenter.pauseCommand.isEnabled = false
        commandCenter.skipForwardCommand.isEnabled = false
        commandCenter.skipBackwardCommand.isEnabled = false
    }
    
    // MARK: - Now Playing Info
    
    @MainActor
    func updateNowPlayingInfo(
        title: String?,
        artist: String?,
        duration: TimeInterval,
        elapsedTime: TimeInterval,
        playbackRate: Double
    ) {
        var nowPlayingInfo = [String: Any]()
        
        if let title = title {
            nowPlayingInfo[MPMediaItemPropertyTitle] = title
        }
        
        if let artist = artist {
            nowPlayingInfo[MPMediaItemPropertyArtist] = artist
        }
        
        nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = duration
        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsedTime
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = playbackRate
        
        nowPlayingCenter.nowPlayingInfo = nowPlayingInfo
    }
    
    @MainActor
    func updatePlaybackPosition(
        elapsedTime: TimeInterval,
        playbackRate: Double
    ) {
        guard var info = nowPlayingCenter.nowPlayingInfo else { return }
        
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsedTime
        info[MPNowPlayingInfoPropertyPlaybackRate] = playbackRate
        
        nowPlayingCenter.nowPlayingInfo = info
    }
    
    @MainActor
    func clearNowPlayingInfo() {
        nowPlayingCenter.nowPlayingInfo = nil
    }
}
