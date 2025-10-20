# ProsperPlayer 🎵

> Modern audio player SDK for iOS with advanced playback features, overlay audio system, sound effects, and production-grade stability

## 🚀 Quick Start

```swift
// Initialize service (setup is automatic!)
let service = try await AudioPlayerService()

// Configure playback
let config = PlayerConfiguration(
    crossfadeDuration: 10.0,
    volume: 0.8,  // 0.0-1.0
    repeatMode: .playlist
)

// Start playlist playback
try await service.loadPlaylist(trackURLs, configuration: config)

// Control playback
try await service.pause()
try await service.resume()
try await service.skipToNext()
try await service.skip(forward: 15.0)

// Overlay audio (ambient sounds, voiceovers)
let overlayConfig = OverlayConfiguration.ambient
try await service.playOverlay(url: rainURL, configuration: overlayConfig)

// Sound effects
let bell = SoundEffect(url: bellURL, volume: 0.8)
await service.preloadSoundEffects([bell])
await service.playSoundEffect(bell)
```

## 🎯 Key Features

### Audio Playback
- ✅ High-quality audio with AVAudioEngine (8192-sample buffers for stability)
- ✅ Dual-player crossfade architecture with Equal-Power algorithm
- ✅ **Playlist management** with auto-advance and cyclic navigation
- ✅ 5 fade curve types (Equal-Power, Linear, Logarithmic, Exponential, S-Curve)
- ✅ Loop playback with seamless crossfade
- ✅ **Production-grade stability** (optimized for Bluetooth/AirPods)
- ✅ Type-safe `Track` model

### Overlay Audio System
- ✅ **Independent audio layer** - plays alongside main track
- ✅ **Unified API** - `playOverlay()` for start/replace operations
- ✅ **Dynamic configuration** - adjust volume and loop settings in runtime
- ✅ **Configurable delays** - adjust timing between iterations (0-30s)
- ✅ **Preset configurations** - `.default`, `.ambient`, `.bell()`

### Sound Effects 🆕
- ✅ **LRU cache** - auto-manages up to 10 effects
- ✅ **Instant playback** - <5ms latency for preloaded effects
- ✅ **Master volume** - adjust all effects without reload
- ✅ **Batch operations** - preload/unload multiple effects
- ✅ **Auto-preload** - smart loading with warnings

### Platform Integration
- ✅ Swift 6 strict concurrency compliance
- ✅ Background audio & Lock Screen controls
- ✅ Skip forward/backward (±15s)
- ✅ Click-free seek with fade
- ✅ Advanced AudioSession configuration (minimizes interruptions)

## 🏗️ Architecture

```
┌─────────────────────────────────────────┐
│      AudioPlayerService (Actor)         │
│  - State management                     │
│  - Playlist logic                       │
│  - Overlay coordination                 │
│  - Sound effects management             │
│  - Public API                           │
│  - Observer pattern                     │
└────────────┬────────────────────────────┘
             │
     ┌───────┴────────┬──────────────┐
     │                │              │
┌────▼────────┐  ┌───▼──────────┐  ┌▼──────────────┐
│AudioEngine  │  │PlaylistMgr   │  │SoundEffects   │
│Actor        │  │(Actor)       │  │Actor 🆕       │
│             │  │              │  │               │
│- Dual-player│  │- Track queue │  │- LRU cache    │
│- Crossfade  │  │- Auto-advance│  │- Master vol   │
│- Buffers    │  │- Navigation  │  │- Batch ops    │
│- Overlay ✨ │  └──────────────┘  └───────────────┘
└─────────────┘
      │
      └──► OverlayPlayerActor
           - Independent lifecycle
           - Loop with delay
           - Configurable fades
           - Volume control
```

**Design principles:**
- Actor isolation (Swift 6 data race prevention)
- Dual-player pattern (seamless crossfades)
- Sample-accurate synchronization (AVAudioTime)
- Equal-Power algorithm (constant perceived loudness)
- **Large buffers** (8192 samples) for Bluetooth stability
- SDK-level playlist management
- **Singleton AudioSession** (shared across all player instances)

