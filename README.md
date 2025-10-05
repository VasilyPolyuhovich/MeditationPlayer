# ProsperPlayer 🎵

> Modern audio player SDK for iOS with advanced playback features

## 🚀 Quick Start

```swift
// Initialize service
let service = AudioPlayerService()
await service.setup()

// Configure playback
let config = PlayerConfiguration(
    crossfadeDuration: 10.0,
    volume: 100,
    enableLooping: true
)

// Start playlist playback
try await service.loadPlaylist(trackURLs, configuration: config)

// Control playback
try await service.pause()
try await service.resume()
try await service.nextTrack()
try await service.skipForward(by: 15.0)
```

## 🎯 Key Features

- ✅ High-quality audio playback with AVAudioEngine
- ✅ Dual-player crossfade architecture
- ✅ **Playlist management** with auto-advance
- ✅ 5 fade curve types (Equal-Power, Linear, Logarithmic, Exponential, S-Curve)
- ✅ Loop playback with seamless crossfade
- ✅ Swift 6 strict concurrency compliance
- ✅ Background audio & Lock Screen controls
- ✅ Skip forward/backward (±15s)
- ✅ Click-free seek with fade

## 🏗️ Architecture

```
┌─────────────────────────────────────────┐
│      AudioPlayerService (Actor)         │
│  - State management                     │
│  - Playlist logic                       │
│  - Public API                           │
│  - Observer pattern                     │
└────────────┬────────────────────────────┘
             │
     ┌───────┴────────┐
     │                │
┌────▼────────┐  ┌───▼──────────────┐
│AudioEngine  │  │PlaylistManager   │
│Actor        │  │(Actor)           │
│             │  │                  │
│- Dual-player│  │- Track queue     │
│- Crossfade  │  │- Auto-advance    │
│- Buffers    │  │- Navigation      │
└─────────────┘  └──────────────────┘
```

**Design principles:**
- Actor isolation (Swift 6 data race prevention)
- Dual-player pattern (seamless crossfades)
- Sample-accurate synchronization (AVAudioTime)
- Equal-Power algorithm (constant perceived loudness)
- SDK-level playlist management

See [Architecture Documentation](Documentation/01_Architecture.md) for details.

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
- `PlayerConfiguration` - Simplified playback configuration
- `AudioPlayerError` - Error types
- `PlayerState` - State machine states
- `SendableTypes` - Swift 6 Sendable types

### AudioServiceKit
Main implementation:
- `AudioPlayerService` - Public API (actor-isolated)
- `PlaylistManager` - Playlist management
- `AudioEngineActor` - AVAudioEngine wrapper
- `RemoteCommandManager` - Lock Screen controls

## 🚦 Installation

### Requirements

- Xcode 15.0+
- iOS 15.0+
- Swift 6.0+
- **Physical device recommended** for audio testing

### Swift Package Manager

```swift
dependencies: [
    .package(url: "https://github.com/[your-org]/ProsperPlayer.git", from: "2.11.0")
]
```

### Manual

```bash
git clone [repository-url]
cd ProsperPlayer
swift build
```

## 📚 Documentation

### Technical Reference

| Document | Description |
|----------|-------------|
| [Architecture](Documentation/01_Architecture.md) | System design, actors, dual-player pattern |
| [API Reference](Documentation/02_API_Reference.md) | Complete API, playlist methods, thread safety |
| [Crossfading](Documentation/03_Crossfading.md) | Equal-Power algorithm, synchronization |
| [Fade Curves](Documentation/04_Fade_Curves.md) | Mathematical analysis (5 curve types) |
| [Concurrency](Documentation/05_Concurrency.md) | Swift 6 patterns, actor isolation |
| [Configuration](Documentation/06_Configuration.md) | PlayerConfiguration reference |
| [Migration Guide](Documentation/07_Migration_Guide.md) | Version upgrade path |

### Examples

**Playlist playback:**
```swift
let service = AudioPlayerService()
await service.setup()

let config = PlayerConfiguration(
    crossfadeDuration: 10.0,
    fadeCurve: .equalPower,
    enableLooping: true,
    volume: 100
)

try await service.loadPlaylist(trackURLs, configuration: config)
```

**Track navigation:**
```swift
// Auto-advance enabled by default
// Manual navigation:
try await service.nextTrack()
try await service.previousTrack()
try await service.jumpToTrack(at: 2)
```

**Single track looping:**
```swift
let config = PlayerConfiguration(
    crossfadeDuration: 10.0,
    enableLooping: true,
    repeatCount: 5  // Loop 5 times
)

try await service.loadPlaylist([trackURL], configuration: config)
```

**State observation:**
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

## 🎮 Playlist API

```swift
// Load and play playlist
try await service.loadPlaylist([url1, url2, url3], configuration: config)

// Add track to playlist
await service.addTrackToPlaylist(url4)

// Remove track
try await service.removeTrackFromPlaylist(at: 1)

// Jump to specific track
try await service.jumpToTrack(at: 2)

// Navigation
try await service.nextTrack()
try await service.previousTrack()

// Get current state
let tracks = await service.getCurrentPlaylist()
let index = await service.getCurrentTrackIndex()
```

## 🧪 Testing

**Run tests on physical device recommended** (simulator may lack audio access):

```bash
# Run all tests
swift test

# Run specific test
swift test --filter AudioPlayerServiceTests

# With Thread Sanitizer
swift test -Xswiftc -sanitize=thread
```

**Manual testing:**
1. Open `Examples/MeditationDemo`
2. Run on physical iOS device
3. Follow `TESTING_CHECKLIST_S10.md`

## 🤝 Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

**Development workflow:**
1. Fork repository
2. Create feature branch
3. Implement changes
4. Add tests (run on device)
5. Submit pull request

## 📊 Performance

### Crossfade Optimization (v2.6.0)

| Duration | Steps | CPU Usage | Improvement |
|----------|-------|-----------|-------------|
| 1s       | 100   | 1%        | Baseline    |
| 10s      | 300   | 3%        | 3.3× faster |
| 30s      | 600   | 6%        | **5× faster** |

### Memory Footprint

- Single track: ~10MB (typical 5min @ 128kbps)
- During crossfade: ~20MB (dual-player)
- Post-crossfade: ~10MB (old track released)

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 📮 Contact

- Issues: [GitHub Issues](https://github.com/[your-org]/ProsperPlayer/issues)
- Documentation: [Technical Docs](Documentation/)

## 🙏 Acknowledgments

- Equal-Power crossfade algorithm based on AES standards
- Swift 6 strict concurrency patterns
- AVFoundation best practices (WWDC 2014-2024)

---

**Version**: 2.11.0  
**Platform**: iOS 15+  
**Build**: [![Swift](https://img.shields.io/badge/Swift-6.0-orange.svg)](https://swift.org)
