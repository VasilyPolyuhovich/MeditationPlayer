# Stage 14: Unit Tests (OPTIONAL - Requires User Approval)

## Status: [ ] Awaiting User Confirmation

## Context Budget: ~20k tokens

## Prerequisites

**User Approval Required:** Ask user before starting this stage.

**Read:**
- All previous stages (understand implementation)
- AsyncOperationQueue behavior

**Load Session:** Yes

---

## Goal

Create unit tests for AsyncOperationQueue behavior.

**Expected:** New file ~200 LOC

---

## Implementation Steps (If Approved)

### 1. Create Test File

**File:** `Tests/AudioServiceKitTests/AsyncOperationQueueTests.swift`

```swift
import XCTest
@testable import AudioServiceKit

final class AsyncOperationQueueTests: XCTestCase {
    
    func testSequentialExecution() async throws {
        let queue = AsyncOperationQueue()
        var results: [Int] = []
        
        // Enqueue 3 operations
        await withTaskGroup(of: Void.self) { group in
            for i in 1...3 {
                group.addTask {
                    try? await queue.enqueue {
                        try await Task.sleep(nanoseconds: 100_000_000)  // 100ms
                        results.append(i)
                    }
                }
            }
        }
        
        // Should execute sequentially: [1, 2, 3]
        XCTAssertEqual(results, [1, 2, 3])
    }
    
    func testPriorityCancellation() async throws {
        let queue = AsyncOperationQueue()
        var executed: [String] = []
        
        // Enqueue low priority (slow)
        Task {
            try? await queue.enqueue(priority: .low, description: "low") {
                try await Task.sleep(nanoseconds: 500_000_000)  // 500ms
                executed.append("low")
            }
        }
        
        try await Task.sleep(nanoseconds: 50_000_000)  // Wait 50ms
        
        // Enqueue high priority (should cancel low)
        try await queue.enqueue(priority: .high, description: "high") {
            executed.append("high")
        }
        
        try await Task.sleep(nanoseconds: 600_000_000)  // Wait for completion
        
        // Low should be cancelled, only high executed
        XCTAssertEqual(executed, ["high"])
    }
    
    func testQueueDepthLimit() async throws {
        let queue = AsyncOperationQueue(maxDepth: 2)
        
        // Enqueue 3 (max 2)
        var errors: [QueueError] = []
        
        for i in 1...3 {
            do {
                try await queue.enqueue {
                    try await Task.sleep(nanoseconds: 100_000_000)
                }
            } catch let error as QueueError {
                errors.append(error)
            }
        }
        
        // Third should fail
        XCTAssertEqual(errors.count, 1)
    }
}
```

### 2. Run Tests

```bash
swift test --filter AsyncOperationQueueTests
```

### 3. Add Integration Test (Simple)

**File:** `Tests/AudioServiceKitIntegrationTests/QueueIntegrationTests.swift`

```swift
import XCTest
@testable import AudioServiceKit

final class QueueIntegrationTests: XCTestCase {
    
    func testRapidNextClicks() async throws {
        // Setup player with 3-track playlist
        let player = try await AudioPlayerService()
        try await player.loadPlaylist([track1, track2, track3])
        
        // Rapid clicks (10x)
        for _ in 1...10 {
            try? await player.skipToNext()
        }
        
        // Should not crash, should eventually play track 3
        // (This is basic smoke test)
    }
}
```

---

## Success Criteria

- [ ] AsyncOperationQueueTests created
- [ ] Sequential execution test passes
- [ ] Priority cancellation test passes
- [ ] Queue depth limit test passes
- [ ] Integration test smoke passes
- [ ] All tests green

---

## Commit Template

```
[Stage 14] Add unit tests for AsyncOperationQueue

Implements test coverage for queue behavior:
- Sequential execution verified
- Priority cancellation verified
- Queue depth limit verified
- Integration smoke test added

Tests: ✅ 4/4 passing

Ref: .implementation-plan/stage-14-unit-tests.md
```

---

## Next Stage (Optional)

**Stage 15 - Integration test (30-min meditation)**
