import Foundation

/// Crossfade progress state for UI observation
public struct CrossfadeProgress: Sendable, Equatable {
    /// Current crossfade phase
    public enum Phase: Sendable, Equatable {
        case idle
        case preparing
        case fading(progress: Double)  // 0.0-1.0
        case switching
        case cleanup
    }

    public let phase: Phase
    public let duration: TimeInterval
    public let elapsed: TimeInterval

    public init(phase: Phase, duration: TimeInterval, elapsed: TimeInterval) {
        self.phase = phase
        self.duration = duration
        self.elapsed = elapsed
    }

    /// Overall progress (0.0-1.0)
    public var progress: Double {
        guard duration > 0 else { return 0 }
        return min(1.0, elapsed / duration)
    }

    /// Is crossfade active
    public var isActive: Bool {
        if case .idle = phase {
            return false
        }
        return true
    }

    /// Idle state
    public static let idle = CrossfadeProgress(
        phase: .idle,
        duration: 0,
        elapsed: 0
    )
}
