# 🎯 AudioPlayerService API Design Document

**Date:** 2025-01-23  
**Status:** Post Option B Simplification  
**Purpose:** Document API decisions based on 3-stage meditation use case

---

## 📋 API Overview (38 Public Methods)

Total: **38 public methods** grouped into 8 categories

---

## ✅ Category 1: Core Playback (7 methods)

### KEEP ALL - Critical for meditation flow

```swift
public func startPlaying(fadeDuration: TimeInterval = 0.0) async throws
public func pause() async throws
public func resume() async throws
public func stop(fadeDuration: TimeInterval = 0.0) async
public func finish(fadeDuration: TimeInterval?) async throws
public func skip(forward interval: TimeInterval = 15.0) async throws
public func skip(backward interval: TimeInterval = 15.0) async throws
```

**Use Case Validation:**
- ✅ `startPlaying()` → Stage 1/2/3 start (validated)
- ✅ `pause()` → Morning routine pause (CRITICAL - daily occurrence!)
- ✅ `resume()` → After phone call/interruption
- ✅ `stop()` → Mid-session stop (user decision)
- ✅ `finish()` → Logical end of session (different semantics from stop)
  - **stop** = "I'm pausing the meditation, might come back"
  - **finish** = "Session complete, cleanup and exit"
- ✅ `skip(forward/backward)` → **Customer requirement!** User wants to jump to favorite part of track

**Decision:** Keep all 7 methods. Different semantics for stop vs finish justified.

---

## ✅ Category 2: Playback Control (3 methods)

### KEEP: 2 methods | CONSIDER INTERNAL: 1 method

```swift
public func seek(to time: TimeInterval, fadeDuration: TimeInterval = 0.1) async throws
public func setVolume(_ volume: Float) async
public func setRepeatMode(_ mode: RepeatMode) async
```

**Use Case Validation:**
- ⚠️ `seek()` → Partially covered by `skip(forward/backward)`. **Consider making internal** (skip methods use it internally)
- ✅ `setVolume()` → User preference adjustment (validated)
- ✅ `setRepeatMode()` → Stage track looping configuration (validated)

**Decision:** 
- Keep `setVolume()` and `setRepeatMode()` 
- **ACTION:** Consider making `seek()` internal (public API = skip forward/backward only)

---

## ✅ Category 3: Configuration (2 methods)

### KEEP ALL - Essential SDK APIs

```swift
public func updateConfiguration(_ config: PlayerConfiguration) async throws
public func reset() async
```

**Use Case Validation:**
- ✅ `updateConfiguration()` → Runtime config changes (crossfade duration, volume, etc.)
- ✅ `reset()` → Clean state between sessions (memory cleanup)

**Decision:** Keep both methods.

---

## ⚠️ Category 4: Playlist Management (6 methods)

### KEEP: 4 methods | REMOVE: 2 duplicates

```swift
public func loadPlaylist(_ tracks: [Track]) async throws
public func loadPlaylist(_ tracks: [URL]) async throws
public func replacePlaylist(_ tracks: [Track]) async throws  // ❌ DUPLICATE
public func replacePlaylist(_ tracks: [URL]) async throws    // ❌ DUPLICATE
public func skipToNext() async throws
public func skipToPrevious() async throws
```

**Use Case Validation:**
- ✅ `loadPlaylist([Track])` → Load Stage 1/2/3 tracks
- ✅ `loadPlaylist([URL])` → Convenience overload (URLs → Tracks internally)
- ❌ `replacePlaylist()` → **DUPLICATE of loadPlaylist()!**
  - Originally: Controlled switching between programmer-prepared playlists
  - Reality: loadPlaylist() with different array works perfectly
- ✅ `skipToNext/Previous()` → Developer tools for 3-stage navigation
  - **Use Case 1:** 3 separate playlists (each loops internally) + manual skip between stages
  - **Use Case 2:** 1 playlist with 3 tracks (each track loops) + circular navigation
  - Circular navigation: 1 track → behaves as 2 identical tracks in playlist

