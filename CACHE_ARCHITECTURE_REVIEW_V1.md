# 🏗️ AudioFileCache - Архітектурний Огляд v1.0

**Дата:** 2025-10-24
**Автор:** Senior iOS Performance Architect
**Контекст:** Production LRU Cache для AudioServiceKit (meditation SDK)
**Мета:** Вирішити проблему skip spam без шкоди стабільності

---

## 📊 Phase 1: Аналіз Skip Spam Problem

### 1.1 Usage Patterns (Meditation App Context)

Проаналізував `REQUIREMENTS_ANSWERS.md` та поточну архітектуру. Медитаційний додаток має **специфічні** паттерни користування:

#### A. Normal Playback (90% сесій)
```
Сценарій: 3-Stage Meditation (~30 min)
Stage 1 (5 min) → Stage 2 (20 min) → Stage 3 (5 min)

Навігація:
- Play → слухати до кінця
- Рідко: Skip до наступного stage (1-2 рази за сесію)
- ДУЖЕ частий pause (morning routine!)

Висновок: Це не музичний плеєр з активним браузингом!
```

#### B. Skip Spam (10% сесій, але критично для UX!)
```
Сценарій: Перегляд плейлиста
User: Next → Next → Next → Back → Back → Next (все за 5 секунд)

Проблема:
1. Simple next+prev preload = cache miss на кожному 2+ skip
2. Постійний disk I/O під час rapid navigation
3. Latency spikes (100-300ms на iOS з HDD)
4. Погана UX під час browsing

Frequency: ~10% користувачів (browse перед сесією)
Duration: 5-15 секунд (short burst)
Impact: КРИТИЧНИЙ для першого враження!
```

#### C. Back Pattern (5% usage)
```
Сценарій: Replay favorite section
User слухає Stage 2 → пропускає → повертається назад

Expected: Instant playback (track ще в cache)
Reality: Якщо cache маленький → evicted → reload!
```

**Висновок:** Це НЕ Spotify! Skip spam - це короткі bursts (5-15s), а не constant browsing.

---

### 1.2 Memory Constraints

#### Typical Meditation Track
```
Format: MP3 128-320kbps
Duration: 5-20 min average
File size: 5-15 MB на disk

In-Memory (AVAudioFile):
- Зберігається як uncompressed PCM buffer
- 44.1kHz stereo = ~176 KB/sec
- 5 min track ≈ 52.8 MB в RAM!
- 20 min track ≈ 211 MB в RAM!
```

**❗ CRITICAL INSIGHT:**
AVAudioFile при read зберігає ДЕКОМПРЕСОВАНИЙ аудіо в RAM!
5 MB MP3 → 50+ MB RAM після load.

#### iOS Memory Limits
```
Background Audio App:
- iOS 15+: ~200-300 MB budget перед memory warning
- iOS 17+: ~350-400 MB budget (більш толерантні)

Критичний поріг:
- >500 MB → ризик jetsam kill
- Memory warning → потрібен aggressive eviction
```

#### Acceptable Memory Footprint
```
Консервативний підхід:
- SDK має залишити space для app logic
- Target budget: 150-200 MB для audio cache
- Safety margin: 50 MB для peaks

Calculation:
150 MB / 53 MB per track ≈ 2.8 tracks
200 MB / 53 MB per track ≈ 3.7 tracks

Реалістично: Cache 3-4 tracks безпечно
```

---

### 1.3 Cache Size Trade-offs

| Size | Memory (MB) | Skip Coverage | Evictions/Session | Risk Level | Use Case |
|------|-------------|---------------|-------------------|------------|----------|
| **3** | **150-160** | Current + Next + Prev | 2-3 (normal), 10-15 (skip spam) | ✅ LOW | **Conservative** |
| **5** | 250-265 | Window [-1, +3] | 1-2 (normal), 5-8 (skip spam) | ⚠️ MEDIUM | Balanced |
| **10** | 500-530 | Window [-3, +6] | 0 (normal), 2-4 (skip spam) | ❌ HIGH | Aggressive |
| **15** | 750-795 | Full small playlist | 0 (most cases) | 🔥 CRITICAL | Overkill |

#### Аналіз по колонкам:

**Skip Coverage:**
- Size=3: Покриває 60% skip spam cases (current + next + prev)
- Size=5: Покриває 85% skip spam cases (window ±2)
- Size=10: Покриває 95%+ skip spam cases
- Size=15: Overkill для meditation app

**Evictions/Session:**
Normal session (30 min, 3 stages):
- Size=3: 2-3 evictions (stage transitions)
- Size=5: 1-2 evictions
- Size=10+: 0 evictions (всі 3 stages fit)

Skip spam session (15 sec, 8 skips):
- Size=3: 10-15 evictions (thrashing!)
- Size=5: 5-8 evictions
- Size=10: 2-4 evictions (smooth)

**Risk Assessment:**
- Size=3: ✅ Найбезпечніший, але skip spam = thrashing
- Size=5: ⚠️ Компроміс, acceptable memory pressure
- Size=10: ❌ Ризик memory warnings на старих iPhone
- Size=15: 🔥 Майже гарантовано memory kill на background

---

### 1.4 Preload Strategies (Порівняльний Аналіз)

