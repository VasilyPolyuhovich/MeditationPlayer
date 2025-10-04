# Prosper Player - iOS Audio Service

Modern, thread-safe audio player service for iOS 18+ built with Swift 6, AVAudioEngine, and strict concurrency.

## Features

✅ **Swift 6 Concurrency** - Actor-isolated design for data-race safety  
✅ **Zero Compiler Warnings** - Full strict concurrency compliance  
✅ **Dual-Player Architecture** - Seamless crossfading between audio files  
✅ **Background Playback** - Continue playing when app is in background  
✅ **Lock Screen Controls** - Play, pause, skip forward/backward (15s)  
✅ **Audio Session Management** - Handle interruptions, route changes  
✅ **State Machine** - GameplayKit-based formal state management  
✅ **Protocol-Oriented** - Extensible architecture for custom features  
✅ **Configurable** - Crossfade duration, fade in/out, volume, repeat count  

## Architecture

```
AudioServiceKit/
├── AudioServiceCore/          # Domain layer (protocols, models)
│   ├── Protocols/
│   │   ├── AudioPlayerProtocol.swift
│   │   ├── AudioSource.swift
│   │   └── AudioFeature.swift
│   └── Models/
│       ├── PlayerState.swift
│       ├── AudioConfiguration.swift
│       ├── AudioPlayerError.swift
│       └── SendableTypes.swift
│
└── AudioServiceKit/           # Implementation layer
    ├── Public/
    │   └── AudioPlayerService.swift
    └── Internal/
        ├── AudioEngineActor.swift
        ├── AudioSessionManager.swift
        ├── RemoteCommandManager.swift
        └── StateMachine/
            ├── AudioStateMachine.swift
            └── States/
                ├── PreparingState.swift
                ├── PlayingState.swift
                ├── PausedState.swift
                ├── FadingOutState.swift
                ├── FinishedState.swift
                └── FailedState.swift
```

## Installation

### Swift Package Manager

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/yourusername/ProsperPlayer.git", from: "1.0.0")
]
```

Or in Xcode: File → Add Package Dependencies

## Quick Start

```swift
import AudioServiceKit
import AudioServiceCore

// Create player service
let audioService = AudioPlayerService()

// Configure playback
let config = AudioConfiguration(
    crossfadeDuration: 10.0,
    fadeInDuration: 3.0,
    fadeOutDuration: 6.0,
    volume: 1.0,
    repeatCount: nil,
    enableLooping: true
)

// Start playing
try await audioService.startPlaying(
    url: audioFileURL,
    configuration: config
)

// Control playback
try await audioService.pause()
try await audioService.resume()
try await audioService.skipForward(by: 15.0)
try await audioService.skipBackward(by: 15.0)
await audioService.setVolume(0.8)
try await audioService.finish(fadeDuration: 6.0)
```

## Configuration

```swift
let config = AudioConfiguration(
    crossfadeDuration: 10.0,      // 1-30 seconds
    fadeInDuration: 3.0,          // Start fade in duration
    fadeOutDuration: 6.0,         // End fade out duration
    volume: 1.0,                  // 0.0 - 1.0
    repeatCount: nil,             // nil = infinite loop
    enableLooping: true,          // Enable seamless looping
    fadeCurve: .equalPower        // Fade curve type (DEFAULT)
)
```

### Fade Curves

Prosper Player supports 5 types of fade curves for smooth transitions:

- **`.equalPower`** (DEFAULT) - Maintains constant perceived loudness. Best for audio crossfading.
- **`.linear`** - Simple linear fade. Not recommended for audio (has -3dB power dip).
- **`.logarithmic`** - Fast start, slow end. Good for fade-in from silence.
- **`.exponential`** - Slow start, fast end. Good for dramatic fade-outs.
- **`.sCurve`** - Smooth S-shaped curve. Good for UI animations.

**Recommendation:** Always use `.equalPower` for audio. It's the professional standard!

See [Documentation/FadeCurves.md](Documentation/FadeCurves.md) for detailed explanation.

## Background Playback Setup

1. **Add Background Mode Capability**
   - Open Xcode project
   - Select target → Signing & Capabilities
   - Add "Background Modes" capability
   - Enable "Audio, AirPlay, and Picture in Picture"

2. **Or manually add to Info.plist:**
```xml
<key>UIBackgroundModes</key>
<array>
    <string>audio</string>
</array>
```

## State Management

The player uses GameplayKit state machine with these states:

- **preparing** - Loading and preparing audio
- **playing** - Active playback
- **paused** - Playback paused
- **fadingOut** - Fading out before stopping
- **finished** - Playback completed
- **failed** - Error occurred

## Observing State Changes

```swift
// Implement observer
class MyObserver: AudioPlayerObserver {
    func playerStateDidChange(_ state: PlayerState) async {
        print("State: \(state)")
    }
    
    func playbackPositionDidUpdate(_ position: PlaybackPosition) async {
        print("Position: \(position.currentTime) / \(position.duration)")
    }
    
    func playerDidEncounterError(_ error: AudioPlayerError) async {
        print("Error: \(error)")
    }
}

// Register observer
await audioService.addObserver(MyObserver())
```

## SwiftUI Integration

```swift
import SwiftUI
import AudioServiceKit

@main
struct MyApp: App {
    @State private var audioService = AudioPlayerService()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.audioService, audioService)
        }
    }
}
```

## Demo App

See `Examples/MeditationDemo` for a complete working example with:
- Play/Pause/Resume controls
- Skip forward/backward (15 seconds)
- Volume control
- Playback position display
- State visualization

## Requirements

- iOS 18.0+
- Swift 6.0+
- Xcode 16.0+

## Future Enhancements

The architecture is designed for easy extension:

- **Phase-based playback** (induction, intentions, returning)
- **On-the-fly audio theme switching** with crossfading
- **Advanced audio source** (streaming, generated)
- **Custom audio features** via plugin architecture

## Technical Details

### Thread Safety
- All AVAudioEngine operations isolated in `AudioEngineActor`
- Swift 6 strict concurrency enforced
- Sendable types for cross-actor data transfer
- No data races by design

### Dual-Player Crossfading
- Two AVAudioPlayerNode with individual mixers
- Volume-based crossfading (10ms steps)
- Synchronized timing via AVAudioTime
- Seamless transitions between files

### Audio Session
- Automatic interruption handling (calls, alarms)
- Route change detection (headphones plug/unplug)
- Background audio support
- Configuration change recovery

### Performance
- Zero allocations in audio render thread
- Efficient buffer scheduling
- Minimal CPU usage during crossfades
- Memory-efficient file loading

## License

MIT License - See LICENSE file for details

## Contributing

Contributions welcome! Please read CONTRIBUTING.md first.

## Support

For issues and questions:
- GitHub Issues: [Project Issues](https://github.com/yourusername/ProsperPlayer/issues)
- Documentation: [Wiki](https://github.com/yourusername/ProsperPlayer/wiki)

---

Built with ❤️ using Swift 6 and AVAudioEngine
