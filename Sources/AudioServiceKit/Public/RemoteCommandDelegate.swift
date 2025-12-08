import Foundation
import AudioServiceCore

/// Delegate protocol for customizing remote command behavior
///
/// Implement this protocol to:
/// - Handle remote commands with custom logic
/// - Customize Now Playing info displayed on lock screen
/// - Configure which commands are enabled
///
/// All methods have default implementations that use SDK defaults.
///
/// **Example:**
/// ```swift
/// class MyController: RemoteCommandDelegate {
///     func remoteCommandShouldHandleSkipForward(_ interval: TimeInterval) async -> Bool {
///         await myChapterManager.next()
///         return false  // handled, skip SDK default
///     }
///
///     func remoteCommandEnabledCommands() -> RemoteCommandOptions {
///         [.play, .pause, .nextTrack, .previousTrack]
///     }
/// }
///
/// player.remoteCommands.delegate = myController
/// ```
@MainActor
public protocol RemoteCommandDelegate: AnyObject {
    
    // MARK: - Command Handlers
    
    /// Called when play command is received
    /// - Returns: `true` to use SDK default behavior, `false` if handled (skip SDK)
    func remoteCommandShouldHandlePlay() async -> Bool
    
    /// Called when pause command is received
    /// - Returns: `true` to use SDK default behavior, `false` if handled (skip SDK)
    func remoteCommandShouldHandlePause() async -> Bool
    
    /// Called when stop command is received
    /// - Returns: `true` to use SDK default behavior, `false` if handled (skip SDK)
    func remoteCommandShouldHandleStop() async -> Bool
    
    /// Called when toggle play/pause command is received (headphone button)
    /// - Returns: `true` to use SDK default behavior, `false` if handled (skip SDK)
    func remoteCommandShouldHandleTogglePlayPause() async -> Bool
    
    /// Called when skip forward command is received
    /// - Parameter interval: Skip interval in seconds
    /// - Returns: `true` to use SDK default behavior, `false` if handled (skip SDK)
    func remoteCommandShouldHandleSkipForward(_ interval: TimeInterval) async -> Bool
    
    /// Called when skip backward command is received
    /// - Parameter interval: Skip interval in seconds
    /// - Returns: `true` to use SDK default behavior, `false` if handled (skip SDK)
    func remoteCommandShouldHandleSkipBackward(_ interval: TimeInterval) async -> Bool
    
    /// Called when next track command is received
    /// - Returns: `true` to use SDK default behavior, `false` if handled (skip SDK)
    func remoteCommandShouldHandleNextTrack() async -> Bool
    
    /// Called when previous track command is received
    /// - Returns: `true` to use SDK default behavior, `false` if handled (skip SDK)
    func remoteCommandShouldHandlePreviousTrack() async -> Bool
    
    /// Called when seek to position command is received
    /// - Parameter position: Target position in seconds
    /// - Returns: `true` to use SDK default behavior, `false` if handled (skip SDK)
    func remoteCommandShouldHandleSeekTo(_ position: TimeInterval) async -> Bool
    
    /// Called when playback rate change is requested
    /// - Parameter rate: Requested playback rate
    /// - Returns: `true` to use SDK default behavior, `false` if handled (skip SDK)
    func remoteCommandShouldHandleChangePlaybackRate(_ rate: Float) async -> Bool
    
    // MARK: - Now Playing Customization
    
    /// Provide custom Now Playing info dictionary
    ///
    /// Return a dictionary with `MPMediaItemProperty*` and `MPNowPlayingInfoProperty*` keys
    /// to completely customize the lock screen display.
    ///
    /// - Parameters:
    ///   - track: Current track metadata
    ///   - position: Current playback position
    /// - Returns: Custom dictionary, or `nil` to use SDK defaults
    ///
    /// **Example:**
    /// ```swift
    /// func remoteCommandNowPlayingInfo(
    ///     for track: Track.Metadata,
    ///     position: PlaybackPosition
    /// ) -> [String: Any]? {
    ///     return [
    ///         MPMediaItemPropertyTitle: "My Custom Title",
    ///         MPMediaItemPropertyArtist: "My App"
    ///         // Omit duration/elapsed for infinite content
    ///     ]
    /// }
    /// ```
    func remoteCommandNowPlayingInfo(
        for track: Track.Metadata,
        position: PlaybackPosition
    ) -> [String: Any]?
    
    // MARK: - Configuration
    
    /// Which commands should be enabled
    /// Called during setup to configure MPRemoteCommandCenter
    /// - Returns: Commands to enable (default: `.standard`)
    func remoteCommandEnabledCommands() -> RemoteCommandOptions
    
    /// Skip intervals for forward/backward commands
    /// - Returns: Tuple with forward and backward intervals in seconds (default: 15, 15)
    func remoteCommandSkipIntervals() -> (forward: TimeInterval, backward: TimeInterval)
    
    /// Supported playback rates for rate change command
    /// - Returns: Array of supported rates (default: [0.5, 1.0, 1.5, 2.0])
    func remoteCommandSupportedPlaybackRates() -> [Float]
}

// MARK: - Default Implementations

public extension RemoteCommandDelegate {
    
    // All handlers return true by default (use SDK behavior)
    
    func remoteCommandShouldHandlePlay() async -> Bool { true }
    func remoteCommandShouldHandlePause() async -> Bool { true }
    func remoteCommandShouldHandleStop() async -> Bool { true }
    func remoteCommandShouldHandleTogglePlayPause() async -> Bool { true }
    func remoteCommandShouldHandleSkipForward(_ interval: TimeInterval) async -> Bool { true }
    func remoteCommandShouldHandleSkipBackward(_ interval: TimeInterval) async -> Bool { true }
    func remoteCommandShouldHandleNextTrack() async -> Bool { true }
    func remoteCommandShouldHandlePreviousTrack() async -> Bool { true }
    func remoteCommandShouldHandleSeekTo(_ position: TimeInterval) async -> Bool { true }
    func remoteCommandShouldHandleChangePlaybackRate(_ rate: Float) async -> Bool { true }
    
    // Now Playing - nil means use SDK defaults
    func remoteCommandNowPlayingInfo(
        for track: Track.Metadata,
        position: PlaybackPosition
    ) -> [String: Any]? { nil }
    
    // Configuration defaults
    func remoteCommandEnabledCommands() -> RemoteCommandOptions { .standard }
    func remoteCommandSkipIntervals() -> (forward: TimeInterval, backward: TimeInterval) { (15.0, 15.0) }
    func remoteCommandSupportedPlaybackRates() -> [Float] { [0.5, 1.0, 1.5, 2.0] }
}
