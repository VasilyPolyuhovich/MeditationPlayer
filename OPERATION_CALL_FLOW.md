# Operation Call Flow Analysis

**Purpose:** Document all await suspension points where actor re-entrancy occurs

**Metrics from scc:**
- AudioPlayerService: **209 cyclomatic complexity** (1155 LOC)
- AudioEngineActor: **172 complexity** (931 LOC)  
- CrossfadeOrchestrator: **33 complexity** (307 LOC)
- PlaybackStateCoordinator: **25 complexity** (185 LOC)

---

## Critical Operations (Sequential Atomicity Required)

### 1. skipToNext() - Complexity: 15+ await points

**Source:** AudioPlayerService.swift:1081

```swift
public func skipToNext() async throws {
    // 🔴 SUSPENSION POINT #1: Debounce check
    guard !isHandlingNavigation else { return }
    isHandlingNavigation = true
    
    defer {
        navigationDebounceTask?.cancel()
        navigationDebounceTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000)  // 🔴 SP #2
            await setNavigationHandlingFlag(false)          // 🔴 SP #3
        }
    }
    
    // 🔴 SUSPENSION POINT #4: Playlist manager
    guard let nextTrack = await playlistManager.skipToNext() else {
        throw AudioPlayerError.noNextTrack
    }
    
    // 🔴 SUSPENSION POINT #5-15: replaceCurrentTrack (see below)
    try await replaceCurrentTrack(
        track: nextTrack,
        crossfadeDuration: configuration.crossfadeDuration
    )
}
```

**Re-entrancy Window:** Between ANY await, another skipToNext() can start!

---

### 2. replaceCurrentTrack() - Complexity: 10+ await points

**Source:** AudioPlayerService.swift (internal)

```swift
private func replaceCurrentTrack(
    track: Track,
    crossfadeDuration: TimeInterval
) async throws {
    
    // 🔴 SUSPENSION POINT #1: State query
    let currentState = await playbackStateCoordinator.getPlaybackMode()
    
    if currentState == .paused {
        // Paused path: instant switch (no crossfade)
        // 🔴 SP #2: State coordinator
        await playbackStateCoordinator.atomicSwitch(newTrack: updatedTrack, mode: .paused)
        
        // 🔴 SP #3: Audio engine
        await audioEngine.stopInactivePlayer()
        
        // 🔴 SP #4: Sync cache
        await syncCachedTrackInfo()
    } else {
        // Playing path: crossfade
        // 🔴 SP #5: Crossfade orchestrator (LONG operation!)
        let result = try await crossfadeOrchestrator.startCrossfade(
            to: track,
            duration: crossfadeDuration,
            curve: .equalPower,
            operation: .replaceTrack
        )
        
        // 🔴 SP #6-10: inside startCrossfade (see below)
    }
}
```

---

### 3. CrossfadeOrchestrator.startCrossfade() - Complexity: 8+ await points

**Source:** CrossfadeOrchestrator.swift:59

```swift
func startCrossfade(
    to track: Track,
    duration: TimeInterval,
    curve: FadeCurve,
    operation: CrossfadeOperation
) async throws -> CrossfadeResult {
    
    // 1. Rollback if crossfade active
    if activeCrossfade != nil {
        Self.logger.debug("[CrossfadeOrch] Active crossfade detected, rolling back")
        // 🔴 SUSPENSION POINT #1: Rollback (complex operation)
        await audioEngine.rollbackCrossfade(
            activeMixer: currentActiveMixer,
            inactiveMixer: currentInactiveMixer,
            duration: 0.3
        )
        activeCrossfade = nil
    }
    
    // 2. Choose strategy
    let strategy = TimeRemainingHelper.determineTransitionStrategy(
        currentTime: currentPosition,
        duration: trackDuration,
        requestedCrossfadeDuration: duration
    )
    
    switch strategy {
    case .fullCrossfade(let adjustedDuration):
        // 🔴 SUSPENSION POINT #2-6: performFullCrossfade (see below)
        return try await performFullCrossfade(...)
        
    case .separateFades(let fadeOut, let fadeIn):
        // 🔴 SUSPENSION POINT #7-8: performSeparateFades
        return try await performSeparateFades(...)
    }
}
```

