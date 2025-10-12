# 🎯 ProsperPlayer v4.0 - FINAL ACTION PLAN v2

**Created:** 2025-10-12  
**Updated:** 2025-10-12 (Phase 1-5 completed, Phase 6-8 planned)  
**Use Case:** Meditation Session Player

---

## 📊 Execution Status

| Phase | Status | Commits | Description |
|-------|--------|---------|-------------|
| Phase 1 | ✅ DONE | 2188113 | replacePlaylist uses config.crossfadeDuration |
| Phase 2 | ✅ DONE | 30d4fa4, d977a92 | startPlaying(fadeDuration:) API |
| Phase 3 | ✅ DONE | b3ae37f | skipToNext/skipToPrevious |
| Phase 4 | ✅ DONE | d12bd47 | Loop crossfade fix |
| Phase 5 | ⚠️ PARTIAL | - | Verification (core OK, demo/tests broken) |
| **Phase 6** | 🔄 TODO | - | **loadPlaylist API** |
| Phase 7 | 📋 PLANNED | - | Cleanup demo/tests |
| Phase 8 | 📋 PLANNED | - | Documentation |

---

## 🎯 v4.0 API - Current State

### ✅ What Works:

```swift
// Configuration (immutable)
let config = PlayerConfiguration(
    crossfadeDuration: 10.0,     // Spotify-style (100%+100%)
    fadeCurve: .equalPower,
    repeatMode: .playlist,       // NO enableLooping!
    volume: 0.8,                 // Float 0.0-1.0
    mixWithOthers: false
)

// Player initialization
let player = AudioPlayerService(configuration: config)

// ❌ MISSING: How to load initial playlist?
// Currently only: await player.replacePlaylist(tracks)  // Semantically wrong!

// Playback control
await player.startPlaying(fadeDuration: 2.0)  // fade-in for cold start
await player.skipToNext()                      // uses config.crossfadeDuration
await player.skipToPrevious()                  // uses config.crossfadeDuration
await player.stop(fadeDuration: 3.0)           // fade-out parameter
```

### ❌ Breaking Changes (v3 → v4):

1. **Configuration immutable** - all `var` → `let`
2. **volume: Int → Float** (0.0-1.0, not 0-100)
3. **Removed properties:**
   - `enableLooping` → use `repeatMode`
   - `fadeInDuration` → computed, then DELETED
   - `volumeFloat` → volume is already Float
   - `singleTrackFadeIn/Out` → DELETED
   - `stopFadeDuration` → DELETED (method parameter)

4. **Removed methods:**
   - `startPlaying(url:configuration:)` → `startPlaying(fadeDuration:)`
   - `loadPlaylist(configuration:)` → DELETED (v3 version)
   - `startPlayingTrack` → DELETED

5. **Protocol changes:**
   - `AudioPlayerProtocol.startPlaying` signature updated

---

## 🚀 PHASE 6: Add loadPlaylist API

### Problem:
```swift
// ❌ Current (semantically wrong):
await player.replacePlaylist(tracks)  // "replace" but nothing to replace!
await player.startPlaying()

// ✅ Should be:
await player.loadPlaylist(tracks)     // Initial load
await player.startPlaying()

// ✅ Then later:
await player.replacePlaylist(newTracks)  // Actual replacement with crossfade
```

### Implementation:

**Step 1: Add to AudioPlayerService**

