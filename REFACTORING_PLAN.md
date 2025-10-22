# Refactoring Plan - Exact Steps

**Date:** 2025-10-22  
**Branch:** `feature/playback-state-coordinator`  
**Goal:** SOLID-compliant architecture with Swift Concurrency control

**User Requirements:**
- ✅ Use Swift Concurrency tools (Task, TaskGroup, actors, async/await)
- ✅ Orchestrator must NOT become god object → use Command/Strategy/State Machine patterns
- ✅ Test after EACH phase
- ❌ NO quick fixes on broken architecture

---

## Current Code State (FACTS)

### PlaybackStateCoordinator.swift (799 lines)
**Location:** `Sources/AudioServiceKit/Internal/PlaybackStateCoordinator.swift`

**What EXISTS:**
- Line 45: `private let audioEngine: AudioEngineActor` (concrete dependency)
- Line 50-160: `CoordinatorState` struct (state definition)
- Line 729-748: `startPlayback()` - calls engine.play() + updateMode(.playing)
- Line 752-758: `pausePlayback()` - calls engine.pause() ONLY (no state update)
- Line 761-767: `resumePlayback()` - calls engine.play() ONLY (no state update)
- Line 770-781: `stopPlayback()` - calls engine methods ONLY (no state update)

**Problem:** State updates happen in Service (lines 324, 365), not in Coordinator methods.

### AudioPlayerService.swift (2363 lines)
**Location:** `Sources/AudioServiceKit/Public/AudioPlayerService.swift`

**What EXISTS:**
- Line 46-50: Concrete dependencies (audioEngine, playbackStateCoordinator, sessionManager, remoteCommandManager)
- Line 227-300: `startPlaying()` - 74 lines orchestrating 10 steps
- Line 302-329: `pause()` - calls coordinator.pauseCrossfade() + pausePlayback() + updateMode(.paused)
- Line 331-369: `resume()` - calls coordinator.resumeCrossfade() + resumePlayback() + updateMode(.playing)
- Line 375-437: `stop()` - orchestrates stop with fade support
- Line 2137-2158: `startEngine()` - internal helper
- Line 2165-2176: `pausePlayback()` - internal helper calling coordinator
- Line 2178-2189: `resumePlayback()` - internal helper calling coordinator

**Problem:** Service orchestrates AND updates coordinator state externally.

### AudioEngineActor.swift (1442 lines)
**Location:** `Sources/AudioServiceKit/Internal/AudioEngineActor.swift`

**What EXISTS:**
- Line 145-155: `prepare()` - AVFoundation engine prepare
- Line 157-162: `start()` - AVFoundation engine start
- Line 164-171: `stop()` - AVFoundation engine stop
- Line 179-196: `pause()` - capture position + pause both players
- Line 198-220+: `play()` - resume from saved position

**Status:** ✅ This component is CORRECT (pure hardware control, no business logic)

---

## Phase 1: Extract Protocols (1-2 hours)

### Step 1.1: Create AudioEngineControl protocol

**New File:** `Sources/AudioServiceKit/Protocols/AudioEngineControl.swift`

**Extract from AudioEngineActor.swift methods:**
```swift
protocol AudioEngineControl: Actor {
    // Lifecycle
    func prepare() async throws
    func start() async throws
    func stop() async
    
    // Playback control
    func pause() async
    func play() async
    
    // File operations
    func loadAudioFile(url: URL) async throws -> TrackInfo
    func scheduleFile(fadeIn: Bool, fadeInDuration: TimeInterval, fadeCurve: FadeCurve) async
    
    // Position
    func getCurrentPosition() async -> PlaybackPosition?
    func seek(to time: TimeInterval) async throws
    
    // Mixer control (for crossfade)
    func getActiveMixerVolume() async -> Float
    func getInactiveMixerVolume() async -> Float
    func fadeActiveMixer(from: Float, to: Float, duration: TimeInterval, curve: FadeCurve) async
    
    // Player control
    func stopBothPlayers() async
    func stopActivePlayer() async
    func stopInactivePlayer() async
    func resetInactiveMixer() async
    
    // Crossfade operations
    func cancelCrossfadeAndStopInactive() async
    
    // State queries
    func isActivePlayerPlaying() async -> Bool
    func getActiveAudioFile() async -> AVAudioFile?
}
```

**Action:** Make `AudioEngineActor` conform to this protocol (add `extension AudioEngineActor: AudioEngineControl {}`)

**Test:** Build project, ensure no compilation errors.

---

### Step 1.2: Create PlaybackStateStore protocol

