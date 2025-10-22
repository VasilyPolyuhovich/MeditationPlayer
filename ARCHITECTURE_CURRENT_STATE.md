# ARCHITECTURE ANALYSIS: Current State

**Date:** 2025-10-22  
**Branch:** feature/playback-state-coordinator  
**Goal:** Document WHAT EXISTS NOW (methods, responsibilities, call flows)

---

## 🏗️ Component Structure

### 1️⃣ **PlaybackStateCoordinator** (799 lines)
**File:** `Sources/AudioServiceKit/Internal/PlaybackStateCoordinator.swift`

**Purpose:** Single Source of Truth (SSOT) for playback state

#### State Management
```swift
struct CoordinatorState {
    let activePlayer: PlayerNode           // .a or .b
    let playbackMode: PlayerState          // .playing, .paused, .finished, etc.
    let activeTrack: Track?
    let activeTrackInfo: TrackInfo?
    let inactiveTrack: Track?
    let inactiveTrackInfo: TrackInfo?
    let activeMixerVolume: Float
    let inactiveMixerVolume: Float
    let isCrossfading: Bool
    
    var isConsistent: Bool { /* validation logic */ }
}
```

#### Public API (33 methods)

**State Mutations (6):**
- `switchActivePlayer()` - Swap A↔B
- `updateMode(PlayerState)` - Change playback mode
- `loadTrackOnInactive(Track, TrackInfo)` - Prepare next track
- `updateMixerVolumes(Float, Float)` - Set volumes
- `updateCrossfading(Bool)` - Set crossfade flag
- `atomicSwitch(Track, TrackInfo)` - Load track + set as active

**State Queries (10):**
- `getCurrentTrack() -> Track?`
- `getPlaybackMode() -> PlayerState`
- `getActivePlayer() -> PlayerNode`
- `getActiveTrackInfo() -> TrackInfo?`
- `isCrossfading() -> Bool`
- `hasActiveCrossfade() -> Bool`
- `hasPausedCrossfade() -> Bool`
- `captureSnapshot() -> CoordinatorState`
- etc.

**Crossfade Operations (5):**
- `startCrossfade(Track, TrackInfo, CrossfadeOperation) -> AsyncStream<Float>`
- `rollbackCurrentCrossfade(TimeInterval) -> Bool`
- `pauseCrossfade() throws -> Bool`
- `resumeCrossfade() throws -> Bool`
- `cancelActiveCrossfade()`

**❌ Playback Control (4) - INCOMPLETE:**
```swift
// Line 729-748
func startPlayback() async throws -> Bool {
    guard state.activeTrack != nil else { throw error }
    
    await audioEngine.play()  // ✅ Calls engine
    updateMode(.playing)      // ✅ Updates state
    
    return true
}

// Line 752-758
func pausePlayback() async {
    await audioEngine.pause()  // ✅ Calls engine
    // ❌ Does NOT update state
    // ❌ Does NOT handle crossfade
}

// Line 761-767
func resumePlayback() async {
    await audioEngine.play()  // ✅ Calls engine
    // ❌ Does NOT update state
    // ❌ Does NOT handle crossfade
}

// Line 770-781
func stopPlayback() async {
    await audioEngine.stopActivePlayer()
    await audioEngine.stopInactivePlayer()
    await audioEngine.resetInactiveMixer()
    // ❌ Does NOT update state
}
```

**🔴 CRITICAL FINDING:**
- `pausePlayback()`, `resumePlayback()`, `stopPlayback()` do NOT update Coordinator state
- They only call AudioEngineActor methods
- This breaks SSOT principle - state changes happen elsewhere

---

### 2️⃣ **AudioPlayerService** (2363 lines)
**File:** `Sources/AudioServiceKit/Public/AudioPlayerService.swift`

**Purpose:** Public API facade + orchestration logic

#### Properties
```swift
// Cached state (sync protocol conformance)
private var _cachedState: PlayerState = .finished
private var _cachedTrackInfo: TrackInfo? = nil

// Components
internal let audioEngine: AudioEngineActor
private let playbackStateCoordinator: PlaybackStateCoordinator
internal let sessionManager: AudioSessionManager
private var remoteCommandManager: RemoteCommandManager!
```

#### Public API Methods