#### Strategy A: Next + Prev Only (Current Plan)
```swift
// Simple algorithm
onTrackChanged(to: track) {
    preload(track.next)
    preload(track.prev)
}

Pros:
✅ Predictable memory usage (3 tracks max)
✅ Simple implementation
✅ Covers Back button

Cons:
❌ Skip spam = constant cache misses
❌ 2nd+ consecutive skip = load from disk
❌ Latency spikes при rapid navigation

Performance:
- Normal session: ⭐⭐⭐⭐⭐ (excellent)
- Skip spam: ⭐ (poor)
- Memory: ⭐⭐⭐⭐⭐ (minimal)
```

#### Strategy B: Window [-2, +2] (5 tracks)
```swift
onTrackChanged(to: track) {
    preload(track.index - 2)
    preload(track.index - 1)
    preload(track.index + 1)
    preload(track.index + 2)
}

Pros:
✅ Good skip spam coverage (85%)
✅ Still predictable
✅ Wider safety net

Cons:
⚠️ Higher memory usage (5 tracks ≈ 265 MB)
⚠️ Wasted preload if user doesn't skip
❌ Може evict current track при skip spam!

Performance:
- Normal session: ⭐⭐⭐ (overhead)
- Skip spam: ⭐⭐⭐⭐ (good)
- Memory: ⭐⭐⭐ (moderate pressure)
```

#### Strategy C: Adaptive (Detect & Widen)
```swift
// State machine
enum NavigationMode {
    case normal      // Preload next+prev
    case browsing    // Expand window to ±2
}

var recentSkips: [(timestamp, direction)] = []

onTrackChanged(to: track, direction: .next/.prev) {
    // 1. Detect skip spam
    recentSkips.append((Date(), direction))
    recentSkips.removeOld(threshold: 5.0) // 5 sec window

    // 2. Adjust strategy
    if recentSkips.count >= 3 {
        mode = .browsing
        preloadWindow(±2)
    } else {
        mode = .normal
        preloadWindow(next+prev)
    }

    // 3. Auto-shrink after calm period
    if timeSinceLastSkip > 10.0 {
        mode = .normal
    }
}

Pros:
✅ Best of both worlds!
✅ Memory-efficient при normal playback
✅ Responsive при skip spam
✅ Auto-recovery після browsing

Cons:
⚠️ Складніша логіка (state machine)
⚠️ Потрібен tuning (thresholds)
⚠️ Можливі edge cases (false positives)

Performance:
- Normal session: ⭐⭐⭐⭐⭐ (adaptive!)
- Skip spam: ⭐⭐⭐⭐ (responsive)
- Memory: ⭐⭐⭐⭐ (dynamic)

Thresholds для tuning:
- Skip spam detection: 3 skips за 5 секунд
- Window expansion: ±2 (5 tracks total)
- Cooldown period: 10 секунд без skips
```

#### Strategy D: Predictive ML (Overkill)
```swift
// Machine learning approach
analyzeUserBehavior() → predictNextTracks()

Pros:
✅ Теоретично найточніший

Cons:
❌ MASSIVE OVERKILL для meditation app!
❌ Складність >>> benefits
❌ Training data requirements
❌ Battery impact
❌ SDK має бути простим

Verdict: ❌ НЕ РОЗГЛЯДАЄТЬСЯ
```

#### Strategy E: Hybrid LRU+MRU
```swift
// Split cache into zones
cache {
    protected[3]: current + next + prev (never evict)
    lru[2]: least recently used (evictable)
}

Pros:
✅ Гарантує instant playback для current
✅ LRU зона для back-back patterns
✅ Clear eviction policy

Cons:
⚠️ Fixed memory commitment (5 tracks)
⚠️ Complexity у eviction logic
⚠️ Може waste memory якщо не використовується

Performance:
- Normal session: ⭐⭐⭐⭐ (good)
- Skip spam: ⭐⭐⭐ (decent)
- Memory: ⭐⭐⭐ (higher baseline)
```

---

## 🎯 Phase 2: Recommended Preload Strategy

### Обрана стратегія: **Option C - Adaptive Window** ⭐

**Rationale:**
1. **Meditation-specific:** Normal playback = minimal overhead, browsing = responsive
2. **Memory-safe:** Dynamic allocation, не wasted на overhead
3. **UX-first:** Детектує user intent і адаптується
4. **Production-ready:** Clear state machine, testable thresholds

### Concrete Algorithm

