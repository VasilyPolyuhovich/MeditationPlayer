# Stage 08: File I/O Timeout Wrapper + Progress

## Status: [ ] Not Started

## Context Budget: ~15k tokens

## Prerequisites

**Read:**
- `QUEUE_UX_PATTERNS.md` (section 2: System Timeout Wrapper)
- Stage 03 (AdaptiveTimeoutManager)

**Load Session:** No

---

## Goal

Wrap AudioEngineActor file loading with timeout + progress tracking.

**Expected Changes:**
- New enum: PlayerEvent (~80 LOC)
- Modified: AudioEngineActor.swift (+60 LOC)
- Modified: CrossfadeOrchestrator.swift (+30 LOC)

---

## Implementation Steps

### 1. Create PlayerEvent Enum

**File:** `Sources/AudioServiceKit/Models/PlayerEvent.swift`

```swift
import Foundation

/// Events emitted by AudioPlayerService for UI updates
///
/// Use AsyncStream<PlayerEvent> to observe long-running operations
public enum PlayerEvent: Sendable {
    // File Loading
    case fileLoadStarted(URL)
    case fileLoadProgress(URL, progress: Double)  // 0.0-1.0
    case fileLoadCompleted(URL, duration: Duration)
    case fileLoadTimeout(URL)
    case fileLoadError(URL, Error)
    
    // Crossfade Progress
    case crossfadeStarted(from: String, to: String)
    case crossfadeProgress(Double)  // 0.0-1.0
    case crossfadeCompleted
    case crossfadeCancelled
    case crossfadeTimeout
    
    // System Events
    case audioSessionInterruption
    case audioSessionRouteChange
    
    // State Changes
    case stateChanged(PlayerState)
    case trackChanged(Track.Metadata)
}
```

### 2. Add Timeout Wrapper to AudioEngineActor

```swift
// In AudioEngineActor:

/// Load file with timeout protection
func loadAudioFileWithTimeout(
    track: Track,
    timeout: Duration,
    onProgress: (@Sendable (PlayerEvent) -> Void)?
) async throws -> Track {
    
    let start = ContinuousClock.now
    
    // Notify start
    onProgress?(.fileLoadStarted(track.url))
    
    // Create timeout task
    let timeoutTask = Task {
        try await Task.sleep(for: timeout)
        throw AudioEngineError.fileLoadTimeout(track.url, timeout)
    }
    
    // Create load task
    let loadTask = Task {
        let file = try AVAudioFile(forReading: track.url)
        return file
    }
    
    // Race: whichever completes first
    let result: AVAudioFile
    do {
        result = try await loadTask.value
        timeoutTask.cancel()
    } catch {
        loadTask.cancel()
        if Task.isCancelled || error is CancellationError {
            onProgress?(.fileLoadTimeout(track.url))
            throw AudioEngineError.fileLoadTimeout(track.url, timeout)
        }
        throw error
    }
    
    // Measure duration
    let duration = ContinuousClock.now - start
    onProgress?(.fileLoadCompleted(track.url, duration: duration))
    
    // Process file (existing logic)
    // ... extract metadata, store file ...
    
    return processedTrack
}

enum AudioEngineError: Error, LocalizedError {
    case fileLoadTimeout(URL, Duration)
    
    var errorDescription: String? {
        switch self {
        case .fileLoadTimeout(let url, let timeout):
            return "File load timeout after \(timeout.formatted()): \(url.lastPathComponent)"
        }
    }
}
```

### 3. Integrate Timeout in CrossfadeOrchestrator

```swift
// In performFullCrossfade, replace:

// OLD:
let trackWithMetadata = try await audioEngine.loadAudioFileOnSecondaryPlayer(track: track)

// NEW:
let expectedLoad = Duration.milliseconds(500)  // Expected I/O time
let adaptiveTimeout = await timeoutManager.adaptiveTimeout(
    for: expectedLoad,
    operation: "fileLoad"
)

let start = ContinuousClock.now
let trackWithMetadata = try await audioEngine.loadAudioFileWithTimeout(
    track: track,
    timeout: adaptiveTimeout,
    onProgress: { event in
        // Forward to observers
        notifyObservers(event)
    }
)
let actual = ContinuousClock.now - start

// Record for future adaptation
await timeoutManager.recordDuration(
    operation: "fileLoad",
    expected: expectedLoad,
    actual: actual
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

- [ ] PlayerEvent enum created
- [ ] loadAudioFileWithTimeout() implemented
- [ ] Timeout races with file load
- [ ] Progress callbacks fire
- [ ] CrossfadeOrchestrator uses adaptive timeout
- [ ] Duration recorded for adaptation
- [ ] Build passes

---

## Commit Template

```
[Stage 08] Add file I/O timeout + progress tracking

Wraps blocking file I/O with timeout protection:
- PlayerEvent enum for UI notifications
- loadAudioFileWithTimeout() in AudioEngineActor
- Adaptive timeout integration
- Progress callbacks (.fileLoadStarted/.Completed)

Prevents infinite hang on corrupted files.

Ref: .implementation-plan/stage-08-file-io-timeout.md
Build: ✅ Passes
```

---

## Next Stage

**Stage 09 - AsyncStream<PlayerEvent> for observers**
