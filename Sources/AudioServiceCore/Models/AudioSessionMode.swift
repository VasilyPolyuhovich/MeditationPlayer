import Foundation

/// Defines how AudioPlayerService manages the AVAudioSession
///
/// iOS audio session is a global resource shared between all apps.
/// This mode determines whether the SDK manages the session or delegates to app developer.
public enum AudioSessionMode: Sendable, Equatable {
    /// SDK manages audio session (default, recommended)
    ///
    /// **Behavior:**
    /// - SDK configures AVAudioSession category and options
    /// - SDK activates/deactivates session automatically
    /// - Self-healing: recovers from media services reset
    /// - Best for: Most apps, simple integration
    ///
    /// **Example:**
    /// ```swift
    /// let player = try await AudioPlayerService(
    ///     audioSessionMode: .managed  // Default
    /// )
    /// ```
    case managed
    
    /// App developer manages audio session (advanced)
    ///
    /// **Behavior:**
    /// - SDK does NOT configure or activate audio session
    /// - SDK validates session configuration at init
    /// - Throws error if session incompatible (e.g., .record category)
    /// - Logs warning if session suboptimal
    /// - Best for: Apps needing custom session management (e.g., recording + playback)
    ///
    /// **Requirements:**
    /// - App must configure AVAudioSession before creating player
    /// - Category must be compatible with playback (.playback, .playAndRecord)
    /// - Category must NOT be .record (playback incompatible)
    ///
    /// **Example:**
    /// ```swift
    /// // 1. Configure session (app responsibility)
    /// let session = AVAudioSession.sharedInstance()
    /// try session.setCategory(.playAndRecord, options: [.allowBluetoothA2DP])
    /// try session.setActive(true)
    ///
    /// // 2. Create player (will validate session)
    /// let player = try await AudioPlayerService(
    ///     audioSessionMode: .external
    /// )
    /// ```
    ///
    /// **Error Messages:**
    /// - Incompatible category → throws with fix instructions
    /// - Suboptimal configuration → warning in console
    case external
}