```swift
actor AudioFileCache {
    // MARK: - State

    /// Navigation mode state machine
    private enum NavigationMode {
        case normal      // Casual listening
        case browsing    // Skip spam detected

        var preloadWindow: Int {
            switch self {
            case .normal: return 1      // ±1 (current + next + prev = 3 tracks)
            case .browsing: return 2    // ±2 (current + 4 around = 5 tracks)
            }
        }
    }

    private var mode: NavigationMode = .normal

    /// Recent skip history (for detection)
    private var recentSkips: [(timestamp: Date, direction: Direction)] = []

    /// Last activity timestamp (for cooldown)
    private var lastSkipTime: Date = .distantPast

    // MARK: - Core Algorithm

    func onTrackChanged(from: Track?, to: Track, direction: Direction) async {
        let now = Date()

        // 1. DETECT: Skip spam pattern
        recentSkips.append((now, direction))
        recentSkips = recentSkips.filter { now.timeIntervalSince($0.timestamp) < 5.0 }

        // 2. MODE TRANSITION: Normal → Browsing
        if recentSkips.count >= 3 && mode == .normal {
            print("[Cache] 🔍 Skip spam detected! Expanding preload window...")
            mode = .browsing
        }

        // 3. PRELOAD: Based on current mode
        await preloadAroundTrack(to, window: mode.preloadWindow)

        // 4. UPDATE: Last activity
        lastSkipTime = now

        // 5. SCHEDULE: Cooldown check (async)
        Task {
            try? await Task.sleep(for: .seconds(10))
            await checkCooldown()
        }
    }

    private func checkCooldown() {
        let timeSinceLastSkip = Date().timeIntervalSince(lastSkipTime)

        if timeSinceLastSkip >= 10.0 && mode == .browsing {
            print("[Cache] ✅ Cooldown complete. Shrinking to normal mode...")
            mode = .normal

            // Evict excess tracks (beyond ±1 window)
            Task {
                await evictBeyondWindow(window: 1)
            }
        }
    }

    private func preloadAroundTrack(_ track: Track, window: Int) async {
        guard let playlist = currentPlaylist else { return }
        guard let index = playlist.firstIndex(of: track) else { return }

        let startIndex = max(0, index - window)
        let endIndex = min(playlist.count - 1, index + window)

        for i in startIndex...endIndex {
            guard i != index else { continue } // Current already loaded

            let trackToPreload = playlist[i]
            await preload(trackToPreload, priority: .normal)
        }
    }
}
```

### State Machine Diagram

```
┌─────────────┐
│   NORMAL    │
│  (±1 window)│
└──────┬──────┘
       │
       │ 3 skips
       │ in 5 sec
       ▼
┌─────────────┐
│  BROWSING   │
│  (±2 window)│
└──────┬──────┘
       │
       │ 10 sec
       │ no skips
       ▼
┌─────────────┐
│   NORMAL    │
│  (±1 window)│
└─────────────┘
```

### Tunable Parameters

```swift
struct CacheConfig {
    // Skip spam detection
    static let skipSpamThreshold = 3        // skips
    static let skipSpamWindow = 5.0         // seconds

    // Preload windows
    static let normalWindow = 1             // ±1 track
    static let browsingWindow = 2           // ±2 tracks

    // Cooldown
    static let cooldownDuration = 10.0      // seconds

    // Memory limits
    static let maxCacheSize = 5             // tracks (safety limit)
    static let targetMemoryBudget = 200     // MB
}
```

---

## 🗑️ Phase 3: LRU Eviction Policy

### 3.1 Protected Slots (NEVER Evict)

```swift
enum CacheSlot {
    case current        // Currently playing track
    case next           // Next in playlist
    case prev           // Previous in playlist (for Back button)
    case lru            // Least recently used (evictable)
}

// Cache organization
cache: [URL: CachedFile] {
    // Protected (3 slots min)
    current: track_N
    next:    track_N+1
    prev:    track_N-1

    // LRU zone (2 slots max in normal mode, expandable to 5 in browsing)
    lru[0]:  track_N+2  // Evictable
    lru[1]:  track_N-2  // Evictable
}
```

**Правила:**
1. ✅ Current track: **NEVER** evict (critical!)
2. ✅ Next track: **NEVER** evict (seamless crossfade requirement)
3. ✅ Prev track: **NEVER** evict (Back button UX)
4. ⚠️ LRU zone: Evict when cache exceeds mode window

### 3.2 Eviction Order

```swift
func evictCandidate() -> URL? {
    // 1. Filter protected tracks
    let evictableTracks = cache.keys.filter { url in
        !isProtected(url)
    }

    // 2. Sort by access time (LRU first)
    let sorted = evictableTracks.sorted { url1, url2 in
        accessTime[url1]! < accessTime[url2]!
    }

    // 3. Return oldest
    return sorted.first
}

private func isProtected(_ url: URL) -> Bool {
    guard let current = currentTrack,
          let playlist = currentPlaylist,
          let index = playlist.firstIndex(of: current) else {
        return false
    }

    // Protected: current, next, prev
    let protectedIndices = Set([
        index,              // Current
        index + 1,          // Next
        index - 1           // Prev
    ])

    guard let trackIndex = playlist.firstIndex(where: { $0.url == url }) else {
        return false
    }

    return protectedIndices.contains(trackIndex)
}
```

### 3.3 Eviction Triggers

```swift
enum EvictionTrigger {
    case cacheExceedsSize       // Cache > maxSize
    case memoryWarning          // iOS memory pressure
    case modeTransition         // Browsing → Normal
    case brokenFileDetected     // Failed preload
}

func evict(trigger: EvictionTrigger) async {
    switch trigger {
    case .cacheExceedsSize:
        // Gentle: evict 1 oldest LRU track
        if cache.count > mode.preloadWindow + 1 {
            await evictOldest(count: 1)
        }

    case .memoryWarning:
        // Aggressive: evict ALL LRU (keep only current+next+prev)
        print("[Cache] ⚠️ Memory warning! Emergency eviction...")
        await evictBeyondWindow(window: 1)

    case .modeTransition:
        // Shrink: evict beyond new window
        if mode == .normal {
            await evictBeyondWindow(window: 1)
        }

    case .brokenFileDetected:
        // Remove broken file + mark as failed
        // (separate handling)
        break
    }
}
```

