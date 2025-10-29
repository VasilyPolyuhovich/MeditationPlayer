//
//  TimeRemainingHelper.swift
//  AudioServiceKit
//
//  Helper for deciding crossfade vs fade strategy based on remaining track time
//

import Foundation

/// Decision for how to transition between tracks based on remaining time
enum TransitionStrategy: Sendable, Equatable {
    /// Full crossfade with requested duration
    case fullCrossfade(duration: TimeInterval)

    /// Reduced crossfade with remaining time as duration
    case reducedCrossfade(duration: TimeInterval)

    /// Separate fades: fade out active, then fade in new track
    case separateFades(fadeOutDuration: TimeInterval, fadeInDuration: TimeInterval)
}

/// Helper for checking remaining track time and deciding transition strategy
struct TimeRemainingHelper {

    /// Decide transition strategy based on remaining track time
    ///
    /// Algorithm from REQUIREMENTS_CROSSFADE_AND_FADE.md Section 1:
    /// ```
    /// IF remaining_time >= requested_duration:
    ///     → fullCrossfade with requested_duration
    /// ELSE IF remaining_time >= (requested_duration / 2):
    ///     → reducedCrossfade with remaining_time
    /// ELSE:
    ///     → separateFades (fade out active, fade in new)
    /// ```
    ///
    /// - Parameters:
    ///   - trackPosition: Current position in track (seconds)
    ///   - trackDuration: Total track duration (seconds)
    ///   - requestedDuration: Desired crossfade duration from config (seconds)
    /// - Returns: Strategy for transitioning between tracks
    static func decideStrategy(
        trackPosition: TimeInterval,
        trackDuration: TimeInterval,
        requestedDuration: TimeInterval
    ) -> TransitionStrategy {
        // Calculate remaining time in track
        let remainingTime = trackDuration - trackPosition

        // Guard against invalid values
        guard remainingTime > 0.0, requestedDuration > 0.0 else {
            // Not enough time for any fade - instant switch
            return .separateFades(fadeOutDuration: 0.1, fadeInDuration: 0.1)
        }

        // Strategy 1: Full crossfade
        if remainingTime >= requestedDuration {
            return .fullCrossfade(duration: requestedDuration)
        }

        // Strategy 2: Reduced crossfade
        if remainingTime >= (requestedDuration / 2.0) {
            return .reducedCrossfade(duration: remainingTime)
        }

        // Strategy 3: Separate fades
        // Use remaining time for fade out, same duration for fade in
        let fadeDuration = max(0.1, remainingTime) // Minimum 0.1s
        return .separateFades(fadeOutDuration: fadeDuration, fadeInDuration: fadeDuration)
    }
}

// MARK: - Debug Description

extension TransitionStrategy: CustomStringConvertible {
    var description: String {
        switch self {
        case .fullCrossfade(let duration):
            return "fullCrossfade(\(String(format: "%.1f", duration))s)"
        case .reducedCrossfade(let duration):
            return "reducedCrossfade(\(String(format: "%.1f", duration))s)"
        case .separateFades(let fadeOut, let fadeIn):
            return "separateFades(out: \(String(format: "%.1f", fadeOut))s, in: \(String(format: "%.1f", fadeIn))s)"
        }
    }
}
