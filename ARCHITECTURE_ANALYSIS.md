# Architecture Analysis - Operation Atomicity Problem

**Date:** 2025-10-24
**Analyst:** Senior Architect
**Problem:** Player operations execute in parallel instead of sequentially, causing race conditions

---

## Executive Summary

**Core Issue:** AudioPlayerService is an `actor`, but operations are NOT atomic because methods `await` on other actors (CrossfadeOrchestrator, AudioEngineActor), allowing re-entrancy.

**Impact:** Race conditions on basic operations like Next→Next→Next causing finish() to execute during crossfade.

**Root Cause:** No operation serialization queue. Actor isolation protects properties but NOT execution flow.

---

## Current Architecture

### Component Hierarchy

```
AudioPlayerService (public actor)
├── CrossfadeOrchestrator (internal class)
│   ├── startCrossfade() async → CrossfadeResult
│   ├── pauseCrossfade() async throws → snapshot
│   ├── resumeCrossfade() async throws → bool
│   └── cancelActiveCrossfade() async
├── AudioEngineActor (internal actor)
│   ├── loadAudioFileOnSecondaryPlayer() throws → Track
│   ├── fadeVolume() async
│   ├── startCrossfadeExecution() async → AsyncStream<Progress>
│   └── rollbackCrossfade() async
├── PlaybackStateCoordinator (internal class)
│   ├── updateMode() → void (sync)
│   ├── switchActivePlayer() → void (sync)
│   └── getCurrentTrack() → Track? (sync)
└── PlaylistManager (internal class)
    ├── skipToNext() → Track? (sync)
    └── skipToPrevious() → Track? (sync)
```

### Operation Categories

**1. Transport Controls** (atomic requirement: sequential)
- `startPlaying()` - load + fade in + play
- `pause()` - fade out + pause engine
- `resume()` - fade in + play engine
- `stop()` - fade out + stop engine

**2. Navigation** (atomic requirement: sequential)
- `skipToNext()` - crossfade to next track
- `skipToPrevious()` - crossfade to previous track
- `seek()` - fade out + seek + fade in

**3. State Queries** (atomic requirement: none, read-only)
- `state` - cached PlayerState
- `currentTrack` - cached Track.Metadata
- `playbackPosition` - cached position

---

## Problem Analysis

### Example: skipToNext() Flow

**User Action:** Tap Next 3 times rapidly

**What SHOULD happen:**
```
Click 1: Next → wait for completion → Next
Click 2: Next → wait for completion → Next
Click 3: Next → wait for completion
```

**What ACTUALLY happens:**
```
t=0.0s:  Click 1 → skipToNext() enters
t=0.1s:  - playlistManager.skipToNext() (sync) → stage2Music
t=0.2s:  - crossfadeOrchestrator.startCrossfade(stage2Music) enters
t=0.3s:    - audioEngine.loadAudioFileOnSecondaryPlayer() [AWAIT]
         
t=1.5s:  Click 2 → skipToNext() enters (re-entrancy!)
t=1.6s:  - debounce check: isHandlingNavigation = false → PASS
t=1.7s:  - isHandlingNavigation = true
t=1.8s:  - playlistManager.skipToNext() → stage3Music
t=1.9s:  - crossfadeOrchestrator.startCrossfade(stage3Music)
t=2.0s:    - rollbackCurrentCrossfade() → cancels crossfade #1
t=2.1s:    - audioEngine.loadAudioFileOnSecondaryPlayer() [AWAIT]

t=3.5s:  Click 3 → skipToNext() enters (re-entrancy!)
t=3.6s:  - debounce check: isHandlingNavigation = false → PASS (debounce expired!)
t=3.7s:  - currentStage = .stage3 (from demo)
t=3.8s:  - Demo logic: transitionToStage3() → calls finishSession()!
t=3.9s:  - finish() called → fadeOut + stop → 💥 Player stops!
```

### Why Actor Isolation Doesn't Help

**Actor Guarantee:** Properties are protected from concurrent access

**Actor Does NOT Guarantee:** Method completes before next method starts