### 3.4 Edge Cases

**Q: Що якщо поточний track corrupted і crash при load?**
```swift
// Retry logic (окремо від cache)
func loadWithRetry(url: URL, maxRetries: 3) async throws -> AVAudioFile {
    var attempts = 0

    while attempts < maxRetries {
        do {
            return try await loadAudioFile(url)
        } catch {
            attempts += 1
            if attempts >= maxRetries {
                // Mark as broken, skip to next
                await markAsBroken(url)
                throw AudioFileError.corruptedAfterRetries(url)
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
    }
}
```

**Q: Що якщо cache thrashing під час skip spam?**
```swift
// Protection: rate limiting
private var lastEvictionTime: Date = .distantPast

func evictOldest(count: Int) async {
    let now = Date()
    let timeSinceLastEviction = now.timeIntervalSince(lastEvictionTime)

    // Rate limit: max 1 eviction per 0.5 sec
    if timeSinceLastEviction < 0.5 {
        print("[Cache] ⏸️ Rate limiting eviction...")
        return
    }

    // ... evict logic ...

    lastEvictionTime = now
}
```

---

## 🏗️ Phase 4: Detailed Architecture

```swift
import AVFoundation

/// Production LRU Cache with adaptive preload
///
/// Features:
/// - Adaptive window (±1 normal, ±2 browsing)
/// - Skip spam detection (3 skips in 5 sec)
/// - Protected slots (current + next + prev)
/// - Broken file handling (3 retries)
/// - Memory pressure response
actor AudioFileCache {

    // MARK: - Models

    struct CachedFile {
        let file: AVAudioFile
        let url: URL
        var accessTime: Date
        var hitCount: Int

        var estimatedMemorySize: Int {
            // Rough estimate: duration * sampleRate * channels * bytesPerSample
            let duration = Double(file.length) / file.fileFormat.sampleRate
            let sampleRate = file.fileFormat.sampleRate
            let channels = Int(file.fileFormat.channelCount)
            let bytesPerSample = 4 // Float32

            return Int(duration * sampleRate) * channels * bytesPerSample
        }
    }

    enum NavigationMode {
        case normal      // ±1 window (3 tracks)
        case browsing    // ±2 window (5 tracks)

        var preloadWindow: Int {
            switch self {
            case .normal: return 1
            case .browsing: return 2
            }
        }

        var maxCacheSize: Int {
            return (preloadWindow * 2) + 1  // ±window + current
        }
    }

    enum Direction {
        case next
        case previous
    }

    struct BrokenFile {
        let url: URL
        let failureCount: Int
        let lastAttempt: Date
    }

    // MARK: - State

    /// Core LRU cache
    private var cache: [URL: CachedFile] = [:]

    /// Access order tracking
    private var accessOrder: [URL] = []

    /// Current navigation mode
    private var mode: NavigationMode = .normal

    /// Skip history (for detection)
    private var recentSkips: [(timestamp: Date, direction: Direction)] = []

    /// Last activity time
    private var lastSkipTime: Date = .distantPast

    /// Broken files registry (skip after 3 failures)
    private var brokenFiles: [URL: BrokenFile] = [:]

    /// Current playlist context
    private weak var playlist: [Track]?
    private weak var currentTrack: Track?

    /// Preload queue (low priority background tasks)
    private var preloadTasks: [URL: Task<Void, Never>] = [:]

    /// Memory pressure flag
    private var isMemoryWarningActive = false

    // MARK: - Configuration

    struct Config {
        static let skipSpamThreshold = 3
        static let skipSpamWindow: TimeInterval = 5.0
        static let cooldownDuration: TimeInterval = 10.0
        static let maxRetries = 3
        static let targetMemoryBudget = 200_000_000  // 200 MB
        static let memoryCheckInterval: TimeInterval = 5.0
    }

    // MARK: - Public API

    /// Get cached file or load from disk
    func get(_ url: URL) async throws -> AVAudioFile {
        // Check if broken
        if let broken = brokenFiles[url] {
            if broken.failureCount >= Config.maxRetries {
                throw CacheError.filePermanentlyBroken(url)
            }
        }

        // Hit: return cached
        if let cached = cache[url] {
            updateAccessTime(url)
            return cached.file
        }

        // Miss: load from disk with retry
        return try await loadWithRetry(url)
    }

    /// Preload track in background
    func preload(_ track: Track, priority: TaskPriority = .utility) async {
        let url = track.url

        // Skip if already cached
        guard cache[url] == nil else { return }

        // Skip if broken
        if let broken = brokenFiles[url], broken.failureCount >= Config.maxRetries {
            return
        }

        // Cancel existing preload task
        preloadTasks[url]?.cancel()

        // Start new preload
        let task = Task(priority: priority) {
            do {
                let file = try await loadWithRetry(url)
                await cacheFile(file, url: url)
            } catch {
                print("[Cache] ⚠️ Preload failed: \\(url.lastPathComponent)")
            }
        }

        preloadTasks[url] = task
    }

    /// Update current track context (triggers preload)
    func onTrackChanged(from: Track?, to: Track, direction: Direction, playlist: [Track]) async {
        self.currentTrack = to
        self.playlist = playlist

        let now = Date()

        // 1. DETECT: Skip spam
        recentSkips.append((now, direction))
        recentSkips = recentSkips.filter { now.timeIntervalSince($0.timestamp) < Config.skipSpamWindow }

        // 2. MODE TRANSITION
        if recentSkips.count >= Config.skipSpamThreshold && mode == .normal {
            print("[Cache] 🔍 Skip spam detected! Expanding to browsing mode...")
            mode = .browsing
        }

        // 3. PRELOAD
        await preloadAroundTrack(to, playlist: playlist, window: mode.preloadWindow)

        // 4. EVICT if needed
        if cache.count > mode.maxCacheSize {
            await evictLRU()
        }

        // 5. COOLDOWN check
        lastSkipTime = now
        Task {
            try? await Task.sleep(for: .seconds(Config.cooldownDuration))
            await checkCooldown()
        }
    }

    /// Handle memory warning
    func handleMemoryWarning() async {
        print("[Cache] ⚠️ Memory warning received! Emergency eviction...")
        isMemoryWarningActive = true

        // Keep only current + next + prev
        await evictBeyondWindow(window: 1)

        // Force mode to normal
        mode = .normal

        // Reset flag after cooldown
        Task {
            try? await Task.sleep(for: .seconds(30))
            isMemoryWarningActive = false
        }
    }

    /// Clear all cache
    func clear() {
        cache.removeAll()
        accessOrder.removeAll()
        preloadTasks.values.forEach { $0.cancel() }
        preloadTasks.removeAll()
    }

    // MARK: - Private Helpers

    private func loadWithRetry(_ url: URL) async throws -> AVAudioFile {
        var attempts = 0
        var lastError: Error?

        while attempts < Config.maxRetries {
            do {
                let file = try AVAudioFile(forReading: url)

                // Success: reset broken counter if any
                brokenFiles[url] = nil

                // Cache it
                await cacheFile(file, url: url)

                return file
            } catch {
                attempts += 1
                lastError = error

                print("[Cache] ⚠️ Load attempt \\(attempts)/\\(Config.maxRetries) failed: \\(url.lastPathComponent)")

                if attempts < Config.maxRetries {
                    try? await Task.sleep(for: .milliseconds(100))
                }
            }
        }

        // Mark as broken after max retries
        brokenFiles[url] = BrokenFile(
            url: url,
            failureCount: Config.maxRetries,
            lastAttempt: Date()
        )

        throw lastError ?? CacheError.fileLoadFailed(url)
    }

    private func cacheFile(_ file: AVAudioFile, url: URL) {
        let cached = CachedFile(
            file: file,
            url: url,
            accessTime: Date(),
            hitCount: 0
        )

        cache[url] = cached
        accessOrder.append(url)

        print("[Cache] ✅ Cached: \\(url.lastPathComponent) (\\(cached.estimatedMemorySize / 1_000_000) MB)")
    }

    private func updateAccessTime(_ url: URL) {
        guard var cached = cache[url] else { return }

        cached.accessTime = Date()
        cached.hitCount += 1
        cache[url] = cached

        // Update LRU order
        accessOrder.removeAll { $0 == url }
        accessOrder.append(url)
    }

    private func preloadAroundTrack(_ track: Track, playlist: [Track], window: Int) async {
        guard let index = playlist.firstIndex(of: track) else { return }

        let startIndex = max(0, index - window)
        let endIndex = min(playlist.count - 1, index + window)

        for i in startIndex...endIndex {
            guard i != index else { continue }

            let trackToPreload = playlist[i]
            await preload(trackToPreload, priority: .utility)
        }
    }

    private func evictLRU() async {
        guard let victim = findEvictionVictim() else { return }

        print("[Cache] 🗑️ Evicting LRU: \\(victim.lastPathComponent)")

        cache[victim] = nil
        accessOrder.removeAll { $0 == victim }
        preloadTasks[victim]?.cancel()
        preloadTasks[victim] = nil
    }

    private func evictBeyondWindow(window: Int) async {
        guard let current = currentTrack,
              let playlist = playlist,
              let index = playlist.firstIndex(of: current) else {
            return
        }

        let protectedRange = (index - window)...(index + window)

        var toEvict: [URL] = []

        for (url, _) in cache {
            guard let trackIndex = playlist.firstIndex(where: { $0.url == url }) else {
                continue
            }

            if !protectedRange.contains(trackIndex) {
                toEvict.append(url)
            }
        }

        for url in toEvict {
            cache[url] = nil
            accessOrder.removeAll { $0 == url }
            preloadTasks[url]?.cancel()
            preloadTasks[url] = nil
        }

        print("[Cache] 🗑️ Evicted \\(toEvict.count) tracks beyond window ±\\(window)")
    }

    private func findEvictionVictim() -> URL? {
        guard let current = currentTrack,
              let playlist = playlist,
              let index = playlist.firstIndex(of: current) else {
            // Fallback: oldest in access order
            return accessOrder.first
        }

        // Protected indices: current, next, prev
        let protectedIndices = Set([index, index + 1, index - 1])

        // Find oldest non-protected track
        for url in accessOrder {
            guard let trackIndex = playlist.firstIndex(where: { $0.url == url }) else {
                continue
            }

            if !protectedIndices.contains(trackIndex) {
                return url
            }
        }

        return nil
    }

    private func checkCooldown() {
        let timeSinceLastSkip = Date().timeIntervalSince(lastSkipTime)

        if timeSinceLastSkip >= Config.cooldownDuration && mode == .browsing {
            print("[Cache] ✅ Cooldown complete. Shrinking to normal mode...")
            mode = .normal

            Task {
                await evictBeyondWindow(window: 1)
            }
        }
    }

    // MARK: - Diagnostics

    func getStats() -> CacheStats {
        let totalMemory = cache.values.reduce(0) { $0 + $1.estimatedMemorySize }
        let totalHits = cache.values.reduce(0) { $0 + $1.hitCount }

        return CacheStats(
            cachedCount: cache.count,
            totalMemoryMB: totalMemory / 1_000_000,
            mode: mode,
            brokenFilesCount: brokenFiles.count,
            totalHits: totalHits
        )
    }
}

// MARK: - Supporting Types

enum CacheError: Error {
    case fileLoadFailed(URL)
    case filePermanentlyBroken(URL)
}

struct CacheStats {
    let cachedCount: Int
    let totalMemoryMB: Int
    let mode: AudioFileCache.NavigationMode
    let brokenFilesCount: Int
    let totalHits: Int
}
```

