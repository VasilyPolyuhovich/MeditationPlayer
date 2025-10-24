# Stage 04: Wrap skipToNext/skipToPrevious

## Status: [ ] Not Started

## Context Budget: ~15k tokens

## Prerequisites

**Read:**
- `OPERATION_CALL_FLOW.md` (skipToNext flow analysis)
- Previous stages 01-03 (queue infrastructure)

**Load Session:** Yes (`load_session()`)

---

## Goal

Integrate AsyncOperationQueue into skipToNext/skipToPrevious, remove debounce code.

**Expected Changes:**
- Modified: `AudioPlayerService.swift` (+30 LOC, -80 LOC debounce)
- Net: -50 LOC

---

## Implementation Steps

### 1. Analyze Current Implementation

```bash
# Find skipToNext method
search_in_file_lines({
  path: "Sources/AudioServiceKit/Public/AudioPlayerService.swift",
  pattern: "public func skipToNext",
  contextLines: 30
})

# Find debounce properties
search_in_file_lines({
  path: "Sources/AudioServiceKit/Public/AudioPlayerService.swift",
  pattern: "navigationDebounce",
  contextLines: 5
})
```

### 2. Add Queue Property to AudioPlayerService

```swift
// In AudioPlayerService actor:

// After existing properties, add:
private let operationQueue = AsyncOperationQueue(maxDepth: 3)
```

### 3. Refactor skipToNext

**Find and replace:**

```swift
// OLD (with debounce):
public func skipToNext() async throws {
    guard !isHandlingNavigation else {
        Self.logger.debug("[NAVIGATION] skipToNext ignored (debounce active)")
        return
    }
    
    isHandlingNavigation = true
    defer {
        navigationDebounceTask?.cancel()
        navigationDebounceTask = Task { ... }
    }
    
    guard let nextTrack = await playlistManager.skipToNext() else {
        throw AudioPlayerError.noNextTrack
    }
    try await replaceCurrentTrack(track: nextTrack, ...)
}

// NEW (with queue):
public func skipToNext() async throws {
    try await operationQueue.enqueue(
        priority: .normal,
        description: "skipToNext"
    ) {
        try await self._skipToNextImpl()
    }
}

private func _skipToNextImpl() async throws {
    guard let nextTrack = await playlistManager.skipToNext() else {
        throw AudioPlayerError.noNextTrack
    }
    try await replaceCurrentTrack(
        track: nextTrack,
        crossfadeDuration: configuration.crossfadeDuration
    )
}
```

### 4. Refactor skipToPrevious

Same pattern as skipToNext.

### 5. Remove Debounce Code

```swift
// DELETE these properties:
private var navigationDebounceTask: Task<Void, Never>?
private var isHandlingNavigation = false
private let navigationDebounceDelay: TimeInterval = 0.5

// DELETE this helper method:
private func setNavigationHandlingFlag(_ value: Bool) async {
    isHandlingNavigation = value
}
```

### 6. Build Verification

```bash
xcodebuild -scheme AudioServiceKit \
  -destination 'id=SIMULATOR_ID' \
  -skipPackagePluginValidation \
  build
```

**Expected:** ✅ Build passes, -80 LOC debounce removed

---

## Success Criteria

- [ ] skipToNext wrapped in operationQueue.enqueue()
- [ ] skipToPrevious wrapped in operationQueue.enqueue()
- [ ] Debounce code removed (~80 LOC)
- [ ] Private _impl methods created
- [ ] Build passes
- [ ] No compiler warnings

---

## Commit Template

```
[Stage 04] Integrate queue into navigation methods

Replaced debounce with proper task serialization:
- skipToNext/Prev now use operationQueue.enqueue()
- Removed navigationDebounce properties (-80 LOC)
- Extracted _skipToNextImpl/_skipToPrevImpl
- Operations execute sequentially (no overlap)

Fixes race condition: Next→Next→Next now properly queued.

Ref: .implementation-plan/stage-04-wrap-navigation.md
Build: ✅ Passes
LOC: -50 (net)
```

---

## If Build Fails

**Common issues:**
- `self` capture in closure → Use `self._skipToNextImpl()`
- Sendable conformance → Verify AudioPlayerService is actor
- Missing await → Add to enqueue call

**Rollback:**
```bash
git reset --hard HEAD~1
```

---

## Next Stage

**Stage 05 - Wrap pause/resume/stop/finish**
