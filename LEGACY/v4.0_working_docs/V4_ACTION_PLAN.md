# 🎯 ProsperPlayer v4.0 - ACTIONABLE EXECUTION PLAN

**Created:** 2025-10-12  
**Status:** Ready to Execute  
**Goal:** Implement v4.0 API changes from FEATURE_OVERVIEW_v4.0.md

---

## 📋 Pre-Execution Checklist

- [x] Phase 1 done (compilation fix - commit 217c8fc)
- [ ] Phase 2: Add fade parameters to methods
- [ ] Phase 3: Fix loop crossfade logic  
- [ ] Phase 4: Expose playlist API (optional)
- [ ] Phase 5: Testing & verification

---

## 🚀 PHASE 2: Add Fade Parameters to Methods

### Goal
Add `fadeDuration` parameter to methods (per v4.0 FEATURE_OVERVIEW)

### 2.1 Fix `startPlaying()` - Add fadeDuration Parameter

**File:** `Sources/AudioServiceKit/Public/AudioPlayerService.swift`

**Current (Line ~141):**
```swift
public func startPlaying(url: URL, configuration: PlayerConfiguration) async throws
```

**Change to:**
```swift
public func startPlaying(fadeDuration: TimeInterval = 0.0) async throws
```

**Implementation:**
```swift
public func startPlaying(fadeDuration: TimeInterval = 0.0) async throws {
    // Validation
    guard fadeDuration >= 0 else {
        throw AudioPlayerError.invalidParameter("fadeDuration must be >= 0")
    }
    
    // Get current track from playlist
    guard let url = await playlistManager.getCurrentTrack() else {
        throw AudioPlayerError.noTrackLoaded
    }
    
    // Transition to preparing
    try await stateMachine.transition(to: .preparing)
    
    // Load audio file
    let trackInfo = try await audioEngine.loadAudioFile(url: url)
    currentTrack = trackInfo
    currentTrackURL = url
    
    // Configure audio session
    try await audioSessionManager.configureForPlayback()
    
    // Start playback
    if fadeDuration > 0 {
        // Start with fade in
        await audioEngine.setVolume(0.0)  // Start silent
        await audioEngine.startPlaying()
        await audioEngine.fadeVolume(from: 0.0, to: configuration.volumeFloat, duration: fadeDuration)
    } else {
        // Instant start
        await audioEngine.setVolume(configuration.volumeFloat)
        await audioEngine.startPlaying()
    }
    
    // Start playback position timer
    startPlaybackPositionTimer()
    
    // Transition to playing
    try await stateMachine.transition(to: .playing)
    
    // Update UI
    await updateNowPlayingInfo()
}
```

**MCP Command:**
```javascript
get_symbol_definition({
  path: "Sources/AudioServiceKit/Public/AudioPlayerService.swift",
  symbolName: "startPlaying"
})
// Read full implementation, then use edit_file to replace
```

---

### 2.2 Fix `stop()` - Fade Already Has Parameter ✅

**Check current implementation:**
```javascript
get_symbol_definition({
  path: "Sources/AudioServiceKit/Public/AudioPlayerService.swift", 
  symbolName: "stop"
})
```

**Expected (should already exist):**
```swift
public func stop(fadeDuration: TimeInterval = 0.0) async
```

✅ If already has parameter - SKIP  
❌ If missing - add parameter

---

### 2.3 Fix `finish()` - Update Signature

**File:** `Sources/AudioServiceKit/Public/AudioPlayerService.swift`

**Current (Line ~377):**
```swift
public func finish(fadeDuration: TimeInterval? = nil) async
```

**Keep as is** ✅ (already has optional fadeDuration)

**Just verify default logic uses crossfadeDuration:**
```swift
let duration = fadeDuration ?? configuration.crossfadeDuration
```

---

## 🚀 PHASE 3: Fix Loop Crossfade Logic

### Goal  
Loop should use full `crossfadeDuration`, not computed fadeInDuration

### 3.1 Fix `loopCurrentTrackWithFade()`

**File:** `Sources/AudioServiceKit/Public/AudioPlayerService.swift`  
**Line:** ~1209-1210

**Current (WRONG):**
```swift
let configuredFadeIn = configuration.fadeInDuration  // = crossfade * 0.3
let configuredFadeOut = configuration.crossfadeDuration * 0.7
```

**Change to:**
```swift
let configuredCrossfade = configuration.crossfadeDuration  // Use full crossfade!
```

**MCP Command:**
```javascript
edit_file({
  path: "Sources/AudioServiceKit/Public/AudioPlayerService.swift",
  edits: [{
    oldText: "let configuredFadeIn = configuration.fadeInDuration\n        let configuredFadeOut = configuration.crossfadeDuration * 0.7",
    newText: "let configuredCrossfade = configuration.crossfadeDuration"
  }],
  dryRun: true
})
```

