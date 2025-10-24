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
    
    /// Queued operations (for priority-based cancellation)
    private var queuedOperations: [QueuedOperation] = []
    
    // MARK: - Initialization
    
    init(maxDepth: Int = 10) {
        self.maxDepth = maxDepth
    }
    
    // MARK: - Public API
    
    /// Enqueue operation for sequential execution with priority
    ///
    /// - Parameters:
    ///   - priority: Operation priority (default: .normal)
    ///   - description: Debug description for monitoring
    ///   - operation: Async throwing closure to execute
    /// - Returns: Result of the operation
    /// - Throws: Operation errors, or QueueError if queue full
    func enqueue<T: Sendable>(
        priority: OperationPriority = .normal,
        description: String = "Operation",
        _ operation: @Sendable @escaping () async throws -> T
    ) async throws -> T {
        
        // 1. Cancel lower priority operations if this is high/critical
        if priority >= .high {
            cancelLowerPriorityOperations(below: priority)
        }
        
        // 2. Check queue depth
        guard queuedOperations.count < maxDepth else {
            throw QueueError.queueFull(maxDepth)
        }
        
        // 3. Wait for previous operation
        await currentOperation?.value
        
        // 4. Execute operation
        let task = Task<T, Error> {
            try await operation()
        }
        
        // 5. Track in queue
        let queuedOp = QueuedOperation(
            priority: priority,
            task: Task { _ = try? await task.value },
            description: description
        )
        queuedOperations.append(queuedOp)
        
        currentOperation = queuedOp.task
        
        // 6. Cleanup after completion
        let opID = queuedOp.id
        defer {
            queuedOperations.removeAll { $0.id == opID }
        }
        
        // 7. Return result
        return try await task.value
    }
    
    /// Get current queue depth (for debugging/monitoring)
    func getQueueDepth() -> Int {
        return queuedOperations.count
    }
    
    // MARK: - Private Helpers
    
    /// Cancel operations with priority lower than specified
    /// - Parameter priority: Minimum priority threshold
    private func cancelLowerPriorityOperations(below priority: OperationPriority) {
        let toCancel = queuedOperations.filter { $0.priority < priority }
        
        for op in toCancel {
            op.task.cancel()
        }
        
        queuedOperations.removeAll { $0.priority < priority }
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
