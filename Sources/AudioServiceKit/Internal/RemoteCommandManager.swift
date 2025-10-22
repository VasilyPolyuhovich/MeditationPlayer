import MediaPlayer
import AudioServiceCore

/// Manager for handling remote control commands and Now Playing info
/// All operations are @MainActor isolated for thread safety
@MainActor
final class RemoteCommandManager: Sendable {
    // MARK: - Properties
    
    // FIXED: Removed 'nonisolated' - these MUST be MainActor isolated
    // MPRemoteCommandCenter and MPNowPlayingInfoCenter are UIKit types that require MainActor
    private let commandCenter: MPRemoteCommandCenter
    private let nowPlayingCenter: MPNowPlayingInfoCenter
    
    // MARK: - Initialization
    
    // FIXED: Removed 'nonisolated' from init - must be MainActor
    init() {
        self.commandCenter = MPRemoteCommandCenter.shared()
        self.nowPlayingCenter = MPNowPlayingInfoCenter.default()
    }
    
    // MARK: - Setup Commands
    
    func setupCommands(
        playHandler: @escaping @Sendable () async -> Void,
        pauseHandler: @escaping @Sendable () async -> Void,
        skipForwardHandler: @escaping @Sendable (TimeInterval) async -> Void,
        skipBackwardHandler: @escaping @Sendable (TimeInterval) async -> Void
    ) {
        // All command setup must happen on MainActor
        
        // Enable play command
        commandCenter.playCommand.isEnabled = true
        commandCenter.playCommand.addTarget { _ in
            Task { @MainActor in
                await playHandler()
            }
            return .success
        }
        
        // Enable pause command
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.pauseCommand.addTarget { _ in
            Task { @MainActor in
                await pauseHandler()
            }
            return .success
        }
        
        // Enable skip forward command (15 seconds)
        commandCenter.skipForwardCommand.isEnabled = true
        commandCenter.skipForwardCommand.preferredIntervals = [15.0]
        commandCenter.skipForwardCommand.addTarget { event in
            if let skipEvent = event as? MPSkipIntervalCommandEvent {
                Task { @MainActor in
                    await skipForwardHandler(skipEvent.interval)
                }
            }
            return .success
        }
        
        // Enable skip backward command (15 seconds)
        commandCenter.skipBackwardCommand.isEnabled = true
        commandCenter.skipBackwardCommand.preferredIntervals = [15.0]
        commandCenter.skipBackwardCommand.addTarget { event in
            if let skipEvent = event as? MPSkipIntervalCommandEvent {
                Task { @MainActor in
                    await skipBackwardHandler(skipEvent.interval)
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
    
    func updatePlaybackPosition(
        elapsedTime: TimeInterval,
        playbackRate: Double
    ) {
        guard var info = nowPlayingCenter.nowPlayingInfo else { return }
        
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsedTime
        info[MPNowPlayingInfoPropertyPlaybackRate] = playbackRate
        
        nowPlayingCenter.nowPlayingInfo = info
    }
    
    func clearNowPlayingInfo() {
        nowPlayingCenter.nowPlayingInfo = nil
    }

    // MARK: - Helper Methods for Protocol Conformance

    func updateNowPlayingInfo(track: TrackInfo) {
        updateNowPlayingInfo(
            title: track.title,
            artist: track.artist,
            duration: track.duration,
            elapsedTime: 0,
            playbackRate: 0
        )
    }

    func updateNowPlayingPlaybackRate(_ rate: Float) {
        guard var info = nowPlayingCenter.nowPlayingInfo else { return }
        info[MPNowPlayingInfoPropertyPlaybackRate] = Double(rate)
        nowPlayingCenter.nowPlayingInfo = info
    }

    func updateNowPlayingPosition(_ position: PlaybackPosition) {
        updatePlaybackPosition(
            elapsedTime: position.currentTime,
            playbackRate: 1.0
        )
    }
}

// MARK: - RemoteCommandManaging Conformance

extension RemoteCommandManager: RemoteCommandManaging {
    func updateNowPlaying(track: TrackInfo) async {
        updateNowPlayingInfo(track: track)
    }

    func updatePlaybackRate(_ rate: Float) async {
        updateNowPlayingPlaybackRate(rate)
    }

    func clearNowPlaying() async {
        clearNowPlayingInfo()
    }

    func updatePlaybackPosition(_ position: PlaybackPosition) async {
        updateNowPlayingPosition(position)
    }
}
