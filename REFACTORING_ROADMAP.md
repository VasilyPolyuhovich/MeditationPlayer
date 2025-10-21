# ProsperPlayer - Refactoring Roadmap

**Created:** 2025-10-21
**Status:** Phase 1 - Quick Fix

---

## Why Refactor?

**Current state:** Bugs з управління станом плеєра (Race #12, #13, UI breaks)
**Root cause:** State розпорошений між компонентами без єдиного джерела правди
**Solution:** Створити координатори для централізованого управління

---

## Phases

| # | Name | Time | Status |
|---|------|------|--------|
| 1 | Quick Fix (Race #13) | 30 min | 🔄 In Progress |
| 2 | PlaybackStateCoordinator | 2-3 hrs | ⏸️ Planned |
| 3 | CrossfadeCoordinator | 2-3 hrs | ⏸️ Planned |
| 4 | Integration & Testing | 2-3 hrs | ⏸️ Planned |
| 5 | Cleanup & Docs | 1-2 hrs | ⏸️ Planned |

**Total:** 8-13 hours across 5 sessions

---

## Phase 1: Quick Fix for Race #13 ⚡

### Problem
Pause → Skip → Resume = plays silence

### Root Cause
```swift
// AudioPlayerService.swift:1351-1356 (під час паузи)
await audioEngine.switchActivePlayer()  // ✅ Switches to playerB
await audioEngine.stopInactivePlayer()  // ✅ Stops playerA
// ❌ PlayerB not prepared! Resume tries to play unprepared player
```

### Fix
```swift
await audioEngine.switchActivePlayer()
await audioEngine.prepareActivePlayer()  // ✅ ADD THIS
await audioEngine.stopInactivePlayer()
```

### Test
1. Pause playback
2. Press skipToNext
3. Press resume
4. ✅ Expected: Correct track plays (not silence)

---

## Next Steps

1. ✅ Apply Phase 1 fix
2. Build & test
3. Commit to main
4. **User tests** → gather feedback
5. Start Phase 2 planning (new session)

---

## Detailed Plans

Детальні плани для Фаз 2-5 будуть створені **після успішного завершення попередньої фази**.

Це дозволяє:
- Адаптувати план на основі реальних результатів
- Уникнути передчасної деталізації
- Зберегти фокус на поточній задачі

---

**Experimental Work:** `feature/crossfade-coordinator-wip` (commit ab91585) - contains initial CrossfadeCoordinator prototype

---

## 📊 Architecture Vision

```
┌─────────────────────────────────────────┐
│      AudioPlayerService (Facade)        │
│  - Public API                           │
│  - Playlist management                  │
│  - UI observers                         │
└────────────┬────────────────────────────┘
             │
    ┌────────┴────────┐
    │                 │
┌───▼────────────┐ ┌─▼──────────────────┐
│ PlaybackState  │ │ CrossfadeCoordinator│
│  Coordinator   │ │                     │
│                │ │ - Lifecycle         │
│ - Single truth │ │ - Progress tracking │
│ - Active track │ │ - Pause/Resume      │
│ - Player A/B   │ │ - Strategy selection│
└───┬────────────┘ └─┬──────────────────┘
    │                │
    └────────┬───────┘
             │
    ┌────────▼────────┐
    │ AudioEngineActor│
    │                 │
    │ - AVFoundation  │
    │ - Mixer volumes │
    │ - Buffer mgmt   │
    └─────────────────┘
```

**Key Principle:** State flows DOWN, events flow UP. No component directly modifies another component's state.

---

## 🗺️ Implementation Phases

### Phase 1: Quick Fix for Race #13 ⚡
**Branch:** `main`
**Time:** 30 minutes
**Status:** Ready to implement

#### Objective
Fix immediate bug: Pause + Skip + Resume plays silence

#### Root Cause
```swift
// AudioPlayerService.swift:1351-1356
} else {
    // Paused - just switch files without starting
    await audioEngine.switchActivePlayer()
    await audioEngine.stopInactivePlayer()
}
```

When paused and skipToNext:
1. ✅ PlayerB loaded with new track
2. ✅ `switchActivePlayer()` → playerB becomes active
3. ✅ PlayerA stopped
4. ❌ **PlayerB not prepared for playback**
5. Resume calls `audioEngine.play()` → playerB has correct track but may not be ready

#### Fix
```swift
} else {
    // Paused - switch and prepare new player
    await audioEngine.switchActivePlayer()
    await audioEngine.prepareActivePlayer()  // ✅ ADD THIS LINE
    await audioEngine.stopInactivePlayer()
}
```

#### Testing
- [ ] Pause playback
- [ ] Press skipToNext
- [ ] Press resume
- [ ] Verify: Correct track plays (not silence)
- [ ] Verify: UI shows correct track info

#### Success Criteria
- ✅ Pause + Skip + Resume plays correct track
- ✅ No regressions in other scenarios
- ✅ Build passes
- ✅ Committed to `main`

---

### Phase 2: PlaybackStateCoordinator 🎮
**Branch:** `feature/playback-state-coordinator`
**Time:** 2-3 hours
**Dependencies:** Phase 1 complete

#### Objective
Create single source of truth for all player state

#### New File: `Sources/AudioServiceKit/Internal/PlaybackStateCoordinator.swift`

```swift
actor PlaybackStateCoordinator {
    // MARK: - State Definition

    struct PlayerState {
        var activePlayer: PlayerNode  // .a or .b
        var playbackMode: PlaybackMode  // .playing, .paused, .stopped

        var activeTrack: Track?
        var inactiveTrack: Track?

        var activeMixerVolume: Float
        var inactiveMixerVolume: Float

        // Validation
        var isConsistent: Bool {
            // Verify state consistency
            return true
        }
    }

    enum PlayerNode {
        case a, b
        var opposite: PlayerNode { self == .a ? .b : .a }
    }

    enum PlaybackMode {
        case playing
        case paused
        case stopped
    }

    // MARK: - State

    private(set) var state: PlayerState

    private let audioEngine: AudioEngineActor
    private let mixerVolumeManager: MixerVolumeManager

    // MARK: - State Transitions

    func loadTrack(_ track: Track, on player: PlayerNode) async throws
    func switchActivePlayer() async
    func updatePlaybackMode(_ mode: PlaybackMode) async
    func updateMixerVolumes(active: Float, inactive: Float) async

    // MARK: - Query

    func getCurrentTrack() -> Track?
    func getPlaybackMode() -> PlaybackMode
    func getActivePlayer() -> PlayerNode
    func captureSnapshot() -> PlayerState
    func restoreSnapshot(_ snapshot: PlayerState) async
}
```

#### Migration Steps

1. **Add coordinator to AudioPlayerService:**
```swift
public actor AudioPlayerService {
    // OLD (remove):
    // private var state: PlayerState

    // NEW (add):
    private let playbackStateCoordinator: PlaybackStateCoordinator

    init(...) {
        self.playbackStateCoordinator = PlaybackStateCoordinator(
            audioEngine: audioEngine,
            mixerManager: mixerVolumeManager
        )
    }
}
```

2. **Replace state reads:**
```swift
// OLD:
if state == .playing { ... }

// NEW:
if await playbackStateCoordinator.getPlaybackMode() == .playing { ... }
```

3. **Replace state writes:**
```swift
// OLD:
state = .paused

// NEW:
await playbackStateCoordinator.updatePlaybackMode(.paused)
```

4. **Update replaceCurrentTrack:**
```swift
// OLD:
await audioEngine.switchActivePlayer()

// NEW:
await playbackStateCoordinator.switchActivePlayer()  // Atomic!
```

#### Testing Checklist
- [ ] Normal playback start/pause/resume
- [ ] Track switching during playback
- [ ] Track switching during pause
- [ ] State consistency validation triggers correctly
- [ ] All existing tests pass

#### Success Criteria
- ✅ All state reads go through coordinator
- ✅ All state writes go through coordinator
- ✅ State validation passes
- ✅ Zero duplicate state tracking
- ✅ All tests green

---

### Phase 3: CrossfadeCoordinator Enhancement 🎵
**Branch:** `feature/crossfade-coordinator-wip` (already exists)
**Time:** 2-3 hours
**Dependencies:** Phase 2 complete

#### Objective
Complete the CrossfadeCoordinator implementation started in commit ab91585

#### Current Status
- ✅ Basic architecture implemented (483 lines)
- ✅ State machine (idle/executing/paused)
- ✅ Progress observation
- ❌ ~50 compilation errors to fix
- ❌ Integration with PlaybackStateCoordinator needed

#### Compilation Errors to Fix

1. **CrossfadeProgress enum format:**
```swift
// Current (incorrect):
updateProgress(.preparing)

// Fix: Use phase property
updateProgress(CrossfadeProgress(phase: .preparing, ...))
```

2. **Missing getInactiveMixer in AudioEngineActor:**
```swift
// Add to AudioEngineActor.swift
func getInactiveMixer() -> AVAudioMixerNode {
    return activePlayer == .a ? mixerB : mixerA
}
```

3. **AVAudioMixerNode Sendable issues:**
```swift
// Add to relevant places
nonisolated(unsafe) var mixerA: AVAudioMixerNode
nonisolated(unsafe) var mixerB: AVAudioMixerNode
```

#### Integration with PlaybackStateCoordinator

```swift
actor CrossfadeCoordinator {
    private let audioEngine: AudioEngineActor
    private let playbackState: PlaybackStateCoordinator  // ✅ ADD

    struct PausedSnapshot {
        let progress: Float
        let operation: OperationType
        let duration: TimeInterval
        let curve: FadeCurve
        let stateSnapshot: PlaybackStateCoordinator.PlayerState  // ✅ Full state
    }

    // Atomic pause
    func pause() async -> PausedSnapshot? {
        guard case .executing = state else { return nil }

        // 1. Capture FULL state
        let stateSnapshot = await playbackState.captureSnapshot()

        // 2. Pause players
        await playbackState.updatePlaybackMode(.paused)

        // 3. Cancel fade task
        executionTask?.cancel()

        // 4. Save snapshot
        let snapshot = PausedSnapshot(
            progress: calculateProgress(),
            operation: currentOperation,
            duration: duration,
            curve: curve,
            stateSnapshot: stateSnapshot  // Complete state!
        )

        state = .paused(snapshot: snapshot)
        return snapshot
    }

    // Atomic resume
    func resume(from snapshot: PausedSnapshot) async {
        // 1. Restore state FIRST
        await playbackState.restoreSnapshot(snapshot.stateSnapshot)

        // 2. Resume crossfade from progress
        let remaining = snapshot.duration * Double(1.0 - snapshot.progress)
        await startCrossfade(
            type: snapshot.operation,
            duration: remaining,
            fadeCurve: snapshot.curve,
            startProgress: snapshot.progress
        )
    }
}
```

#### Migration Steps

1. Fix compilation errors (1 hour)
2. Add PlaybackStateCoordinator integration (30 min)
3. Update AudioPlayerService to use CrossfadeCoordinator (30 min)
4. Remove old crossfade code from AudioPlayerService (30 min)

#### Testing Checklist
- [ ] Normal crossfade (track A → track B)
- [ ] Pause during crossfade at 20% progress
- [ ] Resume from paused crossfade
- [ ] Pause during crossfade at 80% progress (quick finish)
- [ ] Cancel crossfade (skip to next track)
- [ ] Rapid track changes during crossfade
- [ ] UI progress observer receives all updates
- [ ] State consistency after each operation

#### Success Criteria
- ✅ Zero compilation errors
- ✅ All crossfade operations go through coordinator
- ✅ Pause/resume preserves exact state
- ✅ UI progress never breaks
- ✅ Old pausedCrossfadeState logic removed

---

### Phase 4: Integration & Testing 🧪
**Branch:** `feature/comprehensive-refactoring`
**Time:** 2-3 hours
**Dependencies:** Phases 2 & 3 complete

#### Objective
Merge both coordinators and ensure they work together seamlessly

#### Integration Steps

1. **Create integration branch:**
```bash
git checkout -b feature/comprehensive-refactoring main
git merge feature/playback-state-coordinator
git merge feature/crossfade-coordinator-wip
```

2. **Connect coordinators in AudioPlayerService:**
```swift
public actor AudioPlayerService {
    private let audioEngine: AudioEngineActor
    private let playbackState: PlaybackStateCoordinator
    private let crossfadeCoordinator: CrossfadeCoordinator

    init(...) {
        self.playbackState = PlaybackStateCoordinator(...)
        self.crossfadeCoordinator = CrossfadeCoordinator(
            audioEngine: audioEngine,
            playbackState: playbackState  // Share state!
        )
    }
}
```

3. **Update public API methods:**

**startPlaying:**
```swift
public func startPlaying(fadeDuration: TimeInterval = 0.5) async throws {
    // Use playbackState instead of self.state
    await playbackState.updatePlaybackMode(.playing)

    // Initial fade through audioEngine (not crossfade)
    if fadeDuration > 0 {
        await audioEngine.fadeIn(duration: fadeDuration)
    }
}
```

**pause:**
```swift
public func pause() async {
    // Check if crossfade is active
    if await crossfadeCoordinator.isExecuting() {
        // Pause crossfade atomically
        let snapshot = await crossfadeCoordinator.pause()
        // snapshot contains everything needed to resume
    } else {
        // Normal pause
        await playbackState.updatePlaybackMode(.paused)
    }
}
```

**resume:**
```swift
public func resume() async throws {
    // Check if we have paused crossfade
    if let snapshot = await crossfadeCoordinator.getPausedSnapshot() {
        // Resume crossfade from exact point
        await crossfadeCoordinator.resume(from: snapshot)
    } else {
        // Normal resume
        await playbackState.updatePlaybackMode(.playing)
    }
}
```

**skipToNext/skipToPrevious:**
```swift
public func skipToNext() async throws {
    // Cancel any active crossfade
    await crossfadeCoordinator.cancel()

    // Get next track
    let track = try playlist.skipToNext()

    // Load and switch
    try await playbackState.loadTrack(track, on: .inactive)

    // Decide: crossfade or instant switch?
    let isPlaying = await playbackState.getPlaybackMode() == .playing
    if isPlaying {
        await crossfadeCoordinator.start(type: .manualChange)
    } else {
        await playbackState.switchActivePlayer()
    }
}
```

4. **Remove duplicate code:**
```swift
// DELETE these from AudioPlayerService:
// - activeCrossfadeOperation
// - pausedCrossfadeState
// - executeCrossfade() method
// - rollbackCrossfade() method
// - Old pause/resume crossfade logic
```

#### Complete Testing Matrix

| Scenario | Expected Behavior | Status |
|----------|------------------|--------|
| **Basic Playback** |
| Start playing | Track plays, UI updates | ⏸️ |
| Pause | Audio pauses, UI shows paused | ⏸️ |
| Resume | Audio resumes from same position | ⏸️ |
| Stop | Audio stops, resets to beginning | ⏸️ |
| **Track Navigation** |
| Skip to next (playing) | Crossfade to next track | ⏸️ |
| Skip to previous (playing) | Crossfade to previous track | ⏸️ |
| Skip to next (paused) | Load next track, stay paused | ⏸️ |
| Skip to previous (paused) | Load previous track, stay paused | ⏸️ |
| **Crossfade Scenarios** |
| Normal crossfade | Smooth A→B transition | ⏸️ |
| Pause at 20% crossfade | Saves state, both players paused | ⏸️ |
| Resume from 20% | Continues from 20%, finishes crossfade | ⏸️ |
| Pause at 80% crossfade | Saves state, both players paused | ⏸️ |
| Resume from 80% | Quick finish (1 second) | ⏸️ |
| Cancel crossfade (skip) | Crossfade stops, new track loads | ⏸️ |
| **Edge Cases** |
| Rapid skip (5x in 2 sec) | Each skip cancels previous crossfade | ⏸️ |
| Pause during rapid skip | Crossfade cancels, correct track paused | ⏸️ |
| Skip to same track | Detected, no crossfade | ⏸️ |
| **Race Conditions** |
| Race #12: Incomplete cleanup | pausedCrossfadeState always cleared | ⏸️ |
| Race #13: Pause+Skip+Resume | Plays correct track (not silence) | ⏸️ |
| **UI Updates** |
| Crossfade progress | Smooth 0%→100%, no breaks | ⏸️ |
| Track info during crossfade | Shows incoming track at 50% | ⏸️ |
| Paused crossfade UI | Shows paused state, progress frozen | ⏸️ |
| **OverlayPlayer** |
| Play overlay during main | Overlay works independently | ⏸️ |
| Main crossfade with overlay | Overlay unaffected | ⏸️ |
| **SoundEffects** |
| Play effect during main | Effect works independently | ⏸️ |
| Main crossfade with effects | Effects unaffected | ⏸️ |

#### Success Criteria
- ✅ All test scenarios pass
- ✅ Zero race conditions
- ✅ UI never breaks
- ✅ OverlayPlayer & SoundEffects unaffected
- ✅ Code is cleaner and easier to understand

---

### Phase 5: Cleanup & Documentation 📚
**Branch:** `feature/comprehensive-refactoring`
**Time:** 1-2 hours
**Dependencies:** Phase 4 complete

#### Code Cleanup

**Files to delete:**
- None (keep all for git history)

**Code to remove from AudioPlayerService:**
```swift
// DELETE:
private var activeCrossfadeOperation: CrossfadeOperation?
private var pausedCrossfadeState: PausedCrossfadeState?
private var crossfadeProgressTask: Task<Void, Never>?
private var crossfadeCleanupTask: Task<Void, Never>?

private func executeCrossfade(...) { ... }
private func rollbackCrossfade(...) { ... }
private func clearPausedCrossfadeIfNeeded() { ... }
private func cleanupResumedCrossfade() { ... }

// Keep only:
private let playbackStateCoordinator: PlaybackStateCoordinator
private let crossfadeCoordinator: CrossfadeCoordinator
```

**Simplify methods:**
- `pause()` - now 10 lines instead of 100
- `resume()` - now 15 lines instead of 80
- `skipToNext()` - now 20 lines instead of 60

#### Documentation Updates

**1. Create ARCHITECTURE.md:**
```markdown
# ProsperPlayer Architecture

## Overview
ProsperPlayer uses a coordinator-based architecture to manage complex audio playback state.

## Components

### AudioPlayerService (Facade)
- **Role:** Public API, playlist management, UI observers
- **Responsibilities:** Coordinate between coordinators, handle user requests
- **Does NOT:** Directly manage AVFoundation, track internal state

### PlaybackStateCoordinator
- **Role:** Single source of truth for player state
- **Responsibilities:** Track active player, playback mode, track info
- **Guarantees:** State consistency, atomic transitions

### CrossfadeCoordinator
- **Role:** Manage crossfade lifecycle
- **Responsibilities:** Pause/resume, progress tracking, strategy selection
- **Guarantees:** No race conditions, complete state capture

### AudioEngineActor
- **Role:** AVFoundation interface
- **Responsibilities:** Audio playback, buffer management, mixer control
- **Guarantees:** Thread-safe audio operations

## State Flow

```
User Action
    ↓
AudioPlayerService (validates, coordinates)
    ↓
PlaybackStateCoordinator (updates truth)
    ↓
CrossfadeCoordinator (if crossfade needed)
    ↓
AudioEngineActor (executes on AVFoundation)
```

## Key Principles

1. **Single Source of Truth:** All state lives in PlaybackStateCoordinator
2. **Atomic Operations:** State changes are all-or-nothing
3. **Actor Isolation:** Prevent data races with Swift Concurrency
4. **Separation of Concerns:** Each component has clear boundaries
```

**2. Update README.md:**
```markdown
## Architecture Highlights

- ✅ **Coordinator Pattern:** Centralized state management
- ✅ **Swift 6 Concurrency:** Data race prevention with actors
- ✅ **Atomic Operations:** No partial state updates
- ✅ **Pause/Resume Crossfades:** Save and restore exact progress
```

**3. Add code comments:**
```swift
/// Coordinator for player state management.
///
/// This is the SINGLE SOURCE OF TRUTH for:
/// - Which player (A/B) is active
/// - Current playback mode (playing/paused/stopped)
/// - Track information
/// - Mixer volumes
///
/// All state queries and updates MUST go through this coordinator.
/// Direct state manipulation is prohibited.
actor PlaybackStateCoordinator {
    // ...
}
```

#### Git Cleanup

**Squash WIP commits:**
```bash
# Interactive rebase to clean up history
git rebase -i main

# Squash into logical commits:
# 1. "Add PlaybackStateCoordinator"
# 2. "Add CrossfadeCoordinator enhancements"
# 3. "Integrate coordinators in AudioPlayerService"
# 4. "Remove duplicate state tracking"
# 5. "Update documentation"
```

#### Final Review Checklist
- [ ] All tests pass
- [ ] No compiler warnings
- [ ] Code coverage >80%
- [ ] Documentation complete
- [ ] Git history clean
- [ ] Ready for PR review

#### Success Criteria
- ✅ Codebase is cleaner
- ✅ Architecture is documented
- ✅ Future developers can understand design
- ✅ Ready to merge to main

---

## 📈 Progress Tracking

### Current Status: Phase 1 (Quick Fix)

| Phase | Status | Branch | Estimated Time | Actual Time |
|-------|--------|--------|----------------|-------------|
| 1. Quick Fix | 🔄 In Progress | `main` | 30 min | - |
| 2. PlaybackStateCoordinator | ⏸️ Not Started | `feature/playback-state-coordinator` | 2-3 hours | - |
| 3. CrossfadeCoordinator | ⏸️ Not Started | `feature/crossfade-coordinator-wip` | 2-3 hours | - |
| 4. Integration | ⏸️ Not Started | `feature/comprehensive-refactoring` | 2-3 hours | - |
| 5. Cleanup | ⏸️ Not Started | `feature/comprehensive-refactoring` | 1-2 hours | - |

---

## 🎯 Next Steps

### Immediate (Today)
1. ✅ Create this roadmap document
2. ⏸️ Apply Phase 1 quick fix
3. ⏸️ Build and test
4. ⏸️ Commit to main
5. ⏸️ Wait for user testing feedback

### Session 2
1. Create `feature/playback-state-coordinator` branch
2. Implement PlaybackStateCoordinator
3. Migrate AudioPlayerService to use it
4. Test all scenarios
5. Commit

### Session 3
1. Checkout `feature/crossfade-coordinator-wip`
2. Fix compilation errors
3. Add PlaybackStateCoordinator integration
4. Test crossfade scenarios
5. Commit

### Sessions 4-5
1. Integration and testing
2. Documentation
3. Cleanup
4. Merge to main

---

## 🐛 Known Issues Addressed

### Race Condition #12: Incomplete State Cleanup
**Status:** Will be fixed in Phase 3
**Solution:** CrossfadeCoordinator.cancel() atomically clears ALL state

### Race Condition #13: Pause + Skip + Resume Plays Silence
**Status:** Fixed in Phase 1
**Solution:** Added `prepareActivePlayer()` call

### UI Crossfade Progress Breaks
**Status:** Will be fixed in Phase 3
**Solution:** CrossfadeCoordinator guarantees progress updates

### "Plays Only One Player" Instead of Crossfade
**Status:** Will be fixed in Phase 2
**Solution:** PlaybackStateCoordinator ensures consistent state

---

## 📝 Notes

### Design Decisions

**Why Two Coordinators Instead of One?**
- **Separation of Concerns:** State management vs. Crossfade lifecycle are different responsibilities
- **Testability:** Easier to test each coordinator in isolation
- **Reusability:** PlaybackStateCoordinator could be used without crossfades (e.g., instant track switching)

**Why Not Just Fix Bugs Individually?**
- **Technical Debt:** Current architecture makes bugs inevitable
- **Long-term Cost:** Band-aid fixes accumulate complexity
- **Quality:** Systematic refactoring prevents future bugs

**Why Phased Approach?**
- **Risk Management:** Test each phase independently
- **Iterative Delivery:** Quick fix unblocks user, refactoring improves quality
- **Context Preservation:** Each phase is a logical checkpoint

### Risks & Mitigation

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Regression bugs during refactoring | Medium | High | Comprehensive test matrix, phase by phase |
| Refactoring takes longer than estimated | Medium | Medium | Each phase is independently valuable |
| New bugs introduced | Low | High | Actor isolation, atomic operations, validation |
| Breaking changes to public API | Very Low | High | Facade pattern preserves API compatibility |

---

## 🤝 Success Metrics

### Technical Metrics
- Zero race conditions detected
- Test coverage >80%
- Code complexity reduced by >30%
- Duplicate code eliminated

### User Experience Metrics
- Crossfade UI never breaks
- Audio playback is glitch-free
- Pause/resume is instant
- Track switching is smooth

### Maintenance Metrics
- New developers understand architecture in <1 hour
- Bug fix time reduced by 50%
- Feature additions are easier

---

## 📞 Communication

### Status Updates
- After each phase completion
- If blocking issues arise
- When timeline changes

### Decision Points
- Architectural choices
- API changes
- Breaking changes

### Review Checkpoints
- End of Phase 2 (PlaybackStateCoordinator)
- End of Phase 3 (CrossfadeCoordinator)
- Before merging to main

---

**Last Updated:** 2025-10-21
**Next Review:** After Phase 1 completion
