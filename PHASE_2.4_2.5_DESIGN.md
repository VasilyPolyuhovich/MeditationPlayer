# Phase 2.4 & 2.5 Design: Complete Coordinator Migration

## 🎯 Goal

Migrate **all playback orchestration** from AudioPlayerService → PlaybackStateCoordinator, making Service a thin facade.

---

## 📊 Current State Analysis

### AudioPlayerService (2727 lines) - TOO FAT

**Crossfade State (Phase 2.4 target):**
```swift
// Lines 56-123: Crossfade tracking
private var activeCrossfadeOperation: CrossfadeOperation? = nil
private struct PausedCrossfadeState { ... } // 60 lines
private var pausedCrossfadeState: PausedCrossfadeState? = nil
private var crossfadeProgressTask: Task<Void, Never>?
private var crossfadeCleanupTask: Task<Void, Never>?
public private(set) var currentCrossfadeProgress: CrossfadeProgress = .idle
```

**Engine Control (Phase 2.5 target):**
```swift
// Scattered across service:
func startPlaying() {
    await updateState(.preparing)
    try await startEngine()        // ⚠️ Direct engine call
    await updateState(.playing)
}

func pause() {
    await pausePlayback()          // ⚠️ Direct engine call
    await updateState(.paused)
}

func resume() {
    try await resumePlayback()     // ⚠️ Direct engine call
    await updateState(.playing)
}
```

**Problems:**
1. ❌ Service has 200+ lines of crossfade orchestration logic
2. ❌ Service directly calls engine (side effects scattered)
3. ❌ State + side effects mixed together
4. ❌ Hard to test, hard to reason about
5. ❌ Coordinator is just a "state holder", not a real coordinator

---

## 🏗️ Phase 2.4: Crossfade → Coordinator

### Design Principle

**Before:**
```swift
// AudioPlayerService owns crossfade orchestration
func replaceCurrentTrack() {
    if activeCrossfadeOperation != nil {
        await audioEngine.rollbackCrossfade()
        // ... cleanup ...
    }
    let result = await executeCrossfade(...)
    // ... 50+ lines ...
}
```

**After:**
```swift
// PlaybackStateCoordinator owns crossfade orchestration
actor PlaybackStateCoordinator {
    func startCrossfade(to track: Track, duration: TimeInterval) async throws
    func rollbackCurrentCrossfade() async
    func pauseCrossfade() async throws -> PausedCrossfadeState
    func resumeCrossfade(_ state: PausedCrossfadeState) async throws
}

// AudioPlayerService becomes thin facade
func replaceCurrentTrack(track: Track) {
    try await coordinator.startCrossfade(to: track, duration: ...)
}
```

### Migration Plan

#### Step 1: Add Crossfade State to Coordinator

```swift
actor PlaybackStateCoordinator {
    
    // MARK: - Crossfade State
    
    enum CrossfadeOperation {
        case automaticLoop
        case manualChange
    }
    
    struct CrossfadeState {
        let operation: CrossfadeOperation
        let startTime: Date
        let duration: TimeInterval
        let curve: FadeCurve
        let fromTrack: Track
        let toTrack: Track
        var progress: Float  // 0.0...1.0
    }
    
    private var activeCrossfade: CrossfadeState? = nil
    private var pausedCrossfade: PausedCrossfadeState? = nil
    
    // Crossfade progress stream
    private var crossfadeProgressContinuation: AsyncStream<CrossfadeProgress>.Continuation?
    
    func getCrossfadeProgress() -> AsyncStream<CrossfadeProgress> {
        AsyncStream { continuation in
            self.crossfadeProgressContinuation = continuation
        }
    }
}
```

#### Step 2: Migrate Crossfade Operations

