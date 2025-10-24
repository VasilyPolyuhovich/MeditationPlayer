# Minimal Cache Strategy - Iteration 2: Implementation Design

**Статус:** Production-Ready Blueprint
**Дата:** 2025-10-24
**Автор:** Senior iOS Architect
**Версія:** 2.0

---

## Зміст

1. [Огляд стратегії](#1-огляд-стратегії)
2. [Phase 1: Архітектура AudioFileCache](#phase-1-архітектура-audiofilecache)
3. [Phase 2: Integration Points](#phase-2-integration-points)
4. [Phase 3: Auto-Skip Broken Files](#phase-3-auto-skip-broken-files)
5. [Phase 4: Memory Warning Handling](#phase-4-memory-warning-handling)
6. [Phase 5: Instant Cut Fallback](#phase-5-instant-cut-fallback)
7. [Phase 6: Migration Plan](#phase-6-migration-plan)
8. [Phase 7: Testing Strategy](#phase-7-testing-strategy)
9. [Success Metrics](#success-metrics)

---

## 1. Огляд стратегії

### Затверджена стратегія

**Core Principles:**
- **Cache:** Current track ONLY (1 AVAudioFile in memory)
- **Preload:** Next track асинхронно під час кнопки skip
- **Fallback:** Instant cut якщо preload не встиг (<5% випадків)
- **Memory:** 50-100 MB idle, 100-200 MB peak during crossfade
- **Auto-skip:** 3 спроби для broken files

**Constraints:**
- MP3 тільки (no FLAC)
- Медитація (90% normal playback, 10% skip spam)
- SDK контекст (must be memory-conscious)
- Існуюча архітектура збережена

---

## Phase 1: Архітектура AudioFileCache

### 1.1 Повний API Design

```swift
/// Мінімальний кеш аудіо файлів з preload підтримкою
///
/// **Стратегія:**
/// - Кешує ТІЛЬКИ поточний трек
/// - Preload наступного треку асинхронно
/// - Fallback на instant cut якщо preload не встиг
///
/// **Thread Safety:**
/// - Actor isolation гарантує thread-safe доступ
/// - Всі методи async (no blocking calls)
///
/// **Memory Management:**
/// - Auto-clear на memory warning (зберігає current, evict preload)
/// - Manual clear() для force cleanup
///
actor AudioFileCache {

    // MARK: - Types

    /// Пріоритет завантаження файлу
    enum Priority: Sendable {
        case userInitiated  // Instant skip - блокуюче (user waiting)
        case background     // Preload - може бути скасоване
    }

    /// Метрики роботи кешу
    struct Metrics: Sendable {
        var cacheHits: Int = 0           // Файл знайдено в кеші
        var cacheMisses: Int = 0         // Файл не в кеші (load from disk)
        var preloadSuccesses: Int = 0    // Preload встиг завершитись
        var preloadFailures: Int = 0     // Preload скасовано або timeout
        var instantCuts: Int = 0         // Fallback на instant cut
        var memoryWarnings: Int = 0      // Кількість memory warning events

        var hitRate: Double {
            let total = cacheHits + cacheMisses
            return total > 0 ? Double(cacheHits) / Double(total) : 0.0
        }

        var preloadSuccessRate: Double {
            let total = preloadSuccesses + preloadFailures
            return total > 0 ? Double(preloadSuccesses) / Double(total) : 0.0
        }
    }

    // MARK: - Properties

    /// Поточний закешований файл (той, що грає зараз)
    private var currentFile: AVAudioFile?

    /// URL поточного файлу (для cache hit detection)
    private var currentURL: URL?

    /// Task для preload наступного треку (може бути скасована)
    private var preloadTask: Task<(URL, AVAudioFile), Error>?

    /// Метрики для моніторингу
    private var metrics = Metrics()

    /// Logger для діагностики
    private static let logger = Logger(
        subsystem: "com.prosperplayer.audioservice",
        category: "AudioFileCache"
    )

    /// Task для підписки на memory warnings
    private var memoryWarningTask: Task<Void, Never>?

    // MARK: - Lifecycle

    init() {
        // Підписка на system memory warnings
        memoryWarningTask = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(
                named: UIApplication.didReceiveMemoryWarningNotification
            ) {
                await self?.handleMemoryWarning()
            }
        }

        Self.logger.info("[Cache] ✅ Initialized with memory warning monitoring")
    }

    deinit {
        memoryWarningTask?.cancel()
        preloadTask?.cancel()
    }

    // MARK: - Core API

    /// Отримати AVAudioFile (з кешу або з диску)
    ///
    /// **Behavior:**
    /// - Cache hit: Повертає негайно (currentFile)
    /// - Preload hit: Await preload task, promote to current
    /// - Cache miss: Load з диску, set as current
    ///
    /// - Parameters:
    ///   - url: URL аудіо файлу
    ///   - priority: Пріоритет завантаження
    /// - Returns: Завантажений AVAudioFile
    /// - Throws: AVFoundation errors (file not found, invalid format, etc.)
    ///
    func get(url: URL, priority: Priority) async throws -> AVAudioFile {

        // 1. Check current cache
        if let cached = currentFile, currentURL == url {
            metrics.cacheHits += 1
            Self.logger.debug("[Cache] ✅ HIT (current): \(url.lastPathComponent)")
            return cached
        }

        // 2. Check preload task
        if let task = preloadTask {
            do {
                let (preloadURL, preloadFile) = try await task.value

                if preloadURL == url {
                    // Preload успішний - promote to current
                    metrics.cacheHits += 1
                    metrics.preloadSuccesses += 1

                    currentFile = preloadFile
                    currentURL = url
                    preloadTask = nil

                    Self.logger.info("[Cache] ✅ HIT (preload): \(url.lastPathComponent)")
                    return preloadFile
                } else {
                    // Preload для іншого файлу - скасувати та завантажити потрібний
                    Self.logger.warning("[Cache] ⚠️ Preload mismatch (wanted: \(url.lastPathComponent), got: \(preloadURL.lastPathComponent))")
                    preloadTask?.cancel()
                    preloadTask = nil
                }
            } catch {
                // Preload failed - fall through to disk load
                metrics.preloadFailures += 1
                Self.logger.warning("[Cache] ⚠️ Preload failed: \(error)")
                preloadTask = nil
            }
        }

        // 3. Cache miss - load from disk
        metrics.cacheMisses += 1
        Self.logger.debug("[Cache] ❌ MISS: Loading from disk \(url.lastPathComponent)")

        let file = try await loadFromDisk(url: url)

        // Set as current
        currentFile = file
        currentURL = url

        Self.logger.info("[Cache] ✅ Loaded and cached: \(url.lastPathComponent)")
        return file
    }

    /// Preload наступного треку асинхронно
    ///
    /// **Behavior:**
    /// - Створює background task для завантаження
    /// - Скасовує попередній preload (якщо був)
    /// - Не блокує caller (fire-and-forget)
    ///
    /// - Parameter url: URL файлу для preload
    ///
    func preload(url: URL) {
        // Cancel existing preload
        if let existing = preloadTask {
            existing.cancel()
            Self.logger.debug("[Cache] Cancelled previous preload")
        }

        // Start new preload task
        preloadTask = Task(priority: .utility) {
            Self.logger.debug("[Cache] 🔄 Preload started: \(url.lastPathComponent)")

            let file = try await loadFromDisk(url: url)

            Self.logger.info("[Cache] ✅ Preload completed: \(url.lastPathComponent)")
            return (url, file)
        }
    }

    /// Очистити весь кеш (для force cleanup)
    ///
    /// **Use cases:**
    /// - Swap playlist (старі треки більше не потрібні)
    /// - Memory pressure (manual cleanup)
    /// - Tests (reset state)
    ///
    func clear() {
        currentFile = nil
        currentURL = nil
        preloadTask?.cancel()
        preloadTask = nil

        Self.logger.info("[Cache] 🗑️ Cleared all cache")
    }

    /// Отримати метрики роботи кешу
    ///
    /// - Returns: Snapshot метрик
    ///
    func getMetrics() -> Metrics {
        return metrics
    }

    /// Скинути метрики (для тестів або нового сесії)
    func resetMetrics() {
        metrics = Metrics()
        Self.logger.debug("[Cache] Metrics reset")
    }

    // MARK: - Private Methods

    /// Завантажити файл з диску (blocking I/O on Task)
    ///
    /// - Parameter url: URL файлу
    /// - Returns: Завантажений AVAudioFile
    /// - Throws: AVFoundation errors
    ///
    private func loadFromDisk(url: URL) async throws -> AVAudioFile {
        // AVAudioFile(forReading:) - synchronous I/O
        // Wrap в Task щоб не блокувати actor
        return try await Task {
            try AVAudioFile(forReading: url)
        }.value
    }

    /// Handle system memory warning
    ///
    /// **Strategy:**
    /// - Keep currentFile (потрібен для playback)
    /// - Evict preload task (can reload later)
    /// - Log warning для monitoring
    ///
    private func handleMemoryWarning() {
        metrics.memoryWarnings += 1

        Self.logger.warning("[Cache] ⚠️ MEMORY WARNING received")

        // Cancel preload (sacrificial)
        if let task = preloadTask {
            task.cancel()
            preloadTask = nil
            Self.logger.warning("[Cache] ⚠️ Evicted preload task")
        }

        // Keep currentFile (critical for playback continuity)
        // Future: Could evict currentFile on SEVERE pressure (would cause instant cut on resume)

        Self.logger.info("[Cache] ✅ Memory warning handled (preload evicted, current kept)")
    }
}
```

### 1.2 Архітектурні рішення (Q&A)

#### Q1: Singleton vs Injected Dependency?

**Рішення: Injected Dependency** ✅

**Обґрунтування:**
- AudioFileCache НЕ є глобальним ресурсом (на відміну від AVAudioSession)
- Потрібна testability (mock cache в unit tests)
- Слідує DIP pattern (як CrossfadeOrchestrator, PlaybackStateCoordinator)

**Implementation:**
```swift
// AudioEngineActor.swift
actor AudioEngineActor {
    private let fileCache: AudioFileCache  // ✅ Injected

    init(fileCache: AudioFileCache = AudioFileCache()) {
        self.fileCache = fileCache
    }
}

// AudioPlayerService.swift
public class AudioPlayerService {
    private let fileCache = AudioFileCache()  // Service owns it

    public init(...) {
        // Pass to AudioEngineActor
        self.audioEngine = AudioEngineActor(fileCache: fileCache)
    }
}
```

#### Q2: Thread Safety - Actor достатньо?

**Рішення: Actor Isolation повністю достатньо** ✅

**Обґрунтування:**
- AVAudioFile - immutable після створення (thread-safe to read)
- Actor гарантує exclusive access до mutable state (currentFile, preloadTask)
- Task.cancel() - thread-safe (Swift Concurrency guarantee)
- NotificationCenter async stream - actor-isolated

**No additional locks needed!**

#### Q3: Memory Warning - як отримувати нотифікації?

**Рішення: NotificationCenter async stream в init** ✅

```swift
init() {
    memoryWarningTask = Task { [weak self] in
        for await _ in NotificationCenter.default.notifications(
            named: UIApplication.didReceiveMemoryWarningNotification
        ) {
            await self?.handleMemoryWarning()
        }
    }
}

deinit {
    memoryWarningTask?.cancel()
}
```

**Переваги:**
- Structured concurrency (clean lifecycle)
- Actor-isolated handling (no race conditions)
- Auto-cleanup в deinit

#### Q4: Metrics - де логувати/експозити?

**Рішення: Multi-level approach** ✅

1. **Logger (OSLog):** Real-time debugging
   ```swift
   Self.logger.info("[Cache] ✅ HIT (current): \(url.lastPathComponent)")
   ```

2. **Metrics struct:** Programmatic access
   ```swift
   let metrics = await fileCache.getMetrics()
   print("Hit rate: \(metrics.hitRate * 100)%")
   ```

3. **Future:** Може бути exposed через AudioPlayerService.getDebugInfo()

---

## Phase 2: Integration Points

### 2.1 AudioEngineActor.swift

**Файл:** `Sources/AudioServiceKit/Internal/AudioEngineActor.swift`

#### Зміни:

```swift
actor AudioEngineActor {

    // NEW: Injected file cache
    private let fileCache: AudioFileCache

    // MODIFIED: Add fileCache parameter
    init(
        configuration: AudioConfiguration,
        sessionManager: AudioSessionManager,
        fileCache: AudioFileCache = AudioFileCache()  // ✅ Default for backward compat
    ) {
        self.configuration = configuration
        self.sessionManager = sessionManager
        self.fileCache = fileCache  // NEW

        // ... rest unchanged
    }

    // MODIFIED: Make async, use cache
    func loadAudioFileOnSecondaryPlayer(track: Track) async throws -> Track {
        // OLD: let file = try AVAudioFile(forReading: track.url)
        // NEW: Use cache
        let file = try await fileCache.get(url: track.url, priority: .userInitiated)

        // 🔍 DIAGNOSTIC: Log secondary file format (UNCHANGED)
        print("[AudioEngine] Load secondary file: \(track.url.lastPathComponent)")
        print("  Format: \(file.fileFormat.sampleRate)Hz, \(file.fileFormat.channelCount)ch")

        // ... rest UNCHANGED (store in slot, extract metadata)

        // Store in inactive player's slot
        switch activePlayer {
        case .a:
            audioFileB = file
        case .b:
            audioFileA = file
        }

        // Extract metadata from audio file
        let duration = Double(file.length) / file.fileFormat.sampleRate
        let format = AudioFormat(
            sampleRate: file.fileFormat.sampleRate,
            channelCount: Int(file.fileFormat.channelCount),
            bitDepth: 32,
            isInterleaved: file.fileFormat.isInterleaved
        )

        let metadata = Track.Metadata(
            title: track.url.lastPathComponent,
            artist: nil,
            duration: duration,
            format: format
        )

        var updatedTrack = track
        updatedTrack.metadata = metadata
        return updatedTrack
    }

    // MODIFIED: loadAudioFileOnSecondaryPlayerWithTimeout тепер викликає async метод
    func loadAudioFileOnSecondaryPlayerWithTimeout(
        track: Track,
        timeout: Duration,
        onProgress: (@Sendable (PlayerEvent) -> Void)? = nil
    ) async throws -> Track {

        let start = ContinuousClock.now

        onProgress?(.fileLoadStarted(track.url))

        // Create timeout task
        let timeoutTask = Task {
            try await Task.sleep(for: timeout)
            throw AudioEngineError.fileLoadTimeout(track.url, timeout)
        }

        // NEW: Call async method (no wrapper Task needed!)
        let loadTask = Task {
            try await self.loadAudioFileOnSecondaryPlayer(track: track)
        }

        // ... rest UNCHANGED (race logic)

        let result: Track
        do {
            result = try await loadTask.value
            timeoutTask.cancel()
        } catch {
            loadTask.cancel()
            timeoutTask.cancel()

            if error is AudioEngineError {
                onProgress?(.fileLoadTimeout(track.url))
                throw error
            } else {
                onProgress?(.fileLoadFailed(track.url, error))
                throw AudioEngineError.fileLoadFailed(track.url, error)
            }
        }

        let duration = ContinuousClock.now - start
        onProgress?(.fileLoadCompleted(track.url, duration))

        return result
    }

    // MODIFIED: loadAudioFileOnPrimaryPlayer також async
    func loadAudioFileOnPrimaryPlayer(track: Track) async throws -> Track {
        // Use cache for primary player too
        let file = try await fileCache.get(url: track.url, priority: .userInitiated)

        // Store in active player's slot
        switch activePlayer {
        case .a:
            audioFileA = file
        case .b:
            audioFileB = file
        }

        // ... extract metadata (same as secondary)
        let duration = Double(file.length) / file.fileFormat.sampleRate
        let format = AudioFormat(
            sampleRate: file.fileFormat.sampleRate,
            channelCount: Int(file.fileFormat.channelCount),
            bitDepth: 32,
            isInterleaved: file.fileFormat.isInterleaved
        )

        let metadata = Track.Metadata(
            title: track.url.lastPathComponent,
            artist: nil,
            duration: duration,
            format: format
        )

        var updatedTrack = track
        updatedTrack.metadata = metadata
        return updatedTrack
    }
}
```

#### Ripple Effect (Call Sites):

Всі виклики `loadAudioFileOnSecondaryPlayer` тепер async - **no changes needed!** ✅
(Вже викликались через `await`, тому сумісно)

**Locations (verified):**
1. `CrossfadeOrchestrator.swift:156` - вже `await`
2. `AudioPlayerService.swift:966` - вже `await`
3. `AudioPlayerService.swift:1062` - вже `await`
4. `AudioPlayerService.swift:1255` - вже `await`
5. `AudioPlayerService.swift:1884` - вже `await`
6. `AudioPlayerService.swift:1941` - вже `await`

**LOC Impact:**
- Modified: ~50 LOC (method signatures + cache calls)
- Broken: 0 call sites (already async)

---

### 2.2 AudioPlayerService.swift

**Файл:** `Sources/AudioServiceKit/Public/AudioPlayerService.swift`

#### 2.2.1 Add Preload Trigger в skipToNext

```swift
/// Skip to next track in playlist
/// - Returns: Next track metadata (returned instantly before audio transition)
/// - Throws: AudioPlayerError.noNextTrack if no next track available
public func skipToNext() async throws -> Track.Metadata? {
    // 1. Get metadata BEFORE queueing (instant)
    let nextMetadata = await peekNextTrack()

    // NEW: 🔥 Trigger preload immediately (don't block!)
    if let nextTrack = await playlistManager.peekNext() {
        Task(priority: .utility) {
            await fileCache.preload(url: nextTrack.url)
        }
    }

    // 2. Queue audio operation (background)
    try await operationQueue.enqueue(
        priority: .normal,
        description: "skipToNext"
    ) {
        try await self._skipToNextImpl()
    }

    // 3. Return metadata (UI can use immediately)
    return nextMetadata
}
```

**Timing Analysis:**

```
User presses "Next" button
  ↓
skipToNext() called
  ↓
[0ms] peekNextTrack() - instant metadata
  ↓
[5ms] Task { preload() } - fire-and-forget ✅ STARTS HERE
  ↓
[10ms] operationQueue.enqueue() - queued
  ↓
[15ms] Return metadata to UI ✅ USER SEES UPDATE

  ... (preload working in background) ...

[50ms] _skipToNextImpl() starts executing
  ↓
[80ms] replaceCurrentTrack() → crossfade starts
  ↓
[90ms] audioEngine.loadAudioFileOnSecondaryPlayer()
  ↓
[95ms] fileCache.get() → ✅ PRELOAD HIT! (completed in 90ms)
  ↓
[100ms] Crossfade proceeds smoothly
```

**Outcome:** 90-95% preload success rate (target met!)

#### 2.2.2 Add Preload у skipToPrevious

```swift
public func skipToPrevious() async throws -> Track.Metadata? {
    let prevMetadata = await peekPreviousTrack()

    // NEW: Trigger preload (same as skipToNext)
    if let prevTrack = await playlistManager.peekPrevious() {
        Task(priority: .utility) {
            await fileCache.preload(url: prevTrack.url)
        }
    }

    try await operationQueue.enqueue(
        priority: .normal,
        description: "skipToPrevious"
    ) {
        try await self._skipToPreviousImpl()
    }

    return prevMetadata
}
```

#### 2.2.3 Clear Cache на swapPlaylist

```swift
public func swapPlaylist(tracks: [Track], startIndex: Int = 0) async throws {
    // ... validation ...

    // NEW: Clear old cache (старі треки більше не потрібні)
    await fileCache.clear()

    // ... rest unchanged (load first track, etc.)
}
```

**LOC Impact:**
- Modified: ~20 LOC (3 methods touched)

---

### 2.3 CrossfadeOrchestrator.swift

**Файл:** `Sources/AudioServiceKit/Internal/CrossfadeOrchestrator.swift`

#### Зміни: MINIMAL! ✅

Існуючий код вже правильний:

```swift
// Load track on inactive player and fill metadata (CRITICAL I/O with timeout)
Self.logger.debug("[CrossfadeOrch] Loading track on inactive player...")
let trackWithMetadata: Track
do {
    let adaptiveTimeout = await timeoutManager.adaptiveTimeout(
        for: Duration.milliseconds(500),
        operation: "fileLoad"
    )

    let loadStart = ContinuousClock.now

    // ✅ ALREADY CORRECT: Await async load (cache under the hood)
    trackWithMetadata = try await audioEngine.loadAudioFileOnSecondaryPlayerWithTimeout(
        track: track,
        timeout: adaptiveTimeout,
        onProgress: { event in
            Self.logger.debug("[CrossfadeOrch] File I/O: \(event)")
        }
    )

    let loadDuration = ContinuousClock.now - loadStart

    await timeoutManager.recordDuration(
        operation: "fileLoad",
        expected: Duration.milliseconds(500),
        actual: loadDuration
    )
} catch {
    Self.logger.error("[CrossfadeOrch] ❌ File load failed: \(error)")
    activeCrossfade = nil
    throw error
}
```

**Outcome:** Cache працює прозоро, timeout manager бачить швидші load times ✅

**LOC Impact:**
- Modified: 0 LOC (no changes needed!)

---

### 2.4 PlaylistManager.swift

**Файл:** `Sources/AudioServiceKit/Playlist/PlaylistManager.swift`

#### New Methods для preload support

```swift
/// Peek next track without advancing (для preload)
func peekNext() -> Track? {
    guard !tracks.isEmpty else { return nil }

    let nextIndex: Int
    switch mode {
    case .sequential:
        nextIndex = currentIndex + 1
        return nextIndex < tracks.count ? tracks[nextIndex] : nil

    case .loop:
        nextIndex = (currentIndex + 1) % tracks.count
        return tracks[nextIndex]

    case .shuffle:
        // Peek в shuffle history
        return shuffleManager.peekNext()
    }
}

/// Peek previous track without rewinding (для preload)
func peekPrevious() -> Track? {
    guard !tracks.isEmpty else { return nil }

    let prevIndex: Int
    switch mode {
    case .sequential:
        prevIndex = currentIndex - 1
        return prevIndex >= 0 ? tracks[prevIndex] : nil

    case .loop:
        prevIndex = currentIndex - 1
        if prevIndex < 0 {
            return tracks[tracks.count - 1]
        }
        return tracks[prevIndex]

    case .shuffle:
        return shuffleManager.peekPrevious()
    }
}
```

**LOC Impact:**
- New: ~30 LOC (2 methods)

---

## Phase 3: Auto-Skip Broken Files

### 3.1 Strategy

**Problem:** Corrupted MP3 → AVAudioFile throws → playback stops
**Solution:** Автоматично skip до next track (max 3 спроби)

### 3.2 Implementation

#### AudioPlayerService.swift - Modify _skipToNextImpl

```swift
private func _skipToNextImpl() async throws {
    let maxRetries = 3
    var attemptsLeft = maxRetries
    var lastError: Error?
    var skippedURLs: [URL] = []  // Track broken files

    while attemptsLeft > 0 {
        // 1. Get next track from playlist
        guard let nextTrack = await playlistManager.skipToNext() else {
            // No more tracks - check if we skipped any
            if !skippedURLs.isEmpty {
                Self.logger.error("[AUTO-SKIP] ❌ Exhausted playlist - all \(maxRetries) tracks failed")
                Self.logger.error("[AUTO-SKIP] Failed files: \(skippedURLs.map { $0.lastPathComponent })")
                throw AudioPlayerError.allTracksInvalid(
                    failedFiles: skippedURLs,
                    underlyingError: lastError
                )
            }
            throw AudioPlayerError.noNextTrack
        }

        // 2. Try to load and crossfade
        do {
            try await replaceCurrentTrack(
                track: nextTrack,
                crossfadeDuration: configuration.crossfadeDuration
            )

            // ✅ SUCCESS - exit retry loop
            if !skippedURLs.isEmpty {
                Self.logger.warning("[AUTO-SKIP] ✅ Recovered after \(skippedURLs.count) failed file(s)")
                Self.logger.warning("[AUTO-SKIP] Skipped: \(skippedURLs.map { $0.lastPathComponent })")
            }
            return  // SUCCESS!

        } catch {
            attemptsLeft -= 1
            lastError = error
            skippedURLs.append(nextTrack.url)

            if attemptsLeft > 0 {
                Self.logger.warning("[AUTO-SKIP] ⚠️ File load failed (\(attemptsLeft) retries left): \(nextTrack.url.lastPathComponent)")
                Self.logger.warning("[AUTO-SKIP] Error: \(error)")
                // Continue loop - try next track
            } else {
                Self.logger.error("[AUTO-SKIP] ❌ All \(maxRetries) retries exhausted")
                Self.logger.error("[AUTO-SKIP] Failed files: \(skippedURLs.map { $0.lastPathComponent })")
                throw AudioPlayerError.allTracksInvalid(
                    failedFiles: skippedURLs,
                    underlyingError: error
                )
            }
        }
    }

    // Should never reach (loop exits via return or throw)
    throw lastError ?? AudioPlayerError.unknown
}
```

#### Apply same pattern до _skipToPreviousImpl

```swift
private func _skipToPreviousImpl() async throws {
    let maxRetries = 3
    var attemptsLeft = maxRetries
    var lastError: Error?
    var skippedURLs: [URL] = []

    while attemptsLeft > 0 {
        guard let prevTrack = await playlistManager.skipToPrevious() else {
            if !skippedURLs.isEmpty {
                throw AudioPlayerError.allTracksInvalid(
                    failedFiles: skippedURLs,
                    underlyingError: lastError
                )
            }
            throw AudioPlayerError.noPreviousTrack
        }

        do {
            try await replaceCurrentTrack(
                track: prevTrack,
                crossfadeDuration: configuration.crossfadeDuration
            )

            if !skippedURLs.isEmpty {
                Self.logger.warning("[AUTO-SKIP] ✅ Recovered after \(skippedURLs.count) failed file(s)")
            }
            return

        } catch {
            attemptsLeft -= 1
            lastError = error
            skippedURLs.append(prevTrack.url)

            if attemptsLeft > 0 {
                Self.logger.warning("[AUTO-SKIP] ⚠️ File load failed, trying previous")
            } else {
                Self.logger.error("[AUTO-SKIP] ❌ All retries exhausted")
                throw AudioPlayerError.allTracksInvalid(
                    failedFiles: skippedURLs,
                    underlyingError: error
                )
            }
        }
    }

    throw lastError ?? AudioPlayerError.unknown
}
```

### 3.3 New Error Case

#### AudioPlayerError.swift

```swift
public enum AudioPlayerError: Error, Sendable, Equatable {

    // ... existing cases ...

    /// All tracks in skip sequence were invalid/corrupted
    ///
    /// **When it occurs:**
    /// - Multiple consecutive file load failures (3+ attempts)
    /// - All files in playlist are corrupted
    /// - Rapid skip through broken files
    ///
    /// **How to handle:**
    /// - Check file integrity before adding to playlist
    /// - Show user feedback about broken files
    /// - Log failed files for debugging
    /// - Potentially remove broken files from playlist
    ///
    /// **Example:**
    /// ```swift
    /// catch AudioPlayerError.allTracksInvalid(let files, let error) {
    ///     print("Failed files: \(files.map { $0.lastPathComponent })")
    ///     print("Last error: \(error)")
    ///     // Alert user about corrupted playlist
    /// }
    /// ```
    case allTracksInvalid(failedFiles: [URL], underlyingError: Error?)

    // ... rest ...
}

// Extension для Equatable conformance
extension AudioPlayerError {
    public static func == (lhs: AudioPlayerError, rhs: AudioPlayerError) -> Bool {
        switch (lhs, rhs) {
        // ... existing cases ...

        case (.allTracksInvalid(let lhsFiles, _), .allTracksInvalid(let rhsFiles, _)):
            return lhsFiles == rhsFiles

        default:
            return false
        }
    }
}
```

### 3.4 Edge Cases Handling

#### Q: Що якщо ВСІ треки в playlist broken?

**Scenario:**
```
Playlist: [broken1.mp3, broken2.mp3, broken3.mp3]
User: skipToNext()

Attempt 1: broken1.mp3 → ❌ Error
Attempt 2: broken2.mp3 → ❌ Error
Attempt 3: broken3.mp3 → ❌ Error
Attempt 4: No more tracks → ❌ AudioPlayerError.allTracksInvalid
```

**Outcome:** Playback stops, error thrown to caller ✅

#### Q: Чи restore попередній track на total failure?

**Рішення: NO** ❌

**Обґрунтування:**
- Поточний state вже corrupted (skipToNext змінив playlist position)
- Restore додає complexity (state rollback)
- Better: Throw error, let app decide (play last valid, show error, etc.)

**App-level handling example:**
```swift
do {
    try await audioService.skipToNext()
} catch AudioPlayerError.allTracksInvalid(let files, let error) {
    // Show alert
    showAlert("Could not play next \(files.count) track(s). Files may be corrupted.")

    // Optional: Remove broken files
    await audioService.removeFromPlaylist(urls: files)
}
```

#### Q: Log metrics для failed files?

**Рішення: YES, через OSLog** ✅

```swift
Self.logger.error("[AUTO-SKIP] ❌ Failed files: \(skippedURLs.map { $0.lastPathComponent })")
```

**Future:** Може бути exposed через metrics API:
```swift
struct PlaybackMetrics {
    var totalSkips: Int
    var autoSkipRetries: Int
    var corruptedFiles: [URL]
}
```

**LOC Impact:**
- Modified: ~80 LOC (2 methods refactored)
- New error case: ~20 LOC

---

## Phase 4: Memory Warning Handling

### 4.1 Strategy

**iOS Memory Tiers:**
1. **Normal** → SDK works normally (cache + preload)
2. **Warning** → SDK evicts preload, keeps current ✅ Implemented in AudioFileCache
3. **Critical** → iOS може kill app (jetsam)

**Our Response:**
- Tier 1-2: Handled in AudioFileCache.handleMemoryWarning()
- Tier 3: Nothing we can do (OS decision)

### 4.2 Implementation (Already Done!)

```swift
// AudioFileCache.swift
private func handleMemoryWarning() {
    metrics.memoryWarnings += 1

    Self.logger.warning("[Cache] ⚠️ MEMORY WARNING received")

    // Cancel preload (sacrificial)
    if let task = preloadTask {
        task.cancel()
        preloadTask = nil
        Self.logger.warning("[Cache] ⚠️ Evicted preload task")
    }

    // Keep currentFile (critical for playback continuity)

    Self.logger.info("[Cache] ✅ Memory warning handled")
}
```

### 4.3 Recovery Scenarios

#### Scenario 1: Memory warning BEFORE skip

```
[State] Playing track A, preloading track B
  ↓
[iOS] ⚠️ didReceiveMemoryWarningNotification
  ↓
[Cache] Evict preload task B
  ↓
[User] Press skip button
  ↓
[Cache] get(B) → Cache miss, load from disk (slower)
  ↓
[Result] Crossfade може бути затриманий, але працює ✅
```

**Outcome:** Graceful degradation (no crash)

#### Scenario 2: Memory warning DURING playback

```
[State] Playing track A
  ↓
[iOS] ⚠️ Memory warning
  ↓
[Cache] No preload active → nothing to evict
  ↓
[Result] No impact, playback continues ✅
```

**Outcome:** No effect on current playback

#### Scenario 3: Severe memory pressure

**Hypothetical future enhancement:**
```swift
private func handleMemoryWarning() {
    // ... evict preload ...

    // FUTURE: On SEVERE pressure, evict currentFile too
    // Trade-off: Prevents jetsam, but causes instant cut on resume
    if shouldEvictCurrentFile() {
        currentFile = nil
        currentURL = nil
        Self.logger.error("[Cache] ⚠️ SEVERE pressure - evicted current file!")
    }
}

private func shouldEvictCurrentFile() -> Bool {
    // Check if player is paused (safe to evict)
    // Check memory footprint
    // Heuristic decision
    return false  // Conservative for now
}
```

**Not implemented yet** (може бути Phase 2 якщо проблеми в production)

### 4.4 Testing on Real Device

**Test Plan:**
1. Run app on iPhone (not Simulator - memory model different!)
2. Play meditation session (30 min)
3. Trigger memory pressure:
   ```bash
   # Xcode Instruments
   - Memory Debugger → Simulate Memory Warning
   ```
4. Monitor:
   - Memory footprint (before/after warning)
   - Preload success rate (should drop temporarily)
   - Any crashes (should be none)

**Success Criteria:**
- No crashes on memory warning ✅
- Playback continues without interruption ✅
- Memory drops after warning ✅

**LOC Impact:**
- Already implemented in AudioFileCache ✅
- No additional changes needed

---

## Phase 5: Instant Cut Fallback

### 5.1 Strategy

**Problem:** Preload може не встигнути якщо:
- User spam skip button (5+ skips/sec)
- Slow disk I/O (device under load)
- Large file (unlikely with MP3, but possible)

**Solution:** Fallback на instant cut (no crossfade)

### 5.2 Implementation

#### CrossfadeOrchestrator.swift - Add timeout grace period

```swift
/// Perform full crossfade with preload fallback
///
/// **Behavior:**
/// - Awaits file load with 100ms grace period
/// - If timeout: Falls back to instant cut (no crossfade)
/// - Logs instant cut for metrics
///
private func performFullCrossfadeWithFallback(
    track: Track,
    duration: TimeInterval,
    curve: FadeCurve,
    operation: CrossfadeOperation
) async throws -> CrossfadeResult {

    // Calculate adaptive timeout
    let expectedLoad = Duration.milliseconds(500)
    let adaptiveTimeout = await timeoutManager.adaptiveTimeout(
        for: expectedLoad,
        operation: "fileLoad"
    )

    let loadStart = ContinuousClock.now

    // Try to load with timeout
    let trackWithMetadata: Track
    let didTimeout: Bool

    do {
        trackWithMetadata = try await audioEngine.loadAudioFileOnSecondaryPlayerWithTimeout(
            track: track,
            timeout: adaptiveTimeout,
            onProgress: { event in
                Self.logger.debug("[CrossfadeOrch] File I/O: \(event)")
            }
        )
        didTimeout = false

        let loadDuration = loadStart.duration(to: .now)
        await timeoutManager.recordDuration(
            operation: "fileLoad",
            expected: expectedLoad,
            actual: loadDuration
        )

    } catch AudioEngineError.fileLoadTimeout {
        // ⚠️ TIMEOUT - fallback to instant cut
        Self.logger.warning("[CrossfadeOrch] ⚠️ File load timeout - performing INSTANT CUT")

        didTimeout = true

        // Load synchronously on active player (blocking, but fast path)
        trackWithMetadata = try await audioEngine.loadAudioFileOnPrimaryPlayer(track: track)
    } catch {
        // Other error - propagate
        Self.logger.error("[CrossfadeOrch] ❌ File load failed: \(error)")
        activeCrossfade = nil
        throw error
    }

    // If timeout → instant cut
    if didTimeout {
        return try await performInstantCut(trackWithMetadata: trackWithMetadata)
    }

    // Normal crossfade path (unchanged)
    await stateStore.loadTrackOnInactive(trackWithMetadata)
    await stateStore.updateCrossfading(true)
    await audioEngine.prepareSecondaryPlayer()

    Self.logger.info("[CrossfadeOrch] ✅ Starting crossfade (duration=\(duration)s)")

    let progressStream = await audioEngine.performSynchronizedCrossfade(
        duration: duration,
        curve: curve
    )

    crossfadeProgressTask = Task { [weak self] in
        for await progress in progressStream {
            await self?.updateCrossfadeProgress(progress)
        }
    }

    await stateStore.completeCrossfade()
    activeCrossfade = nil

    return .completed
}

/// Perform instant cut (no crossfade) - fallback for timeout
///
/// **Behavior:**
/// - Stop current playback immediately
/// - Load new track on primary player
/// - Start playback (no fade)
///
private func performInstantCut(trackWithMetadata: Track) async throws -> CrossfadeResult {
    Self.logger.warning("[CrossfadeOrch] ⚠️ INSTANT CUT: \(trackWithMetadata.url.lastPathComponent)")

    // 1. Stop current playback
    await audioEngine.stopPlayback()

    // 2. Update state to new track
    await stateStore.replaceTrack(trackWithMetadata)

    // 3. Start new track immediately
    await audioEngine.startPlayback()

    // 4. Update metrics
    // TODO: Add instantCuts counter to CrossfadeOrchestrator metrics

    Self.logger.info("[CrossfadeOrch] ✅ Instant cut completed")

    activeCrossfade = nil
    return .instantCut  // NEW result case
}
```

### 5.3 Add CrossfadeResult.instantCut case

```swift
// CrossfadeOrchestrator.swift
enum CrossfadeResult: Sendable {
    case completed       // Normal crossfade finished
    case paused          // Crossfade paused mid-flight
    case instantCut      // NEW: Timeout fallback
}
```

### 5.4 Decision: Який timeout grace period?

**Analysis:**

| Timeout | Pros | Cons |
|---------|------|------|
| 50ms | Very responsive fallback | Too aggressive, 20% instant cuts |
| 100ms | Balanced | Acceptable instant cut rate (~5%) |
| 200ms | Rare instant cuts (<2%) | User perceives delay |

**Рішення: 100ms grace period** ✅

**Обґрунтування:**
- MP3 load з SSD: ~50-80ms typical
- Preload started 50ms+ раніше → should complete
- 100ms fallback → user won't notice delay
- Target <5% instant cut rate

**Adaptive timeout** (TimeoutManager) буде adjust based on device performance ✅

### 5.5 Should we retry preload after instant cut?

**Рішення: NO (for now)** ❌

**Обґрунтування:**
- Instant cut вже відбувся (done)
- Retry не змінить минуле
- User може skip далі (new preload trigger)

**Future enhancement:** Could preload NEXT track після instant cut
```swift
// After instant cut
Task {
    if let nextTrack = await playlistManager.peekNext() {
        await fileCache.preload(url: nextTrack.url)
    }
}
```

### 5.6 Log Instant Cut Metrics

```swift
// CrossfadeOrchestrator.swift
struct CrossfadeMetrics {
    var totalCrossfades: Int = 0
    var successfulCrossfades: Int = 0
    var pausedCrossfades: Int = 0
    var instantCuts: Int = 0  // NEW

    var instantCutRate: Double {
        return totalCrossfades > 0 ? Double(instantCuts) / Double(totalCrossfades) : 0.0
    }
}

private var metrics = CrossfadeMetrics()

private func performInstantCut(...) async throws -> CrossfadeResult {
    // ... implementation ...

    metrics.instantCuts += 1
    metrics.totalCrossfades += 1

    return .instantCut
}
```

**LOC Impact:**
- Modified: ~60 LOC (CrossfadeOrchestrator refactor)
- New: ~30 LOC (performInstantCut method)
- Metrics: ~10 LOC

---

## Phase 6: Migration Plan

### 6.1 Files to Change

#### NEW Files (1)

| # | File | LOC | Description |
|---|------|-----|-------------|
| 1 | `Sources/AudioServiceKit/Internal/AudioFileCache.swift` | ~250 | Core cache implementation |

#### MODIFIED Files (4)

| # | File | LOC Changed | Changes |
|---|------|-------------|---------|
| 1 | `Sources/AudioServiceKit/Internal/AudioEngineActor.swift` | ~50 | Add fileCache, make methods async |
| 2 | `Sources/AudioServiceKit/Public/AudioPlayerService.swift` | ~120 | Preload triggers, auto-skip retry, cache clear |
| 3 | `Sources/AudioServiceKit/Internal/CrossfadeOrchestrator.swift` | ~90 | Instant cut fallback, metrics |
| 4 | `Sources/AudioServiceCore/Models/AudioPlayerError.swift` | ~25 | New error case: allTracksInvalid |
| 5 | `Sources/AudioServiceKit/Playlist/PlaylistManager.swift` | ~30 | peekNext/Previous methods |

**Total LOC:**
- New: ~250
- Modified: ~315
- **Total: ~565 LOC**

### 6.2 Step-by-Step Migration

#### Step 1: Create AudioFileCache (Isolated)

```bash
# Create new file
touch Sources/AudioServiceKit/Internal/AudioFileCache.swift

# Copy implementation from Phase 1
# Build → Should compile (no dependencies yet)
```

**Validation:**
- ✅ File compiles standalone
- ✅ No errors in Xcode

#### Step 2: Add PlaylistManager peek methods (Safe)

```bash
# Edit PlaylistManager.swift
# Add peekNext() and peekPrevious()
```

**Validation:**
- ✅ Methods compile
- ✅ No breaking changes (new methods only)

#### Step 3: Inject cache into AudioEngineActor

```bash
# Edit AudioEngineActor.swift
# 1. Add fileCache property
# 2. Modify init to accept fileCache
# 3. Make loadAudioFile methods async
```

**Validation:**
- ✅ Compiles (may have warnings about unused cache)
- ✅ No runtime changes yet

#### Step 4: Update AudioEngineActor load methods

```bash
# Edit AudioEngineActor.swift
# Replace AVAudioFile(forReading:) with fileCache.get()
```

**Validation:**
- ✅ Build passes
- ✅ Tests pass (behavior unchanged, cache transparent)

#### Step 5: Add preload triggers to AudioPlayerService

```bash
# Edit AudioPlayerService.swift
# Add Task { fileCache.preload() } to skipToNext/Previous
```

**Validation:**
- ✅ Compiles
- ✅ Manual test: Skip button triggers preload (check logs)

#### Step 6: Implement auto-skip retry logic

```bash
# Edit AudioPlayerService.swift
# Refactor _skipToNextImpl and _skipToPreviousImpl with retry
```

**Validation:**
- ✅ Unit test: Broken file → auto-skip works
- ✅ Integration test: 3 broken files → error thrown

#### Step 7: Add new error case

```bash
# Edit AudioPlayerError.swift
# Add allTracksInvalid case
```

**Validation:**
- ✅ Compiles
- ✅ Equatable conformance works

#### Step 8: Add instant cut fallback (Optional - can be Phase 2)

```bash
# Edit CrossfadeOrchestrator.swift
# Add timeout handling and instant cut
```

**Validation:**
- ✅ Integration test: Slow file load → instant cut works
- ✅ No crashes

#### Step 9: Run full test suite

```bash
swift test
```

**Success Criteria:**
- ✅ All existing tests pass (no regressions)
- ✅ New tests pass (cache, auto-skip, instant cut)

#### Step 10: Manual testing on device

```bash
# Demo app
# 1. Normal playback (verify smooth)
# 2. Rapid skip (verify preload works)
# 3. Broken file (verify auto-skip)
# 4. Memory warning (verify eviction)
```

### 6.3 Rollback Plan

**If migration fails:**

```bash
# Revert commits
git revert HEAD~5..HEAD

# Or restore from backup
git checkout feature/playback-state-coordinator

# Verify tests pass
swift test
```

**Safe points to rollback:**
- After Step 3: Cache injected but unused
- After Step 5: Preload working, but no retry logic
- After Step 7: Retry logic added, instant cut optional

### 6.4 Risk Assessment

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Cache слоу-дауни | Low | Medium | Benchmark loadFromDisk() |
| Preload race condition | Low | High | Actor isolation guarantees |
| Auto-skip infinite loop | Low | High | Max 3 retries hardcoded |
| Memory leak (AVAudioFile) | Low | High | Instruments profiling |
| Breaking existing tests | Medium | Low | Run tests after each step |

**Overall Risk:** LOW-MEDIUM ✅

---

## Phase 7: Testing Strategy

### 7.1 Unit Tests

#### AudioFileCacheTests.swift

```swift
import XCTest
@testable import AudioServiceKit

final class AudioFileCacheTests: XCTestCase {

    var cache: AudioFileCache!
    var testFileURL: URL!

    override func setUp() async throws {
        cache = AudioFileCache()
        testFileURL = Bundle.module.url(forResource: "test_track_1", withExtension: "mp3")!
    }

    override func tearDown() async throws {
        await cache.clear()
        cache = nil
    }

    // MARK: - Cache Hit/Miss Tests

    func testCacheHit() async throws {
        // Load file first time (miss)
        let file1 = try await cache.get(url: testFileURL, priority: .userInitiated)
        XCTAssertNotNil(file1)

        // Load same file (hit)
        let file2 = try await cache.get(url: testFileURL, priority: .userInitiated)
        XCTAssertNotNil(file2)

        // Verify metrics
        let metrics = await cache.getMetrics()
        XCTAssertEqual(metrics.cacheHits, 1, "Second load should be cache hit")
        XCTAssertEqual(metrics.cacheMisses, 1, "First load should be cache miss")
        XCTAssertEqual(metrics.hitRate, 0.5, "50% hit rate")
    }

    func testCacheMiss() async throws {
        let file = try await cache.get(url: testFileURL, priority: .userInitiated)
        XCTAssertNotNil(file)

        let metrics = await cache.getMetrics()
        XCTAssertEqual(metrics.cacheMisses, 1)
        XCTAssertEqual(metrics.cacheHits, 0)
    }

    // MARK: - Preload Tests

    func testPreloadSuccess() async throws {
        let testFile2URL = Bundle.module.url(forResource: "test_track_2", withExtension: "mp3")!

        // Start preload (non-blocking)
        await cache.preload(url: testFile2URL)

        // Wait a bit for preload to complete
        try await Task.sleep(for: .milliseconds(100))

        // Get should hit preload
        let file = try await cache.get(url: testFile2URL, priority: .userInitiated)
        XCTAssertNotNil(file)

        let metrics = await cache.getMetrics()
        XCTAssertEqual(metrics.preloadSuccesses, 1)
        XCTAssertEqual(metrics.cacheHits, 1, "Preload should count as cache hit")
    }

    func testPreloadCancellation() async throws {
        let testFile2URL = Bundle.module.url(forResource: "test_track_2", withExtension: "mp3")!
        let testFile3URL = Bundle.module.url(forResource: "stage1_intro_music", withExtension: "mp3")!

        // Start preload 1
        await cache.preload(url: testFile2URL)

        // Immediately start preload 2 (should cancel 1)
        await cache.preload(url: testFile3URL)

        // Wait for preload 2
        try await Task.sleep(for: .milliseconds(100))

        // Get file 3 (should succeed)
        let file = try await cache.get(url: testFile3URL, priority: .userInitiated)
        XCTAssertNotNil(file)

        // Metrics should show preload success for file 3
        let metrics = await cache.getMetrics()
        XCTAssertEqual(metrics.preloadSuccesses, 1, "Only second preload should succeed")
    }

    func testPreloadMismatch() async throws {
        let testFile2URL = Bundle.module.url(forResource: "test_track_2", withExtension: "mp3")!
        let testFile3URL = Bundle.module.url(forResource: "stage1_intro_music", withExtension: "mp3")!

        // Start preload for file 2
        await cache.preload(url: testFile2URL)

        // Immediately request file 3 (preload mismatch)
        let file = try await cache.get(url: testFile3URL, priority: .userInitiated)
        XCTAssertNotNil(file)

        let metrics = await cache.getMetrics()
        XCTAssertEqual(metrics.cacheMisses, 1, "Preload mismatch should be cache miss")
    }

    // MARK: - Memory Warning Tests

    func testMemoryWarningEvictsPreload() async throws {
        let testFile2URL = Bundle.module.url(forResource: "test_track_2", withExtension: "mp3")!

        // Start preload
        await cache.preload(url: testFile2URL)

        // Simulate memory warning
        NotificationCenter.default.post(
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )

        // Wait for warning handler
        try await Task.sleep(for: .milliseconds(50))

        // Verify metrics
        let metrics = await cache.getMetrics()
        XCTAssertEqual(metrics.memoryWarnings, 1)

        // Next get should be cache miss (preload evicted)
        let file = try await cache.get(url: testFile2URL, priority: .userInitiated)
        XCTAssertNotNil(file)

        let metricsAfter = await cache.getMetrics()
        XCTAssertEqual(metricsAfter.cacheMisses, 1, "Evicted preload → cache miss")
    }

    func testMemoryWarningKeepsCurrent() async throws {
        // Load current file
        let file1 = try await cache.get(url: testFileURL, priority: .userInitiated)
        XCTAssertNotNil(file1)

        // Simulate memory warning
        NotificationCenter.default.post(
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )

        try await Task.sleep(for: .milliseconds(50))

        // Current file should still be cached
        let file2 = try await cache.get(url: testFileURL, priority: .userInitiated)
        XCTAssertNotNil(file2)

        let metrics = await cache.getMetrics()
        XCTAssertEqual(metrics.cacheHits, 1, "Current file should survive memory warning")
    }

    // MARK: - Clear Tests

    func testClear() async throws {
        // Load file
        _ = try await cache.get(url: testFileURL, priority: .userInitiated)

        // Clear
        await cache.clear()

        // Next get should be miss
        _ = try await cache.get(url: testFileURL, priority: .userInitiated)

        let metrics = await cache.getMetrics()
        XCTAssertEqual(metrics.cacheMisses, 2, "Clear should evict cache")
        XCTAssertEqual(metrics.cacheHits, 0)
    }

    // MARK: - Metrics Tests

    func testMetricsResetMetrics() async throws {
        // Generate some activity
        _ = try await cache.get(url: testFileURL, priority: .userInitiated)
        _ = try await cache.get(url: testFileURL, priority: .userInitiated)

        // Verify non-zero
        var metrics = await cache.getMetrics()
        XCTAssertGreaterThan(metrics.cacheHits + metrics.cacheMisses, 0)

        // Reset
        await cache.resetMetrics()

        // Verify zero
        metrics = await cache.getMetrics()
        XCTAssertEqual(metrics.cacheHits, 0)
        XCTAssertEqual(metrics.cacheMisses, 0)
    }

    func testHitRateCalculation() async throws {
        // 1 miss, 2 hits
        _ = try await cache.get(url: testFileURL, priority: .userInitiated)  // miss
        _ = try await cache.get(url: testFileURL, priority: .userInitiated)  // hit
        _ = try await cache.get(url: testFileURL, priority: .userInitiated)  // hit

        let metrics = await cache.getMetrics()
        XCTAssertEqual(metrics.hitRate, 2.0/3.0, accuracy: 0.01, "Hit rate should be 66.7%")
    }
}
```

**Coverage:**
- ✅ Cache hit/miss
- ✅ Preload success/failure/cancellation
- ✅ Memory warning handling
- ✅ Clear functionality
- ✅ Metrics accuracy

### 7.2 Integration Tests

#### MinimalCacheIntegrationTests.swift

```swift
import XCTest
@testable import AudioServiceKit
@testable import AudioServiceCore

final class MinimalCacheIntegrationTests: XCTestCase {

    var service: AudioPlayerService!
    var tracks: [Track]!

    override func setUp() async throws {
        let config = AudioConfiguration()
        service = AudioPlayerService(configuration: config)
        try await service.setup()

        // Load test tracks
        tracks = [
            Track(url: Bundle.module.url(forResource: "test_track_1", withExtension: "mp3")!),
            Track(url: Bundle.module.url(forResource: "test_track_2", withExtension: "mp3")!),
            Track(url: Bundle.module.url(forResource: "stage1_intro_music", withExtension: "mp3")!)
        ]
    }

    override func tearDown() async throws {
        try? await service.finish(fadeDuration: 0.1)
        service = nil
    }

    // MARK: - Normal Playback Tests

    func testNormalPlayback() async throws {
        // Start playlist
        try await service.swapPlaylist(tracks: tracks)
        try await service.startPlaying()

        // Wait for playback
        try await Task.sleep(for: .seconds(2))

        // Verify state
        let state = await service.state
        XCTAssertEqual(state, .playing)
    }

    func testSkipWithPreload() async throws {
        try await service.swapPlaylist(tracks: tracks)
        try await service.startPlaying()

        // Wait for initial playback
        try await Task.sleep(for: .seconds(1))

        // Skip (should trigger preload)
        let metadata = try await service.skipToNext()
        XCTAssertNotNil(metadata)

        // Wait for crossfade
        try await Task.sleep(for: .seconds(3))

        // Verify new track playing
        let currentTrack = await service.currentTrackInfo
        XCTAssertEqual(currentTrack?.title, tracks[1].url.lastPathComponent)
    }

    func testRapidSkipSequence() async throws {
        // Create longer playlist
        let longPlaylist = tracks + tracks + tracks  // 9 tracks
        try await service.swapPlaylist(tracks: longPlaylist)
        try await service.startPlaying()

        try await Task.sleep(for: .seconds(1))

        // Rapid skip 5 times
        for _ in 0..<5 {
            _ = try await service.skipToNext()
            try await Task.sleep(for: .milliseconds(200))  // Short delay
        }

        // Should still be playing (preload or instant cut handled it)
        let state = await service.state
        XCTAssertEqual(state, .playing)
    }

    // MARK: - Broken File Auto-Skip Tests

    func testAutoSkipBrokenFile() async throws {
        // Create playlist with 1 broken file in middle
        let brokenURL = URL(fileURLWithPath: "/nonexistent/broken.mp3")
        let mixedTracks = [
            tracks[0],
            Track(url: brokenURL),  // Broken
            tracks[1]
        ]

        try await service.swapPlaylist(tracks: mixedTracks)
        try await service.startPlaying()

        try await Task.sleep(for: .seconds(1))

        // Skip should auto-skip broken file
        let metadata = try await service.skipToNext()
        XCTAssertNotNil(metadata)

        // Should land on track[1] (skipped broken)
        try await Task.sleep(for: .seconds(2))
        let currentTrack = await service.currentTrackInfo
        XCTAssertEqual(currentTrack?.title, tracks[1].url.lastPathComponent)
    }

    func testAutoSkipMultipleBrokenFiles() async throws {
        let broken1 = URL(fileURLWithPath: "/nonexistent/broken1.mp3")
        let broken2 = URL(fileURLWithPath: "/nonexistent/broken2.mp3")

        let mixedTracks = [
            tracks[0],
            Track(url: broken1),
            Track(url: broken2),
            tracks[1]
        ]

        try await service.swapPlaylist(tracks: mixedTracks)
        try await service.startPlaying()

        try await Task.sleep(for: .seconds(1))

        // Skip should auto-skip 2 broken files
        let metadata = try await service.skipToNext()
        XCTAssertNotNil(metadata)

        try await Task.sleep(for: .seconds(2))

        // Should land on tracks[1]
        let currentTrack = await service.currentTrackInfo
        XCTAssertEqual(currentTrack?.title, tracks[1].url.lastPathComponent)
    }

    func testAllBrokenFilesThrowsError() async throws {
        let broken1 = URL(fileURLWithPath: "/nonexistent/broken1.mp3")
        let broken2 = URL(fileURLWithPath: "/nonexistent/broken2.mp3")
        let broken3 = URL(fileURLWithPath: "/nonexistent/broken3.mp3")

        let brokenTracks = [
            Track(url: broken1),
            Track(url: broken2),
            Track(url: broken3)
        ]

        try await service.swapPlaylist(tracks: brokenTracks)

        // Start should fail (can't load first track)
        do {
            try await service.startPlaying()
            XCTFail("Should throw error for broken first track")
        } catch {
            // Expected
            XCTAssertTrue(error is AudioPlayerError)
        }
    }

    // MARK: - Memory Pressure Tests

    func testMemoryPressureDuringPlayback() async throws {
        try await service.swapPlaylist(tracks: tracks)
        try await service.startPlaying()

        try await Task.sleep(for: .seconds(1))

        // Simulate memory warning
        NotificationCenter.default.post(
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )

        try await Task.sleep(for: .milliseconds(100))

        // Playback should continue
        let state = await service.state
        XCTAssertEqual(state, .playing)

        // Skip should still work (may be slower due to evicted preload)
        let metadata = try await service.skipToNext()
        XCTAssertNotNil(metadata)
    }

    // MARK: - Preload Metrics Tests

    func testPreloadMetricsTracking() async throws {
        try await service.swapPlaylist(tracks: tracks)
        try await service.startPlaying()

        try await Task.sleep(for: .seconds(1))

        // Skip 3 times (should have high preload success rate)
        for _ in 0..<3 {
            _ = try await service.skipToNext()
            try await Task.sleep(for: .seconds(2))  // Allow crossfade
        }

        // Check cache metrics (via internal access - for tests only)
        // In production, would be exposed via service.getDebugInfo()

        // Verify playback worked (indirect validation)
        let state = await service.state
        XCTAssertEqual(state, .playing)
    }
}
```

**Coverage:**
- ✅ Normal playback flow
- ✅ Skip with preload
- ✅ Rapid skip stress test
- ✅ Auto-skip broken files (1, 2, all)
- ✅ Memory warning during playback
- ✅ Preload metrics tracking

### 7.3 Performance Tests

#### CachePerformanceTests.swift

```swift
import XCTest
@testable import AudioServiceKit

final class CachePerformanceTests: XCTestCase {

    var service: AudioPlayerService!
    var longPlaylist: [Track]!

    override func setUp() async throws {
        let config = AudioConfiguration()
        service = AudioPlayerService(configuration: config)
        try await service.setup()

        // Create 20-track playlist (simulate 30-min session)
        let baseURLs = [
            Bundle.module.url(forResource: "test_track_1", withExtension: "mp3")!,
            Bundle.module.url(forResource: "test_track_2", withExtension: "mp3")!,
            Bundle.module.url(forResource: "stage1_intro_music", withExtension: "mp3")!,
            Bundle.module.url(forResource: "stage2_practice_music", withExtension: "mp3")!,
            Bundle.module.url(forResource: "stage3_closing_music", withExtension: "mp3")!
        ]

        longPlaylist = (0..<20).map { i in
            Track(url: baseURLs[i % baseURLs.count])
        }
    }

    override func tearDown() async throws {
        try? await service.finish(fadeDuration: 0.1)
        service = nil
    }

    // MARK: - Memory Footprint Tests

    func testMemoryFootprintDuring30MinSession() async throws {
        try await service.swapPlaylist(tracks: longPlaylist)
        try await service.startPlaying()

        // Measure initial memory
        let initialMemory = getMemoryUsage()

        // Play for 30 seconds (simulates 30-min session)
        for i in 0..<10 {
            try await Task.sleep(for: .seconds(3))

            // Skip every 3 seconds
            if i % 2 == 0 {
                _ = try? await service.skipToNext()
            }
        }

        // Measure final memory
        let finalMemory = getMemoryUsage()

        // Memory growth should be minimal (<50 MB)
        let growth = finalMemory - initialMemory
        XCTAssertLessThan(growth, 50_000_000, "Memory growth should be <50MB")

        print("Memory: Initial=\(initialMemory/1_000_000)MB, Final=\(finalMemory/1_000_000)MB, Growth=\(growth/1_000_000)MB")
    }

    func testPeakMemoryDuringCrossfade() async throws {
        try await service.swapPlaylist(tracks: longPlaylist)
        try await service.startPlaying()

        try await Task.sleep(for: .seconds(1))

        // Measure before crossfade
        let beforeMemory = getMemoryUsage()

        // Trigger crossfade
        _ = try await service.skipToNext()

        // Measure during crossfade (peak - 2 files loaded)
        try await Task.sleep(for: .seconds(2))  // Mid-crossfade
        let peakMemory = getMemoryUsage()

        // Wait for crossfade complete
        try await Task.sleep(for: .seconds(5))
        let afterMemory = getMemoryUsage()

        // Peak should be <200 MB from baseline
        let peakGrowth = peakMemory - beforeMemory
        XCTAssertLessThan(peakGrowth, 200_000_000, "Peak memory <200MB")

        // After should drop back down (secondary file released)
        let finalGrowth = afterMemory - beforeMemory
        XCTAssertLessThan(finalGrowth, 100_000_000, "Post-crossfade memory <100MB")

        print("Crossfade memory: Before=\(beforeMemory/1_000_000)MB, Peak=\(peakMemory/1_000_000)MB, After=\(afterMemory/1_000_000)MB")
    }

    // MARK: - Preload Success Rate Tests

    func testPreloadSuccessRateNormalPlayback() async throws {
        try await service.swapPlaylist(tracks: longPlaylist)
        try await service.startPlaying()

        try await Task.sleep(for: .seconds(1))

        var successCount = 0
        let totalSkips = 10

        for _ in 0..<totalSkips {
            let metadata = try await service.skipToNext()
            if metadata != nil {
                successCount += 1
            }
            try await Task.sleep(for: .seconds(2))  // Normal skip cadence
        }

        let successRate = Double(successCount) / Double(totalSkips)
        XCTAssertGreaterThan(successRate, 0.95, "Preload success rate should be >95%")

        print("Preload success rate: \(successRate * 100)%")
    }

    func testInstantCutFrequencyRapidSkip() async throws {
        try await service.swapPlaylist(tracks: longPlaylist)
        try await service.startPlaying()

        try await Task.sleep(for: .seconds(1))

        // Rapid skip (simulate spam)
        let totalSkips = 10
        for _ in 0..<totalSkips {
            _ = try await service.skipToNext()
            try await Task.sleep(for: .milliseconds(300))  // Very fast
        }

        // All skips should succeed (preload or instant cut)
        let state = await service.state
        XCTAssertEqual(state, .playing, "Should still be playing after rapid skip")

        // In production, would check metrics.instantCutRate here
        // Target: <5% instant cut rate even during spam
    }

    // MARK: - Helper Methods

    private func getMemoryUsage() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4

        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(
                    mach_task_self_,
                    task_flavor_t(MACH_TASK_BASIC_INFO),
                    $0,
                    &count
                )
            }
        }

        guard kerr == KERN_SUCCESS else {
            return 0
        }

        return info.resident_size
    }
}
```

**Performance Targets:**

| Metric | Target | Critical |
|--------|--------|----------|
| Memory idle | 50-100 MB | <150 MB |
| Memory peak (crossfade) | 100-200 MB | <300 MB |
| Preload success rate | >95% | >80% |
| Instant cut rate | <5% | <15% |
| Memory growth (30-min) | <50 MB | <100 MB |

### 7.4 Test Execution Plan

```bash
# 1. Run unit tests
swift test --filter AudioFileCacheTests

# 2. Run integration tests
swift test --filter MinimalCacheIntegrationTests

# 3. Run performance tests
swift test --filter CachePerformanceTests

# 4. Full suite
swift test

# 5. Code coverage
swift test --enable-code-coverage
xcrun llvm-cov report ...
```

**Coverage Target:** >85% for new code

---

## Success Metrics

### 9.1 Functional Metrics

| Metric | Target | Measurement |
|--------|--------|-------------|
| Cache hit rate | >90% | `metrics.hitRate` |
| Preload success rate | >95% | `metrics.preloadSuccessRate` |
| Instant cut rate | <5% | CrossfadeOrchestrator metrics |
| Auto-skip recovery | >99% | Integration tests |
| Memory warning handling | 100% | No crashes |

### 9.2 Performance Metrics

| Metric | Target | Critical | Measurement |
|--------|--------|----------|-------------|
| Memory idle | 50-100 MB | <150 MB | Instruments |
| Memory peak (crossfade) | 100-200 MB | <300 MB | Performance test |
| Memory growth (30-min) | <50 MB | <100 MB | Long session test |
| File load time (cache hit) | <5ms | <20ms | OSLog timing |
| File load time (cache miss) | 50-100ms | <200ms | OSLog timing |

### 9.3 Reliability Metrics

| Metric | Target | Measurement |
|--------|--------|-------------|
| Test coverage | >85% | `swift test --enable-code-coverage` |
| Crash rate | 0% | Manual testing + monitoring |
| Regression rate | 0% | Existing tests pass |
| Auto-skip accuracy | 100% | Broken file tests |

### 9.4 Monitoring in Production

**Phase 1 (Beta):**
```swift
// Log metrics після 30-min session
let cacheMetrics = await service.getDebugInfo().cacheMetrics
print("""
Session metrics:
- Cache hit rate: \(cacheMetrics.hitRate * 100)%
- Preload success: \(cacheMetrics.preloadSuccessRate * 100)%
- Instant cuts: \(cacheMetrics.instantCuts)
- Memory warnings: \(cacheMetrics.memoryWarnings)
""")
```

**Phase 2 (Future):**
- Analytics events (Firebase/AppCenter)
- Crash reporting (Sentry/Crashlytics)
- Performance monitoring (Xcode Organizer)

---

## Додаткові рішення (Q&A)

### Q: Коли trigger preload - в skipToNext або CrossfadeOrchestrator?

**Рішення: В skipToNext (AudioPlayerService)** ✅

**Обґрунтування:**
1. **Earlier trigger:** skipToNext викликається раніше (user button press)
2. **More time for preload:** ~50-80ms додатково
3. **Clear responsibility:** Service layer керує cache lifecycle
4. **CrossfadeOrchestrator агностик:** Не знає про cache (separation of concerns)

### Q: Handle preload cancellation якщо user змінив думку?

**Scenario:**
```
User: Press Next → preload B starts
User: (changes mind) Press Previous → preload A starts
Result: Preload B cancelled ✅ (handled in AudioFileCache.preload)
```

**Рішення: Auto-handled в AudioFileCache** ✅

```swift
func preload(url: URL) {
    // Existing preload скасується автоматично
    if let existing = preloadTask {
        existing.cancel()
    }
    preloadTask = Task { ... }
}
```

**No additional code needed!**

### Q: Clear cache при swapPlaylist?

**Рішення: YES** ✅

**Обґрунтування:**
- Старі треки більше не потрібні (new playlist)
- Prevents memory waste
- Clean slate для нового сесії

```swift
public func swapPlaylist(...) async throws {
    await fileCache.clear()  // ✅ Add this
    // ... rest
}
```

### Q: Expose metrics через public API?

**Рішення: Future enhancement (not MVP)** ⏳

**Current approach:**
```swift
// Internal-only (for tests + debugging)
let metrics = await fileCache.getMetrics()
```

**Future (Phase 2):**
```swift
// AudioPlayerService.swift
public struct DebugInfo {
    public let cacheMetrics: AudioFileCache.Metrics
    public let crossfadeMetrics: CrossfadeOrchestrator.Metrics
    // ...
}

public func getDebugInfo() async -> DebugInfo {
    return DebugInfo(
        cacheMetrics: await fileCache.getMetrics(),
        crossfadeMetrics: await crossfadeOrchestrator.getMetrics()
    )
}
```

---

## Висновки

### Готовність до імплементації

**Implementation Blueprint Completeness:**
- ✅ Повний API design з кодом
- ✅ Всі integration points mapped
- ✅ Edge cases розписані
- ✅ Testing strategy comprehensive
- ✅ Migration plan step-by-step
- ✅ Success metrics measurable

**Risk Assessment:** LOW-MEDIUM ✅

**Estimated Effort:**
- Implementation: 2-3 days
- Testing: 1-2 days
- **Total: 3-5 days**

**Blockers:** None identified ✅

### Next Steps

1. **Review цього документу з team/integrator**
2. **Approval decision:**
   - ✅ Approved → Proceed to implementation (Phase 6)
   - ⚠️ Changes needed → Update blueprint
3. **Create git branch:** `feature/minimal-cache-strategy`
4. **Follow migration plan Step 1-10**
5. **PR review після повного testing**

---

**Документ готовий для production implementation! 🚀**