```swift
/// Load initial playlist before playback
/// 
/// Loads tracks into playlist manager without starting playback.
/// Use this method to prepare the player before calling `startPlaying()`.
/// 
/// - Parameter tracks: Array of track URLs (must not be empty)
/// - Throws: 
///   - `AudioPlayerError.emptyPlaylist` if tracks array is empty
/// 
/// - Note: This is a lightweight operation - no audio loading or playback
/// - Note: For replacing playlist during playback, use `replacePlaylist(_:)`
/// 
/// **Example:**
/// ```swift
/// // Load meditation session
/// try await player.loadPlaylist([intro, meditation, outro])
/// 
/// // Start when user is ready
/// try await player.startPlaying(fadeDuration: 2.0)
/// ```
public func loadPlaylist(_ tracks: [URL]) async throws {
    guard !tracks.isEmpty else {
        throw AudioPlayerError.emptyPlaylist
    }
    
    // Simple load - no audio operations
    await playlistManager.load(tracks: tracks)
    
    Self.logger.info("Loaded playlist with \(tracks.count) tracks")
}
```

**Step 2: Update replacePlaylist documentation**

```swift
/// Replace current playlist with crossfade
/// 
/// Replaces the current playlist with new tracks. If playing, performs
/// smooth crossfade to first track of new playlist. If paused/stopped,
/// performs silent switch.
/// 
/// - Parameter tracks: New playlist tracks (must not be empty)
/// - Throws: 
///   - `AudioPlayerError.invalidConfiguration` if tracks array is empty
///   - Other errors from audio engine
/// 
/// - Note: Uses `configuration.crossfadeDuration` for crossfade
/// - Note: For initial playlist load before playback, use `loadPlaylist(_:)`
/// 
/// **Example:**
/// ```swift
/// // Switch to different session during playback
/// try await player.replacePlaylist(advancedSession)
/// // → Smooth crossfade to new session
/// ```
public func replacePlaylist(_ tracks: [URL]) async throws {
    // ... existing implementation
}
```

**Step 3: Update AudioPlayerProtocol (if needed)**

Add to protocol if loadPlaylist should be part of base contract.

---

## 🚀 PHASE 7: Cleanup Demo & Tests

### Demo App Issues:
- ❌ Uses `enableLooping` → change to `repeatMode`
- ❌ Uses `volume: Int` → change to `Float`

**Files to update:**
- `AudioPlayerViewModel.swift`
- `ConfigurationView.swift`

### Tests Issues:
- ❌ Tests deprecated v3 API
- ❌ Tests `volumeFloat`, `enableLooping`, `singleTrackFade*`

**Action:**
- Delete deprecated tests
- Rewrite for v4.0 API
- Add tests for `loadPlaylist`

---

## 🚀 PHASE 8: Documentation

### Update docs:
1. **V4_FINAL_ACTION_PLAN.md** - mark all phases complete
2. **MIGRATION_GUIDE_v3_to_v4.md** - create new
3. **API_REFERENCE_v4.md** - update with new signatures
4. **BREAKING_CHANGES_v4.md** - comprehensive list

### Migration Guide Content:
```markdown
# Migration Guide: v3 → v4

## Configuration Changes
- `var` → `let` (immutable)
- `volume: Int` → `Float`
- Remove `enableLooping` → use `repeatMode`

## API Changes
- `startPlaying(url:config:)` → `startPlaying(fadeDuration:)`
- Add `loadPlaylist()` before first playback
- `replacePlaylist()` for switching during playback

## Step-by-step migration:
1. Update PlayerConfiguration initialization
2. Replace enableLooping with repeatMode
3. Convert volume Int to Float (divide by 100)
4. Use loadPlaylist + startPlaying pattern
5. Remove volumeFloat references (use volume directly)
```

---

## ✅ Success Criteria (Updated)

### Core API:
- [x] `replacePlaylist(_ tracks: [URL])` БЕЗ crossfadeDuration
- [x] `skipToNext()` / `skipToPrevious()` існують
- [x] Loop використовує повний crossfadeDuration
- [x] `startPlaying(fadeDuration:)` БЕЗ url/config
- [ ] `loadPlaylist(_ tracks: [URL])` для initial load ← **TODO**
- [x] Configuration immutable (всі `let`)
- [x] `volume: Float` замість `Int`

### Quality:
- [x] Код компілюється (core)
- [ ] Demo app компілюється ← **TODO**
- [ ] Тести проходять ← **TODO**
- [ ] Документація оновлена ← **TODO**

### Architecture:
- [x] Configuration в конструкторі
- [x] crossfadeDuration з configuration (не параметр)
- [x] fadeDuration параметр для start/stop
- [x] Protocol conformance OK
- [ ] loadPlaylist в протоколі (опціонально)

---

## 🎯 Key Design Principles

### Configuration:
- ✅ Immutable (`let`) - безпека під час playback
- ✅ В конструкторі - явна ініціалізація
- ✅ `updateConfiguration()` - для зміни під час роботи
- ✅ Float volume - AVFoundation standard (0.0-1.0)

### Playlist Management:
- ✅ `loadPlaylist()` - initial load (швидко, без audio)
- ✅ `replacePlaylist()` - replacement з crossfade
- ✅ Clear semantics - зрозуміло коли що використовувати

### Crossfade:
- ✅ З configuration - playlist операції
- ✅ Spotify-style - 100% + 100% overlap
- ✅ Один параметр - crossfadeDuration для всього

### Fade:
- ✅ Параметр методу - startPlaying, stop
- ✅ Різниця: fade = one player, crossfade = dual players
- ✅ Independent - fadeIn НЕ пов'язаний з crossfade

---

## 📋 Next Steps

1. **Execute Phase 6** - Add loadPlaylist API
2. **Execute Phase 7** - Update demo/tests
3. **Execute Phase 8** - Documentation
4. **Final verification** - Everything works
5. **Release v4.0** 🚀

---

## 🔗 Related Documents

- V4_PHASE_2_FINAL_PLAN.md - Phase 2 detailed plan
- V4_REFACTOR_COMPLETE_PLAN.md - Original refactor analysis
- Building an iOS Audio Player Service... .md - Architecture guide

---

**Current Focus: PHASE 6 - loadPlaylist API**
