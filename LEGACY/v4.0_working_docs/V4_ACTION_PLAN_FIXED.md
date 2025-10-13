# 🎯 ProsperPlayer v4.0 - FIXED ACTION PLAN

**Created:** 2025-10-12  
**Use Case:** Meditation Session Player (NOT universal music player!)

---

## 📋 Use Case - Meditation Session

### Structure:
```
Session has 3 Phases (Induction, Intentions, Returning)
Each Phase has MULTIPLE pre-made playlists to choose from
Each Playlist has MULTIPLE tracks that play with crossfade
Playlist loops infinitely with crossfade
```

### User Actions:
1. **Start session** → `startPlaying(fadeDuration: 2.0)` → plays first track with fade in
2. **Skip track** → `skipToNext()` → crossfade to next track in playlist
3. **Change playlist** → `swapPlaylist([track1, track2], crossfadeDuration: 5.0)` → crossfade to new playlist
4. **Stop session** → `stop(fadeDuration: 3.0)` → fade out both players, cancel crossfade

### What Users DON'T Need:
- ❌ addTrack/insertTrack/removeTrack (playlists are pre-made!)
- ❌ moveTrack (order is fixed!)
- ❌ jumpTo(index) (skipToNext is enough!)

---

## ✅ Correct Public API

```swift
// PLAYBACK CONTROL
func startPlaying(fadeDuration: TimeInterval = 0.0) async throws  // Start first track in current playlist
func stop(fadeDuration: TimeInterval = 0.0) async                  // Stop both players, cancel crossfade
func pause() async throws
func resume() async throws

// NAVIGATION IN TIME
func skipForward(by interval: TimeInterval = 15.0) async  // ±15s
func skipBackward(by interval: TimeInterval = 15.0) async

// NAVIGATION IN PLAYLIST
func skipToNext() async throws  // Next track in current playlist with crossfade

// PLAYLIST MANAGEMENT
func swapPlaylist(_ tracks: [URL], crossfadeDuration: TimeInterval = 5.0) async throws  // Change to new playlist
func getPlaylist() async -> [URL]  // Get current playlist

// CONFIGURATION
func getConfiguration() -> PlayerConfiguration
func updateConfiguration(_ config: PlayerConfiguration) async

// OVERLAY (separate layer)
func startOverlay(url: URL, configuration: OverlayConfiguration) async throws
func stopOverlay() async
// ... other overlay methods
```

---

## 🚀 PHASE 2: Fix Method Signatures

### 2.1 Check `startPlaying()` Signature

**Expected v4.0:**
```swift
func startPlaying(fadeDuration: TimeInterval = 0.0) async throws
```

**Behavior:**
1. Get first track from current playlist
2. Load on primary player
3. Start with fade in (0 → current volume)
4. Begin playback position timer
5. Transition to `.playing` state

**MCP Command:**
```javascript
get_symbol_definition({
  path: "Sources/AudioServiceKit/Public/AudioPlayerService.swift",
  symbolName: "startPlaying"
})
```

---

### 2.2 Check `stop()` Implementation

**Expected v4.0:**
```swift
func stop(fadeDuration: TimeInterval = 0.0) async
```

**Behavior:**
1. If crossfading → cancel crossfade task
2. Fade out active player (current volume → 0)
3. Stop inactive player (if exists)
4. Stop engine
5. Deactivate audio session
6. Clear now playing info
7. Transition to `.finished` state

**MCP Command:**
```javascript
get_symbol_definition({
  path: "Sources/AudioServiceKit/Public/AudioPlayerService.swift",
  symbolName: "stop"
})
```

---

### 2.3 Verify `skipToNext()` Exists

**Expected v4.0:**
```swift
func skipToNext() async throws
```

**Behavior:**
1. Get next track from PlaylistManager
2. If no next track → throw error
3. Use `replaceTrack()` with crossfade
4. Crossfade duration from configuration

**Check if exists:**
```javascript
search_in_file_lines({
  path: "Sources/AudioServiceKit/Public/AudioPlayerService.swift",
  pattern: "func skipToNext",
  limit: 10
})
```

