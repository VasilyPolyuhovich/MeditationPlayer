# SOLID-Compliant Architecture: Target Design

**Date:** 2025-10-22  
**Branch:** feature/playback-state-coordinator  
**Goal:** Propose clear component separation following SOLID principles

---

## 🎯 Design Principles

### 1. Single Responsibility
Each component has ONE reason to change:
- **State Store** → State structure changes
- **Engine Control** → AVFoundation API changes  
- **Orchestrator** → Business flow changes
- **Facade** → Public API changes

### 2. Interface Segregation
Clients depend on minimal interfaces:
- Basic playback vs Advanced features
- State queries vs State mutations
- Engine control vs Crossfade control

### 3. Dependency Inversion
All dependencies are protocols:
- `StateStore` protocol (not concrete Coordinator)
- `AudioEngine` protocol (not concrete Actor)
- `SessionManager` protocol (not concrete class)

---

## 🏗️ Target Architecture

```
┌─────────────────────────────────────────────────────────┐
│                  AudioPlayerService                      │
│                   (Public Facade)                        │
│  • Minimal API delegation                               │
│  • Protocol conformance only                            │
└────────────┬────────────────────────────────────────────┘
             │ delegates to
             ↓
┌─────────────────────────────────────────────────────────┐
│              PlaybackOrchestrator                        │
│              (Business Logic Layer)                      │
│  • Orchestrates multi-step flows                        │
│  • Coordinates: State, Engine, Session, Playlist        │
│  • Error handling & validation                          │
└──┬──────┬──────┬──────┬──────┬──────┬──────┬───────────┘
   │      │      │      │      │      │      │
   ↓      ↓      ↓      ↓      ↓      ↓      ↓
┌──────┐ ┌───────┐ ┌────────┐ ┌───────┐ ┌────────┐ ┌──────┐
│State │ │Engine │ │Session │ │Remote │ │Playlist│ │Timer │
│Store │ │Control│ │Manager │ │Command│ │Manager │ │Manager│
└──────┘ └───────┘ └────────┘ └───────┘ └────────┘ └──────┘
```

---

## 📦 Component Breakdown

### 1️⃣ **AudioPlayerService** (Public Facade)

**File:** `AudioPlayerService.swift` (shrink to ~300 lines)  
**Responsibility:** Protocol conformance + delegation  
**Dependencies:** `PlaybackOrchestrator` (injected)

```swift
public actor AudioPlayerService: AudioPlayerProtocol {
    private let orchestrator: PlaybackOrchestrator
    
    // Cached properties for sync protocol conformance
    private var _cachedState: PlayerState = .finished
    public var state: PlayerState { _cachedState }
    
    public init(orchestrator: PlaybackOrchestrator) {
        self.orchestrator = orchestrator
    }
    
    // ✅ THIN methods - just delegate
    public func startPlaying(fadeDuration: TimeInterval = 0.0) async throws {
        try await orchestrator.startPlaying(fadeDuration: fadeDuration)
        _cachedState = await orchestrator.getCurrentState()
    }
    
    public func pause() async throws {
        try await orchestrator.pause()
        _cachedState = await orchestrator.getCurrentState()
    }
    
    public func resume() async throws {
        try await orchestrator.resume()
        _cachedState = await orchestrator.getCurrentState()
    }
    
    public func stop(fadeDuration: TimeInterval = 0.0) async {
        await orchestrator.stop(fadeDuration: fadeDuration)
        _cachedState = await orchestrator.getCurrentState()
    }
    
    // Playlist delegation
    public func skipForward(_ interval: TimeInterval) async throws {
        try await orchestrator.skipForward(interval)
    }
    
    // Observer management (stays here - UI concern)
    private var observers: [AudioPlayerObserver] = []
    public func addObserver(_ observer: AudioPlayerObserver) { ... }
}
```

**SRP:** ✅ One responsibility = Public API conformance  
**OCP:** ✅ Closed for modification (just delegates)  
**ISP:** ✅ Implements full protocol but delegates to focused components  
**DIP:** ✅ Depends on `PlaybackOrchestrator` protocol

