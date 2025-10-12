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

# 4. Read MAIN reference doc
read_file({ path: "FEATURE_OVERVIEW_v4.0.md" })  # ⭐ COMPLETE SPEC

# 5. Read additional context (if needed)
read_file({ path: "HANDOFF_v4.0_SESSION.md" })
read_file({ path: "LEGACY/v4.0_docs/KEY_INSIGHTS_v4.0.md" })
read_file({ path: "LEGACY/v4.0_docs/TODO_v4.0.md" })
```

---

## 🎯 What We're Doing

**Phase 3: Update API Methods (2-3h)**

### Changes:
1. `startPlaying()` - remove URL param (from PlaylistManager)
2. `stop()` - change to non-optional fade param
3. Add `getVolume()` method
4. Remove deprecated methods

### ⭐ Verify Features:

**1. Overlay Delay Between Loops**
- Check: `OverlayConfiguration.delayBetweenLoops` exists
- Check: `OverlayPlayerActor` implements delay timer
- Natural pauses: wave → silence → wave

**2. Queue Management**
- Check: `PlaylistManager.playNext(url:)` exists
- Check: `PlaylistManager.getUpcomingQueue()` exists

---

## 📚 Documentation Structure

### ⭐ PRIMARY (корінь):
- **`FEATURE_OVERVIEW_v4.0.md`** - Complete functional spec (9 categories)
- `HANDOFF_v4.0_SESSION.md` - Session handoff
- `QUICK_START_v4.0.md` - Quick start
- `START_NEXT_CHAT.md` - This file
- `.claude_instructions` - Project instructions

### 📦 ARCHIVED (LEGACY/):
- `v4.0_docs/` - Important v4.0 docs to keep
  - `KEY_INSIGHTS_v4.0.md` - Critical user insights
  - `SESSION_v4.0_ANALYSIS.md` - Full v4.0 analysis
  - `TODO_v4.0.md` - Phase checklist
- `Temp/` - Old session docs (can delete)
- `.claude/` - Old instructions (can delete)

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

## ✅ Cleanup Complete!

**Archived:**
- LEGACY/Temp/ - 62 old session docs
- LEGACY/.claude/ - 100+ old files
- LEGACY/v4.0_docs/ - 3 important docs saved

**Kept in root:**
- FEATURE_OVERVIEW_v4.0.md ⭐ (main reference)
- HANDOFF_v4.0_SESSION.md
- QUICK_START_v4.0.md
- START_NEXT_CHAT.md
- .claude_instructions

**Clean project structure!** 🎯

---

**Start with:** `load_session()` → Read FEATURE_OVERVIEW → Verify overlay delay → Begin Phase 3 🚀