### Multiple Instances Support 🆕

You can create multiple `AudioPlayerService` instances with different configurations:

```swift
// Component 1: Meditation player
let meditationPlayer = try await AudioPlayerService()
let config1 = PlayerConfiguration(crossfadeDuration: 10.0, volume: 0.8)
try await meditationPlayer.loadPlaylist(meditationTracks, configuration: config1)

// Component 2: Music player
let musicPlayer = try await AudioPlayerService()
let config2 = PlayerConfiguration(crossfadeDuration: 5.0, volume: 1.0)
try await musicPlayer.loadPlaylist(musicTracks, configuration: config2)
```

**How it works:**
- `AudioSessionManager` is a **singleton** (shared across all instances)
- AVAudioSession is configured **once globally** (first instance wins)
- Each player has its own state, playlist, and audio engine
- **No manual setup() needed** - initialization is automatic!

## 🛠️ Tech Stack

- **Language**: Swift 6.0
- **UI Framework**: SwiftUI
- **Concurrency**: Swift Concurrency (async/await, actors)
- **Audio**: AVFoundation (AVAudioEngine, AVAudioSession)
- **Package Manager**: Swift Package Manager
- **Platform**: iOS 15+

## 📦 Modules

### AudioServiceCore
Core domain models and protocols:
- `PlayerConfiguration` - Immutable playback configuration
- `OverlayConfiguration` - Overlay audio settings (loop, delay, fades)
- `Track` 🆕 - Type-safe track model
- `SoundEffect` 🆕 - Sound effect descriptor
- `AudioPlayerError` - Error types
- `PlayerState` / `OverlayState` - State machine states

### AudioServiceKit
Main implementation:
- `AudioPlayerService` - Public API (actor-isolated)
- `PlaylistManager` - Playlist management
- `AudioEngineActor` - AVAudioEngine wrapper with enhanced stability
- `OverlayPlayerActor` - Independent overlay audio system
- `SoundEffectsPlayerActor` 🆕 - Sound effects with LRU cache
- `AudioSessionManager` - Advanced session configuration
- `RemoteCommandManager` - Lock Screen controls

## 🚦 Installation

### Requirements

- Xcode 15.0+
- iOS 15.0+
- Swift 6.0+
- **Physical device recommended** for audio testing (especially Bluetooth)

### Swift Package Manager

```swift
dependencies: [
    .package(url: "https://github.com/VasilyPolyuhovich/ProsperPlayer.git", branch: "main")
]
```

### Manual

```bash
git clone [repository-url]
cd ProsperPlayer
swift build
```

## 📚 Examples

### Basic Playlist

```swift
let service = try await AudioPlayerService()

let config = PlayerConfiguration(
    crossfadeDuration: 10.0,
    fadeCurve: .equalPower,
    repeatMode: .playlist,
    volume: 0.8  // 0.0-1.0
)

// Load with URLs
try await service.loadPlaylist(trackURLs, configuration: config)

// Or load with Track models (type-safe)
let tracks = trackURLs.map { Track(url: $0) }
try await service.loadPlaylist(tracks, configuration: config)
```

### Overlay Audio (Ambient Sounds)

```swift
// Start continuous rain sound
let config = OverlayConfiguration.ambient  // Infinite loop, 30% volume
try await service.playOverlay(url: rainURL, configuration: config)

// Or with Track model
let rainTrack = Track(url: rainURL)
try await service.playOverlay(rainTrack, configuration: config)

// Adjust settings in runtime
await service.setOverlayVolume(0.5)
await service.setOverlayConfiguration(.default)

// Replace with ocean sound (reuses configuration)
try await service.playOverlay(url: oceanURL)

// Stop overlay (main track continues)
await service.stopOverlay()
```

### Timer Bell (Periodic Sound)

```swift
// Bell rings 3 times with 5-minute intervals
let config = OverlayConfiguration.bell(times: 3, interval: 300)
try await service.playOverlay(url: bellURL, configuration: config)

// Timeline:
// 0:00  → fadeIn → DING → fadeOut → [5 min silence]
// 5:00  → fadeIn → DING → fadeOut → [5 min silence]
// 10:00 → fadeIn → DING → fadeOut
```