---

### 2️⃣ **PlaybackOrchestrator** (Business Logic)

**New File:** `PlaybackOrchestrator.swift` (~500 lines)  
**Responsibility:** Multi-step flow orchestration  
**Dependencies:** Injected protocols

```swift
protocol PlaybackOrchestrating {
    func startPlaying(fadeDuration: TimeInterval) async throws
    func pause() async throws
    func resume() async throws
    func stop(fadeDuration: TimeInterval) async
    func getCurrentState() async -> PlayerState
}

actor PlaybackOrchestrator: PlaybackOrchestrating {
    // ✅ Protocol dependencies (DIP)
    private let stateStore: PlaybackStateStore
    private let engineControl: AudioEngineControl
    private let sessionManager: AudioSessionManaging
    private let playlistManager: PlaylistManaging
    private let timerManager: TimerManaging
    private let remoteCommands: RemoteCommandManaging
    
    init(
        stateStore: PlaybackStateStore,
        engineControl: AudioEngineControl,
        sessionManager: AudioSessionManaging,
        playlistManager: PlaylistManaging,
        timerManager: TimerManaging,
        remoteCommands: RemoteCommandManaging
    ) {
        self.stateStore = stateStore
        self.engineControl = engineControl
        // ... assign others
    }
    
    // ✅ Orchestrates multi-step flow
    func startPlaying(fadeDuration: TimeInterval) async throws {
        // 1. Get track from playlist
        guard let track = await playlistManager.getCurrentTrack() else {
            throw AudioPlayerError.emptyPlaylist
        }
        
        // 2. Validate & activate session
        try await sessionManager.activate()
        
        // 3. Prepare engine
        try await engineControl.prepare()
        
        // 4. Load file
        let trackInfo = try await engineControl.loadAudioFile(url: track.url)
        
        // 5. Update state BEFORE starting
        await stateStore.setActiveTrack(track, info: trackInfo)
        await stateStore.updateMode(.preparing)
        
        // 6. Start engine with fade
        try await engineControl.start(fadeInDuration: fadeDuration)
        
        // 7. Update state AFTER starting
        await stateStore.updateMode(.playing)
        
        // 8. Start timer
        await timerManager.startPlaybackTimer()
        
        // 9. Update remote commands
        await remoteCommands.updateNowPlaying(track: trackInfo)
    }
    
    func pause() async throws {
        let currentState = await stateStore.getPlaybackMode()
        
        // Validate state
        guard currentState == .playing || currentState == .preparing else {
            if currentState == .paused { return }
            throw AudioPlayerError.invalidState(...)
        }
        
        // Stop timer first
        await timerManager.stopPlaybackTimer()
        
        // Pause engine
        await engineControl.pause()
        
        // Update state
        await stateStore.updateMode(.paused)
        
        // Update UI
        await remoteCommands.updatePlaybackRate(0.0)
    }
    
    func resume() async throws {
        let currentState = await stateStore.getPlaybackMode()
        
        // Validate state
        guard currentState == .paused else {
            if currentState == .playing { return }
            throw AudioPlayerError.invalidState(...)
        }
        
        // Ensure session active
        try await sessionManager.ensureActive()
        
        // Resume engine
        try await engineControl.resume()
        
        // Update state
        await stateStore.updateMode(.playing)
        
        // Restart timer
        await timerManager.startPlaybackTimer()
        
        // Update UI
        await remoteCommands.updatePlaybackRate(1.0)
    }
    
    func stop(fadeDuration: TimeInterval) async {
        // Stop timer
        await timerManager.stopPlaybackTimer()
        
        // Stop engine (with fade if requested)
        if fadeDuration > 0 {
            await engineControl.fadeOut(duration: fadeDuration)
        }
        await engineControl.stop()
        
        // Update state
        await stateStore.updateMode(.finished)
        await stateStore.clearActiveTrack()
        
        // Clear UI
        await remoteCommands.clearNowPlaying()
    }
    
    func getCurrentState() async -> PlayerState {
        await stateStore.getPlaybackMode()
    }
}
```