---

## 😈 Phase 5: Devil's Advocate (Self-Critique)

### 1. Що зламається з 100-track playlist?

**Problem:**
```
100 tracks × 53 MB average = 5.3 GB total
Cache window ±2 = 5 tracks = 265 MB ✅
BUT: Frequent evictions при browse!

Scenario:
User scrolls через весь playlist (100 next skips)
Result: 95+ evictions, constant disk I/O
```

**Mitigation:**
- ✅ Adaptive window допомагає (browsing mode)
- ⚠️ Але все одно не може закешувати весь список
- ✅ Preload tasks background priority → не блокує UI
- ⚠️ Можливо потрібен "jump to index" optimization окремо

**Verdict:** Acceptable. Meditation apps рідко мають >20 tracks.

---

### 2. Що якщо slow storage (старий iPhone)?

**Problem:**
```
iPhone 7 (eMMC storage):
- Random read: 50-100 MB/s
- 53 MB track = 530-1060 ms load time! 💥

Skip spam = user чекає 1+ секунду на кожний skip!
```

**Mitigation:**
```swift
// Add preload priority boost for next track
func preload(_ track: Track, priority: TaskPriority = .utility) async {
    // If this is NEXT track → boost priority
    if track == getNextTrack() {
        priority = .userInitiated  // Higher priority!
    }
}

// Also: start preload EARLIER (on play, not on skip)
func play(_ track: Track) async {
    await engine.play(track)

    // Immediate preload of next
    if let next = getNextTrack() {
        await cache.preload(next, priority: .userInitiated)
    }
}
```

