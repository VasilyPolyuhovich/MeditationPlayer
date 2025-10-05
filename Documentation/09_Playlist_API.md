# Playlist Management API

**ProsperPlayer v2.11.0 - Complete Playlist Guide**

---

## Overview

The Playlist API provides SDK-level playlist management with automatic track advancement, seamless crossfading, and intuitive navigation. Introduced in v2.11.0, it replaces manual playlist logic in applications.

---

## Core Concept

**Before v2.11.0 (Manual):**
```swift
// App manages playlist logic
var tracks = [track1, track2, track3]
var currentIndex = 0

// Manual advance on track end
func onTrackEnd() {
    currentIndex += 1
    if currentIndex < tracks.count {
        try await service.startPlaying(url: tracks[currentIndex])
    }
}
```

**v2.11.0+ (SDK-Managed):**
```swift
// SDK handles everything
try await service.loadPlaylist([track1, track2, track3], configuration: config)
// Auto-advance, looping, navigation all built-in
```

---

## Playlist Lifecycle

### 1. Load Playlist

```swift
public func loadPlaylist(
    _ tracks: [URL],
    configuration: PlayerConfiguration? = nil
) async throws
```

**Behavior:**
- Validates tracks array (non-empty)
- Loads into PlaylistManager
- Starts playback with first track
- Enables auto-advance logic

**Example:**
```swift
let config = PlayerConfiguration(
    crossfadeDuration: 10.0,
    enableLooping: true
)

try await service.loadPlaylist(
    [track1URL, track2URL, track3URL],
    configuration: config
)
```

**Errors:**
- `emptyPlaylist` - Tracks array is empty
- `invalidConfiguration` - Config validation failed

---

### 2. Auto-Advance

**Automatic progression through playlist.**

**Trigger logic:**
```
Crossfade starts at: duration - crossfadeDuration - 0.1s

Example (60s track, 10s crossfade):
  - Normal playback: 0-49.9s
  - Crossfade zone: 49.9-60s
  - Next track loads: at 49.9s
```

**Behavior:**
- Detects approaching track end
- Preloads next track
- Initiates crossfade
- Swaps to next track seamlessly
- Loops to first track if at end (if looping enabled)

**Configuration:**
```swift
PlayerConfiguration(
    crossfadeDuration: 10.0,  // When to start crossfade
    enableLooping: true,       // Cycle playlist
    repeatCount: nil           // Infinite cycles
)
```

---

### 3. Manual Navigation

#### Next Track

```swift
try await service.nextTrack()
```

**Behavior:**
- Crossfades to next track
- Adaptive crossfade duration (based on remaining time)
- Loops to first if at end

**Use case:** Skip button, gesture control

---

#### Previous Track

```swift
try await service.previousTrack()
```

**Behavior:**
- Crossfades to previous track
- Wraps to last track if at beginning

**Use case:** Back button, gesture control

---

#### Jump to Track

```swift
try await service.jumpToTrack(at: index)
```

**Parameters:**
- `index`: Target track (0-based)

**Behavior:**
- Crossfades to specified track
- Updates current index

**Use case:** Playlist UI selection

**Example:**
```swift
// Jump to 3rd track
try await service.jumpToTrack(at: 2)
```

---

## Dynamic Playlist Updates

### Add Track

```swift
await service.addTrackToPlaylist(url)
```

**Behavior:**
- Appends to end of playlist
- Enables controls if first track
- No playback interruption

**Use case:** "Add to queue" feature

**Example:**
```swift
await service.addTrackToPlaylist(newTrackURL)
```

---

### Remove Track

```swift
try await service.removeTrackFromPlaylist(at: index)
```

**Behavior:**
- Removes track from playlist
- Stops playback if last track removed
- Adjusts current index if needed
- No disruption if removing non-current track

**Use case:** "Remove from queue" feature

**Errors:**
- `invalidPlaylistIndex` - Index out of bounds

**Example:**
```swift
try await service.removeTrackFromPlaylist(at: 1)
```

---

### Move Track

```swift
try await service.moveTrackInPlaylist(from: fromIndex, to: toIndex)
```

**Behavior:**
- Reorders playlist
- Updates current index if affected
- No playback interruption

**Use case:** Drag & drop reordering

**Errors:**
- `invalidPlaylistIndex` - Invalid indices

