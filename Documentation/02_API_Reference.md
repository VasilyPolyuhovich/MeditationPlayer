# API Reference

**ProsperPlayer v2.11.0 - Complete API Guide**

---

## AudioPlayerService

Primary interface for audio playback control with playlist management.

### Initialization

```swift
public init()
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

## Playlist API (v2.11.0)

### loadPlaylist(_:configuration:)

```swift
public func loadPlaylist(
    _ tracks: [URL],
    configuration: PlayerConfiguration? = nil
) async throws
```

**Parameters:**
- `tracks`: Array of track URLs (non-empty)
- `configuration`: Player configuration (uses current if nil)

**Throws:**
- `AudioPlayerError.emptyPlaylist` - Tracks array is empty
- `ConfigurationError.*` - Invalid configuration

**Behavior:**
- Loads playlist into PlaylistManager
- Starts playback with first track
- Enables auto-advance between tracks

**Example:**
```swift
let config = PlayerConfiguration(
    crossfadeDuration: 10.0,
    repeatMode: .playlist
)

try await service.loadPlaylist(
    [track1URL, track2URL, track3URL],
    configuration: config
)
```

---

### nextTrack()

```swift
public func nextTrack() async throws
```

**Behavior:**
- Manual advance to next track in playlist
- Crossfades to next track (adaptive duration)
- Loops to first track if at end (if looping enabled)

**Throws:**
- `AudioPlayerError.emptyPlaylist` - No tracks loaded
- `AudioPlayerError.crossfadeInProgress` - Already crossfading

**Example:**
```swift
try await service.nextTrack()
```

---

### previousTrack()

```swift
public func previousTrack() async throws
```

**Behavior:**
- Manual return to previous track
- Crossfades to previous track
- Wraps to last track if at beginning (if looping)

**Throws:**
- `AudioPlayerError.emptyPlaylist` - No tracks loaded

**Example:**
```swift
try await service.previousTrack()
```

---

### jumpToTrack(at:)

```swift
public func jumpToTrack(at index: Int) async throws
```

**Parameters:**
- `index`: Target track index (0-based)

**Throws:**
- `AudioPlayerError.invalidPlaylistIndex` - Index out of bounds

**Behavior:**
- Crossfades to specified track
- Updates current index

**Example:**
```swift
try await service.jumpToTrack(at: 2)  // Jump to 3rd track
```

---

### addTrackToPlaylist(_:)

```swift
public func addTrackToPlaylist(_ url: URL) async
```

**Parameters:**
- `url`: Track URL to add

**Behavior:**
- Appends track to playlist
- Enables controls if first track

**Example:**
```swift
await service.addTrackToPlaylist(newTrackURL)
```

---

### removeTrackFromPlaylist(at:)

```swift
public func removeTrackFromPlaylist(at index: Int) async throws
```

**Parameters:**
- `index`: Track index to remove

**Throws:**
- `AudioPlayerError.invalidPlaylistIndex` - Invalid index

**Behavior:**
- Removes track from playlist
- Stops playback if last track removed
- Adjusts current index if needed

**Example:**
```swift
try await service.removeTrackFromPlaylist(at: 1)
```

---

### moveTrackInPlaylist(from:to:)

```swift
public func moveTrackInPlaylist(from: Int, to: Int) async throws
```

**Parameters:**
- `from`: Source index
- `to`: Destination index

**Throws:**
- `AudioPlayerError.invalidPlaylistIndex` - Invalid indices

**Example:**
```swift
try await service.moveTrackInPlaylist(from: 0, to: 2)
```

---

### getCurrentPlaylist()

```swift
public func getCurrentPlaylist() async -> [URL]
```

**Returns:** Array of track URLs in playlist

**Example:**
```swift
let tracks = await service.getCurrentPlaylist()
print("Playlist: \(tracks.count) tracks")
```

---

### getCurrentTrackIndex()

```swift
public func getCurrentTrackIndex() async -> Int
```

**Returns:** Current track index (0-based)

**Example:**
```swift
let index = await service.getCurrentTrackIndex()
print("Playing track \(index + 1)")
```

---

### isPlaylistEmpty()

```swift
public func isPlaylistEmpty() async -> Bool
```

**Returns:** `true` if playlist has no tracks

**Example:**
```swift
if await service.isPlaylistEmpty() {
    print("No tracks loaded")
}
```

---

## Legacy Playback Methods

### startPlaying(url:configuration:)

```swift
public func startPlaying(
    url: URL,
    configuration: PlayerConfiguration
) async throws
```

**Note:** Legacy method. Use `loadPlaylist()` for v2.11.0+

**Parameters:**
- `url`: Local audio file URL
- `configuration`: Player configuration

**Throws:**
- `AudioPlayerError.invalidConfiguration`
- `AudioPlayerError.fileNotFound`
- `AudioPlayerError.invalidState`

---

## Playback Control

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

---

### stop()

```swift
public func stop() async
```

**Effects:**
- Stops playback
- Deactivates audio session
- Clears state
- Clears Now Playing info

**State transition:** `*` → `finished`

**Note:** Always succeeds, never throws

---

### reset()

```swift
public func reset() async
```

**Effects:**
- Full engine reset
- **Clears playlist** (v2.11.0)
- Clear all files and state
- Deactivate session
- Re-initialize engine

**Usage:** Prepare for completely new session

---

## Navigation

### seekWithFade(to:fadeDuration:)

```swift
public func seekWithFade(
    to position: TimeInterval,
    fadeDuration: TimeInterval = 0.3
) async throws
```

**Parameters:**
- `position`: Target position in seconds
- `fadeDuration`: Fade duration (default: 0.3s)

**Behavior:**
- Fade out (quick)
- Seek to position
- Fade in (quick)

**Throws:**
- `AudioPlayerError.invalidState` - No active playback

**Example:**
```swift
try await service.seekWithFade(to: 60.0, fadeDuration: 0.2)
```

---

### skipForward(by:) / skipBackward(by:)

```swift
public func skipForward(by interval: TimeInterval = 15.0) async throws
public func skipBackward(by interval: TimeInterval = 15.0) async throws
```

**Parameters:**
- `interval`: Seek distance in seconds (default: 15.0)

**Throws:**
- `AudioPlayerError.invalidState` - During crossfade

**Constraints:**
- Clamped to [0, duration]
- Uses `seekWithFade()` internally

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
- `crossfadeDuration`: Fade duration (1.0-30.0s)

**Behavior:**
- If playing: Crossfade to new track
- If paused: Silent switch

**Validation:** Duration clamped to [1.0, 30.0]

---

## Configuration

### setVolume(_:)

```swift
public func setVolume(_ volume: Float) async
```

**Parameters:**
- `volume`: Master volume [0.0, 1.0]

**Note:** Clamped automatically, never throws

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
    
    var progress: Double {
        currentTime / duration
    }
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

await service.addObserver(MyObserver())
```

