# 🔥 Критичний Аналіз: File Loading & Stability

**Дата:** 24 жовтня 2025  
**Пріоритет:** 🔴 HIGH  
**Impact:** Performance + Stability

---

## 📊 Поточний Стан (Проблеми)

### 1. Поточна Архітектура File Loading

```swift
// AudioEngineActor.swift - lines 624-660
func loadAudioFile(track: Track) throws -> Track {
    let file = try AVAudioFile(forReading: track.url)  // ❌ КОЖЕН РАЗ з диску!
    // ... metadata extraction ...
    return updatedTrack
}
```

**Call sites:** 15 місць у коді  
**Викликається при:**
- `play()` - завантаження першого треку
- `skipToNext()` - кожен skip
- `skipToPrevious()` - кожен back
- `loopCurrentTrackWithFade()` - кожна ітерація лупу
- `replaceCurrentTrack()` - кожна заміна

### 2. Проблеми

| # | Проблема | Impact | Частота |
|---|----------|--------|---------|
| 1 | **Немає кешування** | 🔴 HIGH | Кожен skip = disk I/O |
| 2 | **Повторне завантаження** | 🟡 MEDIUM | Loop = reload same file |
| 3 | **Блокуюча I/O** | 🟡 MEDIUM | UI freeze на великих файлах |
| 4 | **Немає preload** | 🟢 LOW | Next track не готовий |
| 5 | **Index desync на error** | 🔴 HIGH | Skip fails → inconsistent state |

### 3. Типовий Сценарій (30-хвилинна медитація)

```
Старт сесії:
├─ Load Track 1 (stage1_intro.mp3)         ← I/O #1
├─ Play 5 min
├─ Skip to Track 2 (stage2_practice.mp3)   ← I/O #2
├─ Play 20 min (LOOP 4 рази)
│  ├─ Loop iteration 1                     ← I/O #3
│  ├─ Loop iteration 2                     ← I/O #4
│  ├─ Loop iteration 3                     ← I/O #5
│  └─ Loop iteration 4                     ← I/O #6
├─ Skip to Track 3 (stage3_closing.mp3)    ← I/O #7
└─ Play 5 min → Finish
```

**Результат:** 7 disk I/O operations для 3 унікальних файлів  
**Оптимальний:** 3 disk I/O operations (1 на унікальний файл) = **57% reduction**

---

## 🎯 Рішення: Audio File Cache Architecture

### Архітектура (3-рівневий підхід)

```
┌─────────────────────────────────────────────────────────────┐
│                    AudioPlayerService                        │
│                  (Public API - без змін)                     │
└──────────────────────┬──────────────────────────────────────┘
                       │
            ┌──────────▼──────────┐
            │  AudioFileCache     │ ◄─── NEW!
            │  (In-Memory Cache)  │
            └──────────┬──────────┘
                       │
          ┌────────────┴────────────┐
          │                          │
    ┌─────▼──────┐         ┌────────▼──────┐
    │  Primary    │         │  Preload      │
    │  Cache      │         │  Queue        │
    │  (LRU, 5)   │         │  (1-2 files)  │
    └─────┬───────┘         └───────┬───────┘
          │                          │
          └──────────┬───────────────┘
                     │
          ┌──────────▼──────────┐
          │   AudioEngineActor   │
          │  (Consumer - minor   │
          │   changes)           │
          └──────────────────────┘
```

### Компоненти

#### 1. AudioFileCache Actor (NEW)

**Файл:** `Sources/AudioServiceKit/Internal/AudioFileCache.swift` (~250 LOC)