**New File:** `Sources/AudioServiceKit/Protocols/PlaybackStateStore.swift`

**Extract from PlaybackStateCoordinator.swift query/mutation methods:**
```swift
protocol PlaybackStateStore: Actor {
    // QUERIES
    func getPlaybackMode() async -> PlayerState
    func getCurrentTrack() async -> Track?
    func getActiveTrackInfo() async -> TrackInfo?
    func getActivePlayer() async -> PlayerNode
    func getActiveMixerVolume() async -> Float
    func getInactiveMixerVolume() async -> Float
    func isCrossfading() async -> Bool
    
    // MUTATIONS
    func updateMode(_ mode: PlayerState) async
    func atomicSwitch(newTrack: Track, trackInfo: TrackInfo) async
    func switchActivePlayer() async
    func updateMixerVolumes(_ active: Float, _ inactive: Float) async
    func updateCrossfading(_ isCrossfading: Bool) async
    
    // SNAPSHOT
    func captureSnapshot() async -> CoordinatorState
    func restoreSnapshot(_ snapshot: CoordinatorState) async
    
    // VALIDATION
    func isStateConsistent() async -> Bool
}
```

**Action:** Make `PlaybackStateCoordinator` conform to this protocol.

**Test:** Build project, ensure no compilation errors.

---

### Step 1.3: Create supporting protocols

**New File:** `Sources/AudioServiceKit/Protocols/AudioSessionManaging.swift`
```swift
protocol AudioSessionManaging: Actor {
    func activate() async throws
    func ensureActive() async throws
    func deactivate() async throws
}
```

**New File:** `Sources/AudioServiceKit/Protocols/PlaylistManaging.swift`
```swift
protocol PlaylistManaging: Actor {
    func getCurrentTrack() async -> Track?
    func getNextTrack() async -> Track?
    // ... other playlist methods
}
```

**New File:** `Sources/AudioServiceKit/Protocols/TimerManaging.swift`
```swift
protocol TimerManaging: Actor {
    func startPlaybackTimer(positionProvider: @escaping () async -> PlaybackPosition?) async
    func stopPlaybackTimer() async
}
```

**Action:** Make existing implementations conform.

**Test:** Build project, ensure no compilation errors.

---

## Phase 2: Create PlaybackOrchestrator (3-4 hours)

### Step 2.1: Create base PlaybackOrchestrator

**New File:** `Sources/AudioServiceKit/Internal/PlaybackOrchestrator.swift`

**Structure:**
```swift
actor PlaybackOrchestrator {
    // Protocol dependencies (injected)
    private let stateStore: PlaybackStateStore
    private let engineControl: AudioEngineControl
    private let sessionManager: AudioSessionManaging
    private let playlistManager: PlaylistManaging
    private let timerManager: TimerManaging
    
    // Active operation tracking (Swift Concurrency)
    private var activeOperation: Task<Void, Never>?
    
    init(
        stateStore: PlaybackStateStore,
        engineControl: AudioEngineControl,
        sessionManager: AudioSessionManaging,
        playlistManager: PlaylistManaging,
        timerManager: TimerManaging
    ) {
        self.stateStore = stateStore
        self.engineControl = engineControl
        self.sessionManager = sessionManager
        self.playlistManager = playlistManager
        self.timerManager = timerManager
    }
    
    // Public API (to be implemented)
    func startPlaying(fadeDuration: TimeInterval) async throws
    func pause() async throws
    func resume() async throws
    func stop(fadeDuration: TimeInterval) async
}
```

**Test:** Build project, create instance in tests.

---

### Step 2.2: Implement startPlaying with Swift Concurrency control

**Copy logic from AudioPlayerService.swift:227-300**

```swift
func startPlaying(fadeDuration: TimeInterval) async throws {
    // Cancel any active operation
    activeOperation?.cancel()
    
    activeOperation = Task {
        // 1. Get track from playlist
        guard let track = await playlistManager.getCurrentTrack() else {
            throw AudioPlayerError.emptyPlaylist
        }
        
        // 2. Activate session
        try await sessionManager.activate()
        
        // 3. Prepare engine
        try await engineControl.prepare()
        
        // 4. Load file
        let trackInfo = try await engineControl.loadAudioFile(url: track.url)
        
        // 5. Update state BEFORE starting
        await stateStore.atomicSwitch(newTrack: track, trackInfo: trackInfo)
        await stateStore.updateMode(.preparing)
        
        // Check cancellation
        try Task.checkCancellation()
        
        // 6. Start engine
        try await engineControl.start()
        await engineControl.scheduleFile(
            fadeIn: fadeDuration > 0,
            fadeInDuration: fadeDuration,
            fadeCurve: .easeInOut
        )
        
        // 7. Play
        await engineControl.play()
        
        // 8. Update state AFTER starting
        await stateStore.updateMode(.playing)
        
        // 9. Start timer
        await timerManager.startPlaybackTimer { [weak engineControl] in
            await engineControl?.getCurrentPosition()
        }
    }
    
    try await activeOperation?.value
}
```

