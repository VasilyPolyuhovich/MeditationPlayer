# 🚀 Start Next Chat - ProsperPlayer v4.0

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

# 3. Check git status
git_status()

# 4. Read current phase status
read_file({ path: "V4_FINAL_ACTION_PLAN.md" })  # ⭐ CURRENT STATUS

# 5. Read additional context (if needed)
read_file({ path: "V4_MASTER_PLAN.md" })       # Concepts & philosophy
read_file({ path: "FEATURE_OVERVIEW_v4.0.md" }) # Complete spec
read_file({ path: "HANDOFF_v4.0_SESSION.md" })  # Decisions & architecture
```

---

## 📊 Current Status

**Phase Status:** See [V4_FINAL_ACTION_PLAN.md](V4_FINAL_ACTION_PLAN.md) for up-to-date progress

| Phase | Description | Status |
|-------|-------------|--------|
| Phase 1-6 | Core API implementation | ✅ DONE |
| Phase 7 | Cleanup demo/tests | 📋 TODO |
| Phase 8 | Final documentation | 📋 TODO |

**Last Updates:**
- ✅ Phase 6: `loadPlaylist()` API added
- ✅ Docs cleanup: archived working docs to LEGACY/

---

## 📚 Documentation Structure

### ⭐ PRIMARY (корінь):

1. **[V4_FINAL_ACTION_PLAN.md](V4_FINAL_ACTION_PLAN.md)** - Current phase status & execution plan
2. **[V4_MASTER_PLAN.md](V4_MASTER_PLAN.md)** - Concepts & philosophy ("WHY v4.0 works this way")
3. **[FEATURE_OVERVIEW_v4.0.md](FEATURE_OVERVIEW_v4.0.md)** - Complete functional spec
4. **[HANDOFF_v4.0_SESSION.md](HANDOFF_v4.0_SESSION.md)** - Session context & decisions
5. **[START_NEXT_CHAT.md](START_NEXT_CHAT.md)** - This file (quick start)

### 📦 ARCHIVED (LEGACY/):

- `v4.0_working_docs/` - Working analysis docs (archived 2025-10-13)
- `v4.0_docs/` - Important v4.0 docs to keep
  - `KEY_INSIGHTS_v4.0.md` - Critical user insights
  - `SESSION_v4.0_ANALYSIS.md` - Full v4.0 analysis
  - `TODO_v4.0.md` - Phase checklist
- `Temp/` - Old session docs (can delete)
- `.claude/` - Old instructions (can delete)

---

## 🎯 v4.0 API Overview

### Configuration (Immutable):
```swift
let config = PlayerConfiguration(
    crossfadeDuration: 10.0,  // Spotify-style (100%+100%)
    fadeCurve: .equalPower,
    repeatMode: .playlist,    // NO enableLooping!
    volume: 0.8,              // Float 0.0-1.0
    mixWithOthers: false
)
```

### Playlist Loading:
```swift
// 1. Load initial playlist
try await player.loadPlaylist(tracks)

// 2. Start playback
try await player.startPlaying(fadeDuration: 2.0)

// 3. Replace if needed (with crossfade)
try await player.replacePlaylist(newTracks)
```

### Playback Control:
```swift
await player.skipToNext()           // config.crossfadeDuration
await player.skipToPrevious()       // config.crossfadeDuration  
await player.stop(fadeDuration: 3.0)
```

---

## 🚨 Critical Architectural Details

### Crossfade ≠ Fade
📖 See [V4_MASTER_PLAN.md](V4_MASTER_PLAN.md) for detailed explanation

**Quick Summary:**
- **CROSSFADE** = track-to-track (dual-player, 5-15s)
- **FADE** = start/stop (single-player, 1-5s)

### Volume Architecture
📖 See [HANDOFF_v4.0_SESSION.md](HANDOFF_v4.0_SESSION.md) - "Volume Architecture" section for detailed options (A/B/C)

### Queue Management
📖 See [HANDOFF_v4.0_SESSION.md](HANDOFF_v4.0_SESSION.md) - "PlaylistManager Аналіз" section

---

## 💡 Meditation App Principles

**Remember:**
1. Zero glitches (any click = meditation broken)
2. Long crossfades OK (5-15s normal for meditation)
3. Seamless loops critical
4. Overlay = killer feature
5. NO shuffle needed (structured meditation flow)

**Technical:**
- Dual-player for seamless crossfades
- Actor isolation (Swift 6 safety)
- Immutable configuration (thread-safe)
- Crossfade auto-adapt for short tracks

---

## 📋 Next Steps

### If Continuing from Phase 6:

1. **Phase 7: Cleanup demo/tests** (1-2h)
   - Update demo app (enableLooping → repeatMode, volume Int → Float)
   - Fix broken tests
   - Update to use v4.0 API

2. **Phase 8: Final documentation** (1-2h)
   - Update all docs with Phase 6 changes
   - Create migration guide v3 → v4
   - Verify API reference is complete

### If Starting New Feature:

1. Read [V4_FINAL_ACTION_PLAN.md](V4_FINAL_ACTION_PLAN.md) for current status
2. Check which phase is next
3. Review relevant docs before implementation

---

## ✅ Recent Cleanup (2025-10-13)

**Archived 10 working docs to LEGACY/v4.0_working_docs/:**
- Analysis files (ARCHITECTURE_ANALYSIS, CODE_VS_FEATURE, etc.)
- Planning iterations (V4_ACTION_PLAN, V4_REFACTOR_COMPLETE_PLAN, etc.)
- Progress reports (V4_ANALYSIS_PROGRESS_1/2, V4_COMPLETE_ANALYSIS, etc.)

**Kept 5 active docs in root:**
- Current plans and specifications
- Cross-linked for easy navigation

**Project structure is clean!** 🎯

---

**Quick Start:** `load_session()` → Read V4_FINAL_ACTION_PLAN.md → Continue with next phase 🚀
