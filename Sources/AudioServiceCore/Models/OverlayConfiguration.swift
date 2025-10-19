//
//  OverlayConfiguration.swift
//  AudioServiceCore
//
//  Created on 2025-10-09.
//  Feature #4: Overlay Player
//

import Foundation

/// Configuration for overlay audio playback.
///
/// Overlay player provides an independent audio layer that plays alongside the main track
/// without interference. Perfect for ambient sounds (rain, ocean), timer bells, or sound effects.
///
/// ## Example: Infinite Rain Loop
/// ```swift
/// var config = OverlayConfiguration.ambient
/// config.loopMode = .infinite
/// config.volume = 0.3
/// config.fadeInDuration = 2.0
/// config.fadeOutDuration = 2.0
/// config.applyFadeOnEachLoop = false  // Continuous loop
///
/// try await service.startOverlay(url: rainURL, configuration: config)
/// ```
///
/// ## Example: Bell Every 5 Minutes (3 times)
/// ```swift
/// let config = OverlayConfiguration.bell(times: 3, interval: 300)
/// try await service.startOverlay(url: bellURL, configuration: config)
///
/// // Timeline:
/// // 0:00  → fadeIn → DING → fadeOut → [5 min silence]
/// // 5:00  → fadeIn → DING → fadeOut → [5 min silence]
/// // 10:00 → fadeIn → DING → fadeOut
/// ```
///
/// - SeeAlso: `AudioPlayerService.startOverlay(url:configuration:)`
public struct OverlayConfiguration: Sendable, Equatable {
  
  // MARK: - Loop Behavior
  
  /// Loop mode determines how many times the overlay audio repeats.
  public var loopMode: LoopMode
  
  /// Delay before starting the next loop iteration (in seconds).
  ///
  /// Used for timer bells or periodic sounds. The delay represents silence between iterations.
  ///
  /// ## Example:
  /// ```swift
  /// config.loopMode = .count(3)
  /// config.loopDelay = 300.0  // 5 minutes between bells
  /// ```
  ///
  /// **Default:** `0.0` (no delay between loops)
  ///
  /// **Valid Range:** `>= 0.0`
  public var loopDelay: TimeInterval
  
  // MARK: - Volume
  
  /// Overlay volume level, independent from main track volume.
  ///
  /// **Default:** `1.0` (full volume)
  ///
  /// **Valid Range:** `0.0...1.0`
  /// - `0.0` = Silent
  /// - `1.0` = Full volume
  public var volume: Float
  
  // MARK: - Fade Settings
  
  /// Duration of fade-in effect when overlay starts (in seconds).
  ///
  /// **Default:** `0.0` (no fade-in)
  ///
  /// **Valid Range:** `>= 0.0`
  public var fadeInDuration: TimeInterval
  
  /// Duration of fade-out effect when overlay stops (in seconds).
  ///
  /// **Default:** `0.0` (no fade-out)
  ///
  /// **Valid Range:** `>= 0.0`
  public var fadeOutDuration: TimeInterval
  
  /// Fade curve algorithm for volume transitions.
  ///
  /// **Default:** `.linear`
  ///
  /// - SeeAlso: `FadeCurve` for available curve types
  public var fadeCurve: FadeCurve
  
  /// Controls whether fade in/out is applied on each loop iteration.
  ///
  /// ## Behavior:
  /// - `true`: Each loop iteration fades in → plays → fades out
  ///   - Best for distinct sounds like bells or chimes
  ///   - Creates clear separation between iterations
  /// - `false`: Fade only on first start and final stop
  ///   - Best for continuous ambient sounds like rain or ocean
  ///   - Smooth continuous playback
  ///
  /// ## Example: Bell with fades
  /// ```swift
  /// config.applyFadeOnEachLoop = true
  /// // Loop 1: fadeIn → DING → fadeOut → [delay]
  /// // Loop 2: fadeIn → DING → fadeOut → [delay]
  /// // Loop 3: fadeIn → DING → fadeOut
  /// ```
  ///
  /// ## Example: Continuous rain
  /// ```swift
  /// config.applyFadeOnEachLoop = false
  /// // Loop 1: fadeIn → rain sound → [no delay]
  /// // Loop 2: rain sound → [no delay]
  /// // Loop 3: rain sound → fadeOut
  /// ```
  ///
  /// **Default:** `true`
  public var applyFadeOnEachLoop: Bool
  
  // MARK: - Initialization
  
