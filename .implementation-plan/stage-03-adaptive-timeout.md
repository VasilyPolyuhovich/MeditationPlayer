# Stage 03: Adaptive Timeout Manager

## Status: [ ] Not Started

## Context Budget: ~12k tokens

## Prerequisites

**Read:**
- `QUEUE_UX_PATTERNS.md` (section 4: Adaptive Timeout)

**Load Session:** No

---

## Goal

Create AdaptiveTimeoutManager that adjusts timeouts based on device performance.

**Expected:** New file ~120 LOC

---

## Implementation Steps

### 1. Create AdaptiveTimeoutManager.swift

**File:** `Sources/AudioServiceKit/Internal/AdaptiveTimeoutManager.swift`

```swift
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
```

### 2. Build Verification

```bash
xcodebuild -scheme AudioServiceKit \
  -destination 'id=SIMULATOR_ID' \
  -skipPackagePluginValidation \
  build
```

---

## Success Criteria

- [ ] AdaptiveTimeoutManager actor created
- [ ] recordDuration() tracks measurements
- [ ] adaptiveTimeout() calculates smart multiplier
- [ ] Clamps between 2x-5x range
- [ ] Duration extension for math operations
- [ ] Build passes

---

## Commit + Session Save

```bash
# Commit
[Stage 03] Add AdaptiveTimeoutManager

Implements smart timeout adjustment based on device performance:
- Tracks operation duration history (last 10 samples)
- Calculates adaptive multiplier (2x-5x range)
- Prevents false positives on slow devices
- Statistics API for debugging

Ref: .implementation-plan/stage-03-adaptive-timeout.md
Build: ✅ Passes

# Save session (after 3 stages)
save_session({
  context: {
    what: "Week 1 infrastructure (Stages 1-3)",
    status: "Infrastructure complete, ready for integration",
    files: [
      "AsyncOperationQueue.swift",
      "OperationPriority.swift", 
      "AdaptiveTimeoutManager.swift"
    ],
    nextSteps: [
      "Stage 04: Integrate queue into skipToNext/Prev",
      "Stage 05: Wrap pause/resume/stop",
      "Week 2: Full integration"
    ]
  },
  handoff: "Infrastructure готова. Queue + Priority + Adaptive Timeout. Наступний крок - інтеграція в AudioPlayerService."
})
```

---

## Next Stage

**Stage 04 - Wrap skipToNext/skipToPrevious**