**SRP:** ✅ One responsibility = Orchestrate playback flows  
**OCP:** ✅ Extend via strategy injection (not modification)  
**DIP:** ✅ All dependencies are protocols

---

### 3️⃣ **PlaybackStateStore** (Pure State)

**File:** Rename `PlaybackStateCoordinator.swift` → `PlaybackStateStore.swift` (~400 lines)  
**Responsibility:** State storage + queries ONLY  
**Dependencies:** NONE (zero dependencies!)

```swift
protocol PlaybackStateStore {
    // Queries
    func getPlaybackMode() async -> PlayerState
    func getActiveTrack() async -> Track?
    func getActiveTrackInfo() async -> TrackInfo?
    func getActivePlayer() async -> PlayerNode
    func captureSnapshot() async -> PlaybackSnapshot
    
    // Mutations
    func updateMode(_ mode: PlayerState) async
    func setActiveTrack(_ track: Track, info: TrackInfo) async
    func clearActiveTrack() async
    func switchActivePlayer() async
    func updateMixerVolumes(_ active: Float, _ inactive: Float) async
}

actor PlaybackStateStoreImpl: PlaybackStateStore {
    // ✅ Pure state - NO engine control!
    private var state: CoordinatorState
    
    init(initialState: CoordinatorState = .idle) {
        self.state = initialState
    }
    
    // ✅ Pure queries
    func getPlaybackMode() async -> PlayerState {
        state.playbackMode
    }
    
    func getActiveTrack() async -> Track? {
        state.activeTrack
    }
    
    // ✅ Pure mutations
    func updateMode(_ mode: PlayerState) async {
        state = state.withMode(mode)
    }
    
    func setActiveTrack(_ track: Track, info: TrackInfo) async {
        state = state
            .withActiveTrack(track)
            .withActiveTrackInfo(info)
    }
    
    func clearActiveTrack() async {
        state = state
            .withActiveTrack(nil)
            .withActiveTrackInfo(nil)
    }
    
    // ✅ Validation happens here
    func switchActivePlayer() async {
        let newPlayer: PlayerNode = state.activePlayer == .a ? .b : .a
        state = state.withActivePlayer(newPlayer)
        
        // Postcondition: state must be consistent
        assert(state.isConsistent, "State inconsistent after player switch")
    }
}
```

**SRP:** ✅ One responsibility = Store & validate state  
**OCP:** ✅ Extend state structure without changing queries  
**DIP:** ✅ Zero dependencies = highest testability

---

### 4️⃣ **AudioEngineControl** (Engine Operations)

**File:** `AudioEngineActor.swift` (refactor interface)  
**Responsibility:** AVFoundation control ONLY  
**Dependencies:** NONE

```swift
protocol AudioEngineControl {
    // Lifecycle
    func prepare() async throws
    func start(fadeInDuration: TimeInterval) async throws
    func stop() async
    
    // Playback control
    func pause() async
    func resume() async throws
    
    // File loading
    func loadAudioFile(url: URL) async throws -> TrackInfo
    
    // Fade operations
    func fadeOut(duration: TimeInterval) async
    func fadeIn(duration: TimeInterval) async
    
    // Position
    func getCurrentPosition() async -> PlaybackPosition?
    func seek(to time: TimeInterval) async throws
    
    // Mixer operations (for crossfade)
    func setActiveMixerVolume(_ volume: Float) async
    func setInactiveMixerVolume(_ volume: Float) async
}

actor AudioEngineActor: AudioEngineControl {
    // ✅ Pure AVFoundation control
    private let engine: AVAudioEngine
    private let playerNodeA: AVAudioPlayerNode
    private let playerNodeB: AVAudioPlayerNode
    private let mixerA: AVAudioMixerNode
    private let mixerB: AVAudioMixerNode
    
    // ✅ NO state management
    // ✅ NO business logic
    // ✅ Just hardware control
}
```