### Sound Effects 🆕

```swift
// Create sound effects
let bell = SoundEffect(url: bellURL, volume: 1.0, fadeIn: 0.1, fadeOut: 0.3)
let gong = SoundEffect(url: gongURL, volume: 1.0, fadeIn: 0.1, fadeOut: 0.3)

// Batch preload (recommended)
await service.preloadSoundEffects([bell, gong])

// Play instantly (<5ms latency)
await service.playSoundEffect(bell, fadeDuration: 0.1)

// Master volume control (no reload needed!)
await service.setSoundEffectVolume(0.5)  // 50% of original volume

// Manual cleanup (optional - LRU handles this)
await service.unloadSoundEffects([bell])
```

### Track Navigation

```swift
// Auto-advance enabled by default
// Manual navigation:
try await service.skipToNext()     // Cyclic (wraps to first)
try await service.skipToPrevious() // Cyclic (wraps to last)

// Skip within track
try await service.skip(forward: 15.0)
try await service.skip(backward: 15.0)

// Seek with fade
try await service.seek(to: 60.0, fadeDuration: 0.5)
```

### State Observation

```swift
actor Observer: AudioPlayerObserver {
    func playerStateDidChange(_ state: PlayerState) async {
        print("State: \(state)")
    }

    func playbackPositionDidUpdate(_ position: PlaybackPosition) async {
        print("Position: \(position.currentTime)")
    }
}

await service.addObserver(Observer())
```

## 🎮 Full API Reference

### Playlist Management

```swift
// Load playlist
try await service.loadPlaylist([url1, url2, url3], configuration: config)
try await service.loadPlaylist([track1, track2], configuration: config)

// Replace playlist
try await service.replacePlaylist([url4, url5])
try await service.replacePlaylist([track4, track5])

// Query
let playlist = await service.playlist  // Property, not getter!
```

### Playback Control

```swift
try await service.startPlaying(fadeDuration: 3.0)
try await service.pause()
try await service.resume()
await service.stop(fadeDuration: 3.0)  // Non-optional parameter
```

### Navigation

```swift
try await service.skipToNext()
try await service.skipToPrevious()
try await service.skip(forward: 15.0)
try await service.skip(backward: 15.0)
try await service.seek(to: position, fadeDuration: 0.5)
```

### Configuration

```swift
await service.setVolume(0.8)
let repeatMode = await service.repeatMode  // Property
let repeatCount = await service.repeatCount // Property
```

### Overlay API

```swift
// Start/Replace (unified API)
try await service.playOverlay(url: URL, configuration: OverlayConfiguration)
try await service.playOverlay(track: Track, configuration: OverlayConfiguration)
await service.stopOverlay(fadeDuration: 1.0)

// Playback control
await service.pauseOverlay()
await service.resumeOverlay()

// Dynamic configuration
await service.setOverlayVolume(0.5)
await service.setOverlayConfiguration(.ambient)
await service.setOverlayLoopDelay(10.0)

// Query
let state = await service.overlayState  // Property
let config = await service.getOverlayConfiguration()
```

### Sound Effects API 🆕

```swift
// Batch preload
await service.preloadSoundEffects([effect1, effect2, effect3])

// Play (auto-preloads if not in cache)
await service.playSoundEffect(effect, fadeDuration: 0.1)

// Stop current
await service.stopSoundEffect(fadeDuration: 0.3)

// Master volume (dynamic, no reload!)
await service.setSoundEffectVolume(0.7)

// Manual cleanup
await service.unloadSoundEffects([effect1, effect2])

// Query
let current = await service.currentSoundEffect  // Property
```

### Global Control

```swift
// Pause/Resume main + overlay + sound effects
await service.pauseAll()
await service.resumeAll()

// Emergency stop
await service.stopAll()
```

## 🎛️ Audio Stability Configuration

ProsperPlayer includes production-grade audio stability optimizations:

