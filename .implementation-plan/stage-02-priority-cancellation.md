# Stage 02: Priority Enum + Cancellation Logic

## Status: [ ] Not Started

## Context Budget: ~8k tokens

## Prerequisites

**Read:**
- `QUEUE_UX_PATTERNS.md` (section 5: Priority Cancellation)
- Previous stage: `stage-01-async-operation-queue.md`

**Load Session:** No

---

## Goal

Add operation priority system to AsyncOperationQueue with cancellation logic.

**Expected Changes:**
- New file: `Sources/AudioServiceKit/Models/OperationPriority.swift` (~50 LOC)
- Modified: `AsyncOperationQueue.swift` (~+80 LOC)

---

## Implementation Steps

### 1. Create OperationPriority.swift

**File:** `Sources/AudioServiceKit/Models/OperationPriority.swift`

```swift
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
    let priority: OperationPriority
    let task: Task<Void, Never>
    let description: String  // For debugging
}
```

### 2. Modify AsyncOperationQueue

**Add to AsyncOperationQueue:**

```swift
// After existing properties:
/// Queued operations (for priority-based cancellation)
private var queuedOperations: [QueuedOperation] = []

// Modify enqueue method signature:
func enqueue<T>(
    priority: OperationPriority = .normal,
    description: String = "Operation",
    _ operation: @Sendable @escaping () async throws -> T
) async rethrows -> T {
    
    // 1. Cancel lower priority operations if this is high/critical
    if priority >= .high {
        await cancelLowerPriorityOperations(below: priority)
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
    defer {
        queuedOperations.removeAll { $0.task === queuedOp.task }
    }
    
    // 7. Return result
    return try await task.value
}

// New method:
private func cancelLowerPriorityOperations(below priority: OperationPriority) {
    let toCancel = queuedOperations.filter { $0.priority < priority }
    
    for op in toCancel {
        op.task.cancel()
    }
    
    queuedOperations.removeAll { $0.priority < priority }
}

// Update getQueueDepth:
func getQueueDepth() -> Int {
    return queuedOperations.count
}
```

### 3. Verify Structure

```bash
analyze_file_structure({ 
  path: "Sources/AudioServiceKit/Internal/AsyncOperationQueue.swift" 
})

# Check for:
# - enqueue method has priority parameter
# - cancelLowerPriorityOperations exists
# - queuedOperations property exists
```

### 4. Build Verification

```bash
xcodebuild -scheme AudioServiceKit \
  -destination 'id=SIMULATOR_ID' \
  -skipPackagePluginValidation \
  build
```

---

## Success Criteria

- [ ] OperationPriority enum created (4 levels)
- [ ] QueuedOperation struct with priority tracking
- [ ] enqueue() accepts priority parameter
- [ ] cancelLowerPriorityOperations() implemented
- [ ] Build passes
- [ ] No integration yet (infrastructure only)

---

## Commit Template

```
[Stage 02] Add priority-based operation cancellation

Implements priority queue with intelligent cancellation:
- OperationPriority enum (low/normal/high/critical)
- QueuedOperation tracking metadata
- High-priority ops cancel lower-priority queued ops
- Updated enqueue() with priority parameter

UX benefit: Pause immediately cancels queued Next navigation.

Ref: .implementation-plan/stage-02-priority-cancellation.md
Build: ✅ Passes
```

---

## Next Stage

**Stage 03 - Adaptive timeout manager**