**SRP:** ✅ One responsibility = Control AVFoundation  
**DIP:** ✅ Conforms to protocol (injectable)

---

### 5️⃣ **CrossfadeOrchestrator** (Crossfade Logic)

**New File:** `CrossfadeOrchestrator.swift` (~300 lines)  
**Responsibility:** Crossfade flow orchestration  
**Dependencies:** `StateStore`, `EngineControl`

```swift
protocol CrossfadeOrchestrating {
    func startCrossfade(
        to track: Track,
        operation: CrossfadeOperation
    ) async throws -> AsyncStream<Float>
    
    func pauseCrossfade() async throws -> Bool
    func resumeCrossfade() async throws -> Bool
    func cancelCrossfade() async
}

actor CrossfadeOrchestrator: CrossfadeOrchestrating {
    private let stateStore: PlaybackStateStore
    private let engineControl: AudioEngineControl
    
    private var activeCrossfadeTask: Task<Void, Never>?
    private var pausedCrossfadeState: PausedCrossfadeState?
    
    func startCrossfade(
        to track: Track,
        operation: CrossfadeOperation
    ) async throws -> AsyncStream<Float> {
        // 1. Load track on inactive player
        let trackInfo = try await engineControl.loadAudioFile(url: track.url)
        await stateStore.loadTrackOnInactive(track, trackInfo)
        
        // 2. Create crossfade task
        let (stream, continuation) = AsyncStream<Float>.makeStream()
        
        activeCrossfadeTask = Task {
            await performCrossfade(
                duration: operation.duration,
                curve: operation.curve,
                progress: continuation
            )
        }
        
        return stream
    }
    
    private func performCrossfade(
        duration: TimeInterval,
        curve: FadeCurve,
        progress: AsyncStream<Float>.Continuation
    ) async {
        let steps = Int(duration * 60)  // 60 FPS
        
        for step in 0...steps {
            let t = Float(step) / Float(steps)
            let curvedT = curve.apply(t)
            
            await engineControl.setActiveMixerVolume(1.0 - curvedT)
            await engineControl.setInactiveMixerVolume(curvedT)
            
            progress.yield(curvedT)
            
            try? await Task.sleep(nanoseconds: UInt64(1_000_000_000 / 60))
        }
        
        // Complete crossfade
        await stateStore.switchActivePlayer()
        progress.finish()
    }
}
```

**SRP:** ✅ One responsibility = Crossfade orchestration  
**OCP:** ✅ Extend curves without modifying core logic  
**DIP:** ✅ Depends on protocols

---

### 6️⃣ **Supporting Components**

#### TimerManager
```swift
protocol TimerManaging {
    func startPlaybackTimer() async
    func stopPlaybackTimer() async
}

actor TimerManager: TimerManaging {
    private var playbackTimer: Task<Void, Never>?
    private weak var positionDelegate: PlaybackPositionDelegate?
    
    func startPlaybackTimer() async {
        stopPlaybackTimer()
        playbackTimer = Task {
            while !Task.isCancelled {
                if let position = await positionDelegate?.getCurrentPosition() {
                    await positionDelegate?.didUpdatePosition(position)
                }
                try? await Task.sleep(nanoseconds: 250_000_000)  // 4 Hz
            }
        }
    }
}
```

#### RemoteCommandManager
```swift
protocol RemoteCommandManaging {
    func updateNowPlaying(track: TrackInfo) async
    func updatePlaybackRate(_ rate: Float) async
    func clearNowPlaying() async
}

@MainActor
class RemoteCommandManager: RemoteCommandManaging {
    func updateNowPlaying(track: TrackInfo) async {
        var nowPlayingInfo = [String: Any]()
        nowPlayingInfo[MPMediaItemPropertyTitle] = track.title
        // ...
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }
}
```

---

## 📊 Responsibility Matrix

