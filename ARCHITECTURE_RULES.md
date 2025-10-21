# ProsperPlayer - Architecture Rules

**Created:** 2025-10-21  
**Purpose:** Prevent architectural mistakes and ensure consistency

---

## 🎯 Core Principles

### 1. Single Source of Truth (SSOT)

**Rule:** Each piece of state has EXACTLY ONE authoritative source.

**Violations:**
```swift
❌ BAD - Duplicate state tracking
class AudioPlayerService {
    var currentTrack: Track?           // ❌ Duplicate
    var state: PlaybackState           // ❌ Duplicate
}
class AudioEngineActor {
    var currentFile: AVAudioFile?      // ❌ Same info as currentTrack
    var isPlaying: Bool                // ❌ Same info as state
}
```

**Correct:**
```swift
✅ GOOD - Single source
actor PlaybackStateCoordinator {
    private(set) var state: PlayerState  // ✅ ONLY place for this state
}

class AudioPlayerService {
    private let coordinator: PlaybackStateCoordinator
    
    func getCurrentTrack() async -> Track? {
        return await coordinator.state.activeTrack  // ✅ Query SSOT
    }
}
```

---

### 2. Atomic Operations

**Rule:** State changes are all-or-nothing. No partial updates.

**Violations:**
```swift
❌ BAD - Multiple suspend points, state can become inconsistent
func switchTrack() async {
    await audioEngine.switchActivePlayer()     // ⚠️ suspend point
    // ❌ If crash here, state is inconsistent!
    currentTrack = newTrack
    state = .playing
}
```

**Correct:**
```swift
✅ GOOD - Atomic operation via coordinator
func switchTrack() async {
    await coordinator.atomicSwitch(
        newTrack: track,
        mode: .playing
    )
    // ✅ State is consistent or unchanged
}

actor PlaybackStateCoordinator {
    func atomicSwitch(newTrack: Track, mode: PlaybackMode) {
        // No suspend points - atomic!
        var newState = state
        newState.activePlayer = newState.activePlayer.opposite
        newState.activeTrack = newTrack
        newState.playbackMode = mode
        
        // Validate before committing
        guard newState.isConsistent else {
            Logger.error("Invalid state transition")
            return
        }
        
        // Commit atomically
        state = newState
    }
}
```

---

### 3. Immutable State Snapshots

**Rule:** Never mutate state directly. Use copy-on-write snapshots.

**Violations:**
```swift
❌ BAD - Direct mutation
coordinator.state.activeTrack = newTrack  // ❌ Not allowed
coordinator.state.playbackMode = .paused  // ❌ Not allowed
```

**Correct:**
```swift
✅ GOOD - Immutable snapshots
struct PlayerState {
    let activePlayer: PlayerNode
    let playbackMode: PlaybackMode
    let activeTrack: Track?
    
    // Functional updates
    func withTrack(_ track: Track) -> PlayerState {
        return PlayerState(
            activePlayer: activePlayer,
            playbackMode: playbackMode,
            activeTrack: track
        )
    }
}

actor PlaybackStateCoordinator {
    private(set) var state: PlayerState
    
    func updateTrack(_ track: Track) {
        state = state.withTrack(track)  // ✅ New instance
    }
}
```

---

### 4. State Validation

**Rule:** Every state change must validate consistency.

**Required Validations:**
```swift
struct PlayerState {
    var isConsistent: Bool {
        // 1. Active player must have a track
        guard activeTrack != nil else {
            Logger.error("Active player has no track")
            return false
        }
        
        // 2. Playing mode requires active track
        if playbackMode == .playing && activeTrack == nil {
            Logger.error("Playing mode but no track")
            return false
        }
        
        // 3. Mixer volumes in valid range
        guard (0.0...1.0).contains(activeMixerVolume) else {
            Logger.error("Invalid mixer volume: \(activeMixerVolume)")
            return false
        }
        
        // 4. Inactive mixer should be 0 when not crossfading
        if !isCrossfading && inactiveMixerVolume != 0.0 {
            Logger.warning("Inactive mixer should be 0")
            return false
        }
        
        return true
    }
}
```

---

### 5. Coordinator Boundaries

**Rule:** Each coordinator has clear responsibilities. No overlap.

**Component Responsibilities:**

