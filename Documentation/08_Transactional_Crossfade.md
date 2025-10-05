# Transactional Crossfade Pattern

## 🎯 Overview

ProsperPlayer implements a **transactional crossfade pattern** that provides graceful rollback instead of blocking user actions during crossfade transitions. This ensures the system is always in a valid, playable state.

## 📐 Core Concept

### Traditional Approach (Blocking)
```swift
// ❌ OLD: Block user actions during crossfade
func pause() throws {
    guard !isCrossfading else {
        throw Error("Cannot pause during crossfade")
    }
    // pause logic
}
```

**Problems:**
- Poor UX (users see errors)
- Invalid states possible
- User loses control during transitions

### Transactional Approach (Rollback)
```swift
// ✅ NEW: Rollback crossfade transaction
func pause() async {
    if isCrossfading {
        await rollbackCrossfade()  // Graceful rollback
    }
    // pause logic - always works
}
```

**Benefits:**
- ✅ Smooth UX (no errors)
- ✅ Always valid state
- ✅ User maintains control

## 🔄 Transaction States

### Crossfade Transaction Lifecycle

```
1. BEGIN
   ├─ Active player: vol 1.0 → 0.0 (fade out)
   ├─ Inactive player: vol 0.0 → 1.0 (fade in)
   └─ State: IN_PROGRESS

2. INTERRUPT (user action)
   ├─ Trigger: pause/skip/replace/seek
   └─ Action: ROLLBACK

3. ROLLBACK
   ├─ Active player: current → 1.0 (restore, 0.5s)
   ├─ Inactive player: current → 0.0 + stop
   └─ State: STABLE

4. COMMIT (if not interrupted)
   ├─ Active player: 0.0 + stop
   ├─ Inactive player: 1.0 (now active)
   └─ switchActivePlayer()
```

## 🛠️ Implementation

### Core Method: rollbackCrossfade()

**AudioEngineActor:**
```swift
func rollbackCrossfade(rollbackDuration: TimeInterval = 0.5) async -> Float {
    // 1. Capture current volumes
    let activeMixer = getActiveMixerNode()
    let inactiveMixer = getInactiveMixerNode()
    let currentActiveVolume = activeMixer.volume  // e.g., 0.3
    
    // 2. Cancel crossfade task
    activeCrossfadeTask?.cancel()
    
    // 3. Restore active volume (0.3 → 1.0 in 0.5s)
    if currentActiveVolume < 1.0 {
        await fadeVolume(
            mixer: activeMixer,
            from: currentActiveVolume,
            to: 1.0,
            duration: rollbackDuration,
            curve: .linear
        )
    }
    
    // 4. Fade out inactive (0.7 → 0.0 in 0.5s)
    if currentInactiveVolume > 0.0 {
        await fadeVolume(
            mixer: inactiveMixer,
            from: currentInactiveVolume,
            to: 0.0,
            duration: rollbackDuration,
            curve: .linear
        )
    }
    
    // 5. Stop inactive player
    stopInactivePlayer()
    inactiveMixer.volume = 0.0
    
    return currentActiveVolume
}
```

**AudioPlayerService:**
```swift
private func rollbackCrossfade(rollbackDuration: TimeInterval = 0.5) async {
    // Perform engine rollback
    await audioEngine.rollbackCrossfade(rollbackDuration: rollbackDuration)
    
    // Clear flags
    isLoopCrossfadeInProgress = false
    isTrackReplacementInProgress = false
    
    // Update observers
    currentCrossfadeProgress = .idle
    notifyObservers(.idle)
}
```

### Integration Points

**1. Pause/Resume:**
```swift
func pause() async throws {
    if isLoopCrossfadeInProgress || isTrackReplacementInProgress {
        await rollbackCrossfade()  // Rollback first
    }
    await audioEngine.pause()
    // ... rest of pause logic
}
```

**2. Skip Forward/Backward:**
```swift
func skipForward(by interval: TimeInterval) async throws {
    if isLoopCrossfadeInProgress || isTrackReplacementInProgress {
        await rollbackCrossfade()  // Rollback first
    }
    try await audioEngine.seek(to: newTime)
}
```

**3. Seek with Fade:**
```swift
func seekWithFade(to time: TimeInterval) async throws {
    if isLoopCrossfadeInProgress || isTrackReplacementInProgress {
        await rollbackCrossfade()  // Rollback first
    }
    // ... seek logic
}
```

**4. Replace Track (with Retry):**
```swift
func replaceTrack(url: URL, retryDelay: TimeInterval = 1.5) async throws {
    if isTrackReplacementInProgress {
        await rollbackCrossfade()                     // 1. Rollback
        try await Task.sleep(seconds: retryDelay)    // 2. Delay
        // 3. Continue with new track (retry)
    }
    // ... replacement logic
}
```

## 🔁 Double-Tap Retry Pattern

