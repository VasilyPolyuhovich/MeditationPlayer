import Foundation
import AudioServiceCore

/// Extension to FadeCurve for volume calculations
extension FadeCurve {
    /// Calculate volume for a given progress (0.0 to 1.0)
    /// - Parameter progress: Fade progress from 0.0 (start) to 1.0 (end)
    /// - Returns: Volume multiplier (0.0 to 1.0)
    func volume(for progress: Float) -> Float {
        let clampedProgress = max(0.0, min(1.0, progress))
        
        switch self {
        case .linear:
            return clampedProgress
            
        case .equalPower:
            // Equal-power crossfade uses cosine/sine curves
            // This maintains constant total power: fadeOut² + fadeIn² = 1
            let angle = clampedProgress * .pi / 2.0
            return sin(angle)
            
        case .logarithmic:
            // Logarithmic fade: starts fast, ends slow
            if clampedProgress == 0.0 { return 0.0 }
            // Using log10 for smooth curve
            // Map 0.01...1.0 to log space
            let logProgress = (log10(clampedProgress * 0.99 + 0.01) + 2.0) / 2.0
            return logProgress
            
        case .exponential:
            // Exponential fade: starts slow, ends fast
            return clampedProgress * clampedProgress
            
        case .sCurve:
            // S-curve using smoothstep function
            // Slow at start and end, fast in middle
            let t = clampedProgress
            return t * t * (3.0 - 2.0 * t)
        }
    }
    
    /// Get the inverse fade curve (for fade out)
    /// - Parameter progress: Fade progress from 0.0 (start) to 1.0 (end)
    /// - Returns: Volume multiplier (1.0 to 0.0)
    func inverseVolume(for progress: Float) -> Float {
        let clampedProgress = max(0.0, min(1.0, progress))
        
        switch self {
        case .linear:
            return 1.0 - clampedProgress
            
        case .equalPower:
            // Equal-power fade out uses cosine
            let angle = clampedProgress * .pi / 2.0
            return cos(angle)
            
        case .logarithmic:
            // Reverse logarithmic
            return volume(for: 1.0 - clampedProgress)
            
        case .exponential:
            let remaining = 1.0 - clampedProgress
            return remaining * remaining
            
        case .sCurve:
            return volume(for: 1.0 - clampedProgress)
        }
    }
}

/// Helper for crossfade calculations
struct CrossfadeCalculator {
    let curve: FadeCurve
    let duration: TimeInterval
    let stepTime: TimeInterval
    
    /// Number of steps in the crossfade
    var steps: Int {
        return Int(duration / stepTime)
    }
    
    /// Calculate volumes for both tracks at a given step
    /// - Parameter step: Current step (0 to steps)
    /// - Returns: Tuple of (fadeOutVolume, fadeInVolume)
    func volumes(at step: Int) -> (fadeOut: Float, fadeIn: Float) {
        let progress = Float(step) / Float(steps)
        return (
            fadeOut: curve.inverseVolume(for: progress),
            fadeIn: curve.volume(for: progress)
        )
    }
}