**If missing - add:**
```swift
public func skipToNext() async throws {
    guard let nextURL = await playlistManager.skipToNext() else {
        throw AudioPlayerError.noNextTrack
    }
    try await replaceTrack(url: nextURL, crossfadeDuration: configuration.crossfadeDuration)
}
```

---

### 2.4 Verify `swapPlaylist()` Correct

**Expected v4.0:**
```swift
func swapPlaylist(_ tracks: [URL], crossfadeDuration: TimeInterval = 5.0) async throws
```

**Check current:**
```javascript
get_symbol_definition({
  path: "Sources/AudioServiceKit/Public/AudioPlayerService.swift",
  symbolName: "swapPlaylist"
})
```

**Should call:**
- `playlistManager.replacePlaylist(tracks)`
- `replaceTrack()` for crossfade to first track

---

## 🚀 PHASE 3: Fix Loop Crossfade

### 3.1 Fix `calculateAdaptedCrossfadeDuration()`

**Current (WRONG):**
```swift
let configuredFadeIn = configuration.fadeInDuration  // = crossfade * 0.3 ❌
let configuredFadeOut = configuration.crossfadeDuration * 0.7
```

**Fix to:**
```swift
let configuredCrossfade = configuration.crossfadeDuration  // Use full!
let maxCrossfade = trackDuration * 0.4
let adaptedCrossfade = min(configuredCrossfade, maxCrossfade)
return adaptedCrossfade
```

**MCP Command:**
```javascript
replace_lines({
  path: "Sources/AudioServiceKit/Public/AudioPlayerService.swift",
  startLine: 1092,
  endLine: 1110,
  newContent: `    private func calculateAdaptedCrossfadeDuration(trackDuration: TimeInterval) -> TimeInterval {
        // v4.0: Use full crossfadeDuration for loop
        let configuredCrossfade = configuration.crossfadeDuration
        let maxCrossfade = trackDuration * 0.4
        let adaptedCrossfade = min(configuredCrossfade, maxCrossfade)
        
        Self.logger.debug("Adapted crossfade: configured=\\(configuredCrossfade)s, track=\\(trackDuration)s, adapted=\\(adaptedCrossfade)s")
        
        return adaptedCrossfade
    }`,
  dryRun: true
})
```

---

### 3.2 Fix `loopCurrentTrackWithFade()` Log

**Current:**
```swift
let configuredFadeIn = configuration.fadeInDuration
let configuredFadeOut = configuration.crossfadeDuration * 0.7
Self.logger.info("[LOOP_CROSSFADE] Starting: configured=(\(configuredFadeIn)s,\(configuredFadeOut)s)")
```

**Fix to:**
```swift
let configuredCrossfade = configuration.crossfadeDuration
Self.logger.info("[LOOP_CROSSFADE] Starting: configured=\(configuredCrossfade)s, adapted=\(crossfadeDuration)s")
```

**MCP Command:**
```javascript
edit_file({
  path: "Sources/AudioServiceKit/Public/AudioPlayerService.swift",
  edits: [{
    oldText: `let configuredFadeIn = configuration.fadeInDuration
        let configuredFadeOut = configuration.crossfadeDuration * 0.7
        Self.logger.info("[LOOP_CROSSFADE] Starting loop crossfade: track=\\(trackDuration)s, configured=(\\(configuredFadeIn)s,\\(configuredFadeOut)s), adapted=\\(crossfadeDuration)s")`,
    newText: `let configuredCrossfade = configuration.crossfadeDuration
        Self.logger.info("[LOOP_CROSSFADE] Starting loop crossfade: track=\\(trackDuration)s, configured=\\(configuredCrossfade)s, adapted=\\(crossfadeDuration)s")`
  }],
  dryRun: true
})
```

---

## 🚀 PHASE 4: Update Documentation

### 4.1 Fix FEATURE_OVERVIEW_v4.0.md

**Section 5.1 - Update example:**

**Current:**
```swift
await player.loadPlaylist([
    inductionURL,    // Phase 1
    intentionsURL,   // Phase 2
    returningURL     // Phase 3
])
```

