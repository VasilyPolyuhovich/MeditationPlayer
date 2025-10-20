# Changelog

All notable changes to ProsperPlayer will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [4.1.2] - 2025-10-20

### Fixed
- **Critical**: Error -50 when app has other audio components (AVAudioPlayer, AVPlayer, etc.)
- Made `setPreferred*` calls non-throwing (safe to fail if session already configured)
- Added defensive check before `setCategory()` to skip if already correct
- Added detailed logging for session state before configuration

### Technical Details

**Problem**: Error -50 occurred when user's app already had other audio components that configured AVAudioSession before SDK initialization.

**Root Cause**:
1. `setPreferredIOBufferDuration()` fails if session already active
2. `setPreferredSampleRate()` fails if session already active
3. `setCategory()` can fail when setting same category redundantly

**Solution**:
```swift
// 1. Non-throwing preferences (safe to fail)
try? session.setPreferredIOBufferDuration(0.02)
try? session.setPreferredSampleRate(44100.0)

// 2. Defensive category check
let currentCategory = session.category
let currentOptions = session.categoryOptions

if currentCategory != .playback || currentOptions != categoryOptions {
    try session.setCategory(.playback, options: categoryOptions)
} else {
    print("Category already correct, skipping")
}
```

**Compatibility**: Now works seamlessly when app uses:
- AVAudioPlayer for sound effects
- AVPlayer for video playback
- Other audio SDKs
- Multiple AudioPlayerService instances

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
- Deprecated `deactivate()` method → renamed to `_internalDeactivateDeprecated()`
- Added `@available(*, deprecated)` warning to prevent future misuse
- Audio session stays active for all instances (shared singleton)
- Added `force` parameter to `configure()` for media services reset scenario

### Fixed
- **Critical**: Error -50 when creating multiple `AudioPlayerService` instances
- **Critical**: Race condition in `AudioSessionManager.configure()` with concurrent calls
- **Critical**: Removed all `deactivate()` calls from `stopImmediately()`, `reset()`, and `cleanup()`
- **Critical**: Singleton `deactivate()` no longer affects other `AudioPlayerService` instances
- Removed `setActive(false)` before `setCategory()` that caused error -50
- Removed duplicate `configure()` call in `startPlaying()` method
- Following Apple's AVAudioPlayer pattern: activate once, never deactivate

### Technical Details

**Problem 1**: Multiple Instances Error -50
```swift
// ❌ BEFORE (v4.1.0): Each instance created own session manager
let player1 = AudioPlayerService()  // Creates AudioSessionManager()
let player2 = AudioPlayerService()  // Creates AudioSessionManager() → Error -50!

// ✅ AFTER (v4.1.1): Singleton shared by all instances
let player1 = AudioPlayerService()  // Uses AudioSessionManager.shared
let player2 = AudioPlayerService()  // Uses AudioSessionManager.shared ✅
```

**Problem 2**: Race Condition in configure()
```swift
// ❌ BEFORE: Both tasks could pass guard
guard !isConfigured else { return }
try session.setCategory(...)  // Both reach here!
isConfigured = true  // Too late!

// ✅ AFTER: Atomic check-and-set
guard !isConfigured else { return }
isConfigured = true  // Set IMMEDIATELY
try session.setCategory(...)  // Only first task reaches here
```

**Problem 3**: Singleton Deactivation Affecting All Instances
```swift
// ❌ BEFORE: stop() deactivated shared session
let player1 = AudioPlayerService()  // Playing music
let player2 = AudioPlayerService()  // Playing voiceover
player2.stop()  // Calls deactivate() → BREAKS player1!

// ✅ AFTER: stop() never deactivates (Apple pattern)
player2.stop()  // Only stops player2, player1 keeps playing ✅
```

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
player1.stop()  // ✅ Doesn't affect player2!
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