**Update log message:**
```swift
// OLD:
Self.logger.info("[LOOP_CROSSFADE] Starting: configured=(\(configuredFadeIn)s,\(configuredFadeOut)s), adapted=\(crossfadeDuration)s")

// NEW:
Self.logger.info("[LOOP_CROSSFADE] Starting: configured=\(configuredCrossfade)s, adapted=\(crossfadeDuration)s")
```

---

### 3.2 Fix `calculateAdaptedCrossfadeDuration()`

**File:** `Sources/AudioServiceKit/Public/AudioPlayerService.swift`  
**Line:** ~1093-1110

**Current (WRONG):**
```swift
private func calculateAdaptedCrossfadeDuration(trackDuration: TimeInterval) -> TimeInterval {
    let configuredFadeIn = configuration.fadeInDuration  // WRONG
    let configuredFadeOut = configuration.crossfadeDuration * 0.7
    
    let maxFadeIn = min(configuredFadeIn, trackDuration * 0.4)
    let maxFadeOut = min(configuredFadeOut, trackDuration * 0.4)
    
    let actualFadeIn = maxFadeIn
    let actualFadeOut = maxFadeOut
    
    return max(actualFadeIn, actualFadeOut)
}
```

**Change to:**
```swift
private func calculateAdaptedCrossfadeDuration(trackDuration: TimeInterval) -> TimeInterval {
    // v4.0: Use single crossfadeDuration for loop
    let configuredCrossfade = configuration.crossfadeDuration
    
    // Adaptive scaling: max 40% of track duration
    let maxCrossfade = trackDuration * 0.4
    let adaptedCrossfade = min(configuredCrossfade, maxCrossfade)
    
    return adaptedCrossfade
}
```

**MCP Command:**
```javascript
replace_lines({
  path: "Sources/AudioServiceKit/Public/AudioPlayerService.swift",
  startLine: 1092,
  endLine: 1110,
  newContent: `    private func calculateAdaptedCrossfadeDuration(trackDuration: TimeInterval) -> TimeInterval {
        // v4.0: Use single crossfadeDuration for loop
        let configuredCrossfade = configuration.crossfadeDuration
        
        // Adaptive scaling: max 40% of track duration
        let maxCrossfade = trackDuration * 0.4
        let adaptedCrossfade = min(configuredCrossfade, maxCrossfade)
        
        Self.logger.debug("Adapted crossfade: configured=\\(configuredCrossfade)s, track=\\(trackDuration)s, adapted=\\(adaptedCrossfade)s")
        
        return adaptedCrossfade
    }`,
  dryRun: true
})
```

---

## 🚀 PHASE 4: Playlist API (OPTIONAL)

### Decision Required ⚠️

**Current state:**
- ✅ PlaylistManager has all methods (internal)
- ❌ AudioPlayerService exposes only minimal API (public)

**Options:**

**A) Expose All (Full Control)** ⭐ Recommended
```swift
// Add to AudioPlayerService:
public func addTrack(_ url: URL) async
public func insertTrack(_ url: URL, at index: Int) async  
public func removeTrack(at index: Int) async throws
public func moveTrack(from: Int, to: Int) async throws
public func jumpTo(index: Int) async throws
public func skipToNext() async throws
public func skipToPrevious() async throws
```

**B) Keep Minimal (As Is)**
```swift
// Only:
public func swapPlaylist(...) async throws
public func getPlaylist() async -> [URL]
```

**C) Add Most Important Only**
```swift
public func addTrack(_ url: URL) async
public func removeTrack(at index: Int) async throws
public func skipToNext() async throws
public func skipToPrevious() async throws
```

### Implementation (if choosing A or C):

**Template:**
```swift
// Add to AudioPlayerService.swift

public func addTrack(_ url: URL) async {
    await playlistManager.addTrack(url)
}

public func insertTrack(_ url: URL, at index: Int) async {
    await playlistManager.insertTrack(url, at: index)
}

public func removeTrack(at index: Int) async throws {
    guard await playlistManager.removeTrack(at: index) else {
        throw AudioPlayerError.invalidParameter("Invalid index: \(index)")
    }
}

public func skipToNext() async throws {
    guard let nextURL = await playlistManager.skipToNext() else {
        throw AudioPlayerError.noNextTrack
    }
    try await replaceTrack(url: nextURL, crossfadeDuration: configuration.crossfadeDuration)
}

public func skipToPrevious() async throws {
    guard let prevURL = await playlistManager.skipToPrevious() else {
        throw AudioPlayerError.noPreviousTrack
    }
    try await replaceTrack(url: prevURL, crossfadeDuration: configuration.crossfadeDuration)
}
```

