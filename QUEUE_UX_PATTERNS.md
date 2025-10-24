# Task Queue - UX & System Patterns

**Goal:** Serialize operations WITHOUT creating laggy UX

---

## 1. Navigation Coalescing vs Instant Feedback

### Industry Pattern: Optimistic UI Update

**How AVPlayer / Spotify / Apple Music handle rapid Next:**

```swift
// ❌ WRONG: Wait for operation to complete
func onNextTapped() {
    showLoadingSpinner()
    await player.skipToNext()  // Wait 5-15s
    updateTrackInfo()
    hideLoadingSpinner()
}

// ✅ CORRECT: Optimistic update + background operation
func onNextTapped() {
    // 1. Instant UI update (optimistic)
    let nextTrack = playlist.peekNext()
    displayTrackInfo(nextTrack)  // INSTANT feedback
    
    // 2. Queue operation in background
    Task {
        do {
            try await player.skipToNext()
            // UI already updated, no action needed
        } catch {
            // Rollback UI on error
            displayTrackInfo(previousTrack)
            showError(error)
        }
    }
}
```

**Implementation in AudioPlayerService:**

```swift
public actor AudioPlayerService {
    
    // Public: Returns INSTANTLY with next track info
    public func peekNextTrack() async -> Track.Metadata? {
        return await playlistManager.peekNext()
    }
    
    // Public: Queued execution, but returns track info INSTANTLY
    public func skipToNext() async throws -> Track.Metadata {
        let nextTrack = await playlistManager.peekNext()
        
        // Queue the actual audio operation
        try await enqueueOperation(.skipToNext) {
            try await _skipToNextImpl()
        }
        
        return nextTrack  // UI can use this instantly
    }
}
```

**UI Layer:**
```swift
// SwiftUI Demo
Button("Next") {
    Task {
        // Instant UI update
        if let nextTrack = await player.peekNextTrack() {
            currentTrackInfo = nextTrack  // INSTANT
        }
        
        // Background queue operation
        try? await player.skipToNext()
    }
}
```

**Result:** UI feels instant, audio transitions properly queued.

---

## 2. System-Controlled Operations - Timeout Wrapper

### Pattern: Defensive Timeout with User Feedback

```swift
enum OperationResult<T> {
    case success(T)
    case timeout(Duration, String)  // timeout duration, operation name
    case systemError(Error)
}

func withSystemTimeout<T>(
    _ duration: Duration,
    operation: String,
    @Sendable _ body: () async throws -> T
) async -> OperationResult<T> {
    
    let timeoutTask = Task {
        try await Task.sleep(for: duration)
        return OperationResult<T>.timeout(duration, operation)
    }
    
    let operationTask = Task {
        do {
            let result = try await body()
            return OperationResult.success(result)
        } catch {
            return OperationResult<T>.systemError(error)
        }
    }
    
    let result = await Task.select(timeoutTask, operationTask)
    
    timeoutTask.cancel()
    operationTask.cancel()
    
    return result
}
```

**Usage for File I/O:**

```swift
// In AudioEngineActor
func loadAudioFileOnSecondaryPlayer(track: Track) async throws -> Track {
    
    let result = await withSystemTimeout(.seconds(5), operation: "File I/O") {
        try AVAudioFile(forReading: track.url)
    }
    
    switch result {
    case .success(let file):
        // Store file, continue
        return processedTrack
        
    case .timeout(let duration, let op):
        // Log + notify user
        logger.error("⏱️ \(op) timeout after \(duration)")
        notifyObservers(.fileLoadTimeout(track.url))
        throw AudioPlayerError.fileLoadTimeout
        
    case .systemError(let error):
        // System error (file not found, permissions, etc.)
        logger.error("💥 System error: \(error)")
        notifyObservers(.fileLoadError(track.url, error))
        throw AudioPlayerError.invalidAudioFile(error)
    }
}
```

**User Notification:**

