# Stage 01: AsyncOperationQueue Base Implementation

## Status: [ ] Not Started

## Context Budget: ~10k tokens

## Prerequisites

**Read:**
- `ARCHITECTURE_ANALYSIS.md` (section: Solution Direction)
- `OPERATION_CALL_FLOW.md` (understand suspension points)

**Load Session:** No (fresh start)

**Find Simulator:**
```bash
xcrun simctl list devices available | grep "iPhone 16" | grep "Booted" | head -1
# Copy UUID for build command
```

---

## Goal

Create `AsyncOperationQueue` actor that serializes async operations using Task chaining.

**Expected LOC:** ~150 (new file)

---

## Implementation Steps

### 1. Analyze Current Code (Token Optimization)

```bash
# Don't read full file! Use structure analysis:
analyze_file_structure({ 
  path: "Sources/AudioServiceKit/Public/AudioPlayerService.swift" 
})

# Look for:
# - operationQueue property (should not exist yet)
# - enqueueOperation method (should not exist yet)
```

### 2. Create AsyncOperationQueue.swift

**File:** `Sources/AudioServiceKit/Internal/AsyncOperationQueue.swift`

**Template:**
```swift
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
    func enqueue<T>(
        _ operation: @Sendable @escaping () async throws -> T
    ) async rethrows -> T {
        
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
            return "Operation queue full (max: \\(max)). Too many operations queued."
        }
    }
}
```

### 3. Verify Syntax

```bash
# Use get_symbol_definition to verify structure
get_symbol_definition({
  path: "Sources/AudioServiceKit/Internal/AsyncOperationQueue.swift",
  symbolName: "AsyncOperationQueue",
  symbolType: "class"
})
```

### 4. Build Verification

```bash
# Replace SIMULATOR_ID with UUID from step 1
xcodebuild -scheme AudioServiceKit \
  -destination 'id=SIMULATOR_ID' \
  -skipPackagePluginValidation \
  build
```

**Expected:** ✅ Build succeeds (new file doesn't break anything yet)

---

## Success Criteria

- [x] File created: `Sources/AudioServiceKit/Internal/AsyncOperationQueue.swift`
- [x] Actor declared with proper isolation
- [x] `enqueue<T>()` method signature correct
- [x] Task chaining logic implemented
- [x] Queue depth limiting added
- [x] Build passes without warnings
- [x] No integration yet (standalone actor)

---

## Commit Template

```
[Stage 01] Add AsyncOperationQueue actor

Implements task serialization queue to prevent actor re-entrancy:
- Actor-isolated queue with Task chaining
- Max depth limiting (default 10)
- Generic enqueue<T>() with error rethrowing
- Queue depth monitoring for debugging

Not integrated yet (standalone infrastructure).

Ref: .implementation-plan/stage-01-async-operation-queue.md
Related: ARCHITECTURE_ANALYSIS.md (Solution Direction)

Build: ✅ Passes on iOS Simulator
```

---

## If Build Fails

**Rollback:**
```bash
git reset --hard HEAD~1
```

**Create Review:**
```bash
# Create: .implementation-plan/stage-01-review.md
# Content:
## Stage 01 Build Failure

**Error:** [paste compiler error]

**Analysis:**
- Syntax error? → Fix and retry
- Design flaw? → Mark stage FAILED, redesign

**Decision:** [Fix / Rewrite / Skip]
```

**Common Issues:**
- `@Sendable` missing → Add to closure
- Task type mismatch → Check generic constraints
- Actor isolation violation → Verify `actor` keyword

---

## Next Stage

After success: **Stage 02 - Priority enum + cancellation logic**