```swift
actor PlaybackStateCoordinator {
    
    /// Start crossfade from active track to new track
    /// - Returns: CrossfadeResult (.completed, .paused, .cancelled)
    func startCrossfade(
        to track: Track,
        duration: TimeInterval,
        curve: FadeCurve,
        operation: CrossfadeOperation
    ) async throws -> CrossfadeResult {
        
        // 1. Rollback existing crossfade if any
        if activeCrossfade != nil {
            await rollbackCurrentCrossfade()
        }
        
        // 2. Create crossfade state
        guard let fromTrack = state.activeTrack else {
            throw AudioPlayerError.invalidState(message: "No active track")
        }
        
        activeCrossfade = CrossfadeState(
            operation: operation,
            startTime: Date(),
            duration: duration,
            curve: curve,
            fromTrack: fromTrack,
            toTrack: track
        )
        
        // 3. Load track on inactive player
        try await audioEngine.loadAudioFileOnSecondaryPlayer(url: track.url)
        loadTrackOnInactive(track)
        
        // 4. Prepare and start crossfade
        await audioEngine.prepareSecondaryPlayer()
        
        let result = await audioEngine.startCrossfade(
            duration: duration,
            curve: curve
        )
        
        // 5. Handle result
        switch result {
        case .completed:
            // Crossfade completed - switch players
            switchActivePlayer()
            activeCrossfade = nil
            crossfadeProgressContinuation?.yield(.idle)
            return .completed
            
        case .paused:
            // Was paused mid-crossfade
            return .paused
            
        case .cancelled:
            // Cancelled (should not happen here)
            activeCrossfade = nil
            return .cancelled
        }
    }
    
    /// Rollback current crossfade smoothly
    func rollbackCurrentCrossfade() async {
        guard activeCrossfade != nil else { return }
        
        logger.debug("[Coordinator] Rolling back crossfade")
        
        // Quick fade to active player
        _ = await audioEngine.rollbackCrossfade(rollbackDuration: 0.3)
        
        // Clear state
        activeCrossfade = nil
        state = state.withInactiveTrack(nil)
            .withMixerVolumes(active: 1.0, inactive: 0.0)
            .withCrossfading(false)
        
        crossfadeProgressContinuation?.yield(.idle)
    }
    
    /// Pause current crossfade
    func pauseCrossfade() async throws -> PausedCrossfadeState? {
        guard let crossfade = activeCrossfade else { return nil }
        
        logger.debug("[Coordinator] Pausing crossfade")
        
        // Capture engine state
        let engineState = await audioEngine.captureCrossfadeState()
        
        // Create paused state
        let pausedState = PausedCrossfadeState(
            progress: crossfade.progress,
            originalDuration: crossfade.duration,
            curve: crossfade.curve,
            activeMixerVolume: engineState.activeMixerVolume,
            inactiveMixerVolume: engineState.inactiveMixerVolume,
            activePlayerPosition: engineState.activePlayerPosition,
            inactivePlayerPosition: engineState.inactivePlayerPosition,
            activePlayer: state.activePlayer,
            operation: crossfade.operation
        )
        
        // Store and clear active
        pausedCrossfade = pausedState
        activeCrossfade = nil
        
        crossfadeProgressContinuation?.yield(.paused(progress: crossfade.progress))
        
        return pausedState
    }
    
    /// Resume paused crossfade
    func resumeCrossfade() async throws -> Bool {
        guard let paused = pausedCrossfade else { return false }
        
        logger.debug("[Coordinator] Resuming crossfade (strategy: \(paused.resumeStrategy))")
        
        // Delegate to engine
        let resumed = await audioEngine.resumeCrossfade(
            from: paused,
            targetVolume: 1.0
        )
        
        if resumed {
            // Recreate active crossfade from paused state
            activeCrossfade = CrossfadeState(
                operation: paused.operation,
                startTime: Date(),
                duration: paused.remainingDuration,
                curve: paused.curve,
                fromTrack: state.activeTrack!,
                toTrack: state.inactiveTrack!
            )
            pausedCrossfade = nil
        }
        
        return resumed
    }
}
```

#### Step 3: Update AudioPlayerService to Delegate

```swift
actor AudioPlayerService {
    
    // Remove crossfade state fields
    // private var activeCrossfadeOperation ❌ DELETED
    // private var pausedCrossfadeState ❌ DELETED
    // private var crossfadeProgressTask ❌ DELETED
    
    // Delegate to coordinator
    func replaceCurrentTrack(track: Track, crossfadeDuration: TimeInterval) async throws {
        Self.logger.debug("[SERVICE] replaceCurrentTrack → coordinator")
        
        let result = try await playbackStateCoordinator.startCrossfade(
            to: track,
            duration: crossfadeDuration,
            curve: configuration.fadeCurve,
            operation: .manualChange
        )
        
        if result == .completed {
            await updateNowPlayingInfo()
        }
    }
    
    func pause() async throws {
        Self.logger.debug("[SERVICE] pause → coordinator")
        
        // Pause crossfade if active
        _ = await playbackStateCoordinator.pauseCrossfade()
        
        // Pause playback
        await pausePlayback()
        await playbackStateCoordinator.updateMode(.paused)
    }
    
    func resume() async throws {
        Self.logger.debug("[SERVICE] resume → coordinator")
        
        // Try resume crossfade first
        let resumed = try await playbackStateCoordinator.resumeCrossfade()
        
        if !resumed {
            // Normal resume
            try await resumePlayback()
        }
        
        await playbackStateCoordinator.updateMode(.playing)
    }
}
```