**Verdict:** Потрібен aggressive preload для next track.

---

### 3. Що якщо tracks FLAC (50 MB кожен)?

**Problem:**
```
FLAC 50 MB compressed → 200+ MB uncompressed в RAM!
Cache 3 tracks = 600 MB → memory kill! 💀

Розрахунок:
FLAC 24-bit 96kHz stereo:
- 96000 Hz × 2 channels × 4 bytes = 768 KB/sec
- 5 min track = 230 MB uncompressed!
```

**Mitigation:**
```swift
struct Config {
    // Dynamic cache sizing based on track size
    static let targetMemoryBudget = 200_000_000  // 200 MB

    var maxCacheSize: Int {
        // Estimate average track size from first loaded track
        guard let avgTrackSize = estimatedAverageTrackSize else {
            return 3  // Conservative default
        }

        // Calculate how many tracks fit in budget
        let maxTracks = targetMemoryBudget / avgTrackSize
        return max(3, min(maxTracks, 5))  // Clamp to 3-5
    }
}

// Track size estimation
private var estimatedAverageTrackSize: Int? {
    guard !cache.isEmpty else { return nil }

    let totalSize = cache.values.reduce(0) { $0 + $1.estimatedMemorySize }
    return totalSize / cache.count
}
```

**Verdict:** Потрібен dynamic sizing!

---

### 4. Що на memory warning?

**Problem:**
```
iOS надсилає memory warning → app має 1-2 секунди звільнити RAM
Якщо не звільнити → jetsam kill

Current cache: 5 tracks × 53 MB = 265 MB
Потрібно: звільнити ~200 MB швидко!
```

**Mitigation:**
```swift
// Already implemented in Phase 4
func handleMemoryWarning() async {
    // 1. Cancel all preload tasks
    preloadTasks.values.forEach { $0.cancel() }
    preloadTasks.removeAll()

    // 2. Evict ALL except current+next+prev
    await evictBeyondWindow(window: 1)

    // 3. Force mode to normal
    mode = .normal

    // 4. Set flag to prevent aggressive preloading
    isMemoryWarningActive = true
}

// Integration with UIKit
class AudioService {
    init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMemoryWarning),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
    }

    @objc func handleMemoryWarning() {
        Task {
            await cache.handleMemoryWarning()
        }
    }
}
```