```swift
/// In-memory cache для AVAudioFile instances
/// Thread-safe (actor) з LRU eviction policy
actor AudioFileCache {
    
    // MARK: - Configuration
    
    /// Max cached files (based on typical session)
    private let maxCacheSize: Int
    
    /// Max file size (MB) - larger files не кешуються
    private let maxFileSizeMB: Double
    
    // MARK: - Cache Storage
    
    private var cache: [URL: CachedAudioFile] = [:]
    private var accessOrder: [URL] = []  // LRU tracking
    
    // MARK: - Preload Queue
    
    private var preloadQueue: [URL] = []
    private var preloadTask: Task<Void, Never>?
    
    // MARK: - Metrics
    
    private var hits: Int = 0
    private var misses: Int = 0
    private var evictions: Int = 0
    
    // MARK: - Initialization
    
    init(maxCacheSize: Int = 5, maxFileSizeMB: Double = 50.0) {
        self.maxCacheSize = maxCacheSize
        self.maxFileSizeMB = maxFileSizeMB
    }
    
    // MARK: - Public API
    
    /// Get audio file (from cache or load)
    func getAudioFile(for url: URL) async throws -> AVAudioFile {
        // 1. Check cache
        if let cached = cache[url] {
            hits += 1
            updateAccessOrder(url)
            return cached.file
        }
        
        // 2. Cache miss - load from disk
        misses += 1
        let file = try await loadFromDisk(url: url)
        
        // 3. Store in cache (if within size limit)
        let fileSize = try getFileSizeMB(url: url)
        if fileSize <= maxFileSizeMB {
            await addToCache(url: url, file: file, sizeМB: fileSize)
        }
        
        return file
    }
    
    /// Preload file (background, no blocking)
    func preload(url: URL) {
        // Add to queue if not already cached
        guard cache[url] == nil else { return }
        guard !preloadQueue.contains(url) else { return }
        
        preloadQueue.append(url)
        
        // Start preload task if not running
        if preloadTask == nil {
            preloadTask = Task {
                await processPreloadQueue()
            }
        }
    }
    
    /// Clear cache (manual or on memory warning)
    func clear() {
        cache.removeAll()
        accessOrder.removeAll()
        preloadQueue.removeAll()
        preloadTask?.cancel()
        preloadTask = nil
    }
    
    /// Get cache statistics
    func getMetrics() -> CacheMetrics {
        CacheMetrics(
            size: cache.count,
            hits: hits,
            misses: misses,
            evictions: evictions,
            hitRate: Double(hits) / Double(hits + misses)
        )
    }
    
    // MARK: - Private Helpers
    
    private func loadFromDisk(url: URL) async throws -> AVAudioFile {
        // Off main thread I/O
        return try await Task {
            try AVAudioFile(forReading: url)
        }.value
    }
    
    private func addToCache(url: URL, file: AVAudioFile, sizeМB: Double) {
        // Evict LRU if cache full
        if cache.count >= maxCacheSize {
            evictLRU()
        }
        
        cache[url] = CachedAudioFile(
            file: file,
            url: url,
            sizeМB: sizeМB,
            loadedAt: Date()
        )
        
        accessOrder.append(url)
    }
    
    private func evictLRU() {
        guard let lruURL = accessOrder.first else { return }
        cache.removeValue(forKey: lruURL)
        accessOrder.removeFirst()
        evictions += 1
    }
    
    private func updateAccessOrder(_ url: URL) {
        accessOrder.removeAll { $0 == url }
        accessOrder.append(url)  // Move to end (most recent)
    }
    
    private func getFileSizeMB(url: URL) throws -> Double {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let bytes = attrs[.size] as! UInt64
        return Double(bytes) / 1_048_576.0  // Convert to MB
    }
    
    private func processPreloadQueue() async {
        while !preloadQueue.isEmpty {
            let url = preloadQueue.removeFirst()
            
            // Skip if already cached
            guard cache[url] == nil else { continue }
            
            // Load in background
            do {
                let file = try await loadFromDisk(url: url)
                let size = try getFileSizeMB(url: url)
                await addToCache(url: url, file: file, sizeМB: size)
            } catch {
                // Preload failure не critical - просто skip
                print("[Cache] Preload failed: \(url.lastPathComponent) - \(error)")
            }
        }
        
        preloadTask = nil
    }
}

// MARK: - Supporting Types

private struct CachedAudioFile {
    let file: AVAudioFile
    let url: URL
    let sizeМB: Double
    let loadedAt: Date
}

struct CacheMetrics {
    let size: Int
    let hits: Int
    let misses: Int
    let evictions: Int
    let hitRate: Double  // 0.0-1.0
}
```

#### 2. Integration Points

##### AudioEngineActor (Modify existing methods)

```swift
// BEFORE (current):
func loadAudioFileOnSecondaryPlayer(track: Track) throws -> Track {
    let file = try AVAudioFile(forReading: track.url)  // ❌ Every time!
    // ...
}

// AFTER (with cache):
actor AudioEngineActor {
    private let fileCache: AudioFileCache  // NEW property
    
    init(..., fileCache: AudioFileCache = AudioFileCache()) {
        // ...
        self.fileCache = fileCache
    }
    
    func loadAudioFileOnSecondaryPlayer(track: Track) async throws -> Track {
        let file = try await fileCache.getAudioFile(for: track.url)  // ✅ Cached!
        // ... rest unchanged ...
    }
}
```

