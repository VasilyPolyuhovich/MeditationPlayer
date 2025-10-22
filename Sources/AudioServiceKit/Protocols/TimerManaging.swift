//
//  TimerManaging.swift
//  AudioServiceKit
//
//  Protocol abstraction for timer management
//

import Foundation
import AudioServiceCore

/// Protocol for managing playback timers
///
/// Abstracts timer operations to enable dependency injection
/// and unit testing with mock implementations.
///
/// **Responsibility:** Playback position tracking
protocol TimerManaging: Actor {
    /// Start playback timer with position provider
    /// - Parameter positionProvider: Async closure that returns current position
    func startPlaybackTimer(positionProvider: @escaping () async -> PlaybackPosition?) async

    /// Stop playback timer
    func stopPlaybackTimer() async
}