### Advanced AudioSession Setup
```swift
// Automatically configured by AudioSessionManager:
- preferredIOBufferDuration: 20ms (smooth, low-latency)
- preferredSampleRate: 44100 Hz (avoid resampling)
- prefersNoInterruptionsFromSystemAlerts: true (iOS 14.5+)
- Validation warnings for hardware mismatches
```

### Larger Audio Buffers
- **8192 samples** (186ms at 44.1kHz) - prevents artifacts with:
  - Bluetooth headphones / AirPods
  - Heavy UI operations (scrolling, animations)
  - System load and multi-app audio conflicts

### Trade-offs
- **Latency**: +93ms vs smaller buffers (acceptable for meditation/ambient apps)
- **Stability**: Zero audio artifacts under normal conditions
- **CPU Usage**: Minimal increase (<1%)

## 🧪 Testing

**Run tests on physical device recommended** (simulator lacks full audio support):

```bash
# Run all tests
swift test

# Run specific test
swift test --filter AudioPlayerServiceTests

# With Thread Sanitizer
swift test -Xswiftc -sanitize=thread
```

**Manual Testing:**
1. Open `Examples/ProsperPlayerDemo`
2. Run on **physical iOS device**
3. Test with **Bluetooth headphones** / AirPods
4. Verify zero audio artifacts during:
   - Heavy UI scrolling
   - App switching
   - Phone calls (interruption handling)
   - System alerts

## 📊 Performance

### Memory Footprint

- Single track: ~10MB (typical 5min @ 128kbps)
- During crossfade: ~20MB (dual-player)
- With overlay: ~30MB (triple-player)
- Sound effects cache: ~5-50MB (10 effects max)
- Post-crossfade: ~10MB (old track released)

### Sound Effects Performance 🆕

- Preloaded latency: <5ms (instant)
- Auto-preload latency: 50-200ms (disk read)
- LRU cache: 10 effects (configurable)
- Memory per effect: ~50-500KB (depends on duration)

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 📮 Contact