**User Scenario:**
1. User taps "Next Track" → crossfade starts (Track A → B)
2. Mid-crossfade, user taps "Next Track" again → wants Track C

**Behavior:**
```
Time 0.0s: Crossfade A→B starts (5s duration)
Time 2.0s: User taps "Next" again (wants C)
           ├─ Rollback: A restore volume (0.5s)
           ├─ Delay: 1.5s
           └─ Retry: Start crossfade A→C
Time 4.0s: Crossfade A→C completes
```

**Code:**
```swift
func replaceTrack(url: URL, crossfadeDuration: 5.0, retryDelay: 1.5) async {
    if isTrackReplacementInProgress {
        // Current: A→B crossfade at 2.0s (vol A=0.6, B=0.4)
        await rollbackCrossfade(0.5)  
        // After: A=1.0, B=0+stop
        
        try await Task.sleep(1.5)
        // Wait for user to stabilize
        
        // Continue: Start A→C crossfade
    }
    
    // Load C, perform crossfade A→C
}
```

## ⚙️ Configuration

### Rollback Duration
**Default:** 0.5 seconds
**Range:** 0.3s (fast) to 1.0s (smooth)

```swift
// Fast rollback (responsive)
await rollbackCrossfade(rollbackDuration: 0.3)

// Smooth rollback (gentle)
await rollbackCrossfade(rollbackDuration: 0.8)
```

### Retry Delay
**Default:** 1.5 seconds
**Range:** 1.0s (quick) to 3.0s (conservative)

```swift
// Quick retry
try await replaceTrack(url, retryDelay: 1.0)

// Conservative retry
try await replaceTrack(url, retryDelay: 2.5)
```

## 📊 State Guarantees

### Invariants

**Always Valid State:**
```
∀ time t: ∃ active_player(t) ∧ volume(active_player(t)) ∈ [0.0, 1.0]
```

**Single Active Player:**
```
∀ time t: |{p | isPlaying(p, t) ∧ volume(p, t) > 0}| ≤ 2
∧ (crossfading → exactly 2)
∧ (¬crossfading → exactly 1)
```

**Rollback Guarantee:**
```
rollback(state_in_progress) → state_stable
where state_stable: active_volume = 1.0 ∧ inactive_stopped
```

## 🧪 Testing

### Test Scenarios

**1. Pause During Crossfade:**
```swift
await service.startPlaying(url: trackA)
await service.replaceTrack(url: trackB, crossfadeDuration: 5.0)
try await Task.sleep(2.0)  // Mid-crossfade

await service.pause()  // Should rollback + pause

// Verify:
// - Track A playing (paused)
// - Track B stopped
// - Volume A = 1.0
```

**2. Skip During Crossfade:**
```swift
await service.startPlaying(url: trackA)
let duration = trackInfo.duration
// Trigger loop crossfade
try await Task.sleep(duration - 3.0)  // Near end

await service.skipBackward(by: 30.0)  // Should rollback + skip

// Verify:
// - Track A playing
// - Position = duration - 30s
// - No loop crossfade
```

**3. Double-Tap Replace:**
```swift
await service.startPlaying(url: trackA)
await service.replaceTrack(url: trackB)  // A→B
try await Task.sleep(2.0)  // Mid-crossfade

await service.replaceTrack(url: trackC)  // Should rollback + retry

// Verify:
// - Rollback happened
// - Delay occurred (1.5s)
// - Now crossfading A→C
```

## 📈 Performance

### Rollback Cost
- **Time:** 0.5s (configurable)
- **CPU:** Minimal (2 fade operations)
- **Memory:** Zero allocation

### User Impact
- **Latency:** 0.5s perceived delay (acceptable)
- **UX:** Smooth, no errors shown
- **Control:** Always responsive

## 🎨 UI Integration

### Progress Observation

```swift
class ViewModel: CrossfadeProgressObserver {
    func crossfadeProgressDidUpdate(_ progress: CrossfadeProgress) async {
        switch progress.phase {
        case .idle:
            // Crossfade ended (or rolled back)
            showCrossfadeIndicator = false
            
        case .preparing, .fading, .switching, .cleanup:
            // Crossfade in progress
            showCrossfadeIndicator = true
            progressValue = progress.progress
        }
    }
}
```

### Rollback Feedback

```swift
// Optional: Show brief rollback indicator
if progress.phase == .idle && wasCrossfading {
    showToast("Transition cancelled", duration: 1.0)
}
```

## 🔗 Related Patterns

- **Optimistic UI:** Assume success, rollback on failure
- **SAGA Pattern:** Distributed transactions with compensation
- **Command Pattern:** Undo/redo with command history

## 📚 References

- Session #8: Transactional Crossfade Implementation
- `AudioEngineActor.rollbackCrossfade()`
- `AudioPlayerService.rollbackCrossfade()`
- Crossfade Architecture (v2.9.0)

---

**Version:** 2.10.0  
**Pattern:** Transactional Crossfade with Rollback  
**Status:** Production-Ready