##### PlaylistManager (Preload next track)

```swift
// In skipToNext/skipToPrevious:
func skipToNext() -> Track? {
    // ... existing logic ...
    
    // Preload next track in background
    if let nextTrack = peekNext() {
        Task {
            await fileCache.preload(url: nextTrack.url)
        }
    }
    
    return tracks[currentIndex]
}
```

#### 3. Cache Size Strategy

**Розрахунок оптимального розміру:**

```
30-min Meditation Session:
- 3 треки (Intro, Practice, Closing)
- Practice loops 4 рази
- Back/Next navigation

Cache size = 5 files:
- Current track: 1
- Previous track: 1 (для Back button)
- Next track: 1 (preloaded)
- Buffer: 2 (для loop iterations)

Total: 5 files
```

**Memory footprint:**
```
Typical MP3 (5 min, 128kbps):
- Compressed: ~5 MB
- AVAudioFile in memory: ~5 MB (тільки metadata + file handle)
- 5 files × 5 MB = 25 MB total

Worst case (high quality, 320kbps):
- 5 files × 12 MB = 60 MB total

✅ Acceptable for meditation app (не video streaming!)
```

---

## 🛡️ Error Recovery & Stability

### Problem #1: File Load Failure → Index Desync

**Current behavior:**
```swift
// AudioPlayerService.swift
func skipToNext() async throws -> Track.Metadata? {
    let nextMetadata = await peekNextTrack()  // Peek succeeds
    
    try await operationQueue.enqueue {
        try await self._skipToNextImpl()  // ← THROWS here!
    }
    
    // If loadAudioFile fails:
    // ❌ Playlist index already incremented (skipToNext())
    // ❌ But file not loaded → inconsistent state
    
    return nextMetadata  // ← Returns success, but player broken!
}
```

**Solution: Atomic Skip with Rollback**

```swift
// NEW: AudioPlayerService.swift
private func _skipToNextImpl() async throws {
    // 1. Save current state (atomic snapshot)
    let currentState = await playlistManager.captureState()
    
    do {
        // 2. Skip to next (increments index)
        guard let nextTrack = await playlistManager.skipToNext() else {
            throw AudioPlayerError.noNextTrack
        }
        
        // 3. Try to load file (может fail!)
        let loadedTrack = try await audioEngine.loadAudioFileOnSecondaryPlayer(track: nextTrack)
        
        // 4. Success - proceed with crossfade
        try await replaceCurrentTrack(
            track: loadedTrack,
            crossfadeDuration: configuration.crossfadeDuration
        )
        
    } catch {
        // 5. ROLLBACK on failure
        await playlistManager.restoreState(currentState)
        
        // 6. Log error with context
        Self.logger.error("""
        [SKIP] Failed to skip to next track:
          Error: \(error)
          Current index: \(currentState.index)
          Attempted track: \(currentState.attemptedURL?.lastPathComponent ?? "unknown")
          State: ROLLED BACK
        """)
        
        // 7. Re-throw for user handling
        throw error
    }
}
```

**Required: PlaylistManager State Management**

```swift
// PlaylistManager.swift (ADD new methods)

struct PlaylistState {
    let index: Int
    let tracks: [Track]
    let configuration: PlaylistConfiguration
    let attemptedURL: URL?
}

func captureState() -> PlaylistState {
    return PlaylistState(
        index: currentIndex,
        tracks: tracks,
        configuration: configuration,
        attemptedURL: tracks[safe: currentIndex + 1]?.url
    )
}

func restoreState(_ state: PlaylistState) {
    self.currentIndex = state.index
    // Don't restore tracks - they're immutable
}
```

### Problem #2: Auto-Skip Invalid Files

**Current:** Manual error handling by user  
**Better:** SDK handles gracefully