---

## PlayerConfiguration

### Structure

```swift
public struct PlayerConfiguration: Sendable {
    public var crossfadeDuration: TimeInterval  // 1.0-30.0s
    public var fadeCurve: FadeCurve            // Algorithm
    public var repeatMode: RepeatMode           // .off, .singleTrack, .playlist
    public var repeatCount: Int?                // nil = infinite
    public var volume: Int                      // 0-100
    public var stopFadeDuration: TimeInterval   // 0.0-10.0s
    public var mixWithOthers: Bool              // Mix with other audio
    
    // Computed properties:
    public var fadeInDuration: TimeInterval {
        crossfadeDuration * 0.3
    }
    
    public var volumeFloat: Float {
        Float(volume) / 100.0
    }
}
```

**See:** `06_Configuration.md` for complete reference

---

## Overlay Player Control

### Overview

The overlay player provides an independent audio layer for ambient sounds, background music, or atmospheric effects that play alongside the main audio track. The overlay has its own volume control and can loop independently.

**Use Cases:**
- Meditation apps: Rain sounds with guided meditation
- Fitness apps: Background music during workout instructions
- Sleep apps: White noise alongside sleep stories
- Games: Ambient soundscapes with dialogue/effects

**Key Features:**
- Independent of main player state
- Main track crossfades don't affect overlay
- Playlist swaps don't affect overlay
- Separate volume control
- Independent loop configuration

