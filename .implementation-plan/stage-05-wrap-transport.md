# Stage 05: Wrap pause/resume/stop/finish

## Status: [ ] Not Started

## Context Budget: ~12k tokens

## Prerequisites

**Read:**
- Previous stage 04 (navigation pattern)

**Load Session:** No (continue from Stage 04)

---

## Goal

Wrap pause/resume/stop/finish in operationQueue with HIGH priority.

**Expected Changes:** ~+40 LOC (wrapper logic), same pattern as Stage 04

---

## Implementation Steps

### 1. Wrap pause() - HIGH Priority

```swift
// NEW:
public func pause() async throws {
    try await operationQueue.enqueue(
        priority: .high,  // ✅ Cancels queued navigation
        description: "pause"
    ) {
        try await self._pauseImpl()
    }
}

private func _pauseImpl() async throws {
    // Original pause() logic (copy existing body)
    Self.logger.debug("[SERVICE] pause()")
    
    let pausedCrossfade = try await crossfadeOrchestrator.pauseCrossfade()
    
    if pausedCrossfade == nil {
        await crossfadeOrchestrator.performSimpleFadeOut(duration: 0.3)
    }
    
    await audioEngine.pause()
    await playbackStateCoordinator.updateMode(.paused)
    _cachedState = .paused
    stopPlaybackTimer()
}
```

### 2. Wrap resume() - NORMAL Priority

```swift
public func resume() async throws {
    try await operationQueue.enqueue(
        priority: .normal,
        description: "resume"
    ) {
        try await self._resumeImpl()
    }
}

private func _resumeImpl() async throws {
    // Copy existing resume() logic
}
```

### 3. Wrap stop() - HIGH Priority

```swift
public func stop(fadeDuration: TimeInterval = 0.0) async {
    await operationQueue.enqueue(
        priority: .high,
        description: "stop"
    ) {
        await self._stopImpl(fadeDuration: fadeDuration)
    }
}

private func _stopImpl(fadeDuration: TimeInterval) async {
    // Copy existing stop() logic
}
```

### 4. Wrap finish() - HIGH Priority

```swift
public func finish(fadeDuration: TimeInterval?) async throws {
    try await operationQueue.enqueue(
        priority: .high,
        description: "finish"
    ) {
        try await self._finishImpl(fadeDuration: fadeDuration)
    }
}

private func _finishImpl(fadeDuration: TimeInterval?) async throws {
    // Copy existing finish() logic
}
```

### 5. Build + Verify

```bash
# Count changes
scc Sources/AudioServiceKit/Public/AudioPlayerService.swift

# Build
xcodebuild -scheme AudioServiceKit \
  -destination 'id=SIMULATOR_ID' \
  -skipPackagePluginValidation \
  build
```

---

## Success Criteria

- [ ] pause() wrapped (HIGH priority)
- [ ] resume() wrapped (NORMAL priority)
- [ ] stop() wrapped (HIGH priority)
- [ ] finish() wrapped (HIGH priority)
- [ ] All _impl methods created
- [ ] Build passes

---

## Commit Template

```
[Stage 05] Wrap transport controls in queue

Serialized pause/resume/stop/finish:
- pause/stop/finish = HIGH priority (cancel navigation)
- resume = NORMAL priority
- All operations now queue-protected

UX improvement: Pause during crossfade now <100ms.

Ref: .implementation-plan/stage-05-wrap-transport.md
Build: ✅ Passes
```

---

## Next Stage

**Stage 06 - Add peekNext/peekPrevious**