**Example:**
```swift
// Move first track to third position
try await service.moveTrackInPlaylist(from: 0, to: 2)
```

---

## Query Methods

### Get Current Playlist

```swift
let tracks = await service.getCurrentPlaylist()
```

**Returns:** `[URL]` - Array of track URLs

**Use case:** Display playlist UI

---

### Get Current Index

```swift
let index = await service.getCurrentTrackIndex()
```

**Returns:** `Int` - Current track index (0-based)

**Use case:** Highlight current track in UI

**Example:**
```swift
let index = await service.getCurrentTrackIndex()
print("Playing track \(index + 1) of \(tracks.count)")
```

---

### Check if Empty

```swift
let isEmpty = await service.isPlaylistEmpty()
```

**Returns:** `Bool` - True if no tracks

**Use case:** Disable controls when empty

**Example:**
```swift
if await service.isPlaylistEmpty() {
    // Disable play button
}
```

---

## Looping Modes

### Infinite Loop

```swift
PlayerConfiguration(
    enableLooping: true,
    repeatCount: nil  // Infinite
)
```

**Behavior:**
- track1 → track2 → track3 → track1 → ...
- Continues until `stop()` or `reset()`

**Use case:** Meditation, ambient playlists

---

### Limited Repeats

```swift
PlayerConfiguration(
    enableLooping: true,
    repeatCount: 3  // Loop 3 times
)
```

**Behavior:**
- Plays playlist 3 complete cycles
- Stops after 3rd completion

**Use case:** Workout playlists, timed sessions

---

### Single Playthrough

```swift
PlayerConfiguration(
    enableLooping: false
)
```

**Behavior:**
- track1 → track2 → track3 → STOP
- State → `.finished` after last track

**Use case:** Album playback, podcasts

---

## Error Handling

### Playlist Errors

```swift
enum AudioPlayerError {
    case emptyPlaylist                      // No tracks provided
    case invalidPlaylistIndex(Int, Int)     // Index out of bounds
    case noActiveTrack                      // No current track
}
```

**Pattern:**
```swift
do {
    try await service.loadPlaylist(tracks, configuration: config)
} catch AudioPlayerError.emptyPlaylist {
    print("Playlist cannot be empty")
} catch AudioPlayerError.invalidPlaylistIndex(let index, let count) {
    print("Index \(index) out of bounds (0-\(count-1))")
} catch {
    print("Unexpected error: \(error)")
}
```

---

## UI Integration

### SwiftUI Example

```swift
struct PlaylistView: View {
    @State private var service: AudioPlayerService?
    @State private var tracks: [URL] = []
    @State private var currentIndex = 0
    
    var body: some View {
        VStack {
            // Playlist UI
            List(tracks.indices, id: \.self) { index in
                TrackRow(
                    url: tracks[index],
                    isCurrent: index == currentIndex
                )
                .onTapGesture {
                    Task {
                        try? await service?.jumpToTrack(at: index)
                    }
                }
            }
            
            // Controls
            HStack {
                Button("Previous") {
                    Task { try? await service?.previousTrack() }
                }
                Button("Next") {
                    Task { try? await service?.nextTrack() }
                }
            }
        }
        .task {
            // Sync playlist state
            while let s = service {
                tracks = await s.getCurrentPlaylist()
                currentIndex = await s.getCurrentTrackIndex()
                try? await Task.sleep(for: .seconds(0.5))
            }
        }
    }
}
```

---

### ViewModel Pattern

```swift
@MainActor
@Observable
class PlaylistViewModel: AudioPlayerObserver {
    private let service: AudioPlayerService
    
    private(set) var tracks: [URL] = []
    private(set) var currentIndex = 0
    private(set) var isPlaying = false
    
    init(service: AudioPlayerService) {
        self.service = service
        Task { await service.addObserver(self) }
    }
    
    func loadPlaylist(_ urls: [URL]) async {
        do {
            try await service.loadPlaylist(urls)
            await syncState()
        } catch {
            print("Load error: \(error)")
        }
    }
    
    func nextTrack() async {
        try? await service.nextTrack()
        await syncState()
    }
    
    func previousTrack() async {
        try? await service.previousTrack()
        await syncState()
    }
    
    private func syncState() async {
        tracks = await service.getCurrentPlaylist()
        currentIndex = await service.getCurrentTrackIndex()
    }
    
    // AudioPlayerObserver
    func playerStateDidChange(_ state: PlayerState) async {
        await MainActor.run {
            isPlaying = (state == .playing)
        }
    }
}
```