**Decision:** 
- **REMOVE:** `replacePlaylist()` methods (2 methods removed)
- **KEEP:** `loadPlaylist()` + `skipToNext/Previous()`
- **Total:** -2 methods (6 → 4)

---

## ✅ Category 5: Observer Pattern (2 methods)

### KEEP ALL - Standard SDK pattern

```swift
public func addObserver(_ observer: AudioPlayerObserver)
public func removeObserver(_ observer: AudioPlayerObserver)
```

**Use Case Validation:**
- ✅ Observer pattern for event notifications (playback state, progress, errors)
- ✅ Standard SDK design (developers expect this pattern)

**Decision:** Keep both methods.

---

## ⚠️ Category 6: Overlay Player (9 methods)

### KEEP: 7 methods | REFACTOR: 2 methods | REMOVE: 1 getter

```swift
public func playOverlay(_ url: URL) async throws
public func playOverlay(_ track: Track) async throws
public func setOverlayConfiguration(_ configuration: OverlayConfiguration) async throws
public func getOverlayConfiguration() async -> OverlayConfiguration?  // ❓ REMOVE?
public func stopOverlay() async
public func pauseOverlay() async
public func resumeOverlay() async
public func setOverlayVolume(_ volume: Float) async
public func setOverlayLoopMode(_ mode: OverlayConfiguration.LoopMode) async throws  // 🔄 REFACTOR
public func setOverlayLoopDelay(_ delay: TimeInterval) async throws                 // 🔄 REFACTOR
```

**Use Case Validation:**
- ✅ `playOverlay(url/track)` → Stage 2: MANY mantra switches (critical!)
- ✅ `setOverlayConfiguration()` → Setup before play (loop mode, delay, volume)
- ❓ `getOverlayConfiguration()` → **Rarely used.** Can be property getter instead of async method
- ✅ `stopOverlay()` → End overlay playback
- ✅ `pauseOverlay()` → Independent pause (validated)
- ✅ `resumeOverlay()` → Resume overlay independently
- ✅ `setOverlayVolume()` → Runtime volume adjustment
- 🔄 `setOverlayLoopMode()` → NOT duplicate! Runtime loop mode change (during playback)
- 🔄 `setOverlayLoopDelay()` → NOT duplicate! Runtime delay change

**Naming Issue:**
- `setOverlayLoopMode()` + `setOverlayLoopDelay()` names suggest "set config property"
- Reality: **Runtime adjustments** during playback (not initial setup)

**Better Names:**
```swift
// BEFORE (confusing):
public func setOverlayLoopMode(_ mode: OverlayConfiguration.LoopMode) async throws
public func setOverlayLoopDelay(_ delay: TimeInterval) async throws

// AFTER (clear intent):
public func updateOverlayLoopMode(_ mode: OverlayConfiguration.LoopMode) async throws
public func updateOverlayLoopDelay(_ delay: TimeInterval) async throws
```

**Decision:**
- **RENAME:** `setOverlayLoopMode()` → `updateOverlayLoopMode()`
- **RENAME:** `setOverlayLoopDelay()` → `updateOverlayLoopDelay()`
- **REMOVE:** `getOverlayConfiguration()` → Replace with property `public private(set) var overlayConfiguration: OverlayConfiguration?`
- **KEEP:** All other 7 methods
- **Total:** -1 method + 2 renames (9 → 8 methods, clearer semantics)

---

## ✅ Category 7: Global Control (3 methods)

### KEEP ALL - Critical for morning routine

```swift
public func pauseAll() async
public func resumeAll() async
public func stopAll() async
```

**Use Case Validation:**
- ✅ `pauseAll()` → Morning routine global pause (main + overlay + effects) - **CRITICAL!**
- ✅ `resumeAll()` → Resume all after interruption
- ✅ `stopAll()` → Emergency stop (validated)

**Decision:** Keep all 3 methods. Critical for use case.

---

## ✅ Category 8: Sound Effects (5 methods)

### KEEP ALL - Validated for meditation