**MCP Command (after user chooses):**
```javascript
insert_lines({
  path: "Sources/AudioServiceKit/Public/AudioPlayerService.swift",
  afterLine: 850, // After existing playlist methods
  content: `
    // MARK: - Playlist Navigation (v4.0)
    
    public func addTrack(_ url: URL) async {
        await playlistManager.addTrack(url)
    }
    
    // ... etc
  `,
  dryRun: true
})
```

---

## 🚀 PHASE 5: Testing & Verification

### 5.1 Compile Check
```bash
cd /Users/vasily/Projects/Helpful/ProsperPlayer
swift build
```

**Expected:** ✅ Build succeeds

### 5.2 Run Tests
```bash
swift test
```

**Expected:** ✅ All tests pass

### 5.3 Manual Testing (Demo App)

**Test scenarios:**
1. **Fade In:** `await player.startPlaying(fadeDuration: 2.0)` → smooth start
2. **Loop Crossfade:** repeatMode = .singleTrack → seamless loop
3. **Fade Out:** `await player.stop(fadeDuration: 3.0)` → smooth stop
4. **Playlist (if exposed):** skipToNext() → crossfade to next track

---

## 📝 Execution Commands (Step-by-Step)

### Step 1: Read Current Code
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

// 3. Check loopCurrentTrackWithFade
get_symbol_definition({
  path: "Sources/AudioServiceKit/Public/AudioPlayerService.swift",
  symbolName: "loopCurrentTrackWithFade"
})

// 4. Check calculateAdaptedCrossfadeDuration
get_symbol_definition({
  path: "Sources/AudioServiceKit/Public/AudioPlayerService.swift",
  symbolName: "calculateAdaptedCrossfadeDuration"
})
```

### Step 2: Implement Changes (After Reviewing)

**2A: Fix startPlaying (if missing fadeDuration)**
```javascript
edit_file({
  path: "Sources/AudioServiceKit/Public/AudioPlayerService.swift",
  edits: [{
    oldText: "public func startPlaying(url: URL, configuration: PlayerConfiguration) async throws",
    newText: "public func startPlaying(fadeDuration: TimeInterval = 0.0) async throws"
  }],
  dryRun: true
})
```

**2B: Fix loopCurrentTrackWithFade**
```javascript
edit_file({
  path: "Sources/AudioServiceKit/Public/AudioPlayerService.swift",
  edits: [{
    oldText: "let configuredFadeIn = configuration.fadeInDuration\n        let configuredFadeOut = configuration.crossfadeDuration * 0.7",
    newText: "let configuredCrossfade = configuration.crossfadeDuration"
  }],
  dryRun: true
})
```

**2C: Fix calculateAdaptedCrossfadeDuration**
```javascript
replace_lines({
  path: "Sources/AudioServiceKit/Public/AudioPlayerService.swift",
  startLine: 1092,
  endLine: 1110,
  newContent: "    private func calculateAdaptedCrossfadeDuration(trackDuration: TimeInterval) -> TimeInterval {\n        let configuredCrossfade = configuration.crossfadeDuration\n        let maxCrossfade = trackDuration * 0.4\n        let adaptedCrossfade = min(configuredCrossfade, maxCrossfade)\n        return adaptedCrossfade\n    }",
  dryRun: true
})
```

### Step 3: Verify & Commit
```javascript
// 1. Git status
git_status()

// 2. Git diff to review
git_diff({ file: "Sources/AudioServiceKit/Public/AudioPlayerService.swift" })

// 3. Run tests
// (manual: swift test)

// 4. Commit
git_add({ files: ["Sources/AudioServiceKit/Public/AudioPlayerService.swift"] })
git_commit({ message: "feat: v4.0 API - add fade parameters to methods, fix loop crossfade" })
```

---

## ✅ Success Criteria

- [ ] startPlaying() has `fadeDuration` parameter
- [ ] Loop uses full `crossfadeDuration` (not fadeInDuration)
- [ ] calculateAdaptedCrossfadeDuration simplified
- [ ] Code compiles without errors
- [ ] Tests pass
- [ ] Demo app works
- [ ] Changes committed

---

## 🚨 If Something Breaks

**Rollback:**
```javascript
git_restore({ files: ["Sources/AudioServiceKit/Public/AudioPlayerService.swift"] })
```

**Debug:**
```javascript
search_in_file_lines({
  path: "Sources/AudioServiceKit/Public/AudioPlayerService.swift",
  pattern: "fadeInDuration|singleTrack",
  useRegex: true,
  limit: 50
})
```

---

## 📞 Decision Points (Ask User)

1. **Playlist API:** Expose all (A), minimal (B), or important only (C)?
2. **startPlaying signature:** Remove `url` and `configuration` params? (they're redundant if playlist loaded)
3. **Breaking changes:** Mark old methods as `@available(*, deprecated)`?

---

**Start with:** Phase 2 (Step 1 - Read Current Code)  
**Next:** Make changes based on what we find  
**Last:** Test & commit

**Ready to execute? Say "start" and I'll begin with Step 1!** 🚀