---

## Advanced Features

### Adaptive Crossfade

**Duration adapts to remaining time:**

```swift
// Manual next with 10s crossfade:
// - If 20s remaining → full 10s crossfade
// - If 5s remaining → 5s crossfade (adaptive)
// - If 1s remaining → 1s crossfade

try await service.nextTrack()
// SDK calculates optimal crossfade duration
```

---

### Crossfade During Navigation

**All navigation methods crossfade:**
- `nextTrack()` - Crossfade to next
- `previousTrack()` - Crossfade to previous
- `jumpToTrack(at:)` - Crossfade to target

**No gaps, no clicks, seamless transitions.**

---

## Migration from Manual Playlist

### Before (v2.10.1)

```swift
// App-side playlist logic
class ViewModel {
    var tracks: [URL] = []
    var currentIndex = 0
    
    func play() async {
        try await service.startPlaying(url: tracks[currentIndex])
    }
    
    func onTrackEnd() async {
        currentIndex = (currentIndex + 1) % tracks.count
        try await service.replaceTrack(
            url: tracks[currentIndex],
            crossfadeDuration: 10.0
        )
    }
}
```

### After (v2.11.0)

```swift
// SDK handles everything
class ViewModel {
    func play() async {
        let config = PlayerConfiguration(
            crossfadeDuration: 10.0,
            enableLooping: true
        )
        
        try await service.loadPlaylist(tracks, configuration: config)
        // Auto-advance, looping, crossfade built-in
    }
}
```

**Benefits:**
- ✅ 70 LOC reduction (simpler code)
- ✅ No manual position tracking
- ✅ No edge case handling
- ✅ SDK-level optimization

---

## Best Practices

### DO ✅

```swift
// Preload playlist
try await service.loadPlaylist(tracks, configuration: config)

// Use SDK navigation
try await service.nextTrack()

// Query state for UI
let index = await service.getCurrentTrackIndex()
let tracks = await service.getCurrentPlaylist()

// Handle errors
do {
    try await service.jumpToTrack(at: index)
} catch {
    // Show user-friendly message
}
```

### DON'T ❌

```swift
// Don't manage playlist manually
// ❌ tracks[currentIndex++]

// Don't use replaceTrack for navigation
// ❌ service.replaceTrack(url: nextURL)
// ✅ service.nextTrack()

// Don't load empty playlist
// ❌ service.loadPlaylist([])
// Check isEmpty first
```

---

## Testing

### Unit Test

```swift
@Test
func testPlaylistNavigation() async throws {
    let service = AudioPlayerService()
    await service.setup()
    
    let tracks = [track1URL, track2URL, track3URL]
    
    // Load playlist
    try await service.loadPlaylist(tracks)
    
    // Check initial state
    let index = await service.getCurrentTrackIndex()
    #expect(index == 0)
    
    // Next track
    try await service.nextTrack()
    let newIndex = await service.getCurrentTrackIndex()
    #expect(newIndex == 1)
    
    // Previous track
    try await service.previousTrack()
    let backIndex = await service.getCurrentTrackIndex()
    #expect(backIndex == 0)
}
```

---

## Summary

**Key features of Playlist API:**

1. ✅ SDK-level playlist management
2. ✅ Automatic track advancement
3. ✅ Seamless crossfades between tracks
4. ✅ Manual navigation (next/previous/jump)
5. ✅ Dynamic updates (add/remove/move)
6. ✅ Multiple looping modes
7. ✅ Error handling
8. ✅ Thread-safe (actor-isolated)

**Recommended pattern:**
```swift
// Load playlist
let config = PlayerConfiguration(
    crossfadeDuration: 10.0,
    enableLooping: true,
    repeatCount: nil,
    volume: 80
)

try await service.loadPlaylist(trackURLs, configuration: config)

// SDK handles:
// - Auto-advance with crossfade
// - Looping
// - Position tracking
// - State management
```

---

**See also:**
- [API Reference](02_API_Reference.md)
- [Configuration](06_Configuration.md)
- [Migration Guide](07_Migration_Guide.md)
