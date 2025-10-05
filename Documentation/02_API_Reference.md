# API Reference

**ProsperPlayer v2.6.0**

---

## AudioPlayerService

Primary interface for audio playback control.

### Initialization

```swift
public init(configuration: AudioConfiguration = AudioConfiguration())
```

**Post-init requirement:**
```swift
public func setup() async
```

**Example:**
```swift
let service = AudioPlayerService()
await service.setup()
```

---

## Core Methods

### startPlaying(url:configuration:)

```swift
public func startPlaying(
    url: URL,
    configuration: AudioConfiguration
) async throws
```

**Parameters:**
- `url`: Local audio file URL
- `configuration`: Playback configuration

**Throws:**
- `AudioPlayerError.invalidConfiguration` - Config validation failed
- `AudioPlayerError.fileNotFound` - URL invalid
- `AudioPlayerError.invalidState` - Cannot start from current state

**State transition:** `*` → `preparing` → `playing`

**Example:**
```swift
let config = AudioConfiguration(
    crossfadeDuration: 10.0,
    fadeInDuration: 3.0,
    enableLooping: true
)

try await service.startPlaying(
    url: audioURL,
    configuration: config
)
```

---

### pause()

```swift
public func pause() async throws
```

**Precondition:** `state ∈ {playing, preparing}`

**Throws:**
- `AudioPlayerError.invalidState` - Not playing/preparing

**State transition:** `playing` → `paused`

**Idempotent:** Safe to call when already paused

---

### resume()

```swift
public func resume() async throws
```

**Precondition:** `state = paused`

**Throws:**
- `AudioPlayerError.invalidState` - Not paused

**State transition:** `paused` → `playing`

**Idempotent:** Safe to call when already playing

---

### stop()

```swift
public func stop() async
```

**Effects:**
- Stops playback
- Deactivates audio session
- Clears all state
- Clears Now Playing info

**State transition:** `*` → `finished`

**Note:** Always succeeds, never throws

---

### finish(fadeDuration:)

```swift
public func finish(fadeDuration: TimeInterval?) async throws
```

**Parameters:**
- `fadeDuration`: Override config fade-out (optional)

**Behavior:**
1. Fade volume: 1.0 → 0.0
2. Transition to `finished`
3. Deactivate session

**State transition:** `playing` → `fadingOut` → `finished`

---

### skipForward(by:) / skipBackward(by:)

```swift
public func skipForward(by interval: TimeInterval = 15.0) async throws
public func skipBackward(by interval: TimeInterval = 15.0) async throws
```

**Parameters:**
- `interval`: Seek distance in seconds (default: 15.0)

**Throws:**
- `AudioPlayerError.invalidState` - During crossfade or no position

**Constraints:**
- Clamped to [0, duration]
- Blocked during crossfade transitions

**Example:**
```swift
try await service.skipForward(by: 15.0)  // +15s
try await service.skipBackward(by: 30.0) // -30s
```

---

### replaceTrack(url:crossfadeDuration:)

```swift
public func replaceTrack(
    url: URL,
    crossfadeDuration: TimeInterval = 5.0
) async throws
```

**Parameters:**
- `url`: New audio file URL
- `crossfadeDuration`: Fade duration (range: 1.0-30.0s)

**Behavior:**
- If playing: Synchronized crossfade to new track
- If paused: Silent switch (no playback)

**Validation:** Duration clamped to [1.0, 30.0]

**Example:**
```swift
try await service.replaceTrack(
    url: newTrackURL,
    crossfadeDuration: 8.0
)
```

---

### setVolume(_:)

```swift
public func setVolume(_ volume: Float) async
```

**Parameters:**
- `volume`: Master volume [0.0, 1.0]

**Note:** Clamped automatically, never throws

---

### reset()

```swift
public func reset() async
```

**Effects:**
- Full engine reset
- Clear all files and state
- Deactivate session
- Restore default configuration
- Re-initialize engine

**Usage:** Prepare for completely new session

---

### cleanup()

