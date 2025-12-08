import Foundation

/// Options for enabling remote commands (lock screen, Control Center, headphones)
public struct RemoteCommandOptions: OptionSet, Sendable {
    public let rawValue: Int
    
    public init(rawValue: Int) {
        self.rawValue = rawValue
    }
    
    // MARK: - Individual Commands
    
    /// Play command
    public static let play = RemoteCommandOptions(rawValue: 1 << 0)
    
    /// Pause command
    public static let pause = RemoteCommandOptions(rawValue: 1 << 1)
    
    /// Stop command
    public static let stop = RemoteCommandOptions(rawValue: 1 << 2)
    
    /// Toggle play/pause (headphone button)
    public static let togglePlayPause = RemoteCommandOptions(rawValue: 1 << 3)
    
    /// Skip forward command
    public static let skipForward = RemoteCommandOptions(rawValue: 1 << 4)
    
    /// Skip backward command
    public static let skipBackward = RemoteCommandOptions(rawValue: 1 << 5)
    
    /// Next track command
    public static let nextTrack = RemoteCommandOptions(rawValue: 1 << 6)
    
    /// Previous track command
    public static let previousTrack = RemoteCommandOptions(rawValue: 1 << 7)
    
    /// Seek to position command
    public static let seekTo = RemoteCommandOptions(rawValue: 1 << 8)
    
    /// Change playback rate command
    public static let changePlaybackRate = RemoteCommandOptions(rawValue: 1 << 9)
    
    // MARK: - Presets
    
    /// Play and pause only
    public static let playbackOnly: RemoteCommandOptions = [.play, .pause, .togglePlayPause]
    
    /// Standard meditation controls (default)
    public static let standard: RemoteCommandOptions = [.play, .pause, .togglePlayPause, .skipForward, .skipBackward]
    
    /// Full playback controls
    public static let full: RemoteCommandOptions = [
        .play, .pause, .stop, .togglePlayPause,
        .skipForward, .skipBackward,
        .nextTrack, .previousTrack,
        .seekTo, .changePlaybackRate
    ]
    
    /// No commands enabled
    public static let none: RemoteCommandOptions = []
}
