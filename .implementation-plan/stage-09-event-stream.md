# Stage 09: AsyncStream<PlayerEvent> for Long Operations

## Status: [ ] Not Started

## Context Budget: ~12k tokens

## Prerequisites

**Read:** Stage 08 (PlayerEvent enum)

**Load Session:** No

---

## Goal

Add AsyncStream<PlayerEvent> to AudioPlayerService for UI progress updates.

**Expected Changes:** ~40 LOC

---

## Implementation Steps

### 1. Add Stream Property to AudioPlayerService

```swift
// In AudioPlayerService:

// After existing AsyncStream properties:
private var eventContinuation: AsyncStream<PlayerEvent>.Continuation?

/// Stream of player events (file loading, crossfade progress, etc.)
///
/// **Usage in SwiftUI:**
/// ```swift
/// .task {
///     for await event in player.events {
///         switch event {
///         case .fileLoadStarted(let url):
///             showLoadingIndicator(url)
///         case .crossfadeProgress(let progress):
///             updateProgressBar(progress)
///         }
///     }
/// }
/// ```
public var events: AsyncStream<PlayerEvent> {
    AsyncStream { continuation in
        self.eventContinuation = continuation
    }
}
```

### 2. Forward Events from CrossfadeOrchestrator

```swift
// In CrossfadeOrchestrator, add:

/// Callback for player events
private let onEvent: (@Sendable (PlayerEvent) -> Void)?

init(
    audioEngine: AudioEngineActor,
    stateStore: any PlaybackStateStore,
    onEvent: (@Sendable (PlayerEvent) -> Void)? = nil
) {
    self.audioEngine = audioEngine
    self.stateStore = stateStore
    self.onEvent = onEvent
}

// In startCrossfade:
onEvent?(.crossfadeStarted(from: currentTrack, to: track.title))

// In monitoring loop:
for await progress in progressStream {
    onEvent?(.crossfadeProgress(progress))
}

// On completion:
onEvent?(.crossfadeCompleted)
```

### 3. Wire Up in AudioPlayerService Init

```swift
// Modify CrossfadeOrchestrator initialization:

self.crossfadeOrchestrator = CrossfadeOrchestrator(
    audioEngine: audioEngine,
    stateStore: playbackStateCoordinator,
    onEvent: { [weak self] event in
        Task { @MainActor in
            await self?.eventContinuation?.yield(event)
        }
    }
)
```

### 4. Build Verification

```bash
xcodebuild -scheme AudioServiceKit \
  -destination 'id=SIMULATOR_ID' \
  -skipPackagePluginValidation \
  build
```

---

## Success Criteria

- [ ] events AsyncStream property added
- [ ] eventContinuation yields events
- [ ] CrossfadeOrchestrator accepts onEvent callback
- [ ] Events forwarded from orchestrator
- [ ] Build passes

---

## Commit Template

```
[Stage 09] Add AsyncStream<PlayerEvent> for UI updates

Implements event streaming for long operations:
- events AsyncStream<PlayerEvent> property
- CrossfadeOrchestrator forwards events
- File loading progress tracked
- Crossfade progress (0-100%) tracked

UI can show loading indicators and progress bars.

Ref: .implementation-plan/stage-09-event-stream.md
Build: ✅ Passes
```

---

## Next Stage

**Stage 10 - Priority queue cancellation testing**
