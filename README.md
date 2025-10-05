# ProsperPlayer 🎵

> Modern audio player for macOS and iOS with advanced playback features

## 🚀 Quick Start

```swift
// Initialize service
let service = AudioPlayerService()
await service.setup()

// Configure playback
let config = AudioConfiguration(
    crossfadeDuration: 10.0,
    fadeInDuration: 3.0,
    enableLooping: true
)

// Start playback
try await service.startPlaying(url: audioURL, configuration: config)

// Control playback
try await service.pause()
try await service.resume()
try await service.skipForward(by: 15.0)
```

## 🎯 Key Features

- ✅ High-quality audio playback with AVAudioEngine
- ✅ Dual-player crossfade architecture
- ✅ 5 fade curve types (Equal-Power, Linear, Logarithmic, Exponential, S-Curve)
- ✅ Loop playback with seamless crossfade
- ✅ Swift 6 strict concurrency compliance
- ✅ Background audio & Lock Screen controls
- ✅ Skip forward/backward (±15s)

## 🏗️ Architecture

```
┌─────────────────────────────────────────┐
│      AudioPlayerService (Actor)         │
│  - State management                     │
│  - Public API                           │
│  - Observer pattern                     │
└────────────┬────────────────────────────┘
             │
     ┌───────┴────────┐
     │                │
┌────▼────────┐  ┌───▼──────────────┐
│AudioEngine  │  │AudioSession      │
│Actor        │  │Manager (Actor)   │
│             │  │                  │
│- Dual-player│  │- AVAudioSession  │
│- Crossfade  │  │- Interruptions   │
│- Buffers    │  │- Route changes   │
└─────────────┘  └──────────────────┘
```

**Design principles:**
- Actor isolation (Swift 6 data race prevention)
- Dual-player pattern (seamless crossfades)
- Sample-accurate synchronization (AVAudioTime)
- Equal-Power algorithm (constant perceived loudness)

See [Architecture Documentation](Documentation/01_Architecture.md) for details.

## 🛠️ Tech Stack

- **Language**: Swift 6.0
- **UI Framework**: SwiftUI
- **Concurrency**: Swift Concurrency (async/await, actors)
- **Audio**: AVFoundation (AVAudioEngine, AVAudioSession)
- **Package Manager**: Swift Package Manager
- **Platforms**: iOS 15+, macOS 12+

## 📦 Modules

### AudioServiceCore
Core domain models and protocols:
- `AudioConfiguration` - Playback configuration
- `AudioPlayerError` - Error types
- `PlayerState` - State machine states
- `SendableTypes` - Swift 6 Sendable types

### AudioServiceKit
Main implementation:
- `AudioPlayerService` - Public API (actor-isolated)
- `AudioEngineActor` - AVAudioEngine wrapper
- `RemoteCommandManager` - Lock Screen controls

## 🚦 Installation

### Requirements

- Xcode 15.0+
- iOS 15.0+ or macOS 12.0+
- Swift 6.0+

### Swift Package Manager

```swift
dependencies: [
    .package(url: "https://github.com/[your-org]/ProsperPlayer.git", from: "2.6.0")
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
| [API Reference](Documentation/02_API_Reference.md) | Complete API, examples, thread safety |
| [Crossfading](Documentation/03_Crossfading.md) | Equal-Power algorithm, synchronization |
| [Fade Curves](Documentation/04_Fade_Curves.md) | Mathematical analysis (5 curve types) |
| [Concurrency](Documentation/05_Concurrency.md) | Swift 6 patterns, actor isolation |
| [Configuration](Documentation/06_Configuration.md) | AudioConfiguration parameters |
| [Migration Guide](Documentation/07_Migration_Guide.md) | Version upgrade path |

### Examples

**Basic playback:**
```swift
let service = AudioPlayerService()
await service.setup()

try await service.startPlaying(
    url: audioURL,
    configuration: AudioConfiguration()
)
```

**Looping with crossfade:**
```swift
let config = AudioConfiguration(
    crossfadeDuration: 10.0,
    enableLooping: true,
    repeatCount: 5
)

try await service.startPlaying(url: audioURL, configuration: config)
```

**Track replacement:**
```swift
try await service.replaceTrack(
    url: newTrackURL,
    crossfadeDuration: 8.0
)
```

**State observation:**
```swift
actor Observer: AudioPlayerObserver {
    func playerStateDidChange(_ state: PlayerState) async {
        print("State: \(state)")
    }
}

await service.addObserver(Observer())
```

## 🧪 Testing

```bash
# Run all tests
swift test

# Run specific test
swift test --filter AudioPlayerServiceTests

# With Thread Sanitizer
swift test -Xswiftc -sanitize=thread
```

## 🤝 Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

**Development workflow:**
1. Fork repository
2. Create feature branch
3. Implement changes
4. Add tests
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

[To be added]

## 📮 Contact

- Issues: [GitHub Issues](https://github.com/[your-org]/ProsperPlayer/issues)
- Documentation: [Technical Docs](Documentation/)

## 🙏 Acknowledgments

- Equal-Power crossfade algorithm based on AES standards
- Swift 6 strict concurrency patterns
- AVFoundation best practices (WWDC 2014-2024)

---

**Version**: 2.6.0  
**Status**: Production Ready  
**Build**: [![Swift](https://img.shields.io/badge/Swift-6.0-orange.svg)](https://swift.org)
