import Foundation

/// Actor-isolated operation queue for serializing async operations
///
/// Ensures operations execute sequentially (no overlap) to prevent actor re-entrancy issues.
/// Uses Task chaining pattern where each operation awaits the previous one's completion.
///
/// **Usage:**
/// ```swift
/// let queue = AsyncOperationQueue()
/// try await queue.enqueue {
///     await someAsyncOperation()
/// }
/// ```
actor AsyncOperationQueue {
    
    // MARK: - Properties
    
    /// Current operation Task (nil if queue idle)
    private var currentOperation: Task<Void, Never>?
    
    /// Queue depth counter (for monitoring)
    private var queuedCount: Int = 0
    
    /// Maximum queue depth (drop operations beyond this)
    private let maxDepth: Int
    
    // MARK: - Initialization
    
    init(maxDepth: Int = 10) {
        self.maxDepth = maxDepth
    }
    
    // MARK: - Public API
    
    /// Enqueue operation for sequential execution
    ///
    /// - Parameter operation: Async throwing closure to execute
    /// - Returns: Result of the operation
    /// - Throws: Rethrows operation errors, or QueueError if queue full
    func enqueue<T: Sendable>(
        _ operation: @Sendable @escaping () async throws -> T
    ) async throws -> T {
        
        // 1. Check queue depth limit
        guard queuedCount < maxDepth else {
            throw QueueError.queueFull(maxDepth)
        }
        
        queuedCount += 1
        defer { queuedCount -= 1 }
        
        // 2. Wait for previous operation to complete
        await currentOperation?.value
        
        // 3. Execute this operation
        let task = Task<T, Error> {
            try await operation()
        }
        
        // 4. Store as current operation (for next caller to wait)
        currentOperation = Task {
            _ = try? await task.value
        }
        
        // 5. Return result (rethrow errors)
        return try await task.value
    }
    
    /// Get current queue depth (for debugging/monitoring)
    func getQueueDepth() -> Int {
        return queuedCount
    }
    
    /// Cancel all queued operations (emergency stop)
    func cancelAll() {
        currentOperation?.cancel()
        currentOperation = nil
        queuedCount = 0
    }
}

// MARK: - Errors

enum QueueError: Error, LocalizedError {
    case queueFull(Int)
    
    var errorDescription: String? {
        switch self {
        case .queueFull(let max):
            return "Operation queue full (max: \(max)). Too many operations queued."
        }
    }
}
