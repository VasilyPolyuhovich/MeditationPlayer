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

    /// Priority of currently executing operation (nil if queue idle)
    private var currentOperationPriority: OperationPriority?

    #if ENABLE_DIAGNOSTICS
    /// Queue diagnostics (DEBUG-only with compile flag)
    private var diagnostics = QueueDiagnostics()
    #endif

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

        #if ENABLE_DIAGNOSTICS
        let enqueueTime = ContinuousClock.now
        diagnostics.totalOperations += 1
        #endif

        // 1. Cancel lower priority operations if this is high/critical
        if priority >= .high {
            cancelLowerPriorityOperations(below: priority)
        }

        // 2. Cancel current operation if new priority >= current priority
        // This enables Skip #2 to interrupt Skip #1's crossfade immediately
        if let currentPriority = currentOperationPriority,
           priority >= currentPriority {
            currentOperation?.cancel()
            currentOperation = nil
            currentOperationPriority = nil
        }

        // 3. Check queue depth
        guard queuedOperations.count < maxDepth else {
            throw QueueError.queueFull(maxDepth)
        }

        #if ENABLE_DIAGNOSTICS
        diagnostics.currentDepth = queuedOperations.count
        diagnostics.peakDepth = max(diagnostics.peakDepth, diagnostics.currentDepth)
        #endif

        // 4. Wait for previous operation
        await currentOperation?.value

        #if ENABLE_DIAGNOSTICS
        let waitEndTime = ContinuousClock.now
        let waitTime = waitEndTime - enqueueTime
        diagnostics.recordWaitTime(waitTime)
        #endif

        // 5. Execute operation
        #if ENABLE_DIAGNOSTICS
        let executionStartTime = ContinuousClock.now
        #endif

        let task = Task<T, Error> {
            try await operation()
        }

        // 6. Track in queue
        let queuedOp = QueuedOperation(
            priority: priority,
            task: Task { _ = try? await task.value },
            description: description
        )
        queuedOperations.append(queuedOp)

        currentOperation = queuedOp.task
        currentOperationPriority = priority

        // 7. Cleanup after completion
        let opID = queuedOp.id
        defer {
            queuedOperations.removeAll { $0.id == opID }
            currentOperationPriority = nil

            #if ENABLE_DIAGNOSTICS
            diagnostics.currentDepth = queuedOperations.count
            let executionEndTime = ContinuousClock.now
            let executionTime = executionEndTime - executionStartTime
            diagnostics.recordExecutionTime(executionTime)
            diagnostics.recordStateSnapshot(
                depth: queuedOperations.count,
                operation: description,
                priority: priority
            )
            #endif
        }

        // 8. Return result
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

        #if ENABLE_DIAGNOSTICS
        diagnostics.totalCancellations += queuedOperations.count
        #endif
    }

    #if ENABLE_DIAGNOSTICS
    /// Get queue diagnostics (requires ENABLE_DIAGNOSTICS flag)
    /// - Returns: Diagnostics snapshot with timing and depth metrics
    func getQueueDiagnostics() -> QueueDiagnostics {
        return diagnostics
    }

    /// Reset diagnostics counters (DEBUG-only)
    func resetDiagnostics() {
        diagnostics = QueueDiagnostics()
    }
    #endif
}

#if ENABLE_DIAGNOSTICS

// MARK: - Queue Diagnostics (ENABLE_DIAGNOSTICS)

/// Comprehensive queue diagnostics for debugging and performance analysis
/// Only compiled when ENABLE_DIAGNOSTICS flag is set
struct QueueDiagnostics: Sendable {
    // Queue depth tracking
    var currentDepth: Int = 0
    var peakDepth: Int = 0

    // Operation counters
    var totalOperations: Int = 0
    var totalCancellations: Int = 0

    // Timing metrics (stored as nanoseconds)
    var waitTimes: RollingBuffer<UInt64> = RollingBuffer(capacity: 100)
    var executionTimes: RollingBuffer<UInt64> = RollingBuffer(capacity: 100)

    // State history (last 50 snapshots)
    var stateHistory: [StateSnapshot] = []
    private let maxHistorySize = 50

    // Computed percentiles (P50, P95, P99)
    var p50WaitTime: TimeInterval { waitTimes.percentile(0.50) }
    var p95WaitTime: TimeInterval { waitTimes.percentile(0.95) }
    var p99WaitTime: TimeInterval { waitTimes.percentile(0.99) }