---

### 4. CrossfadeOrchestrator.performFullCrossfade() - Complexity: 6+ await points

```swift
private func performFullCrossfade(...) async throws -> CrossfadeResult {
    
    // 1. Capture snapshot for rollback
    let snapshot = await stateStore.captureSnapshot()  // 🔴 SP #1
    
    // 2. Load file (BLOCKING I/O!)
    let trackWithMetadata: Track
    do {
        // 🔴 SUSPENSION POINT #2: File I/O (100-500ms!)
        trackWithMetadata = try await audioEngine.loadAudioFileOnSecondaryPlayer(track: track)
    } catch {
        activeCrossfade = nil
        throw error
    }
    
    // 3. Update state
    await stateStore.loadTrackOnInactive(trackWithMetadata)  // 🔴 SP #3
    
    // 4. Start crossfade execution
    // 🔴 SUSPENSION POINT #4: Crossfade (5-15 seconds!)
    let progressStream = await audioEngine.startCrossfadeExecution(
        duration: adjustedDuration,
        curve: curve
    )
    
    // 5. Monitor progress
    let crossfadeId = activeCrossfade!.id
    crossfadeProgressTask = Task {
        // 🔴 SUSPENSION POINT #5: AsyncStream iteration
        for await progress in progressStream {
            await updateCrossfadeProgress(progress)  // 🔴 SP #6
        }
    }
    
    // 6. Wait for completion
    // 🔴 SUSPENSION POINT #7: Long wait (5-15s)
    await crossfadeProgressTask?.value
    
    // 7. Identity check (race detection)
    if activeCrossfade?.id != crossfadeId {
        return .cancelled  // New crossfade started!
    }
    
    // 8. Cleanup
    await stateStore.switchActivePlayer()  // 🔴 SP #8
    
    return .completed
}
```

---

### 5. pause() - Complexity: 4+ await points

```swift
public func pause() async throws {
    Self.logger.debug("[SERVICE] pause()")
    
    // 1. Check if crossfade active
    // 🔴 SUSPENSION POINT #1
    let pausedCrossfade = try await crossfadeOrchestrator.pauseCrossfade()
    
    if pausedCrossfade == nil {
        // 2. Regular pause (no crossfade active)
        // 🔴 SUSPENSION POINT #2: Fade out
        await crossfadeOrchestrator.performSimpleFadeOut(duration: 0.3)
    }
    
    // 3. Pause engine
    // 🔴 SUSPENSION POINT #3: Engine
    await audioEngine.pause()
    
    // 4. Update state
    // 🔴 SUSPENSION POINT #4: Coordinator
    await playbackStateCoordinator.updateMode(.paused)
    
    _cachedState = .paused
    stopPlaybackTimer()
}
```

---

### 6. resume() - Complexity: 6+ await points

```swift
public func resume() async throws {
    Self.logger.debug("[SERVICE] resume()")
    
    // 1. Validate state
    // 🔴 SUSPENSION POINT #1
    guard await playbackStateCoordinator.getPlaybackMode() == .paused else {
        throw AudioPlayerError.invalidState(...)
    }
    
    // 2. Check if resuming crossfade
    // 🔴 SUSPENSION POINT #2
    let resumedCrossfade = try await crossfadeOrchestrator.resumeCrossfade()
    
    if !resumedCrossfade {
        // 3. Regular resume (no crossfade)
        // 🔴 SUSPENSION POINT #3: Engine play
        await audioEngine.play()
        
        // 🔴 SUSPENSION POINT #4: Fade in
        await crossfadeOrchestrator.performSimpleFadeIn(duration: 0.3)
    }
    
    // 4. Update state
    // 🔴 SUSPENSION POINT #5: Coordinator
    await updateState(.playing)
    
    // 🔴 SUSPENSION POINT #6: Sync track info
    await syncCachedTrackInfo()
    
    startPlaybackTimer()
}
```

---

## Suspension Point Summary