**Swift Concurrency tools used:**
- `Task` for cancellable operation
- `Task.checkCancellation()` for early exit
- `activeOperation?.cancel()` to cancel previous operation

**Test:** Call startPlaying(), verify state transitions.

---

### Step 2.3: Implement pause with error handling

**Copy logic from AudioPlayerService.swift:302-329**

```swift
func pause() async throws {
    // Validate current state
    let currentState = await stateStore.getPlaybackMode()
    guard currentState == .playing || currentState == .preparing else {
        if currentState == .paused { return }
        throw AudioPlayerError.invalidState(
            current: currentState.description,
            attempted: "pause"
        )
    }
    
    // Stop timer
    await timerManager.stopPlaybackTimer()
    
    // Pause engine (may throw)
    await engineControl.pause()
    
    // Update state ONLY after success
    await stateStore.updateMode(.paused)
}
```

**Swift Concurrency safety:**
- State check BEFORE actions
- State update ONLY after success
- If engine.pause() throws, state stays unchanged

**Test:** Call pause() from .playing and .paused states.

---

### Step 2.4: Implement resume with session check

**Copy logic from AudioPlayerService.swift:331-369**

```swift
func resume() async throws {
    // Validate current state
    let currentState = await stateStore.getPlaybackMode()
    guard currentState == .paused else {
        if currentState == .playing { return }
        throw AudioPlayerError.invalidState(
            current: currentState.description,
            attempted: "resume"
        )
    }
    
    // Ensure session active
    try await sessionManager.ensureActive()
    
    // Resume engine
    await engineControl.play()
    
    // Update state ONLY after success
    await stateStore.updateMode(.playing)
    
    // Restart timer
    await timerManager.startPlaybackTimer { [weak engineControl] in
        await engineControl?.getCurrentPosition()
    }
}
```

**Test:** Call resume() from .paused state.

---

### Step 2.5: Implement stop with optional fade

**Copy logic from AudioPlayerService.swift:375-437**

```swift
func stop(fadeDuration: TimeInterval) async {
    // Cancel active operation
    activeOperation?.cancel()
    
    // Stop timer
    await timerManager.stopPlaybackTimer()
    
    if fadeDuration > 0 {
        // Fade out
        let currentVolume = await engineControl.getActiveMixerVolume()
        await engineControl.fadeActiveMixer(
            from: currentVolume,
            to: 0.0,
            duration: fadeDuration,
            curve: .easeInOut
        )
    }
    
    // Stop engine
    await engineControl.stopBothPlayers()
    
    // Update state
    await stateStore.updateMode(.finished)
}
```

**Test:** Call stop() with fadeDuration=0 and fadeDuration=1.0.

---

### Step 2.6: Prevent god object - evaluate line count

**After implementing 4 methods:**
- Count lines in PlaybackOrchestrator.swift
- If >500 lines → proceed to Step 2.7
- If <500 lines → skip to Phase 3

---

### Step 2.7: (Conditional) Split using Command Pattern

**IF Orchestrator >500 lines, create:**

**New File:** `Sources/AudioServiceKit/Internal/PlaybackCommands/StartPlayingCommand.swift`
```swift
protocol PlaybackCommand {
    func execute() async throws
}

struct StartPlayingCommand: PlaybackCommand {
    let fadeDuration: TimeInterval
    let dependencies: PlaybackDependencies
    
    func execute() async throws {
        // Move startPlaying logic here
    }
}
```

**Refactor Orchestrator:**
```swift
actor PlaybackOrchestrator {
    func startPlaying(fadeDuration: TimeInterval) async throws {
        let command = StartPlayingCommand(
            fadeDuration: fadeDuration,
            dependencies: dependencies
        )
        try await command.execute()
    }
}
```

**Test:** Ensure behavior unchanged after split.

---

## Phase 3: Refactor StateCoordinator → StateStore (2-3 hours)

### Step 3.1: Remove engine control from PlaybackStateCoordinator

**File:** `Sources/AudioServiceKit/Internal/PlaybackStateCoordinator.swift`

