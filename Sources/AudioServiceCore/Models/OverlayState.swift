//
//  OverlayState.swift
//  AudioServiceCore
//
//  Created on 2025-10-09.
//  Feature #4: Overlay Player
//

import Foundation

/// Represents the current state of the overlay audio player.
///
/// The overlay player maintains an independent lifecycle from the main audio player,
/// allowing it to be controlled separately for ambient sounds, timer bells, or effects.
///
/// ## State Transitions:
/// ```
/// idle → preparing → playing ⟷ paused
///                      ↓
///                  stopping → idle
/// ```
///
/// ## Example:
/// ```swift
/// // Initial state
/// overlay.state == .idle
///
/// // Loading file
/// try await service.startOverlay(url: rainURL, configuration: .ambient)
/// // State: idle → preparing → playing
///
/// // User pauses
/// await service.pauseOverlay()
/// // State: playing → paused
///
/// // User resumes
/// await service.resumeOverlay()
/// // State: paused → playing
///
/// // User stops with fade
/// await service.stopOverlay()
/// // State: playing → stopping → idle
/// ```
public enum OverlayState: Sendable, Equatable {
  /// Overlay player is not loaded or has been stopped.
  ///
  /// This is the initial state and the state after stopping.
  /// No audio file is loaded, and no resources are allocated.
  case idle
  
  /// Overlay audio file is being loaded and prepared for playback.
  ///
  /// Transitioning from `idle` to `playing`. This state is typically brief
  /// as file loading happens asynchronously.
  case preparing
  
  /// Overlay audio is currently playing.
  ///
  /// The audio is actively rendering and can be heard alongside the main track.
  /// From this state, you can:
  /// - Pause playback (`pauseOverlay()`)
  /// - Stop with fade (`stopOverlay()`)
  /// - Replace file (`replaceOverlay(url:)`)
  case playing
  
  /// Overlay audio is paused but can be resumed.
  ///
  /// Audio position is preserved. Calling `resumeOverlay()` will continue
  /// playback from where it was paused.
  case paused
  
  /// Overlay audio is fading out before stopping.
  ///
  /// This state occurs when `stopOverlay()` is called with a fade-out duration.
  /// After the fade completes, the state transitions to `idle`.
  case stopping
}

// MARK: - CustomStringConvertible

extension OverlayState: CustomStringConvertible {
  public var description: String {
    switch self {
    case .idle: return "Idle"
    case .preparing: return "Preparing"
    case .playing: return "Playing"
    case .paused: return "Paused"
    case .stopping: return "Stopping"
    }
  }
}

// MARK: - State Queries

public extension OverlayState {
  /// Indicates whether the overlay is actively playing audio.
  var isPlaying: Bool {
    self == .playing
  }
  
  /// Indicates whether the overlay is paused and can be resumed.
  var isPaused: Bool {
    self == .paused
  }
  
  /// Indicates whether the overlay is in a transitional state.
  var isTransitioning: Bool {
    self == .preparing || self == .stopping
  }
  
  /// Indicates whether the overlay is ready to load new audio.
  var isIdle: Bool {
    self == .idle
  }
}