```swift
public func cleanup() async
```

**Effects:**
- Stop playback
- Deactivate session
- Remove remote commands
- Clear observers

**Usage:** Before service deallocation

---

## Properties

### state

```swift
public private(set) var state: PlayerState { get }
```

**Values:**
```swift
enum PlayerState: Sendable {
    case preparing
    case playing
    case paused
    case fadingOut
    case finished
    case failed(AudioPlayerError)
}
```

---

### configuration

```swift
public private(set) var configuration: AudioConfiguration { get }
```

**Mutable via:**
- `startPlaying(url:configuration:)` - sets new config
- `reset()` - restores default

---

### currentTrack

```swift
public private(set) var currentTrack: TrackInfo? { get }
```

```swift
struct TrackInfo: Sendable {
    let title: String
    let artist: String?
    let duration: TimeInterval
    let format: AudioFormat
}
```

---

### playbackPosition

```swift
public private(set) var playbackPosition: PlaybackPosition? { get }
```

```swift
struct PlaybackPosition: Sendable {
    let currentTime: TimeInterval
    let duration: TimeInterval
}
```

**Update frequency:** 2 Hz (every 0.5s)

---

## Observer Pattern

### AudioPlayerObserver

```swift
public protocol AudioPlayerObserver: Sendable {
    func playerStateDidChange(_ state: PlayerState) async
    func playbackPositionDidUpdate(_ position: PlaybackPosition) async
    func playerDidEncounterError(_ error: AudioPlayerError) async
}
```

### Registration

```swift
public func addObserver(_ observer: AudioPlayerObserver)
public func removeAllObservers()
```

**Example:**
```swift
actor MyObserver: AudioPlayerObserver {
    func playerStateDidChange(_ state: PlayerState) async {
        print("State: \(state)")
    }
    
    func playbackPositionDidUpdate(_ position: PlaybackPosition) async {
        print("Time: \(position.currentTime)")
    }
    
    func playerDidEncounterError(_ error: AudioPlayerError) async {
        print("Error: \(error)")
    }
}

let observer = MyObserver()
await service.addObserver(observer)
```

---

## AudioConfiguration

### Structure

```swift
public struct AudioConfiguration: Sendable {
    public let crossfadeDuration: TimeInterval  // Default: 10.0
    public let fadeInDuration: TimeInterval     // Default: 3.0
    public let fadeOutDuration: TimeInterval    // Default: 6.0
    public let fadeCurve: FadeCurve            // Default: .equalPower
    public let enableLooping: Bool              // Default: false
    public let repeatCount: Int?                // Default: nil (infinite)
}
```

### Validation Rules

```swift
func validate() throws {
    guard crossfadeDuration >= 1.0 && crossfadeDuration <= 30.0 else {
        throw AudioPlayerError.invalidConfiguration(
            "crossfadeDuration must be in range [1.0, 30.0]"
        )
    }
    
    guard fadeInDuration >= 0.0 && fadeInDuration <= 10.0 else {
        throw AudioPlayerError.invalidConfiguration(
            "fadeInDuration must be in range [0.0, 10.0]"
        )
    }
    
    guard fadeOutDuration >= 0.0 && fadeOutDuration <= 30.0 else {
        throw AudioPlayerError.invalidConfiguration(
            "fadeOutDuration must be in range [0.0, 30.0]"
        )
    }
    
    if let count = repeatCount {
        guard count > 0 else {
            throw AudioPlayerError.invalidConfiguration(
                "repeatCount must be > 0"
            )
        }
    }
}
```

---

## FadeCurve

```swift
public enum FadeCurve: Sendable {
    case equalPower    // sin/cos (recommended)
    case linear        // t
    case logarithmic   // log₁₀-based
    case exponential   // t²
    case sCurve        // smoothstep
}
```

**See:** `04_Fade_Curves.md` for mathematical details

---

## Error Handling

### AudioPlayerError

```swift
public enum AudioPlayerError: Error {
    case invalidState(current: String, attempted: String)
    case invalidConfiguration(String)
    case fileNotFound(URL)
    case engineError(String)
    case sessionError(String)
}
```

