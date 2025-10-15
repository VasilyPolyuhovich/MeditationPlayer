# ✅ ProsperPlayer v4.0 - TODO Checklist

**Start here in new chat!**

---

## 📍 Current Progress

- [x] Phase 1: Git setup (v4-dev branch)
- [x] Phase 2: Delete fade parameters from config
- [ ] Phase 3: Update API methods (2-3h)
- [ ] Phase 4: Fix loop crossfade auto-adapt (2-3h)
- [ ] Phase 5: Pause crossfade save/continue (3-4h)
- [ ] Phase 6: Volume dual-mixer coordination (1h)
- [ ] Phase 7: Remove deprecated API (1h)
- [ ] Phase 8: Testing & documentation (2h)

**Total remaining:** 12-18 hours

---

## 🎯 Phase 3: Update API Methods (NEXT!)

### Step 1: Update Method Signatures
```swift
// AudioPlayerService.swift

// ✅ Update these:
func startPlaying(fadeDuration: TimeInterval = 0.0) async throws
func stop(fadeDuration: TimeInterval = 0.0) async
func seekWithFade(to: TimeInterval, fadeDuration: TimeInterval = 0.1) async throws

// ❌ Remove these:
func startPlaying(url: URL, configuration: PlayerConfiguration) async throws
func stopWithDefaultFade() async
func setSingleTrackFadeDurations(fadeIn:fadeOut:) async throws
```

### Step 2: Add Volume Methods
```swift
// AudioPlayerService.swift
public func setVolume(_ volume: Float) async
public func getVolume() async -> Float

// AudioEngineActor.swift
func setGlobalVolume(_ volume: Float)
func getGlobalVolume() -> Float
```

### Step 3: Update Demo App
- Update UI to use new API
- Test compilation
- Verify all features work

---

## 🎯 Phase 4: Crossfade Auto-Adapt

### Implementation:
```swift
// In loopCurrentTrackWithFade():
let trackDuration = currentTrack?.duration ?? 0
let maxCrossfade = trackDuration * 0.4  // Max 40%
let actualCrossfade = min(configuration.crossfadeDuration, maxCrossfade)

// Use actualCrossfade instead of configuration.crossfadeDuration
```

### Test Cases:
- [ ] 15s track + 10s config → 6s actual
- [ ] 60s track + 10s config → 10s actual
- [ ] 120s track + 5s config → 5s actual

---

## 🎯 Phase 5: Pause Crossfade State

### Implementation:
```swift
// AudioPlayerService.swift
private struct CrossfadeState: Sendable {
    let progress: Float
    let totalDuration: TimeInterval
    let playerAVolume: Float
    let playerBVolume: Float
    let remainingDuration: TimeInterval
}

private var savedCrossfadeState: CrossfadeState?

func pause() async throws {
    if isCrossfading {
        savedCrossfadeState = CrossfadeState(...)
    }
    await audioEngine.pauseBothPlayers()
}

func resume() async throws {
    if let saved = savedCrossfadeState {
        await continueCrossfade(from: saved)
        savedCrossfadeState = nil
    }
    await audioEngine.resumeBothPlayers()
}
```

### Test Cases:
- [ ] Pause at 30% crossfade → resume continues from 30%
- [ ] Pause at 70% crossfade → resume finishes last 30%
- [ ] Pause during normal playback → no crossfade state

---

## 🎯 Phase 6: Volume Coordination

### Implementation:
```swift
// AudioEngineActor.swift
private var globalVolume: Float = 1.0

func setGlobalVolume(_ volume: Float) {
    globalVolume = max(0.0, min(1.0, volume))
    mainMixerNode.volume = globalVolume
}

// Crossfade logic:
func performCrossfade() {
    // PlayerA/B mixers fade independently
    mixerNodeA.volume = 1.0 → 0.0  // Crossfade math
    mixerNodeB.volume = 0.0 → 1.0  // Crossfade math
    
    // Main mixer stays at globalVolume
    mainMixerNode.volume = globalVolume  // Constant!
}
```

### Test Cases:
- [ ] Change volume during crossfade → correct output
- [ ] Change volume during normal playback → correct
- [ ] Crossfade while volume at 50% → correct blend

---

## 🎯 Phase 7: Remove Deprecated

### Files to Clean:
- [ ] Remove old startPlaying(url:configuration:)
- [ ] Remove stopWithDefaultFade()
- [ ] Remove stopImmediatelyWithoutFade()
- [ ] Remove setSingleTrackFadeDurations()
- [ ] Update all call sites in demo app
- [ ] Verify compilation

---

## 🎯 Phase 8: Testing & Docs

### Testing:
- [ ] Unit tests for new API
- [ ] Integration tests for crossfade auto-adapt
- [ ] Manual testing in demo app
- [ ] Memory leak tests (Instruments)
- [ ] Thread sanitizer (TSan)

### Documentation:
- [ ] Update README.md
- [ ] Update API docs
- [ ] Update migration guide (v3.1 → v4.0)
- [ ] Update PlayerConfiguration docs
- [ ] Update examples

---

## 🚨 Critical Checks Before Done

### Functional:
- [ ] Seamless loop crossfade works
- [ ] Pause/resume crossfade preserves state
- [ ] seekWithFade has NO click
- [ ] Volume works with dual-mixers
- [ ] Overlay player works independently

### Code Quality:
- [ ] Zero compiler warnings
- [ ] Zero data races (TSan)
- [ ] No memory leaks (Instruments)
- [ ] All tests pass
- [ ] SwiftLint clean

### Documentation:
- [ ] README updated
- [ ] CHANGELOG updated
- [ ] API docs complete
- [ ] Migration guide ready
- [ ] Examples work

---

## 📚 Reference Files

**Read these first:**
- `Temp/QUICK_START_v4.0.md` - Quick overview
- `Temp/SESSION_v4.0_ANALYSIS.md` - Full analysis (10KB)
- `Temp/KEY_INSIGHTS_v4.0.md` - Critical decisions

**Planning docs:**
- `.claude/planning/V4.0_CLEAN_PLAN.md`
- `.claude/planning/PLAYER_CONFIGURATION_GUIDE.md`

---

## 💡 Remember

**Meditation Focus:**
- Zero glitches/clicks (mandatory)
- Long crossfades OK (5-15s)
- Seamless = critical
- Overlay = killer feature

**Architecture:**
- Dual-player for seamless
- Actor isolation (Swift 6)
- Volume coordination (dual-mixer)
- Crossfade auto-adapt (max 40%)

---

**Start Phase 3 now!** Update API methods → Test → Move to Phase 4

Timeline: 2-3h for Phase 3, 12-18h total