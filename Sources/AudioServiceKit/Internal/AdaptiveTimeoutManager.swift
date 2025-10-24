import Foundation

/// Manages adaptive timeouts based on system performance
///
/// Measures actual operation durations and adjusts future timeouts
/// to minimize false positives on slower devices.
actor AdaptiveTimeoutManager {
    
    // MARK: - Measurement History
    
    private struct OperationMeasurement {
        let expected: Duration
        let actual: Duration
        let timestamp: Date
        
        var slowdownFactor: Double {
            return actual.seconds / expected.seconds
        }
    }
    
    private var measurements: [String: [OperationMeasurement]] = [:]
    private let maxSamplesPerOperation = 10
    
    // MARK: - Configuration
    
    private let minMultiplier: Double = 2.0   // Never less than 2x
    private let maxMultiplier: Double = 5.0   // Never more than 5x
    private let defaultMultiplier: Double = 2.5
    
    // MARK: - Public API
    
    /// Record actual duration for an operation
    func recordDuration(
        operation: String,
        expected: Duration,
        actual: Duration
    ) {
        let measurement = OperationMeasurement(
            expected: expected,
            actual: actual,
            timestamp: Date()
        )
        
        if measurements[operation] == nil {
            measurements[operation] = []
        }
        
        measurements[operation]?.append(measurement)
        
        // Keep only recent samples
        if measurements[operation]!.count > maxSamplesPerOperation {
            measurements[operation]?.removeFirst()
        }
    }
    
    /// Calculate adaptive timeout for operation
    func adaptiveTimeout(
        for expected: Duration,
        operation: String
    ) -> Duration {
        
        guard let history = measurements[operation], !history.isEmpty else {
            // No history → use default multiplier
            return expected * defaultMultiplier
        }
        
        // Calculate average slowdown from recent samples
        let recentSamples = Array(history.suffix(5))  // Last 5 measurements
        let avgSlowdown = recentSamples
            .map { $0.slowdownFactor }
            .reduce(0, +) / Double(recentSamples.count)
        
        // Apply safety margin (1.5x of observed slowdown)
        let multiplier = avgSlowdown * 1.5
        
        // Clamp to reasonable range
        let clampedMultiplier = max(minMultiplier, min(maxMultiplier, multiplier))
        
        return expected * clampedMultiplier
    }
    
    /// Get statistics for debugging
    func getStats(for operation: String) -> TimeoutStats? {
        guard let history = measurements[operation], !history.isEmpty else {
            return nil
        }
        
        let slowdowns = history.map { $0.slowdownFactor }
        let avgSlowdown = slowdowns.reduce(0, +) / Double(slowdowns.count)
        let maxSlowdown = slowdowns.max() ?? 1.0
        
        return TimeoutStats(
            operation: operation,
            sampleCount: history.count,
            averageSlowdown: avgSlowdown,
            maxSlowdown: maxSlowdown,
            recommendedMultiplier: avgSlowdown * 1.5
        )
    }
    
    /// Clear all measurements (for testing)
    func reset() {
        measurements.removeAll()
    }
}

// MARK: - Stats Model

struct TimeoutStats: Sendable {
    let operation: String
    let sampleCount: Int
    let averageSlowdown: Double
    let maxSlowdown: Double
    let recommendedMultiplier: Double
}

// MARK: - Duration Extension

extension Duration {
    var seconds: Double {
        let (seconds, attoseconds) = self.components
        return Double(seconds) + Double(attoseconds) / 1e18
    }
    
    static func * (lhs: Duration, rhs: Double) -> Duration {
        let totalSeconds = lhs.seconds * rhs
        let seconds = Int64(totalSeconds)
        let attoseconds = Int64((totalSeconds - Double(seconds)) * 1e18)
        return Duration(secondsComponent: seconds, attosecondsComponent: attoseconds)
    }
}