**startPlaying(fadeDuration)** - Lines 227-300
```swift
// ✅ COMPLETE orchestration:
1. Get track from playlistManager
2. Validate configuration
3. Activate audio session
4. Prepare audio engine
5. Load audio file
6. atomicSwitch() on coordinator  // ✅ State update
7. updateState(.preparing)         // ✅ State update
8. updateNowPlayingInfo()
9. startEngine()                   // → calls coordinator.startPlayback()
10. updateState(.playing)          // ✅ State update
11. startPlaybackTimer()
```

**pause()** - Lines 302-329
```swift
// ✅ COMPLETE with crossfade handling:
1. Guard state validation
2. pauseCrossfade() on coordinator  // ✅ Crossfade handling
3. pausePlayback() (internal)       // → calls coordinator.pausePlayback()
4. updateMode(.paused) on coordinator  // ✅ State update
5. updateNowPlayingPlaybackRate(0.0)
```

**resume()** - Lines 331-369
```swift
// ✅ COMPLETE with crossfade handling:
1. Guard state validation
2. resumeCrossfade() on coordinator    // ✅ Crossfade handling
3. If no crossfade: resumePlayback()   // → calls coordinator.resumePlayback()
4. updateMode(.playing) on coordinator // ✅ State update
5. updateNowPlayingPlaybackRate(1.0)
```

**stop(fadeDuration)** - Lines 375-437
```swift
// ✅ COMPLETE with fade support:
1. clearPausedCrossfade() on coordinator
2. If crossfading: cancelActiveCrossfade()
3. If fadeDuration > 0: stopWithFade()
4. Else: stopImmediately()

stopImmediately():
- stopPlaybackTimer()
- audioEngine.stopBothPlayers()
- Reset local state
- updateState(.finished)  // ✅ State update via Service
```

#### Internal Helper Methods

**startEngine()** - Lines 2137-2158
```swift
1. audioEngine.start()
2. audioEngine.scheduleFile(fadeIn, fadeDuration)
3. playbackStateCoordinator.startPlayback()  // ✅ Calls coordinator
4. Clear pendingFadeInDuration
```

**pausePlayback()** - Lines 2165-2176
```swift
1. stopPlaybackTimer()
2. playbackStateCoordinator.pausePlayback()  // ✅ Calls coordinator
3. Capture playbackPosition
```

**resumePlayback()** - Lines 2178-2189
```swift
1. ensureSessionActive()
2. playbackStateCoordinator.resumePlayback()  // ✅ Calls coordinator
3. startPlaybackTimer()
```

**🟡 FINDING:**
- Service DOES update coordinator state via `updateMode()` calls
- Service acts as orchestrator, coordinator acts as state holder
- **BUT:** Coordinator's playback methods (pause/resume/stop) don't update their own state
- This creates confusion: who owns state updates?

---

### 3️⃣ **AudioEngineActor** (1442 lines)
**File:** `Sources/AudioServiceKit/Internal/AudioEngineActor.swift`

**Purpose:** AVFoundation audio engine wrapper (dual-player + mixers)

#### Low-Level Playback Control

**prepare()** - Line 145-155
```swift
// Validate nodes attached
engine.prepare()
```

**start()** - Line 157-162
```swift
guard !isEngineRunning else { return }
try engine.start()
isEngineRunning = true
```

**stop()** - Line 164-171
```swift
guard isEngineRunning else { return }
playerNodeA.stop()
playerNodeB.stop()
engine.stop()
isEngineRunning = false
```

**pause()** - Line 179-196
```swift
// 1. Capture current position to offset
if let current = getCurrentPosition() {
    let frame = AVAudioFramePosition(current.currentTime * sampleRate)
    if activePlayer == .a {
        playbackOffsetA = frame
    } else {
        playbackOffsetB = frame
    }
}

// 2. Pause BOTH players (safe during crossfade)
playerNodeA.pause()
playerNodeB.pause()
```

**play()** - Line 198-220+
```swift
let player = getActivePlayerNode()
guard let file = getActiveAudioFile() else { return }

let offset = activePlayer == .a ? playbackOffsetA : playbackOffsetB

// Validate offset < file.length
guard offset < file.length else { return }

// Check if needs reschedule after pause
let needsReschedule = !player.isPlaying && offset > 0

if needsReschedule {
    // Stop, reschedule from offset, play
}
```

**✅ FINDING:**
- AudioEngineActor is pure hardware control
- No state management, no business logic
- Just AVAudioEngine operations

---