```swift
// New observer event
public enum PlayerEvent {
    case fileLoadTimeout(URL)           // Show "Track loading slow..." toast
    case fileLoadError(URL, Error)      // Show "Cannot load track" error
    case audioSessionInterruption       // iOS system interruption
    case crossfadeTimeout               // "Audio transition delayed"
}

// Demo app handles
player.addObserver { event in
    switch event {
    case .fileLoadTimeout(let url):
        showToast("⏱️ Loading \(url.lastPathComponent) is taking longer than expected...")
    case .fileLoadError(let url, let error):
        showAlert("❌ Cannot load track", error.localizedDescription)
    case .crossfadeTimeout:
        showToast("⚠️ Audio transition delayed, please wait...")
    }
}
```

---

## 3. Progress Tracking - File Load & Crossfade

### Current Problem:
```swift
try await audioEngine.loadAudioFileOnSecondaryPlayer(track)
// ^^^ Blocks 100-500ms, no feedback
```

### Solution: Progress Stream

```swift
// AudioEngineActor - return progress stream
func loadAudioFileWithProgress(track: Track) -> AsyncStream<LoadProgress> {
    AsyncStream { continuation in
        Task {
            continuation.yield(.started)
            
            // Measure I/O time
            let start = ContinuousClock.now
            
            do {
                let file = try AVAudioFile(forReading: track.url)
                let duration = ContinuousClock.now - start
                
                continuation.yield(.completed(duration: duration))
                continuation.finish()
            } catch {
                continuation.yield(.failed(error))
                continuation.finish()
            }
        }
    }
}

enum LoadProgress {
    case started
    case completed(duration: Duration)
    case failed(Error)
}
```

**Usage in CrossfadeOrchestrator:**

```swift
func startCrossfade(...) async throws -> CrossfadeResult {
    
    // Stream progress to UI
    for await progress in audioEngine.loadAudioFileWithProgress(track) {
        switch progress {
        case .started:
            notifyObservers(.fileLoadStarted(track.url))
        case .completed(let duration):
            logger.info("✅ File loaded in \(duration.formatted())")
        case .failed(let error):
            throw error
        }
    }
    
    // Continue with crossfade...
}
```

**UI shows loading:**
```swift
// Demo app
.onReceive(player.events) { event in
    switch event {
    case .fileLoadStarted(let url):
        showLoadingIndicator(for: url)  // Small spinner on track card
    case .fileLoadCompleted:
        hideLoadingIndicator()
    }
}
```

---

## 4. Adaptive Timeout - System Load Detection

### Problem: False Positives

Fade takes 2.1x expected → timeout fires → but fade actually completing

### Solution: System Load Aware Timeout

```swift
actor TimeoutManager {
    
    // Measure system responsiveness
    private var recentOperationDurations: [Duration] = []
    private let maxSamples = 10
    
    func recordDuration(_ duration: Duration, expected: Duration) {
        recentOperationDurations.append(duration)
        if recentOperationDurations.count > maxSamples {
            recentOperationDurations.removeFirst()
        }
    }
    
    func adaptiveTimeout(for expected: Duration) -> Duration {
        // Calculate average slowdown factor
        let slowdownFactors = recentOperationDurations.map { actual in
            actual / expected
        }
        
        let avgSlowdown = slowdownFactors.reduce(0, +) / Double(slowdownFactors.count)
        
        // Clamp between 2x and 5x
        let multiplier = max(2.0, min(5.0, avgSlowdown * 1.5))
        
        return expected * multiplier
    }
}
```

**Usage:**

```swift
let expectedFade = Duration.seconds(0.3)
let adaptiveTimeout = await timeoutManager.adaptiveTimeout(for: expectedFade)

try await withTimeout(adaptiveTimeout) {
    await fadeVolume(...)
}

// Record actual duration for future adaptation
let actualDuration = ContinuousClock.now - start
await timeoutManager.recordDuration(actualDuration, expected: expectedFade)
```

