# 🚀 Start Next Chat - ProsperPlayer v4.0 Phase 3

**Project:** `/Users/vasily/Projects/Helpful/ProsperPlayer`  
**Branch:** `v4-dev`  
**Focus:** Meditation Audio Player (NOT Spotify clone!)

---

## 📍 Quick Start Commands

```bash
# 1. Load context
load_session()

# 2. Verify project
current_project()

# 3. Check git
git_status()

# 4. Read key docs
read_file({ path: "FEATURE_OVERVIEW_v4.0.md" })  # ⭐ COMPLETE REFERENCE
read_file({ path: "HANDOFF_v4.0_SESSION.md" })
read_file({ path: "Temp/KEY_INSIGHTS_v4.0.md" })
```

---

## 🎯 What We're Doing

**Phase 3: Update API Methods (2-3h)**

### Changes:
1. `startPlaying()` - remove URL param (from PlaylistManager)
2. `stop()` - change to non-optional fade param
3. Add `getVolume()` method
4. Remove deprecated methods

### ⭐ NEW: Verify Overlay Delay Feature
**Critical addition:** `delayBetweenLoops` in OverlayConfiguration

**What it does:**
- Natural pause between overlay repeats
- wave → silence → wave (природність)
- Prevents audio overwhelm

**Check:**
- [ ] OverlayConfiguration has `delayBetweenLoops` field
- [ ] OverlayPlayerActor implements delay timer
- [ ] Works with `.infinite` and `.count(N)` modes

---

## 📚 Key Files

**Must Read:**
- `FEATURE_OVERVIEW_v4.0.md` - ⭐ **COMPLETE** функціонал (9 категорій)
- `HANDOFF_v4.0_SESSION.md` - Full context with decisions
- `Temp/KEY_INSIGHTS_v4.0.md` - Critical insights
- `Temp/TODO_v4.0.md` - Phase checklist

**Code:**
- `Sources/AudioServiceKit/Public/AudioPlayerService.swift`
- `Sources/AudioServiceKit/Internal/AudioEngineActor.swift`
- `Sources/AudioServiceKit/Internal/OverlayPlayerActor.swift` ← check delay
- `Sources/AudioServiceCore/PlayerConfiguration.swift`
- `Sources/AudioServiceCore/OverlayConfiguration.swift` ← check field

---

## 🚨 Critical Decisions Needed

### 1. Volume Architecture (choose one):

**Option A: mainMixer only** ✅ RECOMMENDED
```swift
mainMixerNode.volume = globalVolume
mixerA.volume = crossfadeVolA  // independent
mixerB.volume = crossfadeVolB  // independent
```

**Option B: multiply each mixer**
```swift
mixerA.volume = crossfadeVolA * globalVolume
mixerB.volume = crossfadeVolB * globalVolume
```

**Option C: @Published wrapper**
```swift
@MainActor class ViewModel {
    @Published var volume: Float = 1.0
}
```

### 2. Queue Management

**Check PlaylistManager has:**
- [ ] `playNext(url:)` - insert after current
- [ ] `getUpcomingQueue()` - show next tracks

**If missing** → add wrapper methods

### 3. Overlay Delay (verify implementation)

**Check OverlayConfiguration:**
```swift
struct OverlayConfiguration {
    let delayBetweenLoops: TimeInterval  // Should exist!
}
```

---

## 💡 Remember

**Meditation App Principles:**
1. Zero glitches (any click = meditation broken)
2. Long crossfades OK (5-15s normal)
3. Seamless loops critical
4. Overlay = killer feature
5. **Overlay delay** = natural pauses ⭐
6. NO shuffle needed

**Technical:**
- Dual-player for seamless
- Actor isolation (Swift 6)
- Volume coordination needed
- Crossfade auto-adapt (Phase 4)
- **Overlay delay timer** (verify!)

---

## 📋 Next Steps

1. **Verify Overlay Delay** ← START HERE
   - Check OverlayConfiguration.delayBetweenLoops
   - Check OverlayPlayerActor implementation
   
2. **Verify PlaylistManager** - check queue methods

3. **Choose Volume option** - A/B/C

4. **Implement Phase 3** - update API

5. **Test** - seamless transitions, no clicks

6. **Continue** - Phases 4-8

**Timeline:** 2-3h this phase, 12-18h total

---

## ✅ Feature Overview Complete!

**FEATURE_OVERVIEW_v4.0.md** містить:
- 9 категорій features
- Overlay with delayBetweenLoops ⭐
- Complete API reference
- Use cases для meditation
- Same page checklist

**User каже:** "майже ідеальне розуміння!" 🎯

---

**Start with:** `load_session()` → Verify overlay delay → Begin Phase 3 🚀