- Issues: [GitHub Issues](https://github.com/VasilyPolyuhovich/ProsperPlayer/issues)

## 🙏 Acknowledgments

- Equal-Power crossfade algorithm based on AES standards
- Swift 6 strict concurrency patterns
- AVFoundation best practices (WWDC 2014-2024)
- Audio stability optimizations based on production feedback

---

## 🔄 Migration to v4.1.4

### Breaking Changes

#### Async Throws Initialization

**v4.1.1-4.1.3**:
```swift
let player = AudioPlayerService()
```

**v4.1.4**:
```swift
let player = try await AudioPlayerService()
```

**Why?** Proper error propagation from audio engine setup. If stereo format creation fails, you'll now receive a clear error instead of silent failure.

**Migration steps:**

1. **Add `try await` to all AudioPlayerService initializations:**
```swift
// Before
let audioService = AudioPlayerService()

// After
let audioService = try await AudioPlayerService()
```

2. **Update dependency injection containers:**
```swift
// Before (Factory DI)
var audioPlayerService: Factory<AudioPlayerService> {
    self { AudioPlayerService() }
}

// After
@MainActor
func createAudioPlayerService() async throws -> AudioPlayerService {
    try await AudioPlayerService(configuration: .default)
}
```

3. **Handle errors in SwiftUI:**
```swift
struct ContentView: View {
    @State private var audioService: AudioPlayerService?
    @State private var error: Error?
    
    var body: some View {
        if let audioService = audioService {
            PlayerView(audioService: audioService)
        } else if let error = error {
            ErrorView(error: error)
        } else {
            ProgressView()
                .task {
                    do {
                        audioService = try await AudioPlayerService()
                    } catch {
                        self.error = error
                    }
                }
        }
    }
}
```

#### Audio Routing Fix

**What changed:** Added `.defaultToSpeaker` to default audio session options.

**Impact:** Audio now plays through **loudspeaker** instead of **ear speaker** when using `.playAndRecord` category.

**No migration needed** - this fix is automatic!

---

## 🔄 Migration from v4.1.0 to v4.1.1

### Breaking Changes

#### 1. No Manual `setup()` Required

**OLD (v4.1.0)**:
```swift
let player = AudioPlayerService()
await player.setup()  // ❌ Required manual call
try await player.loadPlaylist(tracks, configuration: config)
```

**v4.1.1**:
```swift
let player = AudioPlayerService()
// ✅ No setup() needed - automatic!
try await player.loadPlaylist(tracks, configuration: config)
```

**NEW (v4.1.4)**:
```swift
let player = try await AudioPlayerService()
// ✅ Async throws init with proper error handling
try await player.loadPlaylist(tracks, configuration: config)
```

**Migration**: Simply remove all `await service.setup()` calls from your code.

---

#### 2. Multiple Instances Now Supported

**Problem in v4.1.0**: Creating multiple instances caused error -50.

**Fixed in v4.1.1**:
```swift
// Both instances work correctly now!
let player1 = try await AudioPlayerService()
let player2 = try await AudioPlayerService()  // ✅ No error!

// Each with different configurations
try await player1.loadPlaylist(tracks1, configuration: config1)
try await player2.loadPlaylist(tracks2, configuration: config2)
```

**How it works**:
- `AudioSessionManager` is now a singleton (shared globally)
- AVAudioSession configured once (first instance wins)
- Each player has independent state and playlist

---

#### 3. AudioSession Options Conflicts

⚠️ **Important**: If different instances use different `audioSessionOptions`, the first one wins:

```swift
// Player 1 - sets options
let config1 = PlayerConfiguration(
    audioSessionOptions: [.mixWithOthers, .duckOthers]
)
try await player1.loadPlaylist(tracks1, configuration: config1)  // ✅ Applied

// Player 2 - different options
let config2 = PlayerConfiguration(
    audioSessionOptions: []  // ⚠️ Ignored! Player1's options used
)
try await player2.loadPlaylist(tracks2, configuration: config2)
// Console: [AudioSession] ⚠️ WARNING: Attempting to reconfigure with different options!
```

**Best Practice**: Use same options for all instances:
```swift
let sharedOptions: [AVAudioSession.CategoryOptions] = [.mixWithOthers, .duckOthers]
let config1 = PlayerConfiguration(audioSessionOptions: sharedOptions)
let config2 = PlayerConfiguration(audioSessionOptions: sharedOptions)
```

---

## 🆕 What's New in v4.1.4

### Error Handling
- **Throwing initialization** - `AudioPlayerService.init()` now `async throws`
- **Proper error propagation** - audio engine setup errors are caught and reported
- **Clear error messages** - `AudioPlayerError.engineStartFailed` with detailed reasons
- **No silent failures** - stereo format creation errors are visible

### Audio Routing Fix
- **Loudspeaker routing** - added `.defaultToSpeaker` option
- **Correct speaker selection** - uses loudspeaker (music) instead of ear speaker (calls)
- **Better audio quality** - proper volume levels with `.playAndRecord` category

---

## 🆕 What's New in v4.1

### Sound Effects System
- **LRU cache** with automatic management (10 effects limit)
- **Master volume control** - adjust all effects instantly without reload
- **Batch operations** - preload/unload multiple effects at once
- **Auto-preload** - smart loading with console warnings
- **Instant playback** - <5ms latency for preloaded effects

### API Improvements
- **Unified Overlay API** - `playOverlay()` replaces start/replace
- **Track model** - type-safe audio file handling
- **Properties** - `repeatMode`, `playlist`, `currentSoundEffect` instead of getters
- **Renamed methods** - `skip(forward:)`, `skip(backward:)`, `seek(to:fadeDuration:)`
- **Reduced API surface** - removed 15 deprecated methods (-25%)

### Bug Fixes
- Fixed telephone call interruption handling
- Fixed Bluetooth route change crashes (300ms debounce)
- Fixed media services reset position preservation
- Fixed AVAudioEngine overlay node crashes
- Fixed state oscillation during crossfade pause

---

**Version**: 4.1.4
**Platform**: iOS 15+
**Build**: [![Swift](https://img.shields.io/badge/Swift-6.0-orange.svg)](https://swift.org)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