---

### startOverlay(url:configuration:)

```swift
public func startOverlay(
    url: URL,
    configuration: OverlayConfiguration
) async throws
```

**Parameters:**
- `url`: Local file URL for overlay audio
- `configuration`: Overlay playback configuration

**Throws:**
- `AudioPlayerError.fileNotFound` - File doesn't exist
- `AudioPlayerError.invalidAudioFile` - Unsupported format
- `AudioPlayerError.audioSessionError` - Session setup failed

**Behavior:**
- Loads overlay audio file
- Starts playback with fade-in
- Loops according to configuration
- Independent volume control

**Example:**
```swift
let config = OverlayConfiguration(
    volume: 0.3,
    loopMode: .infinite,
    fadeInDuration: 2.0,
    fadeOutDuration: 2.0
)

try await player.startOverlay(url: rainURL, configuration: config)
```

---

### stopOverlay()

```swift
public func stopOverlay() async
```

**Behavior:**
- Stops overlay with fade-out
- Uses fade-out duration from configuration
- Safe to call when no overlay is playing

**Example:**
```swift
await player.stopOverlay()
```

---

### pauseOverlay() / resumeOverlay()

```swift
public func pauseOverlay() async
public func resumeOverlay() async
```

**Behavior:**
- `pauseOverlay()`: Pause at current position
- `resumeOverlay()`: Continue from paused position
- Only affects overlay player
- Safe to call when not playing/paused

**Example:**
```swift
await player.pauseOverlay()
// ... later ...
await player.resumeOverlay()
```

---

### replaceOverlay(url:)

```swift
public func replaceOverlay(url: URL) async throws
```

**Parameters:**
- `url`: New audio file URL

**Throws:**
- `AudioPlayerError.invalidState` - No overlay active
- `AudioPlayerError.fileNotFound` - File not found
- `AudioPlayerError.invalidAudioFile` - Unsupported format

**Behavior:**
- Crossfades from current to new overlay file
- Uses crossfade duration from configuration
- Maintains playback state

**Example:**
```swift
// Switch from rain to ocean sounds
try await player.replaceOverlay(url: oceanURL)
```

---

### setOverlayVolume(_:)

```swift
public func setOverlayVolume(_ volume: Float) async
```

**Parameters:**
- `volume`: Volume level (0.0 = silent, 1.0 = full)

**Behavior:**
- Changes overlay volume independently
- Does not affect main player volume
- Applied immediately without fading
- Clamped to [0.0, 1.0] range

**Example:**
```swift
// Reduce overlay to 20%
await player.setOverlayVolume(0.2)
```

---

### getOverlayState()

```swift
public func getOverlayState() async -> OverlayState
```

**Returns:** Current overlay state

**States:**
```swift
enum OverlayState: Sendable {
    case idle
    case playing
    case paused
    case stopping
    case crossfading
    
    var isPlaying: Bool { self == .playing }
    var isPaused: Bool { self == .paused }
    var isIdle: Bool { self == .idle }
}
```

**Example:**
```swift
let state = await player.getOverlayState()
if state.isPlaying {
    print("Overlay is playing")
}
```

---

## Global Control

Control both main player and overlay simultaneously.

### pauseAll()

```swift
public func pauseAll() async
```

**Behavior:**
- Pauses main player
- Pauses overlay (if playing)
- Useful for interruptions (phone calls, alarms)

**Example:**
```swift
// Handle phone call interruption
await player.pauseAll()
```

---

### resumeAll()

```swift
public func resumeAll() async
```

**Behavior:**
- Resumes main player
- Resumes overlay (if paused)
- Restores playback after interruption

**Example:**
```swift
// Resume after interruption ends
await player.resumeAll()
```

---

### stopAll()

```swift
public func stopAll() async
```

**Behavior:**
- Stops main player
- Stops overlay
- Emergency stop / full reset
- Both systems reset to idle

**Example:**
```swift
// Emergency stop
await player.stopAll()
```

---

## OverlayConfiguration

### Structure

