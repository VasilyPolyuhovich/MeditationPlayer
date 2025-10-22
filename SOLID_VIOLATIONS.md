# SOLID Violations Analysis

**Date:** 2025-10-22  
**Branch:** feature/playback-state-coordinator  
**Goal:** Identify concrete SOLID principle violations with line numbers

---

## 1️⃣ Single Responsibility Principle (SRP)

> "A class should have one, and only one, reason to change"

### ❌ Violation #1: AudioPlayerService has 7+ responsibilities

**File:** `AudioPlayerService.swift` (2363 lines)  
**Lines:** Entire class

**Current Responsibilities:**
1. **Public API facade** (lines 227-520)
2. **Playback orchestration** (lines 227-300, 302-369)
3. **State management** (lines 31-35, 324-326, 365, 461)
4. **Timer management** (lines 54, 299, 2169, 2188)
5. **Session management** (via sessionManager, lines 252-259)
6. **Remote command handling** (via remoteCommandManager, lines 48-50)
7. **Playlist coordination** (lines 229-232, 242)
8. **Crossfade orchestration** (lines 319, 354, 384-392)
9. **Sound effects** (lines 79-80)
10. **Now playing info** (lines 292, 328, 368)

**Evidence:**
```swift
// Line 227-300: 74 lines orchestrating startPlaying
// Mixes: validation, session, engine, coordinator, state, timer, UI
public func startPlaying(fadeDuration: TimeInterval = 0.0) async throws {
    guard let track = await playlistManager.getCurrentTrack() else { ... }  // Playlist
    try configuration.validate()                                             // Validation
    await syncConfigurationToPlaylistManager()                               // Playlist sync
    try await sessionManager.activate()                                      // Session
    try await audioEngine.prepare()                                          // Engine
    let trackInfo = try await audioEngine.loadAudioFile(url: url)           // Engine
    await playbackStateCoordinator.atomicSwitch(...)                        // Coordinator
    await updateState(.preparing)                                            // State
    await updateNowPlayingInfo()                                             // Remote commands
    try await startEngine()                                                  // Engine
    await updateState(.playing)                                              // State
    startPlaybackTimer()                                                     // Timer
}
```

**Impact:** Any change to orchestration logic, state management, or UI updates requires modifying this monolithic class.

---

### ❌ Violation #2: PlaybackStateCoordinator mixes state + engine control

**File:** `PlaybackStateCoordinator.swift`  
**Lines:** 729-781

**Current Responsibilities:**
1. **State storage** (lines 50-160: CoordinatorState struct)
2. **State queries** (lines 400-600+)
3. **State mutations** (lines 200-350)
4. **Engine control** (lines 742, 755, 764, 774-778)
5. **Crossfade orchestration** (lines 500-700+)

**Evidence:**
```swift
// Line 729-748: Mixes state validation with engine control
func startPlayback() async throws -> Bool {
    guard state.activeTrack != nil else { throw error }  // State query
    
    await audioEngine.play()  // ❌ Direct engine control
    updateMode(.playing)      // State mutation
    
    return true
}

// Line 752-758: Engine control without state update
func pausePlayback() async {
    await audioEngine.pause()  // ❌ Engine control
    // Missing: updateMode(.paused)
}
```

**Impact:** State coordinator directly depends on audio engine, violating separation of concerns.

---

## 2️⃣ Open/Closed Principle (OCP)

> "Software entities should be open for extension, but closed for modification"

### ❌ Violation #3: Cannot extend playback behavior without modifying Service

**File:** `AudioPlayerService.swift`  
**Lines:** 227-300 (startPlaying), 302-329 (pause), 331-369 (resume)

**Problem:** All orchestration logic is hardcoded in Service methods.

**Example:** Adding "fade-out on pause" feature requires:
1. Modifying `pause()` method (line 302)
2. Adding new helper method
3. Risk breaking existing pause behavior

**Better Design:** Strategy pattern
```swift
protocol PlaybackStrategy {
    func start() async throws
    func pause() async throws
    func resume() async throws
}

class StandardPlayback: PlaybackStrategy { ... }
class FadeOnPausePlayback: PlaybackStrategy { ... }
```

---

## 3️⃣ Liskov Substitution Principle (LSP)

> "Derived classes must be substitutable for their base classes"

### ✅ No violations found

All concrete types (Service, Coordinator, Engine) don't have inheritance hierarchies.  
Protocol conformance (AudioPlayerProtocol) is properly implemented.

---

## 4️⃣ Interface Segregation Principle (ISP)

> "Clients should not be forced to depend on interfaces they don't use"

### ❌ Violation #4: AudioPlayerService exposes ALL operations in one protocol

**File:** `AudioPlayerProtocol.swift` (AudioServiceCore)  
**File:** `AudioPlayerService.swift` (implements protocol)

**Problem:** Single fat interface combines:
- Basic playback: play, pause, resume, stop
- Advanced playback: finish, fade
- Playlist: skip, shuffle, repeat
- Sound effects: playSound
- Overlay: playOverlay, stopOverlay
- Configuration: updateConfiguration
- Observers: addObserver, removeObserver