**DELETE these methods (lines 729-781):**
- `startPlayback()` - Line 729-748
- `pausePlayback()` - Line 752-758
- `resumePlayback()` - Line 761-767
- `stopPlayback()` - Line 770-781

**REMOVE property (line 45):**
- `private let audioEngine: AudioEngineActor`

**UPDATE init:** Remove audioEngine parameter.

**Test:** Build fails at call sites - expected.

---

### Step 3.2: Update call sites in PlaybackOrchestrator

**Find usages:** Search for `coordinator.startPlayback`, `coordinator.pausePlayback`, `coordinator.resumePlayback`, `coordinator.stopPlayback`

**Replace with direct engine calls:**
- `coordinator.startPlayback()` → `engineControl.play()` + `stateStore.updateMode(.playing)`
- `coordinator.pausePlayback()` → `engineControl.pause()`
- `coordinator.resumePlayback()` → `engineControl.play()`
- (Already done in Step 2.2-2.5)

**Test:** Build succeeds, Orchestrator compiles.

---

### Step 3.3: Rename PlaybackStateCoordinator → PlaybackStateStore

**Action:**
1. Rename file: `PlaybackStateCoordinator.swift` → `PlaybackStateStore.swift`
2. Rename class: `actor PlaybackStateCoordinator` → `actor PlaybackStateStoreImpl`
3. Update all references in codebase

**Test:** Build project, run existing tests.

---

## Phase 4: Simplify AudioPlayerService (1-2 hours)

### Step 4.1: Inject PlaybackOrchestrator into Service

**File:** `Sources/AudioServiceKit/Public/AudioPlayerService.swift`

**REPLACE properties (lines 44-51):**
```swift
// OLD:
internal let audioEngine: AudioEngineActor
private let playbackStateCoordinator: PlaybackStateCoordinator
internal let sessionManager: AudioSessionManager
// ...

// NEW:
private let orchestrator: PlaybackOrchestrator
```

**UPDATE init:** Accept `orchestrator: PlaybackOrchestrator` parameter.

---

### Step 4.2: Replace startPlaying logic with delegation

**File:** `AudioPlayerService.swift`

**REPLACE lines 227-300 (74 lines) with:**
```swift
public func startPlaying(fadeDuration: TimeInterval = 0.0) async throws {
    try await orchestrator.startPlaying(fadeDuration: fadeDuration)
    _cachedState = await orchestrator.getCurrentState()
    await syncCachedTrackInfo()
}
```

**Test:** Call startPlaying(), verify state updates.

---

### Step 4.3: Replace pause/resume/stop with delegation

**REPLACE pause() (lines 302-329):**
```swift
public func pause() async throws {
    try await orchestrator.pause()
    _cachedState = await orchestrator.getCurrentState()
}
```

**REPLACE resume() (lines 331-369):**
```swift
public func resume() async throws {
    try await orchestrator.resume()
    _cachedState = await orchestrator.getCurrentState()
}
```

**REPLACE stop() (lines 375-437):**
```swift
public func stop(fadeDuration: TimeInterval = 0.0) async {
    await orchestrator.stop(fadeDuration: fadeDuration)
    _cachedState = await orchestrator.getCurrentState()
}
```

**DELETE internal helpers (lines 2137-2189):**
- `startEngine()`
- `pausePlayback()`
- `resumePlayback()`

**Test:** All public API methods work.

---

### Step 4.4: Count lines in AudioPlayerService

**Expected result:** ~500-800 lines (down from 2363)

**If still >1000 lines:** Crossfade, playlist, overlay, sound effects logic can be extracted to separate managers.

---

## Phase 5: Extract CrossfadeOrchestrator (3-4 hours)

### Step 5.1: Create CrossfadeOrchestrator protocol

**New File:** `Sources/AudioServiceKit/Protocols/CrossfadeOrchestrating.swift`

```swift
protocol CrossfadeOrchestrating: Actor {
    func startCrossfade(
        to track: Track,
        operation: CrossfadeOperation
    ) async throws -> AsyncStream<Float>
    
    func pauseCrossfade() async throws -> Bool
    func resumeCrossfade() async throws -> Bool
    func cancelCrossfade() async
    func hasActiveCrossfade() async -> Bool
    func hasPausedCrossfade() async -> Bool
    func clearPausedCrossfade() async
}
```

---

### Step 5.2: Move crossfade logic from PlaybackStateCoordinator

**Find methods in PlaybackStateCoordinator.swift:**
- `startCrossfade()` - Line ~500-600
- `pauseCrossfade()` - Line ~650
- `resumeCrossfade()` - Line ~680
- `cancelActiveCrossfade()` - Line ~710
- Related state: `activeCrossfadeState`, `pausedCrossfadeState`

