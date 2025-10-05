# ProsperPlayer Architecture

**Version:** 2.6.0  
**Swift:** 6.0 (strict concurrency)  
**Platforms:** iOS 15+, macOS 12+

---

## System Design

### Core Architecture

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

### Isolation Domains

**Actor Boundaries:**
- `AudioPlayerService` (actor) - main coordinator
- `AudioEngineActor` (actor) - AVAudioEngine isolation
- `AudioSessionManager` (actor) - session lifecycle
- `RemoteCommandManager` (@MainActor) - Lock Screen controls

**Thread Safety:** Guaranteed at compile-time via Swift 6 actor isolation.

---

## Dual-Player Crossfade System

### Implementation

```swift
// Two complete playback chains
PlayerA → MixerA ─┐
                  ├─→ MainMixer → Output
PlayerB → MixerB ─┘

// Crossfade sequence:
1. Load on inactive player
2. Sync start time: t₀ + buffer_delay
3. Fade volumes: A(1→0), B(0→1)
4. Switch active player
```

### Sample-Accurate Synchronization

```swift
let syncTime = AVAudioTime(
    sampleTime: lastRenderTime.sampleTime + 2048,
    atRate: sampleRate
)
inactivePlayer.play(at: syncTime)
```

**Buffer delay:** 2048 samples ≈ 46ms @ 44.1kHz

---

## State Machine

### States

```swift
enum PlayerState: Sendable {
    case preparing  // Loading audio, configuring engine
    case playing    // Active playback
    case paused     // Playback suspended
    case fadingOut  // Volume fade before stop
    case finished   // Playback complete
    case failed     // Error state
}
```

### Transition Graph

```
         ┌──────┐
    ┌───►│failed│◄────┐
    │    └──────┘     │
    │                 │
┌───▼──────┐    ┌────▼─────┐    ┌────────┐
│preparing ├───►│ playing  ├───►│paused  │
└──────────┘    └─────┬────┘    └────┬───┘
                      │              │
                      ▼              │
                 ┌────────────┐      │
                 │ fadingOut  │◄─────┘
                 └─────┬──────┘
                       ▼
                 ┌──────────┐
                 │ finished │
                 └──────────┘
```

### Actor-Safe Implementation

```swift
protocol AudioStateProtocol: Sendable {
    var playerState: PlayerState { get }
    func didEnter(from: (any AudioStateProtocol)?, 
                   context: AudioStateMachineContext) async
}

actor AudioStateMachine {
    private var currentStateBox: any AudioStateProtocol
    
    func enter(_ newState: any AudioStateProtocol) async -> Bool
}
```

**Note:** GameplayKit removed in v2.4.0 for Swift 6 compliance.

---

## Component Details

### AudioEngineActor

**Responsibilities:**
- AVAudioEngine lifecycle
- Dual AVAudioPlayerNode management
- Buffer scheduling
- Volume control
- Position tracking

**Key Methods:**
```swift
func setup()
func loadAudioFile(url: URL) throws -> TrackInfo
func scheduleFile(fadeIn: Bool, fadeInDuration: TimeInterval, fadeCurve: FadeCurve)
func seek(to: TimeInterval) throws
func performSynchronizedCrossfade(duration: TimeInterval, curve: FadeCurve) async
```

### AudioSessionManager

**Responsibilities:**
- AVAudioSession configuration
- Interruption handling (calls, alarms, Siri)
- Route change detection (headphone plug/unplug)
- Background audio capability

**Event Handlers:**
```swift
setInterruptionHandler(_ handler: @escaping @Sendable (Bool) -> Void)
setRouteChangeHandler(_ handler: @escaping @Sendable (AVAudioSession.RouteChangeReason) -> Void)
```

### RemoteCommandManager

**@MainActor Isolated**

**Controls:**
- Play/Pause
- Skip forward/backward (±15s)
- Now Playing info (Lock Screen)
- Playback position updates

---

## Data Flow

### Playback Start Sequence

```
1. User: startPlaying(url:, config:)
      ↓
2. Validate configuration
      ↓
3. Configure audio session
      ↓
4. Prepare audio engine
      ↓
5. Load audio file
      ↓
6. Enter preparing state
      ↓
7. Schedule buffer with fade-in
      ↓
8. Start playback timer (0.5s interval)
      ↓
9. Transition to playing state
      ↓
10. Update Now Playing info
```

### Crossfade Sequence

```
Active Player A (1.0) → (fading out) → (0.0) → stopped
Inactive Player B (0.0) → (fading in) → (1.0) → active

Timeline:
t₀: Start secondary player at sync time
t₀→t₁: Parallel volume fades (duration = crossfadeDuration)
t₁: Stop primary player, switch active reference
```

---

## Performance Characteristics

### Memory

- Audio files: Loaded entirely in memory
- Typical meditation track: ~10MB (5min @ 128kbps)
- Dual-player overhead: 2× file size during crossfade

### CPU

- Volume fade: Adaptive step sizing (v2.6.0)
  - 1s fade: 100 steps (10ms/step)
  - 30s fade: 600 steps (50ms/step) - 5× reduction
- Position updates: 2 Hz (every 0.5s)
- Audio rendering: Real-time thread (< 1ms/buffer)

### Latency

- Crossfade sync: 46ms buffer delay @ 44.1kHz
- Seek operation: < 50ms
- State transitions: < 10ms

---

## Swift 6 Concurrency Model

### Actor Isolation

All mutable state protected by actors:
```swift
actor AudioPlayerService {
    private var state: PlayerState  // Actor-isolated
    private var currentTrack: TrackInfo?
    private var playbackPosition: PlaybackPosition?
}
```

### Sendable Types

All cross-actor data is `Sendable`:
```swift
struct AudioConfiguration: Sendable { }
struct TrackInfo: Sendable { }
struct PlaybackPosition: Sendable { }
enum PlayerState: Sendable { }
enum FadeCurve: Sendable { }
```

### @Sendable Closures

All async handlers:
```swift
func setupCommands(
    playHandler: @escaping @Sendable () async -> Void,
    pauseHandler: @escaping @Sendable () async -> Void
)
```

**Guarantee:** Compile-time data race prevention.

---

## Testing Architecture

### Unit Tests

- State machine transitions
- Fade curve mathematics
- Configuration validation
- Error handling

### Integration Tests

- Full playback cycle
- Crossfade synchronization
- Interruption recovery
- Route change handling

### Concurrency Tests

- Thread Sanitizer (TSan)
- Actor reentrancy scenarios
- Sendable conformance
- Isolation boundary verification

---

## Dependencies

### System Frameworks
- `AVFoundation` - Audio engine, session
- `MediaPlayer` - Remote commands, Now Playing
- `Combine` - Reactive patterns (minimal)

### Swift Packages
- None (zero external dependencies)

---

## References

- [AVAudioEngine Programming Guide](https://developer.apple.com/documentation/avfaudio/avaudioengine)
- [Swift Concurrency](https://docs.swift.org/swift-book/LanguageGuide/Concurrency.html)
- [Audio Session Programming Guide](https://developer.apple.com/library/archive/documentation/Audio/Conceptual/AudioSessionProgrammingGuide/)
- WWDC 2014 Session 502: AVAudioEngine in Practice
- WWDC 2021 Session 10254: Swift Concurrency Behind the Scenes