**Impact:** 
- Test doubles must implement 20+ methods even if testing only pause/resume
- Cannot inject minimal interface for simple use cases

**Evidence:**
```swift
// Demo app only needs:
service.startPlaying()
service.pause()
service.resume()
service.stop()

// But gets access to:
service.playOverlay()
service.playSound()
service.updateConfiguration()
service.finishCurrentTrack()
// ... 15 more methods
```

**Better Design:** Multiple focused protocols
```swift
protocol BasicPlayback { play, pause, resume, stop }
protocol PlaylistControl { skip, shuffle, repeat }
protocol OverlayControl { playOverlay, stopOverlay }
protocol SoundEffects { playSound, stopSound }
```

---

### ❌ Violation #5: PlaybackStateCoordinator exposes 33 methods

**File:** `PlaybackStateCoordinator.swift`

**Methods grouped by client:**
- **Service needs (10):** atomicSwitch, updateMode, startPlayback, pausePlayback, resumePlayback, stopPlayback, pauseCrossfade, resumeCrossfade, cancelActiveCrossfade, clearPausedCrossfade
- **Crossfade needs (8):** startCrossfade, rollbackCurrentCrossfade, loadTrackOnInactive, switchActivePlayer, updateMixerVolumes, updateCrossfading
- **Queries (10):** getCurrentTrack, getPlaybackMode, getActivePlayer, hasActiveCrossfade, etc.
- **Debug (5):** captureSnapshot, restoreSnapshot, logCurrentState

**Problem:** Every client sees ALL 33 methods.

**Better Design:**
```swift
protocol PlaybackStateStore {
    func getState() -> CoordinatorState
    func updateMode(PlayerState)
}

protocol CrossfadeController {
    func startCrossfade(...) -> AsyncStream<Float>
    func pauseCrossfade() throws
}
```

---

## 5️⃣ Dependency Inversion Principle (DIP)

> "Depend on abstractions, not concretions"

### ❌ Violation #6: PlaybackStateCoordinator depends on concrete AudioEngineActor

**File:** `PlaybackStateCoordinator.swift`  
**Lines:** 45, 742, 755, 764, 774-778

**Evidence:**
```swift
// Line 45: Concrete dependency
private let audioEngine: AudioEngineActor  // ❌ Not a protocol

// Line 742: Direct concrete call
await audioEngine.play()  // ❌ Tightly coupled

// Line 755:
await audioEngine.pause()  // ❌ Tightly coupled
```

**Impact:**
- Cannot test Coordinator without real AudioEngineActor
- Cannot substitute different engine implementations
- Coordinator knows about AVFoundation details (indirectly)

**Better Design:**
```swift
protocol AudioEngine {
    func play() async
    func pause() async
    func stop() async
}

actor PlaybackStateCoordinator {
    private let audioEngine: AudioEngine  // ✅ Protocol
}
```

---

### ❌ Violation #7: AudioPlayerService depends on concrete managers

**File:** `AudioPlayerService.swift`  
**Lines:** 46-50

**Evidence:**
```swift
internal let audioEngine: AudioEngineActor           // ❌ Concrete
private let playbackStateCoordinator: PlaybackStateCoordinator  // ❌ Concrete
internal let sessionManager: AudioSessionManager     // ❌ Concrete
private var remoteCommandManager: RemoteCommandManager!  // ❌ Concrete
```

**Impact:**
- Cannot unit test Service in isolation
- Must bring up entire dependency tree
- Integration tests, not unit tests

**Better Design:**
```swift
internal let audioEngine: AudioEngineProtocol
private let stateManager: PlaybackStateManager
internal let sessionManager: SessionManagerProtocol
private var remoteCommands: RemoteCommandProtocol
```

---

## 📊 Summary of Violations

| Principle | Violations | Severity | Impact |
|-----------|-----------|----------|---------|
| **SRP** | 2 | 🔴 Critical | AudioPlayerService (10 responsibilities), Coordinator (5 responsibilities) |
| **OCP** | 1 | 🟡 Medium | Cannot extend behavior without modification |
| **LSP** | 0 | ✅ None | No inheritance hierarchies |
| **ISP** | 2 | 🟠 High | Fat interfaces force unnecessary dependencies |
| **DIP** | 2 | 🔴 Critical | Concrete dependencies prevent testing |

**Total:** 7 violations across 4 principles

---

## 🎯 Root Causes

### 1. God Class Pattern
- **AudioPlayerService:** 2363 lines, 10+ responsibilities
- Should be split into: Facade, Orchestrator, StateManager, UIAdapter

### 2. Leaky Abstraction
- **PlaybackStateCoordinator:** Claims to be "state" but controls engine
- Should be: Pure state storage + queries

### 3. Missing Abstractions
- All dependencies are concrete classes, not protocols
- Prevents testing, substitution, extension

### 4. Confusion of Concerns
- State management split between Service and Coordinator
- Engine control split between Coordinator and Service
- No clear boundary: who owns what?

---

## Next Steps

See `ARCHITECTURE_TARGET.md` for SOLID-compliant design proposal.
