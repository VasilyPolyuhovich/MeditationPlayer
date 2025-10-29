//
//  AudioSessionManaging.swift
//  AudioServiceKit
//
//  Protocol abstraction for audio session management
//

import Foundation

/// Protocol for managing AVAudioSession lifecycle
///
/// Abstracts audio session operations to enable dependency injection
/// and unit testing with mock implementations.
///
/// **Responsibility:** Audio session control only
protocol AudioSessionManaging: Actor {
    /// Activate audio session
    /// - Throws: AudioPlayerError if activation fails
    func activate() async throws

    /// Ensure audio session is active (activate if needed)
    /// - Throws: AudioPlayerError if activation fails
    func ensureActive() async throws

    /// Deactivate audio session
    /// - Throws: AudioPlayerError if deactivation fails
    func deactivate() async throws
    
    /// Force reconfigure audio session with our category and options
    /// Used for recovery after external code changes audio session category
    /// - Throws: AudioPlayerError if reconfiguration fails
    func forceReconfigure() async throws
}