| Component | Owns | Does NOT Own |
|-----------|------|--------------|
| **PlaybackStateCoordinator** | Active player, track info, playback mode, mixer volumes | Crossfade progress, fade tasks |
| **CrossfadeCoordinator** | Crossfade lifecycle, progress, pause/resume | Which player is active, track info |
| **AudioEngineActor** | AVFoundation operations, buffer scheduling | Decision-making about tracks/state |
| **AudioPlayerService** | Public API, playlist management, UI observers | Internal state, crossfade logic |

**Communication Flow:**
```
AudioPlayerService (decides WHAT to do)
    ↓
PlaybackStateCoordinator (updates truth)
    ↓
CrossfadeCoordinator (HOW to crossfade)
    ↓
AudioEngineActor (executes on AVFoundation)
```

**Violations:**
```swift
❌ BAD - CrossfadeCoordinator modifying player state
class CrossfadeCoordinator {
    func execute() {
        audioEngine.activePlayer = .b  // ❌ Not your responsibility!
    }
}

❌ BAD - AudioEngineActor making decisions
actor AudioEngineActor {
    func play() {
        if currentTrack.shouldCrossfade {  // ❌ Not your decision!
            startCrossfade()
        }
    }
}
```

**Correct:**
```swift
✅ GOOD - Coordinator asks permission, doesn't assume
class CrossfadeCoordinator {
    func execute() async {
        // Ask state coordinator to switch
        await playbackState.switchActivePlayer()  // ✅ Correct authority
    }
}

✅ GOOD - Engine executes, doesn't decide
actor AudioEngineActor {
    func play() {
        // Just execute the command
        player.play()  // ✅ Simple execution
    }
}
```

---

### 6. Test-Driven Development

**Rule:** Write tests BEFORE implementation for critical paths.

**Test Template:**
```swift
@Test("PlaybackStateCoordinator - Switch active player")
func testSwitchActivePlayer() async {
    // Given
    let coordinator = PlaybackStateCoordinator()
    let initialPlayer = await coordinator.state.activePlayer
    
    // When
    await coordinator.switchActivePlayer()
    
    // Then
    let finalPlayer = await coordinator.state.activePlayer
    #expect(finalPlayer == initialPlayer.opposite)
    #expect(await coordinator.state.isConsistent)
}
```

**Required Test Coverage:**
- ✅ All atomic operations
- ✅ State validation rules
- ✅ Error cases
- ✅ Race condition scenarios

---

### 7. No Band-Aid Fixes

**Rule:** If you find yourself adding `if` checks for edge cases, refactor instead.

**Warning Signs:**
```swift
❌ BAD - Band-aid fix
func resume() async {
    if pausedCrossfadeState != nil {  // ⚠️ Band-aid
        // Special case #1
    } else if activeCrossfadeOperation != nil {  // ⚠️ Band-aid
        // Special case #2
    } else {
        // Normal case
    }
}
```

**Refactored:**
```swift
✅ GOOD - Architectural solution
func resume() async {
    let snapshot = await crossfadeCoordinator.getPausedSnapshot()
    
    if let snapshot = snapshot {
        // Coordinator handles ALL crossfade complexity
        await crossfadeCoordinator.resume(from: snapshot)
    } else {
        // Simple case
        await playbackState.updateMode(.playing)
    }
}
```

---

## 🚨 Code Review Checklist

Before committing code, verify:

- [ ] State has single source (no duplicates)
- [ ] Operations are atomic (no partial updates)
- [ ] State validation passes
- [ ] Responsibilities are clear (correct coordinator)
- [ ] Tests written and passing
- [ ] No band-aid fixes (architectural solution)

---

## 📊 Architecture Diagram

