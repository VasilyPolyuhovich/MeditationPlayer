//
//  PlaylistManaging.swift
//  AudioServiceKit
//
//  Protocol abstraction for playlist management
//

import Foundation
import AudioServiceCore

/// Protocol for managing playlist operations
///
/// Abstracts playlist operations to enable dependency injection
/// and unit testing with mock implementations.
///
/// **Responsibility:** Playlist navigation and queries
protocol PlaylistManaging: Actor {
    /// Get current track from playlist
    /// - Returns: Current track or nil if playlist empty
    func getCurrentTrack() async -> Track?

    /// Get next track in playlist
    /// - Returns: Next track or nil if at end
    func getNextTrack() async -> Track?

    /// Get previous track in playlist
    /// - Returns: Previous track or nil if at beginning
    func getPreviousTrack() async -> Track?

    /// Move to next track
    /// - Throws: AudioPlayerError if operation fails
    func moveToNext() async throws

    /// Move to previous track
    /// - Throws: AudioPlayerError if operation fails
    func moveToPrevious() async throws

    /// Check if there's a next track
    /// - Returns: true if next track exists
    func hasNextTrack() async -> Bool

    /// Check if there's a previous track
    /// - Returns: true if previous track exists
    func hasPreviousTrack() async -> Bool
}