  /// Creates a new overlay configuration with default values.
  ///
  /// ## Defaults:
  /// - `loopMode`: `.once`
  /// - `loopDelay`: `0.0`
  /// - `volume`: `1.0`
  /// - `fadeInDuration`: `0.0`
  /// - `fadeOutDuration`: `0.0`
  /// - `fadeCurve`: `.linear`
  /// - `applyFadeOnEachLoop`: `true`
  public init(
    loopMode: LoopMode = .once,
    loopDelay: TimeInterval = 0.0,
    volume: Float = 1.0,
    fadeInDuration: TimeInterval = 0.0,
    fadeOutDuration: TimeInterval = 0.0,
    fadeCurve: FadeCurve = .linear,
    applyFadeOnEachLoop: Bool = true
  ) {
    self.loopMode = loopMode
    self.loopDelay = loopDelay
    self.volume = volume
    self.fadeInDuration = fadeInDuration
    self.fadeOutDuration = fadeOutDuration
    self.fadeCurve = fadeCurve
    self.applyFadeOnEachLoop = applyFadeOnEachLoop
  }
  
  // MARK: - Validation
  
  /// Validates all configuration parameters.
  ///
  /// ## Validation Rules:
  /// - `volume`: Must be in range `0.0...1.0`
  /// - `loopDelay`: Must be `>= 0.0`
  /// - `fadeInDuration`: Must be `>= 0.0`
  /// - `fadeOutDuration`: Must be `>= 0.0`
  /// - `loopMode`: If `.count(n)`, then `n > 0`
  ///
  /// - Returns: `true` if all parameters are valid, `false` otherwise
  public var isValid: Bool {
    guard volume >= 0.0 && volume <= 1.0 else { return false }
    guard loopDelay >= 0.0 else { return false }
    guard fadeInDuration >= 0.0 else { return false }
    guard fadeOutDuration >= 0.0 else { return false }
    
    // Validate loop count if specified
    if case .count(let times) = loopMode {
      guard times > 0 else { return false }
    }
    
    return true
  }
}

// MARK: - Loop Mode

public extension OverlayConfiguration {
  /// Determines how many times the overlay audio repeats.
  enum LoopMode: Sendable, Equatable {
    /// Play audio file once and stop.
    case once
    
    /// Repeat audio a specific number of times.
    ///
    /// - Parameter times: Number of repetitions (must be > 0)
    ///
    /// ## Example:
    /// ```swift
    /// config.loopMode = .count(3)  // Play 3 times total
    /// ```
    case count(Int)
    
    /// Loop audio indefinitely until explicitly stopped.
    ///
    /// ## Example:
    /// ```swift
    /// config.loopMode = .infinite  // Continuous playback
    /// ```
    case infinite
  }
}

// MARK: - Preset Configurations

public extension OverlayConfiguration {
  /// Preset configuration for ambient sounds (rain, ocean, forest).
  ///
  /// ## Settings:
  /// - Loop: Infinite
  /// - Volume: 30% (subtle background)
  /// - Fade in: 2 seconds
  /// - Fade out: 2 seconds
  /// - Fade on each loop: `false` (continuous)
  ///
  /// ## Example:
  /// ```swift
  /// try await service.startOverlay(url: rainURL, configuration: .ambient)
  /// ```
  static var ambient: Self {
    var config = Self()
    config.loopMode = .infinite
    config.volume = 0.3
    config.fadeInDuration = 2.0
    config.fadeOutDuration = 2.0
    config.applyFadeOnEachLoop = false
    return config
  }
  
  /// Preset configuration for timer bells or periodic sounds.
  ///
  /// ## Settings:
  /// - Loop: Specified number of times
  /// - Delay: Specified interval between rings
  /// - Volume: 50% (clearly audible)
  /// - Fade in: 0.5 seconds
  /// - Fade out: 0.5 seconds
  /// - Fade on each loop: `true` (distinct rings)
  ///
  /// ## Example:
  /// ```swift
  /// let config = OverlayConfiguration.bell(times: 3, interval: 300)
  /// try await service.startOverlay(url: bellURL, configuration: config)
  /// // Rings at 0:00, 5:00, 10:00
  /// ```
  ///
  /// - Parameters:
  ///   - times: Number of times to ring the bell (must be > 0)
  ///   - interval: Time between rings in seconds
  ///
  /// - Returns: Configured overlay for bell timer
  static func bell(times: Int, interval: TimeInterval) -> Self {
    var config = Self()
    config.loopMode = .count(times)
    config.loopDelay = interval
    config.volume = 0.5
    config.fadeInDuration = 0.5
    config.fadeOutDuration = 0.5
    config.applyFadeOnEachLoop = true
    return config
  }
}
