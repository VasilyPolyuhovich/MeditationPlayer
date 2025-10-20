# Changelog

All notable changes to ProsperPlayer will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [4.1.3] - 2025-10-20

### Fixed
- **Critical**: Removed `setActive(false)` before `setCategory()` that caused error -50
- **Critical**: Removed duplicate `configure()` call in `startPlaying()` method
- Following Apple best practices: `setCategory()` can be called on active session

### Changed
- Added `force` parameter to `configure()` for media services reset scenario
- Singleton configure now idempotent - multiple calls safely ignored
- Media services reset uses `configure(force: true)` for clean reconfiguration

### Technical Details

**Root Cause of Error -50**:
```swift
// ❌ WRONG (caused -50):
try? session.setActive(false)  // Deactivates session
try session.setCategory(...)   // Can fail if other audio is active

// ✅ CORRECT (Apple recommended):
try session.setCategory(...)   // Works on active session!
try session.setActive(true)    // Then activate
```

**Removed Duplicate Configure**:
```swift
// Before (v4.1.2): configure() called TWICE
func setup() {
    try sessionManager.configure()  // ← First call
}

func startPlaying() {
    try sessionManager.configure()  // ← Second call (duplicate!)
}

// After (v4.1.3): configure() called ONCE
func setup() {
    try sessionManager.configure()  // ← Only here
}

func startPlaying() {
    try sessionManager.activate()   // ← Just activate
}
```

## [4.1.2] - 2025-10-20

### Fixed
- **Critical Race Condition**: Fixed race condition in `AudioSessionManager.configure()`
  - Problem: Two concurrent configure() calls could both pass guard check and both try to set AVAudioSession category → Error -50
  - Solution: Set `isConfigured = true` IMMEDIATELY after guard (atomic check-and-set)
  - Now guaranteed thread-safe even with concurrent initialization from multiple instances

### Technical Details
```swift
// Before (RACE CONDITION):
guard !isConfigured else { return }
try session.setCategory(...)  // ← Both tasks could reach here!
isConfigured = true  // ← Too late!

// After (ATOMIC):
guard !isConfigured else { return }
isConfigured = true  // ← Set IMMEDIATELY (atomic with guard)
try session.setCategory(...)  // ← Only first task reaches here
```

## [4.1.1] - 2025-10-20

### Added
- **Multiple Instances Support**: Create multiple `AudioPlayerService` instances with different configurations
- Automatic setup on first use - no need to call `setup()` manually
- Detailed logging for AudioSession configuration conflicts

### Changed
- **BREAKING**: `AudioSessionManager` is now a **singleton** (`AudioSessionManager.shared`)
- **BREAKING**: `setup()` is now `internal` and called automatically on first use
- AVAudioSession configured once globally (first instance wins)
- Observers setup moved to singleton initialization

### Fixed
- **Critical Bug**: Error -50 when creating multiple `AudioPlayerService` instances
- AudioSession configuration conflict detection and warnings
- Race condition in session manager initialization

### Migration Guide
```swift
// OLD (v4.1.0)
let player = AudioPlayerService()
await player.setup()  // ❌ Required manual call
try await player.loadPlaylist(tracks, configuration: config)

// NEW (v4.1.1)
let player = AudioPlayerService()
// ✅ No setup() needed - automatic!
try await player.loadPlaylist(tracks, configuration: config)

// Multiple instances now work correctly
let player1 = AudioPlayerService()
let player2 = AudioPlayerService()  // ✅ No error -50!
```

## [4.1.0] - 2025-10-19

### Added
- **Sound Effects Player** with LRU cache (10 effects limit)
- Batch operations: `preloadSoundEffects()`, `unloadSoundEffects()`
- Master volume control for sound effects
- `Track` model for type-safe audio handling
- Dynamic overlay volume control via `setOverlayVolume()`
- `SoundEffectsView` demo UI with 3 effects (bell, gong, countdown)
- New properties: `repeatMode`, `repeatCount`, `playlist`, `currentSoundEffect`, `overlayState`

### Changed
- **Unified Overlay API**: `playOverlay()` replaces `startOverlay()` and `replaceOverlay()`
- **Configuration API**: `setOverlayConfiguration()` for persistent overlay settings
- **Track Support**: `loadPlaylist()` and `replacePlaylist()` accept `[Track]` or `[URL]`
- **Renamed Methods**:
  - `skipForward(by:)` → `skip(forward:)`
  - `skipBackward(by:)` → `skip(backward:)`
  - `seekWithFade(to:fadeDuration:)` → `seek(to:fadeDuration:)`
- **Volume API**: Master volume control for sound effects (no per-effect reload needed)

### Removed
- 15 deprecated methods (reduced API surface by 25%)
- Duplicate methods: `stopWithDefaultFade()`, `stopImmediatelyWithoutFade()`
- Legacy methods: `replaceTrack()` (now internal)
- Old sound effects API: `playSoundEffect(id:)`, `unloadAllSoundEffects()`
- Getters replaced by properties: `getRepeatMode()`, `getPlaylist()`, etc.

### Fixed
- **Critical Bugs**:
  - Telephone call interruption handling
  - Bluetooth route change crashes (300ms debounce added)
  - Media services reset position preservation
  - AVAudioEngine overlay node crashes
- **High Priority**:
  - State oscillation during crossfade pause
  - Concurrent crossfade operations
  - `*All` methods state management (pauseAll, stopAll, resumeAll)
  - Swift 6 concurrency warnings
- **API Fixes**:
  - Stop fade bug (incorrect fade-out)
  - Protocol conformance issues
  - Observer pattern AnyObject constraint

### Technical
- LRU cache with auto-eviction for sound effects
- Instant playback (<5ms latency for preloaded effects)
- Master volume formula: `final = effect.volume × master.volume`
- Swift 6 strict concurrency compliance

## [4.0.0] - 2025-10-18

### Added
- **ProsperPlayerDemo** - Modern SwiftUI showcase replacing MeditationDemo
- Overlay player controls UI
- Volume fade settings
- Crossfade visualizer
- Advanced demo components (PlayerControls, PositionTracker, CrossfadeVisualizer)

### Changed
- **Major Refactoring**: Immutable `PlayerConfiguration`
- **Volume Type**: Changed from `Int` to `Float` (0.0-1.0 range)
- **Playlist Navigation**: New API for `skipToNext()` and `skipToPrevious()`
- **Demo Rename**: MeditationDemo → ProsperPlayerDemo (moved old to LEGACY/)

### Documentation
- Archived v4.0 working docs to `LEGACY/v4.0_working_docs/`
- Updated README with new examples
- Added comprehensive API documentation

## [2.11.0] - 2025-10-05

### Added
- **Initial Release**: Core audio player with crossfade support
- Playlist management with repeat modes (.once, .playlist, .track)
- Overlay player for ambient sounds and voiceovers
- Volume synchronization
- Configurable audio session options
- 5 fade curve types (Equal-Power, Linear, Logarithmic, Exponential, S-Curve)
- Swift 6 concurrency support
- AVAudioEngine-based architecture

### Features
- High-quality audio with 8192-sample buffers
- Dual-player crossfade architecture
- Seamless loop playback
- Remote control integration
- Audio session interruption handling
- Demo app with sample tracks
