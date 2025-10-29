//
//  RemoteCommandManaging.swift
//  AudioServiceKit
//
//  Protocol abstraction for remote command management
//

import Foundation
import AudioServiceCore

/// Protocol for managing MPRemoteCommandCenter and Now Playing
///
/// Abstracts remote command and now playing operations to enable
/// dependency injection and unit testing with mock implementations.
///
/// **Responsibility:** Control Center / Lock Screen integration
/// Note: Implementations are @MainActor (UIKit requirement), not Actor
protocol RemoteCommandManaging {
    /// Update Now Playing info with track details
    /// - Parameter track: Track information to display
    func updateNowPlaying(track: Track.Metadata) async

    /// Update playback rate (0.0 = paused, 1.0 = playing)
    /// - Parameter rate: Playback rate
    func updatePlaybackRate(_ rate: Float) async

    /// Clear Now Playing info
    func clearNowPlaying() async

    /// Update playback position
    /// - Parameter position: Current playback position
    func updatePlaybackPosition(_ position: PlaybackPosition) async
}