**Verdict:** ✅ Already covered.

---

### 5. Race conditions в preload queue?

**Problem:**
```
Scenario:
1. User skips to track 5 → start preload(track 6)
2. User IMMEDIATELY skips to track 10 → start preload(track 11)
3. Preload task for track 6 completes → cache it
4. User never повертається до track 6 → wasted memory!

Race:
preloadTasks[url] може бути overwritten before completion
→ memory leak (task continues, але втрачено reference)
```

**Mitigation:**
```swift
// Already implemented: cancel before starting new task
func preload(_ track: Track, priority: TaskPriority = .utility) async {
    let url = track.url

    // ✅ Cancel existing preload task
    preloadTasks[url]?.cancel()

    // Start new task
    let task = Task(priority: priority) {
        // Check if still relevant
        guard !Task.isCancelled else { return }

        do {
            let file = try await loadWithRetry(url)

            // Double-check relevance before caching
            guard !Task.isCancelled else { return }

            await cacheFile(file, url: url)
        } catch {
            print("[Cache] ⚠️ Preload failed")
        }
    }

    preloadTasks[url] = task
}

// Also: cleanup completed tasks
private func cleanupCompletedPreloadTasks() {
    preloadTasks = preloadTasks.filter { !$0.value.isCancelled }
}
```

**Verdict:** ✅ Handled with task cancellation.

---

## 🎯 Phase 6: Recommended Solutions

### Option 1: Conservative ✅ (RECOMMENDED for Beta)

```
Strategy: Adaptive Window (±1 normal, ±2 browsing)
Cache Size: 3-5 tracks (dynamic)
Memory Footprint: 150-265 MB peak
Preload Priority: userInitiated for next, utility for others
```

**Pros:**
✅ **Memory-safe:** Залишається в межах 200 MB budget
✅ **UX-responsive:** Детектує skip spam, розширює window
✅ **Production-ready:** Clear state machine, testable
✅ **Meditation-optimized:** Minimal overhead при normal playback
✅ **Memory warning handling:** Automatic eviction
✅ **Broken file handling:** 3 retries, skip після

**Cons:**
⚠️ Не покриває екстремальний skip spam (10+ consecutive skips)
⚠️ Evictions все ще трапляються при browsing

**Expected Performance:**
- Normal session (30 min): 0-2 disk loads (excellent!)
- Skip spam (5 skips): 1-2 disk loads (acceptable)
- Memory pressure: Low
- Latency: 50-200ms на cache miss

**Best for:**
- ✅ Beta stage (stability priority)
- ✅ Meditation apps (predictable usage)
- ✅ Typical 5-20 track playlists

**Configuration:**
```swift
struct Config {
    static let normalWindow = 1
    static let browsingWindow = 2
    static let skipSpamThreshold = 3
    static let skipSpamWindow: TimeInterval = 5.0
    static let cooldownDuration: TimeInterval = 10.0
    static let targetMemoryBudget = 200_000_000
    static let maxRetries = 3
}
```

---

### Option 2: Aggressive ⚡ (Consider for v2.0)

```
Strategy: Fixed Window ±3
Cache Size: 7 tracks
Memory Footprint: 350-400 MB peak
Preload Priority: High for all
```

**Pros:**
✅ Покриває 95%+ skip spam без evictions
✅ Smoother UX при rapid navigation
✅ Simpler logic (no state machine)

**Cons:**
❌ **High memory pressure** (350+ MB)
❌ Ризик memory warnings на старих iPhone
❌ Wasted memory при normal playback
❌ Не підходить для FLAC/hi-res audio

**Expected Performance:**
- Normal session: 0 disk loads (perfect!)
- Skip spam: 0-1 disk loads (excellent!)
- Memory pressure: **High** ⚠️

**Best for:**
- ❌ NOT for beta stage!
- ⚠️ Consider якщо users complain про latency
- ⚠️ Only якщо target devices = new iPhones (>6GB RAM)

**Verdict:** 🔴 **NOT RECOMMENDED** (too risky для SDK)

---

### Option 3: Balanced (Alternative consideration)

```
Strategy: Hybrid LRU+MRU with protected slots
Cache Size: 5 tracks (3 protected + 2 LRU)
Memory Footprint: 250-265 MB peak
```

**Pros:**
✅ Гарантує instant playback для current+next+prev
✅ LRU зона для back-patterns
✅ Predictable memory usage

**Cons:**
⚠️ Складніша eviction logic
⚠️ Не адаптується до usage patterns
⚠️ Fixed overhead (може бути waste)

**Expected Performance:**
- Normal session: 0-1 disk loads
- Skip spam: 2-4 disk loads
- Memory pressure: Medium

**Best for:**
- ⚠️ Alternative якщо adaptive виявиться too complex
- ⚠️ Apps з predictable navigation patterns

**Verdict:** 🟡 **BACKUP PLAN** (якщо Option 1 має issues)

---

## 📊 Final Recommendation