    var p50ExecutionTime: TimeInterval { executionTimes.percentile(0.50) }
    var p95ExecutionTime: TimeInterval { executionTimes.percentile(0.95) }
    var p99ExecutionTime: TimeInterval { executionTimes.percentile(0.99) }

    // Queue utilization rate (% time queue non-empty)
    var utilizationRate: Double {
        guard totalOperations > 0 else { return 0.0 }
        let totalTime = Double(waitTimes.sum + executionTimes.sum)
        let idleTime = totalTime - Double(executionTimes.sum)
        return totalTime > 0 ? (totalTime - idleTime) / totalTime : 0.0
    }

    mutating func recordWaitTime(_ duration: Duration) {
        let nanoseconds = UInt64(duration.components.seconds) * 1_000_000_000 +
                          UInt64(duration.components.attoseconds / 1_000_000_000)
        waitTimes.append(nanoseconds)
    }

    mutating func recordExecutionTime(_ duration: Duration) {
        let nanoseconds = UInt64(duration.components.seconds) * 1_000_000_000 +
                          UInt64(duration.components.attoseconds / 1_000_000_000)
        executionTimes.append(nanoseconds)
    }

    mutating func recordStateSnapshot(depth: Int, operation: String, priority: OperationPriority) {
        let snapshot = StateSnapshot(
            timestamp: Date(),
            queueDepth: depth,
            operation: operation,
            priority: priority
        )
        stateHistory.append(snapshot)

        // Maintain fixed history size
        if stateHistory.count > maxHistorySize {
            stateHistory.removeFirst(stateHistory.count - maxHistorySize)
        }
    }

    /// Generate comprehensive diagnostic report
    func generateReport() -> String {
        var report = """
        ╔═══════════════════════════════════════════╗
        ║   AsyncOperationQueue Diagnostics         ║
        ╚═══════════════════════════════════════════╝

        Queue Depth:
          Current: \(currentDepth)
          Peak:    \(peakDepth)

        Operations:
          Total:         \(totalOperations)
          Cancellations: \(totalCancellations)
          Utilization:   \(String(format: "%.1f%%", utilizationRate * 100))

        Wait Times (ms):
          P50 (median): \(String(format: "%.2f", p50WaitTime * 1000))
          P95:          \(String(format: "%.2f", p95WaitTime * 1000))
          P99:          \(String(format: "%.2f", p99WaitTime * 1000))

        Execution Times (ms):
          P50 (median): \(String(format: "%.2f", p50ExecutionTime * 1000))
          P95:          \(String(format: "%.2f", p95ExecutionTime * 1000))
          P99:          \(String(format: "%.2f", p99ExecutionTime * 1000))

        Recent State History (last \(min(10, stateHistory.count))):
        """

        for snapshot in stateHistory.suffix(10) {
            let timestamp = snapshot.timestamp.formatted(date: .omitted, time: .standard)
            report += "\n  [\(timestamp)] depth=\(snapshot.queueDepth) priority=\(snapshot.priority) op=\(snapshot.operation)"
        }

        report += "\n\n═══════════════════════════════════════════\n"
        return report
    }
}

/// State snapshot for diagnostics history
struct StateSnapshot: Sendable {
    let timestamp: Date
    let queueDepth: Int
    let operation: String
    let priority: OperationPriority
}

/// Rolling buffer for percentile calculations
struct RollingBuffer<T: Numeric & Comparable>: Sendable where T: Sendable {
    private var buffer: [T]
    private let capacity: Int

    var sum: T {
        buffer.reduce(0, +)
    }

    init(capacity: Int) {
        self.capacity = capacity
        self.buffer = []
        buffer.reserveCapacity(capacity)
    }

    mutating func append(_ value: T) {
        buffer.append(value)
        if buffer.count > capacity {
            buffer.removeFirst()
        }
    }

    func percentile(_ p: Double) -> TimeInterval {
        guard !buffer.isEmpty else { return 0.0 }
        let sorted = buffer.sorted()
        let index = Int(Double(sorted.count) * p)
        let clampedIndex = min(index, sorted.count - 1)
        let nanos = sorted[clampedIndex]
        return TimeInterval(nanos as! UInt64) / 1_000_000_000.0
    }
}

#endif

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