```
┌─────────────────────────────────────────────────────────┐
│          AudioPlayerService (Facade)                    │
│  - Public API (play, pause, skip, etc.)                │
│  - Playlist management                                  │
│  - UI observers                                         │
│  - Decision: "User wants to skip track"                │
└──────────────┬──────────────────────────────────────────┘
               │ Query state ↓
               │ Issue commands ↓
               │
    ┌──────────┴──────────┐
    │                     │
┌───▼────────────────┐ ┌─▼─────────────────────┐
│ PlaybackState      │ │ CrossfadeCoordinator  │
│  Coordinator       │ │                       │
│                    │ │ - Lifecycle mgmt      │
│ OWNS:              │ │ - Progress tracking   │
│ - Active player    │ │ - Pause/Resume        │
│ - Playback mode    │ │ - Strategy selection  │
│ - Track info       │ │                       │
│ - Mixer volumes    │ │ OWNS:                 │
│                    │ │ - Crossfade state     │
│ STATE AUTHORITY    │ │ - Fade progress       │
│ (Single Truth)     │ │ - Paused snapshots    │
└───┬────────────────┘ └─┬─────────────────────┘
    │                    │
    │ Execute ↓          │ Execute ↓
    │                    │
    └────────┬───────────┘
             │
    ┌────────▼─────────┐
    │ AudioEngineActor │
    │                  │
    │ - AVFoundation   │
    │ - Buffer mgmt    │
    │ - Mixer control  │
    │                  │
    │ NO DECISIONS     │
    │ (Pure execution) │
    └──────────────────┘
```

---

## 🔄 Migration Strategy

### Phase 1: Create Coordinator ✅
- Implement PlaybackStateCoordinator
- Write comprehensive tests
- Do NOT integrate yet

### Phase 2: Parallel Run 🔄
- AudioPlayerService uses BOTH old state AND coordinator
- Compare values in debug mode
- Fix discrepancies

### Phase 3: Switchover
- Route all reads through coordinator
- Keep old state for validation

### Phase 4: Cleanup
- Remove old state variables
- Remove validation code

**Never skip phases!** Each phase is a safety checkpoint.

---

## 📝 Example: Correct Implementation

```swift
// ============================================
// PlaybackStateCoordinator.swift
// ============================================

actor PlaybackStateCoordinator {
    // MARK: - State Definition
    
    struct PlayerState {
        let activePlayer: PlayerNode
        let playbackMode: PlaybackMode
        let activeTrack: Track?
        let inactiveTrack: Track?
        let activeMixerVolume: Float
        let inactiveMixerVolume: Float
        let isCrossfading: Bool
        
        var isConsistent: Bool {
            // Validation logic
            guard activeTrack != nil else { return false }
            guard (0.0...1.0).contains(activeMixerVolume) else { return false }
            return true
        }
        
        // Functional updates
        func withMode(_ mode: PlaybackMode) -> PlayerState {
            PlayerState(
                activePlayer: activePlayer,
                playbackMode: mode,
                activeTrack: activeTrack,
                inactiveTrack: inactiveTrack,
                activeMixerVolume: activeMixerVolume,
                inactiveMixerVolume: inactiveMixerVolume,
                isCrossfading: isCrossfading
            )
        }
    }
    
    // MARK: - State (SINGLE SOURCE OF TRUTH)
    
    private(set) var state: PlayerState
    
    // MARK: - Dependencies
    
    private let audioEngine: AudioEngineActor
    
    // MARK: - Init
    
    init(audioEngine: AudioEngineActor) {
        self.audioEngine = audioEngine
        self.state = PlayerState(
            activePlayer: .a,
            playbackMode: .stopped,
            activeTrack: nil,
            inactiveTrack: nil,
            activeMixerVolume: 1.0,
            inactiveMixerVolume: 0.0,
            isCrossfading: false
        )
    }
    
    // MARK: - Atomic Operations
    
    func switchActivePlayer() {
        // No suspend points - atomic!
        let newState = PlayerState(
            activePlayer: state.activePlayer.opposite,
            playbackMode: state.playbackMode,
            activeTrack: state.inactiveTrack,  // Swap
            inactiveTrack: state.activeTrack,  // Swap
            activeMixerVolume: state.inactiveMixerVolume,  // Swap
            inactiveMixerVolume: state.activeMixerVolume,  // Swap
            isCrossfading: state.isCrossfading
        )
        
        guard newState.isConsistent else {
            Logger.error("Invalid state after switch")
            return
        }
        
        state = newState
    }
    
    func updateMode(_ mode: PlaybackMode) {
        let newState = state.withMode(mode)
        
        guard newState.isConsistent else {
            Logger.error("Invalid state for mode: \(mode)")
            return
        }
        
        state = newState
    }
}
```

---

**Last Updated:** 2025-10-21  
**Review:** Before starting Phase 2 implementation