| Operation | Await Count | Longest Await | Re-entrancy Risk |
|-----------|-------------|---------------|------------------|
| skipToNext() | 15+ | 5-15s (crossfade) | 🔴 CRITICAL |
| skipToPrevious() | 15+ | 5-15s (crossfade) | 🔴 CRITICAL |
| pause() | 4 | 0.3s (fade) | 🟡 MEDIUM |
| resume() | 6 | 5-15s (crossfade resume) | 🟡 MEDIUM |
| stop() | 3 | 0.3s (fade) | 🟢 LOW |
| startPlaying() | 8+ | 2s (fade) | 🟡 MEDIUM |

---

## Race Condition Scenarios

### Scenario 1: Next → Next → Next (User rapid clicks)

```
Timeline:
t=0.0s:  skipToNext() #1 enters
t=0.1s:    await playlistManager.skipToNext() → stage2
t=0.2s:    await crossfadeOrchestrator.startCrossfade(stage2)
t=0.3s:      await audioEngine.loadAudioFileOnSecondaryPlayer() [SUSPENDED]

t=1.5s:  skipToNext() #2 enters (RE-ENTRANCY!)
t=1.6s:    debounce check passes (flag reset by Task in defer)
t=1.7s:    await playlistManager.skipToNext() → stage3
t=1.8s:    await crossfadeOrchestrator.startCrossfade(stage3)
t=1.9s:      Detects activeCrossfade #1 → rollbackCrossfade()
t=2.0s:      await audioEngine.loadAudioFileOnSecondaryPlayer() [SUSPENDED]

t=3.5s:  skipToNext() #3 enters (RE-ENTRANCY!)
t=3.6s:    debounce check passes
t=3.7s:    await playlistManager.skipToNext() → NO NEXT (end of list)
t=3.8s:    Demo's nextStage() sees stage3 → calls finishSession()
t=3.9s:    finish() executes → fadeOut + stop → 💥 STOPS PLAYBACK

t=5.0s:  Crossfade #2 completes → tries to switchActivePlayer()
         BUT player is already stopped! → State corruption
```

### Scenario 2: Play → Pause → Next (Overlapping operations)

```
Timeline:
t=0.0s:  startPlaying() enters
t=0.1s:    await audioEngine.loadAudioFileOnPrimaryPlayer() [SUSPENDED]

t=0.5s:  pause() enters (RE-ENTRANCY!)
t=0.6s:    await crossfadeOrchestrator.pauseCrossfade() → no active crossfade
t=0.7s:    await performSimpleFadeOut() [SUSPENDED]

t=0.8s:  skipToNext() enters (RE-ENTRANCY!)
t=0.9s:    await playlistManager.skipToNext() → next track
t=1.0s:    await crossfadeOrchestrator.startCrossfade() [SUSPENDED]

Result: Three operations running in parallel!
- startPlaying loading file
- pause() fading out
- skipToNext() starting crossfade

→ Undefined behavior, state corruption likely
```

---

## Solution: Task Serialization Queue

**Concept:** Queue all operations, execute one at a time

```swift
actor AudioPlayerService {
    private var operationQueue: Task<Void, Never>?
    
    private func enqueueOperation<T>(_ operation: @Sendable @escaping () async throws -> T) async rethrows -> T {
        // Wait for previous operation
        await operationQueue?.value
        
        // Execute this operation
        let task = Task<T, Error> {
            try await operation()
        }
        
        // Store as current
        operationQueue = Task {
            _ = try? await task.value
        }
        
        return try await task.value
    }
    
    public func skipToNext() async throws {
        try await enqueueOperation {
            try await _skipToNextImpl()
        }
    }
    
    private func _skipToNextImpl() async throws {
        // Original skipToNext logic (without debounce)
        guard let nextTrack = await playlistManager.skipToNext() else {
            throw AudioPlayerError.noNextTrack
        }
        try await replaceCurrentTrack(track: nextTrack, ...)
    }
}
```

**Benefits:**
- ✅ True sequential execution (no overlap)
- ✅ Remove all debounce code (no longer needed)
- ✅ Remove UUID identity tracking (no races possible)
- ✅ Simpler, cleaner code

---

## Next Steps

1. ✅ Documented all suspension points
2. ⏭ Implement task serialization queue
3. ⏭ Remove band-aids (debounce, UUID tracking)
4. ⏭ Test with rapid clicks (should handle gracefully)
5. ⏭ Measure performance impact (queue overhead)

