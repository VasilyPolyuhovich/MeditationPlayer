import Foundation

/// Priority levels for player operations
///
/// Higher priority operations can cancel lower priority ones.
/// Used by AsyncOperationQueue for intelligent operation management.
public enum OperationPriority: Int, Comparable, Sendable {
    /// Low priority: Playlist mutations, configuration changes
    case low = 0

    /// Normal priority: Navigation (next/prev track)
    case normal = 1

    /// High priority: Transport controls (pause/stop) - can cancel normal
    case high = 2

    /// Critical priority: System events (interruption) - cancels everything
    case critical = 3

    public static func < (lhs: OperationPriority, rhs: OperationPriority) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }
}

/// Operation metadata for queue management
struct QueuedOperation {
    let id: UUID
    let priority: OperationPriority
    let task: Task<Void, Never>
    let description: String  // For debugging

    init(priority: OperationPriority, task: Task<Void, Never>, description: String) {
        self.id = UUID()
        self.priority = priority
        self.task = task
        self.description = description
    }
}