## 📊 Call Flow Analysis

### Flow 1: startPlaying()
```
User
  ↓ startPlaying(fadeDuration)
Service.startPlaying()
  ↓ orchestrates 10 steps:
  ├─ playlistManager.getCurrentTrack()
  ├─ sessionManager.activate()
  ├─ audioEngine.prepare()
  ├─ audioEngine.loadAudioFile()
  ├─ coordinator.atomicSwitch()          ← State update
  ├─ Service.updateState(.preparing)     ← State update
  ├─ Service.startEngine()
  │   ├─ audioEngine.start()
  │   ├─ audioEngine.scheduleFile()
  │   └─ coordinator.startPlayback()     ← Calls engine.play()
  ├─ Service.updateState(.playing)       ← State update
  └─ Service.startPlaybackTimer()
```

**✅ State updates:** Service owns orchestration + state updates

---

### Flow 2: pause()
```
User
  ↓ pause()
Service.pause()
  ├─ coordinator.pauseCrossfade()        ← Crossfade logic
  ├─ Service.pausePlayback()
  │   ├─ stopPlaybackTimer()
  │   └─ coordinator.pausePlayback()     ← Just calls engine.pause()
  │       └─ engine.pause()
  └─ coordinator.updateMode(.paused)     ← State update
```

**🟡 Issue:** State update happens in Service, not in coordinator.pausePlayback()

---

### Flow 3: resume()
```
User
  ↓ resume()
Service.resume()
  ├─ coordinator.resumeCrossfade()       ← Crossfade logic
  ├─ Service.resumePlayback()
  │   ├─ ensureSessionActive()
  │   └─ coordinator.resumePlayback()    ← Just calls engine.play()
  │       └─ engine.play()
  └─ coordinator.updateMode(.playing)    ← State update
```

**🟡 Issue:** State update happens in Service, not in coordinator.resumePlayback()

---

### Flow 4: stop()
```
User
  ↓ stop(fadeDuration)
Service.stop()
  ├─ coordinator.clearPausedCrossfade()
  ├─ coordinator.cancelActiveCrossfade()
  └─ Service.stopImmediately()
      ├─ stopPlaybackTimer()
      ├─ engine.stopBothPlayers()
      └─ Service.updateState(.finished)  ← State update
```

**🔴 Issue:** coordinator.stopPlayback() exists but NOT used! Service calls engine directly.

---

## 🎯 Summary: What EXISTS

### Responsibilities Distribution

| Component | Current Responsibility |
|-----------|------------------------|
| **Coordinator** | • SSOT for state storage<br>• Crossfade orchestration ✅<br>• State queries ✅<br>• playback methods ❌ (incomplete) |
| **Service** | • Public API facade ✅<br>• Orchestration logic ✅<br>• State updates ✅<br>• Timer management ✅<br>• Session management ✅<br>• Remote commands ✅ |
| **Engine** | • AVFoundation control ✅<br>• Mixer operations ✅<br>• File loading ✅ |

### Critical Issues Found

1. **Coordinator.pausePlayback() incomplete:**
   - Line 752-758: Only calls `engine.pause()`
   - Does NOT call `updateMode(.paused)`
   - State update happens in Service instead

2. **Coordinator.resumePlayback() incomplete:**
   - Line 761-767: Only calls `engine.play()`
   - Does NOT call `updateMode(.playing)`
   - State update happens in Service instead

3. **Coordinator.stopPlayback() unused:**
   - Line 770-781: Implementation exists
   - But Service.stop() never calls it
   - Service calls `engine.stopBothPlayers()` directly

4. **Inconsistent pattern:**
   - `startPlayback()` DOES update state (line 745)
   - `pause/resume/stop` do NOT update state
   - This breaks SSOT principle

---

## 🚨 Root Cause

**Original assumption (from Phase 2.4+2.5 plan):**
> "Move playback orchestration to Coordinator"

**Reality:**
- Only STATE STORAGE moved to Coordinator
- ORCHESTRATION still in Service
- Coordinator's playback methods are **INCOMPLETE WRAPPERS**
- They just forward to Engine without state management

**Result:** Split responsibility pattern
- Service: orchestrates + updates coordinator state
- Coordinator: stores state + provides queries
- Coordinator playback methods: useless middlemen

---

## Next Steps

See `ARCHITECTURE_TARGET.md` for SOLID-compliant design.