```swift
// NEW: AudioPlayerService.swift
private func _skipToNextImpl() async throws {
    let maxRetries = 3  // Skip up to 3 broken files
    var retriesLeft = maxRetries
    
    while retriesLeft > 0 {
        // Try to skip
        do {
            let nextTrack = await playlistManager.skipToNext()
            guard let track = nextTrack else {
                throw AudioPlayerError.noNextTrack
            }
            
            // Try to load
            let loaded = try await audioEngine.loadAudioFileOnSecondaryPlayer(track: track)
            
            // Success - proceed
            try await replaceCurrentTrack(track: loaded, crossfadeDuration: configuration.crossfadeDuration)
            return  // Exit loop
            
        } catch {
            retriesLeft -= 1
            
            if retriesLeft > 0 {
                Self.logger.warning("[SKIP] File load failed, auto-skipping to next (\(retriesLeft) retries left)")
                // Continue loop - try next track
            } else {
                // All retries exhausted
                Self.logger.error("[SKIP] Failed to skip after \(maxRetries) attempts")
                throw AudioPlayerError.allTracksInvalid
            }
        }
    }
}
```

---

## 📊 Performance Impact Analysis

### With Cache (Optimistic)

| Operation | Before (ms) | After (ms) | Improvement |
|-----------|-------------|------------|-------------|
| First load | 50-200 | 50-200 | 0% (cold) |
| Skip (next) | 50-200 | **5-10** | **80-95%** ✅ |
| Skip (back) | 50-200 | **5-10** | **80-95%** ✅ |
| Loop iteration | 50-200 | **5-10** | **80-95%** ✅ |
| Preloaded next | 50-200 | **<1** | **99%** ✅ |

### Memory

| Scenario | Memory | Acceptable? |
|----------|--------|-------------|
| 5 cached files (128kbps) | ~25 MB | ✅ Yes |
| 5 cached files (320kbps) | ~60 MB | ✅ Yes |
| 10 cached files (worst) | ~120 MB | ⚠️ Maybe (adjust maxCacheSize) |

### Disk I/O Reduction

**30-min session (typical):**
- Before: 7 I/O operations
- After: 3 I/O operations (3 unique files)
- **Reduction: 57%** ✅

---

## 🔧 Implementation Plan

### Phase 1: Cache Infrastructure (Week 1)
- [ ] Create `AudioFileCache.swift` (~250 LOC)
- [ ] Unit tests for cache behavior
- [ ] LRU eviction tests
- [ ] Thread safety tests (actor isolation)

### Phase 2: Integration (Week 2)
- [ ] Modify `AudioEngineActor` to use cache
- [ ] Update `loadAudioFileOnSecondaryPlayer` (async)
- [ ] Update `loadAudioFileOnPrimaryPlayer` (async)
- [ ] Build + test

### Phase 3: Preloading (Week 2)
- [ ] Add preload calls in `PlaylistManager.skipToNext()`
- [ ] Add preload calls in `PlaylistManager.skipToPrevious()`
- [ ] Test preload doesn't block operations

### Phase 4: Error Recovery (Week 3)
- [ ] Implement `PlaylistState` snapshot/restore
- [ ] Implement atomic skip with rollback
- [ ] Add auto-skip for invalid files (optional)
- [ ] Integration tests for error scenarios

### Phase 5: Metrics & Monitoring (Week 3)
- [ ] Add cache metrics logging
- [ ] Add file load timing logs
- [ ] Dashboard for cache hit rate
- [ ] Memory pressure handling

---

## 🎯 Success Criteria

### Performance
- ✅ Cache hit rate >70% in typical session
- ✅ Skip latency <20ms (cached)
- ✅ Memory usage <100 MB (5-file cache)

### Stability
- ✅ Zero index desyncs on file load failure
- ✅ Graceful handling of invalid files
- ✅ No memory leaks after 1-hour session

### UX
- ✅ Instant Next/Back navigation (cached)
- ✅ No UI freeze on file loads
- ✅ Smooth crossfades (no stuttering)

---

## 🚀 Advanced Solutions (Production-Grade)

### Option 1: AVAssetResourceLoader (Apple Native)

**Pros:**
- ✅ Handles streaming + caching natively
- ✅ Integrated with AVFoundation
- ✅ Supports HTTP range requests

**Cons:**
- ❌ Overkill for local files
- ❌ More complex setup
- ❌ Better for network streaming

**When to use:** If you plan to add cloud streaming later

### Option 2: NSCache (System Memory Management)

**Replace custom LRU with NSCache:**

```swift
actor AudioFileCache {
    private let cache = NSCache<NSURL, CachedAudioFile>()
    
    init(maxCacheSize: Int = 5) {
        cache.countLimit = maxCacheSize
        cache.name = "AudioFileCache"
    }
    
    func getAudioFile(for url: URL) async throws -> AVAudioFile {
        // NSCache handles LRU automatically!
        if let cached = cache.object(forKey: url as NSURL) {
            return cached.file
        }
        
        let file = try await loadFromDisk(url: url)
        cache.setObject(CachedAudioFile(file), forKey: url as NSURL)
        return file
    }
}
```