---

## 🏗️ Phase 2.5: Engine Control → Coordinator

### Design Principle

**Goal:** Coordinator becomes the **only** actor that talks to AudioEngineActor. Service never calls engine directly.

**Before:**
```swift
// AudioPlayerService directly calls engine
func startPlaying() {
    try await startEngine()        // ❌ Direct!
    await updateState(.playing)
}

func pause() {
    await pausePlayback()          // ❌ Direct!
    await updateState(.paused)
}
```

**After:**
```swift
// PlaybackStateCoordinator owns all engine interactions
actor PlaybackStateCoordinator {
    func startPlayback() async throws
    func pausePlayback() async
    func resumePlayback() async throws
    func stopPlayback() async
}

// AudioPlayerService delegates
func startPlaying() {
    try await coordinator.startPlayback()
}

func pause() {
    await coordinator.pausePlayback()
}
```

### Migration Plan

#### Step 1: Add Engine Control to Coordinator

```swift
actor PlaybackStateCoordinator {
    
    // MARK: - Engine Control
    
    /// Start playback from stopped/finished state
    func startPlayback() async throws {
        logger.debug("[Coordinator] startPlayback()")
        
        guard state.activeTrack != nil else {
            throw AudioPlayerError.invalidState(message: "No track loaded")
        }
        
        // Update state first
        updateMode(.preparing)
        
        // Start engine
        try await audioEngine.startEngine()
        
        // Transition to playing
        updateMode(.playing)
        
        logger.info("[Coordinator] ✅ Playback started")
    }
    
    /// Pause playback (may pause crossfade too)
    func pausePlayback() async {
        logger.debug("[Coordinator] pausePlayback()")
        
        // Pause crossfade if active
        _ = try? await pauseCrossfade()
        
        // Pause engine
        await audioEngine.pauseEngine()
        
        // Update state
        updateMode(.paused)
        
        logger.info("[Coordinator] ✅ Playback paused")
    }
    
    /// Resume playback (may resume crossfade too)
    func resumePlayback() async throws {
        logger.debug("[Coordinator] resumePlayback()")
        
        guard state.playbackMode == .paused else {
            throw AudioPlayerError.invalidState(message: "Not paused")
        }
        
        // Try resume crossfade first
        let resumedCrossfade = try await resumeCrossfade()
        
        if !resumedCrossfade {
            // Normal resume
            try await audioEngine.resumeEngine()
        }
        
        // Update state
        updateMode(.playing)
        
        logger.info("[Coordinator] ✅ Playback resumed")
    }
    
    /// Stop playback completely
    func stopPlayback(fadeDuration: TimeInterval?) async throws {
        logger.debug("[Coordinator] stopPlayback()")
        
        // Cancel any crossfade
        await rollbackCurrentCrossfade()
        
        // Stop engine (with optional fade)
        if let duration = fadeDuration {
            try await audioEngine.stopWithFade(duration: duration)
        } else {
            await audioEngine.stopEngine()
        }
        
        // Reset state
        state = CoordinatorState(
            activePlayer: .a,
            playbackMode: .finished,
            activeTrack: nil,
            inactiveTrack: nil,
            activeMixerVolume: 1.0,
            inactiveMixerVolume: 0.0,
            isCrossfading: false
        )
        
        logger.info("[Coordinator] ✅ Playback stopped")
    }
}
```

#### Step 2: Update AudioPlayerService