**Result:** Timeout adapts to device performance (old iPhone vs M4 iPad)

---

## 5. How Other Players Handle Queue "Lag"

### Research: AVPlayer, Spotify, Apple Music

**Pattern 1: Instant State + Queued Action**
```
User taps Next
├─ [0ms] UI updates (shows next track)
├─ [0ms] Button disabled (prevent spam)
├─ [50ms] Audio crossfade starts (queued)
└─ [5s] Crossfade completes → button enabled
```

**Pattern 2: Visual Queue Indicator**
```
Apple Music: Shows "..." on track title while loading
Spotify: Dims next track card while transitioning
YouTube Music: Shows small spinner on playback bar
```

**Pattern 3: Operation Cancellation**
```
User: Next → Next → Pause
      └─ First Next cancelled
      └─ Second Next cancelled
      └─ Pause executes immediately
```

**Implementation for AudioServiceKit:**

```swift
public enum OperationPriority {
    case low        // playlist mutations, configuration
    case normal     // navigation (next/prev)
    case high       // transport (pause/stop) - can cancel normal
    case critical   // system (interruption) - cancels everything
}

actor OperationQueue {
    private var queue: [(priority: OperationPriority, op: Operation)] = []
    
    func enqueue(_ priority: OperationPriority, _ op: Operation) {
        if priority == .high || priority == .critical {
            // Cancel lower priority operations
            queue.removeAll { $0.priority.rawValue < priority.rawValue }
        }
        queue.append((priority, op))
    }
}
```

**UX Result:**
```
User: Next → Next → Pause
      └─ First Next queued (normal)
      └─ Second Next queued (normal)
      └─ Pause arrives (high) → cancels both Next → executes immediately
```

User gets instant pause, feels responsive.

---

## 6. Final UX Strategy for AudioServiceKit

### A. Instant Feedback (All Operations)
```swift
// Every operation returns metadata INSTANTLY
public func skipToNext() async throws -> Track.Metadata {
    let nextTrack = await playlistManager.peekNext()
    // UI uses nextTrack immediately
    
    try await enqueueOperation(.skipToNext) { ... }
    return nextTrack
}
```

### B. Progress Events (Long Operations)
```swift
// Operations >1s emit progress
public AsyncStream<PlayerEvent> events {
    // .fileLoadStarted, .crossfadeProgress(0.5), etc.
}
```

### C. Priority Cancellation (User Trumps Queue)
```swift
// Pause/Stop cancel queued navigation
func pause() async throws {
    cancelQueuedOperations(below: .high)
    try await enqueueOperation(.pause, priority: .high) { ... }
}
```

### D. Smart Timeouts (Adaptive)
```swift
// Timeout adapts to device performance
// Old iPhone: 5x multiplier
// New iPad: 2x multiplier
```

### E. Visual Queue State (Demo App)
```swift
// Show queue depth in UI
Text("Queued: \(player.queuedOperationCount)")
    .foregroundColor(queuedCount > 1 ? .orange : .clear)
```

---

## Implementation Checklist

- [ ] Add `peekNext()`/`peekPrevious()` for instant UI
- [ ] Return `Track.Metadata` from all navigation methods
- [ ] Add `AsyncStream<PlayerEvent>` for progress
- [ ] Implement priority-based cancellation
- [ ] Add adaptive timeout manager
- [ ] Wrap file I/O with timeout + progress
- [ ] Demo app: optimistic UI updates
- [ ] Demo app: loading indicators for slow ops
- [ ] Demo app: queue depth indicator (debug)

---

## Performance Targets

| Metric | Target | Current | After Queue |
|--------|--------|---------|-------------|
| Next tap → UI update | <50ms | ~200ms | <20ms (optimistic) |
| Pause during crossfade | <100ms | ~1s | <50ms (cancel + priority) |
| File load feedback | Instant | None | Progress stream |
| False timeout rate | <1% | N/A | <1% (adaptive) |