**Pros:**
- ✅ System manages memory pressure
- ✅ Auto-eviction on memory warning
- ✅ Less code to maintain

**Cons:**
- ❌ Less control over eviction policy
- ❌ No built-in metrics
- ❌ Thread-safe but not actor-isolated

**Recommendation:** Start with custom LRU (better control), migrate to NSCache if needed

### Option 3: Persistent Disk Cache (SQLite + File System)

**For very large files or offline-first apps:**

```swift
actor PersistentAudioCache {
    private let memoryCache: AudioFileCache  // L1 cache
    private let diskCache: DiskCacheManager  // L2 cache (SQLite)
    
    func getAudioFile(for url: URL) async throws -> AVAudioFile {
        // 1. Check memory cache (fast)
        if let file = await memoryCache.get(url) {
            return file
        }
        
        // 2. Check disk cache (slower, but still cached)
        if let file = await diskCache.get(url) {
            await memoryCache.set(url, file)
            return file
        }
        
        // 3. Load from original location
        let file = try await loadFromDisk(url: url)
        await diskCache.set(url, file)
        await memoryCache.set(url, file)
        return file
    }
}
```

**When to use:**
- Large file libraries (100+ tracks)
- Slow storage (SD cards)
- Offline-first apps

**Recommendation:** Not needed for meditation app (small playlist, fast storage)

---

## 📝 Рекомендація (Priority Order)

### 🔴 HIGH Priority (Start Now)
1. **AudioFileCache with LRU** (Phase 1-2) - 2 weeks
   - Biggest ROI: 80-95% latency reduction
   - Simple, focused solution
   - No external dependencies

2. **Atomic Skip with Rollback** (Phase 4) - 1 week
   - Fixes critical index desync bug
   - Low complexity, high impact

### 🟡 MEDIUM Priority (After Cache)
3. **Preloading Strategy** (Phase 3) - 3 days
   - Further improves UX
   - Depends on cache infrastructure

4. **Auto-skip Invalid Files** (Phase 4, optional) - 2 days
   - Nice-to-have, not critical
   - Better UX for corrupted files

### 🟢 LOW Priority (Future)
5. **Metrics & Dashboard** (Phase 5) - 1 week
   - Useful for optimization
   - Not blocking for beta release

6. **NSCache Migration** (Optional)
   - Consider after real-world usage
   - If memory pressure becomes issue

---

## 💡 Quick Win (Minimal Change)

**Якщо потрібно швидке покращення без повного cache:**

```swift
// AudioEngineActor.swift - ADD simple cache
actor AudioEngineActor {
    private var fileCache: [URL: AVAudioFile] = [:]  // Simple dict cache
    
    func loadAudioFileOnSecondaryPlayer(track: Track) async throws -> Track {
        // Check cache first
        if let cached = fileCache[track.url] {
            print("[AudioEngine] ✅ Cache HIT: \(track.url.lastPathComponent)")
            return createTrackWithMetadata(file: cached, url: track.url)
        }
        
        // Cache miss - load from disk
        print("[AudioEngine] ⏳ Cache MISS: \(track.url.lastPathComponent)")
        let file = try AVAudioFile(forReading: track.url)
        
        // Store in cache (no eviction - simple!)
        fileCache[track.url] = file
        
        return createTrackWithMetadata(file: file, url: track.url)
    }
}
```

**Pros:**
- ✅ 20 рядків коду
- ✅ 80%+ improvement for repeated tracks
- ✅ Zero external dependencies

**Cons:**
- ❌ Unbounded memory growth (no eviction)
- ❌ Not production-ready

**When to use:** Quick prototype to validate improvement, before full cache implementation

---

## 🎬 Conclusion

**Recommended Path Forward:**

1. **Week 1-2:** Implement `AudioFileCache` with LRU + integration
2. **Week 3:** Add atomic skip with rollback + preloading
3. **Week 4:** Testing + metrics

**Expected Results:**
- ✅ 80-95% latency reduction on repeated operations
- ✅ Zero index desyncs
- ✅ Smooth 30-min sessions without I/O hiccups
- ✅ Memory usage <100 MB

**ROI:** High impact, moderate effort, production-ready solution for meditation app use case.