| Component | Lines | Responsibilities | Dependencies |
|-----------|-------|------------------|--------------|
| **AudioPlayerService** | ~300 | API facade (1) | Orchestrator |
| **PlaybackOrchestrator** | ~500 | Business flows (1) | 6 protocols |
| **PlaybackStateStore** | ~400 | State storage (1) | None |
| **AudioEngineControl** | ~800 | AVFoundation (1) | None |
| **CrossfadeOrchestrator** | ~300 | Crossfade logic (1) | 2 protocols |
| **TimerManager** | ~100 | Timer management (1) | None |
| **RemoteCommandManager** | ~200 | Now playing UI (1) | None |

**Total:** ~2600 lines (vs current ~3600 lines)  
**Components:** 7 focused components (vs current 3 bloated)  
**SRP Compliance:** 100% (each has ONE responsibility)

---

## 🔄 Migration Strategy

### Phase 1: Extract Protocols (1-2 hours)
```swift
// Create protocol files
- AudioEngineControl.swift
- PlaybackStateStore.swift
- PlaybackOrchestrating.swift
```

### Phase 2: Create PlaybackOrchestrator (2-3 hours)
```swift
// Move orchestration logic from Service
- startPlaying() logic
- pause() logic
- resume() logic
- stop() logic
```

### Phase 3: Refactor PlaybackStateCoordinator (1-2 hours)
```swift
// Remove engine control, keep only state
- Delete pausePlayback() engine calls
- Delete resumePlayback() engine calls
- Delete stopPlayback() engine calls
- Keep only state mutations
```

### Phase 4: Simplify AudioPlayerService (1 hour)
```swift
// Make thin facade
- Replace 74-line startPlaying with 3-line delegation
- Replace logic with orchestrator calls
```

### Phase 5: Extract CrossfadeOrchestrator (2-3 hours)
```swift
// Move crossfade logic from StateCoordinator
- startCrossfade()
- pauseCrossfade()
- resumeCrossfade()
```

**Total Estimated Time:** 8-12 hours

---

## ✅ SOLID Compliance Checklist

### Single Responsibility
- [x] Service = API facade only
- [x] Orchestrator = business flows only
- [x] StateStore = state storage only
- [x] EngineControl = hardware only
- [x] CrossfadeOrchestrator = crossfade only

### Open/Closed
- [x] Service closed (just delegates)
- [x] Orchestrator extensible via strategy injection
- [x] StateStore extensible via state structure changes

### Liskov Substitution
- [x] No inheritance hierarchies (actor-based)

### Interface Segregation
- [x] PlaybackOrchestrating (4 methods)
- [x] PlaybackStateStore (8 methods)
- [x] AudioEngineControl (10 methods)
- [x] CrossfadeOrchestrating (4 methods)

### Dependency Inversion
- [x] All dependencies are protocols
- [x] Zero concrete dependencies
- [x] Constructor injection everywhere

---

## 🎯 Benefits

### Testability
```swift
// Before: Cannot test Service without entire stack
let service = AudioPlayerService(...)  // Requires 6 real objects

// After: Mock any protocol
let mockStore = MockPlaybackStateStore()
let mockEngine = MockAudioEngineControl()
let orchestrator = PlaybackOrchestrator(
    stateStore: mockStore,
    engineControl: mockEngine,
    ...
)
```

### Maintainability
- Bug in pause? Check `PlaybackOrchestrator.pause()` (~20 lines)
- Bug in state? Check `PlaybackStateStore` (zero dependencies)
- Bug in engine? Check `AudioEngineControl` (no business logic)

### Extensibility
```swift
// Add "fade on pause" without modifying existing code
class FadeOnPauseOrchestrator: PlaybackOrchestrating {
    private let baseOrchestrator: PlaybackOrchestrating
    
    func pause() async throws {
        await engineControl.fadeOut(duration: 0.3)
        try await baseOrchestrator.pause()
    }
}
```

---

## 📝 Next Steps

1. **Review this design** with user
2. **Create detailed refactoring plan** with concrete line changes
3. **Implement Phase 1** (extract protocols)
4. **Test after each phase** (ensure behavior unchanged)
5. **Document migration** for future reference

**Question for user:** Does this architecture separation make sense? Should we proceed with Phase 1?