**Fix to:**
```swift
// Phase 1: Induction - choose from pre-made playlists
let inductionPlaylistA = [track1, track2, track3]
let inductionPlaylistB = [calm1, calm2]

// Start session with Playlist A
await player.swapPlaylist(inductionPlaylistA, crossfadeDuration: 5.0)
await player.startPlaying(fadeDuration: 2.0)

// Tracks play: track1 → crossfade → track2 → crossfade → track3 → loop
// User can skip: await player.skipToNext()
// Or change playlist: await player.swapPlaylist(inductionPlaylistB)
```

**Section 5.2 - Remove unnecessary operations:**

Delete:
```swift
// ❌ NOT NEEDED for meditation use case:
func addTrack(_ url: URL) async
func insertTrack(_ url: URL, at index: Int) async
func removeTrack(at index: Int) async throws
func moveTrack(from: Int, to: Int) async throws
func jumpTo(index: Int) async throws
```

Keep only:
```swift
// ✅ What meditation session needs:
func skipToNext() async throws  // Next track in playlist
func swapPlaylist(_ tracks: [URL], crossfadeDuration: TimeInterval) async throws
func getPlaylist() async -> [URL]
```

---

## 📝 Step-by-Step Execution

### Step 1: Verify Current State
```javascript
// 1. Check startPlaying
get_symbol_definition({
  path: "Sources/AudioServiceKit/Public/AudioPlayerService.swift",
  symbolName: "startPlaying"
})

// 2. Check stop
get_symbol_definition({
  path: "Sources/AudioServiceKit/Public/AudioPlayerService.swift",
  symbolName: "stop"
})

// 3. Check skipToNext exists
search_in_file_lines({
  path: "Sources/AudioServiceKit/Public/AudioPlayerService.swift",
  pattern: "func skipToNext",
  limit: 5
})

// 4. Check swapPlaylist
get_symbol_definition({
  path: "Sources/AudioServiceKit/Public/AudioPlayerService.swift",
  symbolName: "swapPlaylist"
})
```

### Step 2: Fix Loop Crossfade (Phase 3)
```javascript
// Fix calculateAdaptedCrossfadeDuration
replace_lines({
  path: "Sources/AudioServiceKit/Public/AudioPlayerService.swift",
  startLine: 1092,
  endLine: 1110,
  newContent: "...",  // See Phase 3.1
  dryRun: true
})

// Fix loopCurrentTrackWithFade log
edit_file({...})  // See Phase 3.2
```

### Step 3: Add Missing Methods (if needed)
```javascript
// If skipToNext missing:
insert_lines({
  path: "Sources/AudioServiceKit/Public/AudioPlayerService.swift",
  afterLine: 850,
  content: "public func skipToNext() async throws {...}"
})
```

### Step 4: Test & Commit
```bash
swift build  # Should succeed
swift test   # Should pass
```

```javascript
git_add({ files: ["Sources/AudioServiceKit/Public/AudioPlayerService.swift"] })
git_commit({ message: "feat: v4.0 - fix loop crossfade, simplify API for meditation use case" })
```

---

## ✅ Success Criteria

- [ ] `startPlaying(fadeDuration:)` starts first track from playlist
- [ ] `stop(fadeDuration:)` stops both players, cancels crossfade
- [ ] `skipToNext()` crossfades to next track in playlist
- [ ] `swapPlaylist()` crossfades to new playlist
- [ ] Loop uses full `crossfadeDuration` (not fadeIn/Out split)
- [ ] No unnecessary add/insert/remove/move methods exposed

---

## 🎯 Correct Understanding

**Meditation Session Player:**
- ✅ Pre-made playlists (multiple per phase)
- ✅ Swap between playlists with crossfade
- ✅ Tracks auto-play with crossfade
- ✅ Playlist loops with crossfade
- ✅ Simple navigation (skip to next track)

**NOT a Universal Music Player:**
- ❌ No manual playlist editing
- ❌ No random access (jumpTo)
- ❌ No shuffle
- ❌ Focus on structured meditation sessions

---

**Ready to start Phase 2 (Step 1)?** 🚀