### Error Recovery

**Pattern:**
```swift
do {
    try await service.startPlaying(url: url, configuration: config)
} catch AudioPlayerError.invalidConfiguration(let msg) {
    print("Config error: \(msg)")
    // Fix configuration and retry
} catch AudioPlayerError.fileNotFound(let url) {
    print("File not found: \(url)")
    // Check file existence
} catch {
    print("Unexpected error: \(error)")
    await service.reset()  // Full reset
}
```

---

## Usage Patterns

### Basic Playback

```swift
let service = AudioPlayerService()
await service.setup()

let config = AudioConfiguration(
    fadeInDuration: 2.0,
    fadeOutDuration: 3.0
)

try await service.startPlaying(url: audioURL, configuration: config)
try await service.pause()
try await service.resume()
await service.stop()
```

---

### Looping with Crossfade

```swift
let config = AudioConfiguration(
    crossfadeDuration: 10.0,
    enableLooping: true,
    repeatCount: 5  // Loop 5 times
)

try await service.startPlaying(url: audioURL, configuration: config)
```

---

### Track Replacement

```swift
// Playing track A
try await service.replaceTrack(
    url: trackB_URL,
    crossfadeDuration: 8.0
)
// Smooth crossfade to track B
```

---

### State Observation

```swift
actor ViewModel: AudioPlayerObserver {
    @Published var isPlaying = false
    @Published var currentTime: TimeInterval = 0
    
    func playerStateDidChange(_ state: PlayerState) async {
        await MainActor.run {
            isPlaying = (state == .playing)
        }
    }
    
    func playbackPositionDidUpdate(_ position: PlaybackPosition) async {
        await MainActor.run {
            currentTime = position.currentTime
        }
    }
}
```

---

## Thread Safety

**All methods are actor-isolated and inherently thread-safe.**

**Concurrency model:**
```swift
// Multiple concurrent calls are serialized
Task { try await service.pause() }
Task { try await service.skipForward() }
// Guaranteed sequential execution
```

**UI Integration:**
```swift
// SwiftUI
@State private var service: AudioPlayerService?

.task {
    let s = AudioPlayerService()
    await s.setup()
    service = s
}

// Calls from UI always safe
Button("Play") {
    Task {
        try? await service?.resume()
    }
}
```

---

## Performance Considerations

**Blocking operations:**
- `startPlaying()`: ~100-500ms (file load + engine setup)
- `replaceTrack()`: ~50-200ms (file load only)
- `seek()`: < 50ms
- All other methods: < 10ms

**Recommended:**
- Preload files before `startPlaying()`
- Use observers for UI updates (avoid polling)
- Call `cleanup()` before deallocation
- Use `reset()` for complete state reset

---

## SwiftUI Integration

```swift
struct ContentView: View {
    @State private var service: AudioPlayerService?
    @StateObject private var viewModel = AudioViewModel()
    
    var body: some View {
        VStack {
            if let service = service {
                PlayerControls(service: service)
                    .onAppear {
                        Task {
                            await viewModel.observe(service)
                        }
                    }
            }
        }
        .task {
            let s = AudioPlayerService()
            await s.setup()
            service = s
        }
    }
}
```

---

## Testing

### Unit Test Example

```swift
@Test
func testPauseResume() async throws {
    let service = AudioPlayerService()
    await service.setup()
    
    try await service.startPlaying(url: testURL, configuration: .init())
    
    // Wait for playing state
    try await Task.sleep(nanoseconds: 100_000_000)
    
    try await service.pause()
    let pausedState = await service.state
    #expect(pausedState == .paused)
    
    try await service.resume()
    let playingState = await service.state
    #expect(playingState == .playing)
}
```

---

## Migration from v2.5.0

**Breaking changes:** None

**New features:**
- Issue #8 fix: Float precision tolerance (internal)
- Issue #9 fix: Adaptive volume fade steps (internal)

**Deprecated:** None