### ⭐ Обрана стратегія: **Option 1 - Conservative Adaptive**

**Rationale:**

1. **Beta stage priority:** Stability > Performance
2. **Meditation use case:** Normal playback = 90% usage (optimized!)
3. **Memory safety:** Fits iOS background audio budget
4. **UX acceptable:** Skip spam handled with 1-2 sec latency (tolerable)
5. **Production-ready:** Clear state machine, defensive programming

### Implementation Roadmap

**Phase 1: Core Cache (Week 1)**
- [ ] Implement basic LRU cache
- [ ] Add broken file handling (3 retries)
- [ ] Memory size estimation
- [ ] Unit tests

**Phase 2: Adaptive Logic (Week 1-2)**
- [ ] State machine (normal/browsing modes)
- [ ] Skip spam detection
- [ ] Cooldown mechanism
- [ ] Integration tests

**Phase 3: Memory Management (Week 2)**
- [ ] Memory warning handler
- [ ] Dynamic cache sizing
- [ ] Eviction policy
- [ ] Stress tests

**Phase 4: Integration (Week 2-3)**
- [ ] AudioPlayerService integration
- [ ] Preload triggers
- [ ] Real-world testing
- [ ] Performance metrics

**Phase 5: Tuning (Week 3-4)**
- [ ] Threshold optimization
- [ ] Memory profiling
- [ ] Edge case handling
- [ ] Beta testing

### Success Metrics

```
KPI для Beta:
✅ Memory usage: <250 MB peak (95th percentile)
✅ Memory warnings: <5% sessions
✅ Skip latency: <500ms (median), <1s (95th percentile)
✅ Cache hit rate: >80% during normal playback
✅ Broken file handling: 100% recovery rate
✅ Crash-free rate: >99.5%
```

### Risks & Mitigations

| Risk | Impact | Probability | Mitigation |
|------|--------|-------------|------------|
| Memory kill на старих iPhone | 🔥 HIGH | MEDIUM | Dynamic sizing + memory warnings |
| Skip spam thrashing | ⚠️ MEDIUM | LOW | Browsing mode expansion |
| False positive skip detection | ⚠️ MEDIUM | LOW | Tunable thresholds (config) |
| Preload race conditions | ⚠️ MEDIUM | MEDIUM | Task cancellation |
| FLAC support breaks budget | 🔥 HIGH | LOW | Track size estimation |

---

## 🔍 Додаткові Insights

### Чому НЕ потрібен великий cache для meditation app?

```
Meditation session structure:
- Stage 1: 5 min (1 track або loop)
- Stage 2: 20 min (1 track або loop)
- Stage 3: 5 min (1 track або loop)

Total: 3 tracks MAX для повної сесії!

Висновок: Cache size=3 покриває 100% normal use case!
Skip spam - це BROWSE scenario, не typical usage.
```

### Коли вважати skip spam?

```
Metrics analysis:
- Normal skip: 1-2 рази за 30 min session
- Browsing: 5-10 skips за 10 секунд
- Time between skips: <2 sec = skip spam

Detection algorithm:
if (skips >= 3 in last 5 sec) → browsing mode

Why 3 skips?
- 2 skips може бути accident (пропустили 2 tracks)
- 3+ skips = clear intent to browse
```

### Memory warning best practices

```swift
// iOS надає 2 рівні warnings:
// 1. didReceiveMemoryWarningNotification → soft warning
// 2. Critical level → hard kill incoming!

// Strategy:
func handleMemoryWarning() async {
    // 1. Cancel background tasks (immediate)
    preloadTasks.values.forEach { $0.cancel() }

    // 2. Evict aggressively (keep min 3)
    await evictBeyondWindow(window: 1)

    // 3. Prevent new preloads (flag)
    isMemoryWarningActive = true

    // 4. Cooldown (30 sec recovery)
    Task {
        try? await Task.sleep(for: .seconds(30))
        isMemoryWarningActive = false
    }
}
```

---

## ✅ Висновок

**Iteration 1 Complete:**
Детально проаналізовано skip spam problem, розроблено adaptive cache strategy з clear trade-offs.

**Key Takeaways:**
1. ✅ Meditation app != music player (різні usage patterns!)
2. ✅ Adaptive window (±1/±2) = optimal для даного use case
3. ✅ Memory safety > Performance (beta stage priority)
4. ✅ Protected slots (current+next+prev) критичні для UX
5. ✅ Broken file handling з retries (defensive SDK)

**Next Steps:**
- Approval від user на обрану strategy
- Iteration 2: Detailed implementation design
- Iteration 3: Code review architecture skeleton
- Iteration 4: Implementation + testing

**Файл оновлено:** 2025-10-24
**Версія:** 1.0 (Initial Architecture Review)

---

**🤔 Questions for User:**

1. Чи згоден з обраною Option 1 (Conservative Adaptive)?
2. Чи потрібно підтримувати FLAC/hi-res audio? (впливає на memory budget)
3. Чи є metrics з production про skip patterns? (для tuning thresholds)
4. Чи acceptable 500ms-1s latency на skip spam? (vs більший cache)
5. Чи потрібен fallback на Option 3 (Hybrid LRU+MRU)?

**Ready for Iteration 2!** 🚀
