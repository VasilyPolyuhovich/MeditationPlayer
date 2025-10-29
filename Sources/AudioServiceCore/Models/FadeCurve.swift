import Foundation

/// Fade curve algorithm for volume transitions during crossfades.
///
/// Different curves produce different perceived loudness characteristics:
/// - **Equal-Power**: Maintains constant perceived loudness (recommended for crossfades)
/// - **Linear**: Simple but has -3dB power dip at midpoint (good for UI animations)
/// - **Logarithmic**: Fast attack, slow decay (good for fade-in)
/// - **Exponential**: Slow attack, fast decay (good for fade-out)
/// - **S-Curve**: Smooth acceleration/deceleration (matches animation curves)
///
/// ## Example:
/// ```swift
/// let config = PlayerConfiguration(
///     crossfadeDuration: 10.0,
///     fadeCurve: .equalPower
/// )
/// ```
///
/// ## Mathematical Properties:
/// - **Equal-Power**: cos²(θ) + sin²(θ) = 1 (constant power)
/// - **Linear**: Simple y = x (but has power dip)
/// - **Logarithmic**: log₁₀(9x + 1) (natural attack)
/// - **Exponential**: x² (natural decay)
/// - **S-Curve**: 3x² - 2x³ (smooth like easeInOut)
///
/// - SeeAlso: `Documentation/04_Fade_Curves.md` for detailed analysis
public enum FadeCurve: String, Sendable, Equatable, CaseIterable {
    /// Equal-power crossfade (cos²/sin² law)
    ///
    /// **Properties:**
    /// - Maintains constant perceived loudness
    /// - No power dip at crossfade midpoint
    /// - Industry standard for audio crossfades
    ///
    /// **Use for:**
    /// - Track-to-track crossfades
    /// - Loop crossfades
    /// - Any audio mixing scenario
    ///
    /// **Formula:** volume = cos(π/2 × progress)
    case equalPower = "equal_power"

    /// Linear fade (simple proportional)
    ///
    /// **Properties:**
    /// - Simple y = x relationship
    /// - -3dB power dip at 50% crossfade
    /// - Good for UI synchronization
    ///
    /// **Use for:**
    /// - Visual fade effects
    /// - Quick transitions
    /// - When matching UI animations
    ///
    /// **Formula:** volume = progress
    case linear = "linear"

    /// Logarithmic fade (fast attack)
    ///
    /// **Properties:**
    /// - Rapid volume increase at start
    /// - Gradual approach to maximum
    /// - Mimics natural sound perception
    ///
    /// **Use for:**
    /// - Fade-in from silence
    /// - Intro sections
    ///
    /// **Formula:** volume = log₁₀(9 × progress + 1)
    case logarithmic = "logarithmic"

    /// Exponential fade (slow attack)
    ///
    /// **Properties:**
    /// - Gradual volume increase at start
    /// - Rapid approach to maximum
    /// - Opposite of logarithmic
    ///
    /// **Use for:**
    /// - Fade-out to silence
    /// - Outro sections
    ///
    /// **Formula:** volume = progress²
    case exponential = "exponential"

    /// S-curve fade (smooth easing)
    ///
    /// **Properties:**
    /// - Slow start, fast middle, slow end
    /// - Matches easeInOut animation curve
    /// - Symmetric around midpoint
    ///
    /// **Use for:**
    /// - UI-synchronized fades
    /// - Smooth transitions
    /// - When matching SwiftUI animations
    ///
    /// **Formula:** volume = 3x² - 2x³
    case sCurve = "s_curve"

    // MARK: - Volume Calculation

    /// Calculate volume for fade-in at given progress.
    ///
    /// - Parameter progress: Fade progress from 0.0 (silent) to 1.0 (full volume)
    /// - Returns: Volume level from 0.0 to 1.0
    ///
    /// ## Example:
    /// ```swift
    /// let curve = FadeCurve.equalPower
    /// let vol = curve.volume(for: 0.5)  // ~0.707 at midpoint
    /// ```
    public func volume(for progress: Float) -> Float {
        // Clamp progress to valid range
        let p = max(0.0, min(1.0, progress))

        switch self {
        case .equalPower:
            // cos(π/2 × (1 - progress)) = sin(π/2 × progress)
            return sin(Float.pi / 2.0 * p)

        case .linear:
            return p

        case .logarithmic:
            // log₁₀(9x + 1) normalized to [0, 1]
            return log10(9.0 * p + 1.0)

        case .exponential:
            // Quadratic curve
            return p * p

        case .sCurve:
            // Cubic easing: 3x² - 2x³
            return 3.0 * p * p - 2.0 * p * p * p
        }
    }

    /// Calculate volume for fade-out at given progress.
    ///
    /// Equivalent to `volume(for: 1.0 - progress)`.
    ///
    /// - Parameter progress: Fade progress from 0.0 (full volume) to 1.0 (silent)
    /// - Returns: Volume level from 1.0 to 0.0
    ///
    /// ## Example:
    /// ```swift
    /// let curve = FadeCurve.equalPower
    /// let vol = curve.inverseVolume(for: 0.5)  // ~0.707 at midpoint
    /// ```
    public func inverseVolume(for progress: Float) -> Float {
        return volume(for: 1.0 - progress)
    }
}

// MARK: - Crossfade Calculator

/// Helper for calculating crossfade volumes over time.
///
/// Pre-calculates step count and provides synchronized volume pairs for
/// smooth crossfade transitions.
///
/// ## Example:
/// ```swift
/// let calculator = CrossfadeCalculator(
///     curve: .equalPower,
///     duration: 10.0,
///     stepTime: 0.01  // 10ms steps
/// )
///
/// for step in 0...calculator.steps {
///     let (fadeOut, fadeIn) = calculator.volumes(at: step)
///     await updateVolumes(outgoing: fadeOut, incoming: fadeIn)
///     try await Task.sleep(nanoseconds: 10_000_000)  // 10ms
/// }
/// ```
public struct CrossfadeCalculator {
    /// Fade curve algorithm
    public let curve: FadeCurve

    /// Total crossfade duration in seconds
    public let duration: TimeInterval

    /// Time per step in seconds (e.g., 0.01 = 10ms)
    public let stepTime: TimeInterval

    /// Total number of steps for crossfade
    public let steps: Int

    /// Creates a crossfade calculator.
    ///
    /// - Parameters:
    ///   - curve: Fade curve algorithm
    ///   - duration: Total crossfade duration in seconds
    ///   - stepTime: Time per step in seconds (default: 0.01 = 10ms)
    public init(curve: FadeCurve, duration: TimeInterval, stepTime: TimeInterval = 0.01) {
        self.curve = curve
        self.duration = duration
        self.stepTime = stepTime
        self.steps = Int(duration / stepTime)
    }

    /// Get volumes for both players at specific step.
    ///
    /// - Parameter step: Current step number (0 to steps)
    /// - Returns: Tuple of (fadeOut, fadeIn) volumes
    ///
    /// ## Example:
    /// ```swift
    /// let (out, in) = calculator.volumes(at: 500)
    /// // At step 500 of 1000 steps → 50% progress
    /// // Equal-power: both ≈ 0.707 (maintains constant power)
    /// ```
    public func volumes(at step: Int) -> (fadeOut: Float, fadeIn: Float) {
        let progress = Float(step) / Float(steps)
        let fadeOut = curve.inverseVolume(for: progress)
        let fadeIn = curve.volume(for: progress)
        return (fadeOut, fadeIn)
    }
}