```swift
public func preloadSoundEffects(_ effects: [SoundEffect]) async
public func playSoundEffect(_ effect: SoundEffect, fadeDuration: TimeInterval = 0.0) async
public func stopSoundEffect(fadeDuration: TimeInterval = 0.0) async
public func setSoundEffectVolume(_ volume: Float) async
public func unloadSoundEffects(_ effects: [SoundEffect]) async
```

**Use Case Validation:**
- ✅ `preloadSoundEffects()` → Preload gongs/bells for stage transitions
- ✅ `playSoundEffect()` → Play gong/bell at transition moment
- ✅ `stopSoundEffect()` → Stop currently playing effect
- ✅ `setSoundEffectVolume()` → Runtime volume control
- ✅ `unloadSoundEffects()` → Memory cleanup after session

**Decision:** Keep all 5 methods.

---

## 📊 API Cleanup Summary

### Before Cleanup: 38 methods
### After Cleanup: 35 methods

**Changes:**

1. **REMOVED (3 methods):**
   - ❌ `replacePlaylist(_ tracks: [Track])` → duplicate of loadPlaylist
   - ❌ `replacePlaylist(_ tracks: [URL])` → duplicate of loadPlaylist
   - ❌ `getOverlayConfiguration()` → replace with property

2. **RENAMED (2 methods) - Better semantics:**
   - 🔄 `setOverlayLoopMode()` → `updateOverlayLoopMode()`
   - 🔄 `setOverlayLoopDelay()` → `updateOverlayLoopDelay()`

3. **CONSIDER INTERNAL (1 method):**
   - ⚠️ `seek(to:fadeDuration:)` → used internally by skip methods, rarely needed publicly

**Net Result:** -3 methods, +2 clarity improvements

---

## 🎯 Final API Count: 35 Public Methods

### By Category:
1. Core Playback: 7 methods ✅
2. Playback Control: 2 methods (seek considered internal) ✅
3. Configuration: 2 methods ✅
4. Playlist Management: 4 methods (-2 duplicates) ✅
5. Observer Pattern: 2 methods ✅
6. Overlay Player: 8 methods (-1 getter, +2 renames) ✅
7. Global Control: 3 methods ✅
8. Sound Effects: 5 methods ✅

**Total:** 35 methods (was 38)

---

## 🚀 Implementation Plan

### Phase 1: Remove Duplicates
- [ ] Remove `replacePlaylist(_ tracks: [Track])`
- [ ] Remove `replacePlaylist(_ tracks: [URL])`
- [ ] Update tests/examples that use replacePlaylist → loadPlaylist

### Phase 2: Refactor Overlay Methods
- [ ] Rename `setOverlayLoopMode()` → `updateOverlayLoopMode()`
- [ ] Rename `setOverlayLoopDelay()` → `updateOverlayLoopDelay()`
- [ ] Remove `getOverlayConfiguration()` async method
- [ ] Add `public private(set) var overlayConfiguration: OverlayConfiguration?`

### Phase 3: Consider Internal API
- [ ] Evaluate `seek()` usage in SDK integrations
- [ ] If unused: make internal (prefix with underscore or move to internal extension)

### Phase 4: Documentation
- [ ] Update public API documentation
- [ ] Add code examples for 3-stage meditation use case
- [ ] Document stop vs finish semantics
- [ ] Document skipToNext/Previous circular navigation

---

## ✅ Validation Against Requirements

**3-Stage Meditation Session (30 min):**
- ✅ Stage 1 (5 min): `loadPlaylist()` → `startPlaying()` → background music + overlay instructions + effects
- ✅ Stage 2 (20 min): `skipToNext()` or `loadPlaylist()` → MANY `playOverlay()` switches + effects
- ✅ Stage 3 (5 min): `skipToNext()` or `loadPlaylist()` → calming music + overlay guidance + effects
- ✅ Morning pause: `pauseAll()` → daily occurrence (CRITICAL!)
- ✅ Phone call: Auto `pauseAll()` → auto `resumeAll()` after interruption
- ✅ Session complete: `finish()` → cleanup and exit

**API Coverage: 100%** ✅

---

**Decision Status:** Ready for implementation  
**Next Steps:** Execute Phase 1-4 implementation plan