```swift
public struct OverlayConfiguration: Sendable {
    public var volume: Float              // 0.0-1.0
    public var loopMode: LoopMode         // .once, .count(n), .infinite
    public var loopDelay: TimeInterval    // 0.0-600.0s
    public var fadeInDuration: TimeInterval   // 0.1-10.0s
    public var fadeOutDuration: TimeInterval  // 0.1-10.0s
    public var applyFadeOnEachLoop: Bool  // Fade on every iteration
}
```

### Loop Modes

```swift
public enum LoopMode: Sendable {
    case once          // Play once, then stop
    case count(Int)    // Play N times (1-1000)
    case infinite      // Loop forever
}
```

### Presets

```swift
// Ambient background sounds
OverlayConfiguration.ambient
// volume: 0.3, loopMode: .infinite, fade: 2.0s each

// Periodic bell/chime sounds
OverlayConfiguration.bell(times: 3, interval: 300)
// volume: 0.5, loopMode: .count(3), delay: 300s, fade: 0.5s each

// Short notification sounds
OverlayConfiguration.notification
// volume: 0.7, loopMode: .once, fade: 0.3s each
```

### Validation

**Automatic clamping:**
- `volume`: [0.0, 1.0]
- `fadeInDuration`: [0.1, 10.0]
- `fadeOutDuration`: [0.1, 10.0]
- `loopDelay`: [0.0, 600.0]
- `loopMode.count`: [1, 1000]

**Example:**
```swift
var config = OverlayConfiguration()
config.volume = 0.4
config.loopMode = .count(5)
config.fadeInDuration = 1.5
config.fadeOutDuration = 1.5
config.applyFadeOnEachLoop = true

try await player.startOverlay(url: ambientURL, configuration: config)
```

---

## Error Handling

### AudioPlayerError

```swift
public enum AudioPlayerError: Error {
    case invalidState(current: String, attempted: String)
    case fileNotFound(URL)
    case engineError(String)
    case sessionError(String)
    
    // Playlist errors (v2.11.0):
    case emptyPlaylist
    case invalidPlaylistIndex(index: Int, count: Int)
    case noActiveTrack
}
```

### ConfigurationError

```swift
public enum ConfigurationError: Error {
    case invalidCrossfadeDuration(TimeInterval)
    case invalidVolume(Int)
    case invalidRepeatCount(Int)
}
```

---

## Usage Patterns

### Playlist Playback

```swift
let service = AudioPlayerService()
await service.setup()

let config = PlayerConfiguration(
    crossfadeDuration: 10.0,
    repeatMode: .playlist,
    volume: 80
)

try await service.loadPlaylist(trackURLs, configuration: config)

// Auto-advance enabled
// Manual navigation:
try await service.nextTrack()
try await service.previousTrack()
```

---

### Dynamic Playlist

```swift
// Add tracks on the fly
await service.addTrackToPlaylist(newTrackURL)

// Remove tracks
try await service.removeTrackFromPlaylist(at: 2)

// Reorder
try await service.moveTrackInPlaylist(from: 0, to: 3)

// Query state
let tracks = await service.getCurrentPlaylist()
let index = await service.getCurrentTrackIndex()
```

---

### State Observation

```swift
actor ViewModel: AudioPlayerObserver {
    @Published var isPlaying = false
    @Published var currentTime: TimeInterval = 0
    @Published var trackName = ""
    
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

**All methods are actor-isolated and thread-safe.**

**Concurrency model:**
```swift
// Multiple concurrent calls are serialized
Task { try await service.pause() }
Task { try await service.nextTrack() }
// Guaranteed sequential execution
```

---

## Performance

**Operation latency:**
- `loadPlaylist()`: ~100-500ms (file load + setup)
- `nextTrack()`: ~50-200ms (file load)
- `seekWithFade()`: < 50ms
- All other methods: < 10ms

**Recommendations:**
- Preload files for instant playback
- Use observers for UI updates
- Call `reset()` for complete cleanup

---

## Platform Support

- **iOS**: 15.0+
- **Testing**: Physical device recommended (simulator may lack audio)

---

**See also:**
- [Configuration Reference](06_Configuration.md)
- [Migration Guide](07_Migration_Guide.md)
- [Concurrency Patterns](05_Concurrency.md)
