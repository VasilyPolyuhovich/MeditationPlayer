# Stage 10: Priority Queue Cancellation Verification

## Status: [ ] Not Started

## Context Budget: ~10k tokens

## Prerequisites

**Read:** Stages 02, 04, 05 (queue integration)

**Load Session:** Yes (`load_session()`) - End of Week 2

---

## Goal

Add logging + verification that priority cancellation works correctly.

**Expected Changes:** +30 LOC (debug logging)

---

## Implementation Steps

### 1. Add Queue Monitoring to AudioPlayerService

```swift
// In AudioPlayerService:

/// Get current operation queue depth (for debugging)
public func getQueueDepth() async -> Int {
    return await operationQueue.getQueueDepth()
}

/// Get queued operations list (for debugging)
public func getQueuedOperations() async -> [String] {
    return await operationQueue.getQueuedDescriptions()
}
```

### 2. Add to AsyncOperationQueue

```swift
// In AsyncOperationQueue:

func getQueuedDescriptions() -> [String] {
    return queuedOperations.map { $0.description }
}
```

### 3. Add Cancellation Logging

```swift
// In AsyncOperationQueue.cancelLowerPriorityOperations:

private func cancelLowerPriorityOperations(below priority: OperationPriority) {
    let toCancel = queuedOperations.filter { $0.priority < priority }
    
    if !toCancel.isEmpty {
        print("[Queue] 🚫 Cancelling \(toCancel.count) lower-priority ops:")
        for op in toCancel {
            print("  - \(op.description) (priority: \(op.priority))")
            op.task.cancel()
        }
    }
    
    queuedOperations.removeAll { $0.priority < priority }
}
```

### 4. Manual Test Scenario

**Create test document:**

**File:** `.implementation-plan/stage-10-manual-test.md`

```markdown
# Manual Test: Priority Cancellation

## Test 1: Next → Next → Pause

**Steps:**
1. Load 3-track playlist in demo
2. Tap Next (queues crossfade ~5s)
3. Immediately tap Next again (queues second crossfade)
4. Immediately tap Pause (HIGH priority)

**Expected:**
- Console shows: "Cancelling 2 lower-priority ops"
- Pause executes immediately (<100ms)
- No audio continues playing

**Actual:** [Test and record result]

## Test 2: Next Spam (10 taps)

**Steps:**
1. Tap Next 10 times rapidly

**Expected:**
- Queue depth never exceeds 3 (maxDepth limit)
- Operations execute sequentially
- All 3 tracks play eventually

**Actual:** [Test and record result]
```

### 5. Build + Log Test

```bash
# Build
xcodebuild -scheme AudioServiceKit \
  -destination 'id=SIMULATOR_ID' \
  -skipPackagePluginValidation \
  build

# Note: Manual testing required (Stage 10 is verification, not code-heavy)
```

---

## Success Criteria

- [ ] getQueueDepth() API added
- [ ] getQueuedOperations() API added
- [ ] Cancellation logging added
- [ ] Manual test document created
- [ ] Build passes

**Manual verification (user will test):**
- [ ] Next → Next → Pause cancels both Next
- [ ] 10x Next spam doesn't overflow queue
- [ ] Console logs show cancellation

---

## Commit + Session Save

```bash
# Commit
[Stage 10] Add queue monitoring + cancellation logging

Adds debugging APIs for queue behavior:
- getQueueDepth() for UI indicators
- getQueuedOperations() for debugging
- Cancellation logging in console
- Manual test scenarios documented

Ready for user testing.

Ref: .implementation-plan/stage-10-queue-verification.md
Build: ✅ Passes

# Save session (Week 3 start)
save_session({
  context: {
    what: "Week 3 robustness (Stages 7-10)",
    status: "Timeout wrapper + events + queue monitoring complete",
    files: [
      "PlayerEvent.swift",
      "AudioEngineActor (timeout wrapper)",
      "AsyncOperationQueue (monitoring)"
    ],
    nextSteps: [
      "Stage 11-13: Cleanup (remove band-aids)",
      "User manual testing of queue behavior",
      "Week 4: Cleanup phase"
    ]
  },
  handoff: "Timeout + progress + event stream готово. Queue має monitoring. Наступне - cleanup: видалити debounce, UUID tracking, defensive checks."
})
```

---

## Next Stage

**Stage 11 - Remove debounce code**