**Create:** `Sources/AudioServiceKit/Internal/CrossfadeOrchestrator.swift`

**Move logic + inject dependencies:**
```swift
actor CrossfadeOrchestrator: CrossfadeOrchestrating {
    private let stateStore: PlaybackStateStore
    private let engineControl: AudioEngineControl
    
    private var activeCrossfadeTask: Task<Void, Never>?
    private var pausedCrossfadeState: PausedCrossfadeState?
    
    init(
        stateStore: PlaybackStateStore,
        engineControl: AudioEngineControl
    ) {
        self.stateStore = stateStore
        self.engineControl = engineControl
    }
    
    // Move crossfade methods here
}
```

**Test:** Build, verify crossfade operations work.

---

### Step 5.3: Update PlaybackOrchestrator to use CrossfadeOrchestrator

**Inject crossfade orchestrator:**
```swift
actor PlaybackOrchestrator {
    private let crossfadeOrchestrator: CrossfadeOrchestrating
    
    // In pause():
    if await crossfadeOrchestrator.hasActiveCrossfade() {
        _ = try await crossfadeOrchestrator.pauseCrossfade()
    }
}
```

**Test:** Pause during crossfade, resume from paused crossfade.

---

## Testing Strategy (After Each Phase)

### Unit Tests
```swift
func testPauseFromPlaying() async throws {
    let mockStore = MockPlaybackStateStore()
    let mockEngine = MockAudioEngineControl()
    let orchestrator = PlaybackOrchestrator(
        stateStore: mockStore,
        engineControl: mockEngine,
        ...
    )
    
    mockStore.setState(.playing)
    try await orchestrator.pause()
    
    XCTAssertEqual(mockEngine.pauseCalled, true)
    XCTAssertEqual(mockStore.currentState, .paused)
}
```

### Integration Tests
```swift
func testStartPlayingToCompletion() async throws {
    // Use real components
    let service = AudioPlayerService(orchestrator: realOrchestrator)
    try await service.startPlaying()
    
    // Verify audio plays
    XCTAssertEqual(service.state, .playing)
}
```

### Manual Testing Checklist
- [ ] Start playing → pause → resume → stop
- [ ] Start playing → skip forward → pause
- [ ] Crossfade between tracks → pause mid-crossfade → resume
- [ ] Start playing → Bluetooth disconnect → resume
- [ ] Stop with fade (fadeDuration > 0)

---

## Success Criteria

### Phase 1 ✅
- [ ] All protocols created
- [ ] Existing actors conform to protocols
- [ ] Project builds without errors

### Phase 2 ✅
- [ ] PlaybackOrchestrator implements 4 methods (start/pause/resume/stop)
- [ ] Uses Swift Concurrency: Task, cancellation, error handling
- [ ] If >500 lines: split using Command pattern
- [ ] All unit tests pass

### Phase 3 ✅
- [ ] PlaybackStateCoordinator renamed to PlaybackStateStoreImpl
- [ ] Engine control removed from StateStore
- [ ] StateStore has ZERO dependencies
- [ ] Project builds

### Phase 4 ✅
- [ ] AudioPlayerService delegates to Orchestrator
- [ ] Service is <1000 lines (ideally <800)
- [ ] Public API unchanged (backward compatible)
- [ ] All integration tests pass

### Phase 5 ✅
- [ ] CrossfadeOrchestrator extracted
- [ ] Crossfade operations work (pause/resume crossfade)
- [ ] PlaybackOrchestrator uses CrossfadeOrchestrator
- [ ] Manual test: crossfade → pause → resume

---

## Swift Concurrency Usage Summary

**Tools used:**
1. ✅ **Task** - cancellable operations in `activeOperation`
2. ✅ **Task.checkCancellation()** - early exit from long operations
3. ✅ **actor** - thread-safe access to orchestrator state
4. ✅ **async/await** - proper error propagation
5. ✅ **AsyncStream** - crossfade progress reporting
6. 🔜 **TaskGroup** - (if needed for parallel operations)

**Race condition prevention:**
- State check → Action → State update (atomic sequence)
- If Action throws error → State unchanged
- Cancel previous operation before starting new one

---

## Rollback Plan

**If phase fails:**
1. `git stash` current changes
2. `git checkout feature/playback-state-coordinator`
3. Review what went wrong
4. Fix issue
5. `git stash pop`
6. Continue

**If complete failure:**
- All analysis documents preserved
- Can restart from Phase 1 with lessons learned

---

**Next Step:** Wait for user confirmation, then start Phase 1.
