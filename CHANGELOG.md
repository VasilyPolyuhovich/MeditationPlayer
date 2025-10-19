# Changelog

All notable changes to ProsperPlayer will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