**From Swift Concurrency docs:**
> "Actors serialize access to their mutable state, but they do NOT prevent reentrancy. When an actor-isolated method suspends (await), other actor-isolated code can run."

**Illustration:**
```swift
actor AudioPlayerService {
    func skipToNext() async throws {
        let track = await playlistManager.skipToNext()
        await crossfadeOrchestrator.startCrossfade(track)
        // ^^^ SUSPENSION POINT: Other skipToNext() can start here!
    }
}
```

### Current Mitigation Attempts (Band-aids)

**1. Debounce Flag:**
```swift
private var isHandlingNavigation = false
private let navigationDebounceDelay: TimeInterval = 0.5

func skipToNext() async throws {
    guard !isHandlingNavigation else { return }  // Ignore rapid clicks
    isHandlingNavigation = true
    defer {
        Task { 
            try? await Task.sleep(nanoseconds: 500_000_000)
            await setNavigationHandlingFlag(false)
        }
    }
    // ... operation
}
```

**Problems:**
- ❌ Not foolproof: 500ms window can expire during long operation
- ❌ Complexity: defer + Task + sleep + flag reset
- ❌ User can still break it with timing

**2. UUID Identity Tracking:**
```swift
struct ActiveCrossfadeState {
    let id: UUID
    // ...
}

let crossfadeId = activeCrossfade!.id
await crossfadeProgressTask?.value
if activeCrossfade?.id != crossfadeId {
    return .cancelled  // Different crossfade started
}
```

**Problems:**
- ❌ Reactive: detects race AFTER it happened
- ❌ Cleanup still runs partially
- ❌ State corruption possible before detection

---

## Root Cause Summary

**Problem:** Actor re-entrancy during `await` on cross-actor calls

**Missing:** Operation serialization queue

**Result:** Multiple operations execute in overlapping time windows

---

## Expected Behavior (Sequential Atomicity)

```
User Action Sequence:
play() → pause() → resume() → skipToNext() → skipToNext() → stop()

Execution Timeline (SHOULD BE):
|----play----|----pause----|----resume----|----skip1----|----skip2----|----stop----|
      ↑           ↑              ↑              ↑             ↑            ↑
   completes   completes      completes      completes    completes   completes
```

**Requirements:**
1. ✅ Operation starts ONLY after previous completes
2. ✅ No overlapping execution
3. ✅ State is consistent at operation boundaries
4. ✅ User gets predictable behavior

---

## Solution Direction

**Option A: Task Serialization Queue**
```swift
actor AudioPlayerService {
    private var operationQueue: Task<Void, Never>?
    
    func skipToNext() async throws {
        operationQueue = Task {
            await operationQueue?.value  // Wait for previous
            await _skipToNextImpl()       // Execute this
        }
        try await operationQueue!.value
    }
}
```

**Option B: AsyncSerialExecutor (Swift 6+)**
```swift
actor AudioPlayerService {
    private let executor = AsyncSerialExecutor()
    
    func skipToNext() async throws {
        try await executor.execute {
            await _skipToNextImpl()
        }
    }
}
```

**Option C: Manual Semaphore**
```swift
actor AudioPlayerService {
    private var isOperationRunning = false
    
    func skipToNext() async throws {
        while isOperationRunning {
            await Task.yield()
        }
        isOperationRunning = true
        defer { isOperationRunning = false }
        await _skipToNextImpl()
    }
}
```

---

## Next Steps

1. **Validate hypothesis:** Confirm actor re-entrancy is the issue
2. **Choose solution:** Task queue vs executor vs semaphore
3. **Implement:** Add serialization to critical operations
4. **Test:** Verify rapid clicks don't cause race conditions
5. **Remove band-aids:** Delete debounce, UUID tracking

---

## Questions for Product Owner

1. Should ALL operations serialize, or only navigation (skipToNext/skipToPrevious)?
2. Should state queries (state, currentTrack) block during operations?
3. Maximum acceptable operation queue depth? (e.g., drop requests after 3 queued)
4. Timeout for operations? (prevent infinite hang if crossfade deadlocks)