```swift
actor AudioPlayerService {
    
    // Remove direct engine calls
    // private func startEngine() ❌ DELETED
    // private func pausePlayback() ❌ DELETED
    // private func resumePlayback() ❌ DELETED
    
    func startPlaying(fadeInDuration: TimeInterval? = nil) async throws {
        Self.logger.debug("[SERVICE] startPlaying → coordinator")
        
        // Delegate to coordinator
        try await playbackStateCoordinator.startPlayback()
        
        // Service-level concerns
        await updateNowPlayingInfo()
        startPlaybackTimer()
    }
    
    func pause() async throws {
        Self.logger.debug("[SERVICE] pause → coordinator")
        
        // Delegate to coordinator
        await playbackStateCoordinator.pausePlayback()
        
        // Service-level concerns
        stopPlaybackTimer()
    }
    
    func resume() async throws {
        Self.logger.debug("[SERVICE] resume → coordinator")
        
        // Delegate to coordinator
        try await playbackStateCoordinator.resumePlayback()
        
        // Service-level concerns
        startPlaybackTimer()
    }
    
    func stop(fadeDuration: TimeInterval? = nil) async throws {
        Self.logger.debug("[SERVICE] stop → coordinator")
        
        // Delegate to coordinator
        try await playbackStateCoordinator.stopPlayback(fadeDuration: fadeDuration)
        
        // Service-level concerns
        stopPlaybackTimer()
        await updateNowPlayingInfo()
    }
}
```

---

## 📈 Expected Impact

### Before (Current)

```
AudioPlayerService: 2727 lines
├─ State management: ~100 lines
├─ Crossfade logic: ~200 lines
├─ Engine control: ~150 lines
├─ Playlist: ~300 lines
├─ API methods: ~800 lines
├─ Helpers: ~400 lines
└─ Other: ~777 lines

PlaybackStateCoordinator: 328 lines
└─ Just state holder (passive)
```

### After (Phase 2.4 + 2.5)

```
AudioPlayerService: ~1800 lines (-900)
├─ Delegation: ~200 lines
├─ Playlist: ~300 lines
├─ API facade: ~600 lines
├─ NowPlaying/Timer: ~300 lines
├─ Helpers: ~200 lines
└─ Other: ~200 lines

PlaybackStateCoordinator: ~800 lines (+472)
├─ State management: ~200 lines
├─ Crossfade orchestration: ~250 lines
├─ Engine control: ~200 lines
└─ Validation: ~150 lines
```

**Benefits:**
1. ✅ Clear separation: Service = facade, Coordinator = brain
2. ✅ Easier testing: Mock coordinator instead of full service
3. ✅ Better isolation: Crossfade logic in one place
4. ✅ Single entry point to engine (coordinator only)
5. ✅ Less chance of state inconsistency

---

## 🚀 Implementation Order

### Phase 2.4 (Crossfade)
1. ✅ Add crossfade state to coordinator
2. ✅ Implement `startCrossfade()`
3. ✅ Implement `rollbackCurrentCrossfade()`
4. ✅ Implement `pauseCrossfade()` / `resumeCrossfade()`
5. ✅ Update Service to delegate
6. ✅ Remove crossfade state from Service
7. ✅ Test all crossfade scenarios

### Phase 2.5 (Engine Control)
1. ✅ Add engine control methods to coordinator
2. ✅ Implement `startPlayback()` / `pausePlayback()` / `resumePlayback()` / `stopPlayback()`
3. ✅ Update Service to delegate
4. ✅ Remove direct engine calls from Service
5. ✅ Test all playback scenarios

---

## ✅ Success Criteria

**Phase 2.4:**
- [ ] No `activeCrossfadeOperation` in Service
- [ ] No `pausedCrossfadeState` in Service
- [ ] No `executeCrossfade()` in Service
- [ ] All crossfade logic in Coordinator
- [ ] Build passes
- [ ] All manual tests pass

**Phase 2.5:**
- [ ] No `startEngine()` in Service
- [ ] No `pausePlayback()` in Service  
- [ ] No `resumePlayback()` in Service
- [ ] No direct `audioEngine.X()` calls in Service
- [ ] All engine control in Coordinator
- [ ] Build passes
- [ ] All manual tests pass

**Final Check:**
- [ ] Service is <2000 lines
- [ ] Coordinator is ~800 lines
- [ ] Clear architectural boundaries
- [ ] No regressions from Phase 2.2 hotfixes
- [ ] User testing passes (Start → Next → Next smooth)
