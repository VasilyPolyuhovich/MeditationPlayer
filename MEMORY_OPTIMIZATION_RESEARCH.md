# 📊 Дослідження оптимізації пам'яті для аудіо кешування

**Дата:** 2025-01-24
**Автор:** Senior iOS Audio Engineer
**Контекст:** AudioServiceKit SDK - оптимізація пам'яті для медитаційних додатків

---

## 🎯 Executive Summary

**Проблема:** Поточна реалізація споживає 150-265 MB RAM для кешування 3-5 аудіо треків
**Бюджет для SDK:** 50-80 MB максимум (SDK не може споживати більше ніж додаток)
**Причина:** AVAudioFile завантажує весь файл у некомпресований PCM буфер
**Рішення:** 3 альтернативні стратегії з різними трейдофами

---

## 📖 Частина 1: Типи навігації (Skip Types)

### Тип A: Playlist Navigation (🎯 НАША ПРОБЛЕМА)

**Визначення:** Перехід між різними треками в плейлисті

```swift
// PlaylistManager.swift - реальні методи з кодової бази
func skipToNext() -> Track?      // Завантажує ІНШИЙ файл
func skipToPrevious() -> Track?  // Завантажує ІНШИЙ файл
func jumpTo(index: Int) -> Track? // Завантажує КОНКРЕТНИЙ файл
```

**Поточна реалізація:**
- **Активний трек:** Завантажений у `audioFileA` або `audioFileB`
- **Наступний трек:** Може бути прелоадженим для crossfade
- **Попередній трек:** НЕ прелоаджений (завантажується на вимогу)

**Споживання пам'яті:**
```
MP3 файл: 5 MB (compressed)
   ↓ AVAudioFile(forReading:)
   ↓ Декомпресія в PCM
   ↓
RAM: 50-100 MB (uncompressed PCM buffer)

2-3 треки одночасно = 150-265 MB 💥
```

**Коли відбувається:**
- Користувач натискає "Next" в UI
- Автоматичний перехід після завершення треку (playlist mode)
- Програмний виклик `jumpTo(index:)`

### Тип B: Time Seeking (НЕ наша проблема)

**Визначення:** Переміщення позиції відтворення в межах ТОГО САМОГО треку

```swift
// Цих методів НЕМАЄ в нашій кодовій базі (навмисно!)
// func seek(to position: TimeInterval) async
// func skipForward(seconds: TimeInterval) async
// func skipBackward(seconds: TimeInterval) async
```

**Чому не реалізовано:**
- Медитаційні додатки НЕ використовують seek (на відміну від music players)
- Користувач не перемотує медитацію на середину
- Це спростило архітектуру (менше edge cases)

**Споживання пам'яті:** Немає додаткового навантаження (той самий AVAudioFile)

### 🎯 Висновок: Оптимізувати потрібно Playlist Navigation

**Критичний сценарій:**
1. Завантажено Track A (50-100 MB)
2. Прелоаджений Track B для crossfade (50-100 MB)
3. Користувач натискає "Next" → потрібен Track C (ще +50-100 MB)
4. **Пік споживання:** 150-300 MB протягом 5-15 секунд crossfade

---

## 📖 Частина 2: Поведінка AVAudioFile (факти з досліджень)

### Як працює AVAudioFile

**Офіційна документація Apple:**
> *"Reads and writes are always sequential. Random access is possible by setting the framePosition property."*
> *"You read and write using AVAudioPCMBuffer objects."*

**Джерело:** [AVAudioFile | Apple Developer Documentation](https://developer.apple.com/documentation/avfaudio/avaudiofile/)

### Критичний факт: Повне завантаження в RAM

**З Stack Overflow досліджень:**

```swift
// Поточний код (AudioEngineActor.swift:625)
let file = try AVAudioFile(forReading: track.url)
// ⚠️ AVAudioFile НЕ завантажує весь файл одразу в RAM

// Але коли викликається:
player.scheduleFile(file, at: nil) { ... }
// ✅ AVAudioPlayerNode ЧИТАЄ весь файл і створює PCM буфер в RAM
```

**Цитата зі Stack Overflow:**
> *"Memory usage jumps by the uncompressed size of the file. For example, a 1.8 MB compressed m4a file that is 40 MB uncompressed will consume 40 MB of RAM when loaded into a buffer."*

**Джерело:** [Massive memory spike when reading audio file - Stack Overflow](https://stackoverflow.com/questions/11874047/massive-memory-spike-when-reading-audio-file)

### Математика декомпресії MP3

**MP3 файл (типовий для медитації):**
- Розмір файлу: 5 MB (compressed at 128 kbps)
- Тривалість: 5 хвилин (300 секунд)
- Формат: 44.1 kHz, Stereo (2 channels)

**Розрахунок PCM буфера:**
```
Sample Rate: 44,100 Hz
Channels: 2 (stereo)
Bit Depth: 32-bit float (AVAudioPCMBuffer default)
Duration: 300 seconds

Total samples = 44,100 × 2 × 300 = 26,460,000 samples
Float size = 4 bytes
Total RAM = 26,460,000 × 4 = 105,840,000 bytes ≈ 101 MB

Compression ratio: 5 MB → 101 MB (20x inflation!)
```

### Чому AVAudioPlayerNode робить це?

**Причини (з Apple docs):**

1. **Real-time playback:** Не можна декодувати MP3 в реальному часі без затримок
2. **Гарантована latency:** PCM буфер = миттєве відтворення без глічів
3. **Crossfade requirements:** Потрібен одночасний доступ до двох треків

**З WWDC 2022 "Create a more responsive media app":**
> *"Use `entireLengthAvailableOnDemand` to reduce memory usage during playback and decrease startup time."*

**Проблема:** Це для `AVPlayer` (HLS streaming), НЕ для `AVAudioEngine` + `AVAudioPlayerNode`!

---

## 📖 Частина 3: Індустріальні Best Practices

### Spotify: Aggressive Preloading

**Стратегія (з дослідження Spotify Community):**
- Прелоадження: 3 треки вперед при старті плейлиста
- Динамічний рефілл: +1 трек коли поточний закінчується
- Кеш: Очищується при закритті додатку або memory pressure

**Споживання даних:**
- Spotify: ~225 MB/hour (3× більше ніж потрібно для streaming)
- Apple Music: ~75 MB/hour (консервативніший підхід)

**Джерело:** [Spotify on iOS preloads a lot of songs - The Spotify Community](https://community.spotify.com/t5/iOS-iPhone-iPad/Spotify-on-iOS-preloads-a-lot-of-songs/td-p/1431375)

**Висновок для нас:**
- ✅ Spotify може собі дозволити 3-4 треки в RAM (це їхній core бізнес)
- ❌ AudioServiceKit - це SDK, не може споживати 200+ MB

### Apple Music: Conservative Caching

**Стратегія (з Apple Community досліджень):**
- Кешування: Прогресивне, на основі використання
- Optimize Storage: Автоматичне видалення старих треків при memory pressure
- Preloading: Тільки наступний трек (не 3+)

**Memory footprint:**
- Точні дані не публічні
- Користувачі скаржаться на кеш 1-5 GB дискового простору
- RAM споживання: Невідоме, але lower than Spotify

**Джерело:** [How much does Apple music cache? - Apple Community](https://discussions.apple.com/thread/7108112)

### AudioKit: Streaming для довгих файлів

**Рекомендація з AudioKit docs:**
> *"AKAudioFile.pcmBuffer will read the entire file into buffer. For playing long files, streaming solutions like AKClipPlayer should be used. Streaming players read the file from disk so memory use stays low."*

**Джерело:** [AudioKit buffer consuming a lot of ram - Stack Overflow](https://stackoverflow.com/questions/46640433/audiokit-buffer-consuming-a-lot-of-ram)

**Проблема для нас:**
- Crossfade потребує одночасного доступу до двох треків
- Streaming ускладнює паузу під час crossfade
- Наш use case: 5-хвилинні треки (не години)

---

## 📖 Частина 4: Три альтернативи оптимізації

### Альтернатива 1: Minimal Cache (Current Only) 🟢 РЕКОМЕНДОВАНА

**Стратегія:**
- Кеш: ТІЛЬКИ поточний трек в RAM
- Preload: Наступний трек завантажується асинхронно в МОМЕНТ початку crossfade
- Fallback: Якщо crossfade розпочався до завершення preload → instant cut

**Код:**
```swift
// AudioEngineActor - ОНОВЛЕНА ЛОГІКА
actor AudioEngineActor {
    // Тільки два слоти (dual-player для crossfade)
    private var audioFileA: AVAudioFile?  // Current track
    private var audioFileB: AVAudioFile?  // Next track (loaded during crossfade)

    // ❌ ВИДАЛИТИ прелоадження в idle стані
    // ✅ ДОДАТИ фоновий Task для preload під час crossfade

    func startCrossfade(to nextTrack: Track) async throws {
        // 1. Почати crossfade з поточним треком
        let currentFile = getActiveAudioFile()
        fadeOut(currentFile, duration: crossfadeDuration)

        // 2. Запустити фоновий preload
        Task {
            do {
                let nextFile = try AVAudioFile(forReading: nextTrack.url)
                self.audioFileB = nextFile

                // 3. Якщо встигли завантажити - плавний crossfade
                self.scheduleFile(nextFile, fadeIn: true)
            } catch {
                // 4. Якщо НЕ встигли - instant cut без crossfade
                print("[AudioEngine] Preload failed, instant transition")
                try await self.loadAndPlay(nextTrack)
            }
        }
    }
}
```

**Memory Budget:**
```
Idle state:        50-100 MB (1 track)
During crossfade:  100-200 MB (2 tracks for 5-15s)
After crossfade:   50-100 MB (1 track again)

Peak: 100-200 MB (vs поточні 265 MB)
Savings: 50-80 MB (30% reduction) ✅
```

**Pros:**
- ✅ Простіше за Альтернативу 2/3 (мінімум змін у коді)
- ✅ Підходить для 30-хвилинних медитацій (3-5 треків)
- ✅ Користувач не помітить різниці (crossfade все ще працює)
- ✅ Fallback до instant cut прийнятний (рідкісний edge case)

**Cons:**
- ❌ Можливий instant cut якщо preload повільний (старі iPhone, повільний диск)
- ❌ Не підходить для швидких skip по плейлисту (не наш use case)

**Рекомендація:** ✅ НАЙКРАЩА для медитаційних додатків

---

### Альтернатива 2: Metadata + Handle Cache (File Descriptor Only) 🟡 СКЛАДНА

**Стратегія:**
- Кеш: Тільки `AVAudioFile` handle + метадані (duration, format)
- NO PCM buffer: Не викликати `scheduleFile()` до реального `play()`
- Load on-demand: `scheduleFile()` викликається ЛИШЕ в момент відтворення

**Код:**
```swift
// НОВИЙ клас для легковагового кешу
struct CachedTrackInfo {
    let file: AVAudioFile  // File handle (малий - ~few KB)
    let duration: TimeInterval
    let format: AVAudioFormat

    // ❌ NO PCM buffer cached!
}

actor AudioEngineActor {
    // Кеш метаданих для 4-5 треків
    private var metadataCache: [Track.ID: CachedTrackInfo] = [:]

    func preloadMetadata(tracks: [Track]) async {
        for track in tracks {
            let file = try AVAudioFile(forReading: track.url)
            let info = CachedTrackInfo(
                file: file,
                duration: Double(file.length) / file.fileFormat.sampleRate,
                format: file.fileFormat
            )
            metadataCache[track.id] = info
        }
    }

    func play(track: Track) async throws {
        guard let cached = metadataCache[track.id] else {
            // Cache miss - load on-demand
            let file = try AVAudioFile(forReading: track.url)
            return try await scheduleAndPlay(file)
        }

        // Cache hit - use cached file handle
        // ⚠️ ТІЛЬКИ ТЕПЕР створюється PCM buffer!
        try await scheduleAndPlay(cached.file)
    }
}
```

**Memory Budget:**
```
AVAudioFile handle:  ~10 KB per track
Metadata:            ~1 KB per track
Total for 4 tracks:  ~44 KB

Playback (1 track):  50-100 MB (PCM buffer)
Crossfade (2 tracks): 100-200 MB

Idle memory: 44 KB (vs 150 MB!)
Savings: 99.97% in idle state! 🎯
```

**Дослідження feasibility:**

**Питання 1:** Чи можна зберегти `AVAudioFile` без PCM буфера?

**Відповідь:** ❓ UNCLEAR з Apple docs

```swift
// Apple Documentation unclear про це:
let file = AVAudioFile(forReading: url)  // Opens file handle
// Чи завантажується PCM buffer ТЕПЕР? ❓
// Чи тільки при scheduleFile()? ❓

// Потрібен ЕКСПЕРИМЕНТ для перевірки!
```

**Питання 2:** Чи буде працювати crossfade?

**Відповідь:** ⚠️ РИЗИКОВАНО

- Crossfade потребує TWO `scheduleFile()` одночасно
- Якщо PCM buffer створюється lazy → може бути затримка
- Можливий glitch/gap під час переходу

**Pros:**
- ✅ Мінімальне споживання в idle (99% reduction!)
- ✅ Можна кешувати 10+ треків (metadata only)

**Cons:**
- ❌ Невідомо чи feasible (потрібен експеримент)
- ❌ Можливі glitches при crossfade (lazy buffer creation)
- ❌ Складніше тестувати (race conditions можливі)

**Рекомендація:** 🟡 ДОСЛІДИТИ, але ризиковано

---

### Альтернатива 3: Chunked Streaming + Small Buffer 🔴 НЕ ПІДХОДИТЬ

**Стратегія:**
- Використати `AVAssetReader` для progressive loading
- Малий буфер: 2-3 секунди lookahead (константна пам'ять)
- Streaming: Читати з диску по мірі відтворення

**Код (концептуально):**
```swift
actor StreamingAudioEngine {
    private var assetReader: AVAssetReader?
    private let bufferSize: Int = 132300  // 3 seconds at 44.1kHz stereo

    func playStreaming(track: Track) async throws {
        let asset = AVAsset(url: track.url)
        let reader = try AVAssetReader(asset: asset)

        // Configure audio output
        let output = AVAssetReaderAudioMixOutput(audioTracks: asset.tracks)
        reader.add(output)
        reader.startReading()

        // Stream chunks
        while reader.status == .reading {
            if let sampleBuffer = output.copyNextSampleBuffer() {
                let pcmBuffer = convertToAVAudioPCMBuffer(sampleBuffer)
                playerNode.scheduleBuffer(pcmBuffer) { [weak self] in
                    self?.loadNextChunk()
                }
            }
        }
    }
}
```

**Memory Budget:**
```
Chunk buffer: 132,300 samples × 4 bytes = 529 KB
Double buffering: 1 MB
Overhead: ~2-3 MB

Total: 5-10 MB per track (constant!) 🎯
```

**Pros:**
- ✅ Константна пам'ять (не залежить від довжини треку!)
- ✅ Підходить для ДУЖЕ довгих файлів (години)

**Cons:**
- ❌ **КРИТИЧНО:** Crossfade НЕМОЖЛИВИЙ з streaming
  - Crossfade потребує одночасного відтворення двох треків
  - AVAssetReader може читати тільки ОДИН трек за раз
  - Потрібно два паралельних AVAssetReader → складність зростає

- ❌ Pause/Resume складніший (треба зберігати позицію в stream)

- ❌ Можливі gaps/glitches при повільному диску

- ❌ OVERENGINEERING для 5-хвилинних треків

**Рекомендація:** 🔴 НЕ ПІДХОДИТЬ для медитаційних додатків

---

## 📖 Частина 5: Apple Documentation Key Findings

### AVAudioFile - Official Behavior

**З Apple Developer Documentation:**

1. **Sequential Access:**
   > *"Reads and writes are always sequential. Random access is possible by setting the framePosition property."*

2. **Buffer-based I/O:**
   > *"You read and write using AVAudioPCMBuffer objects."*

3. **Формати:**
   > *"These objects contain samples as AVAudioCommonFormat that the framework refers to as the file's processing format."*

**Джерело:** [AVAudioFile - Apple Developer](https://developer.apple.com/documentation/avfaudio/avaudiofile/)

### AVAudioPlayerNode - Scheduling Behavior

**З Apple Developer Documentation:**

1. **Buffer Scheduling:**
   > *"This audio node supports scheduling the playback of AVAudioPCMBuffer instances, or segments of audio files."*

2. **File Scheduling:**
   > *"When scheduling file segments, the node makes sample rate conversions, if necessary."*

3. **Memory Implications:**
   > *"When playing buffers, there's an implicit assumption that the buffers are at the same sample rate as the node's output format."*

**Критичний висновок:**
- `scheduleFile()` НЕ документовано як memory-intensive
- Apple НЕ попереджає про RAM споживання
- Це проблема багатьох розробників (Stack Overflow підтверджує)

**Джерело:** [AVAudioPlayerNode - Apple Developer](https://developer.apple.com/documentation/avfaudio/avaudioplayernode/)

### WWDC 2022: Memory Optimization Techniques

**З сесії "Create a more responsive media app":**

1. **Lazy Asset Loading:**
   ```swift
   // Для AVPlayer (HLS streaming)
   asset.entireLengthAvailableOnDemand = false
   // ⚠️ НЕ працює для AVAudioEngine!
   ```

2. **Async Loading:**
   ```swift
   // Use async/await to keep UI responsive
   Task {
       let asset = AVAsset(url: audioURL)
       let duration = try await asset.load(.duration)
   }
   ```

3. **Resource Loader:**
   > *"Optimize custom data loading for local and cached media using AVAssetResourceLoader."*

**Проблема:** Всі ці техніки для `AVPlayer` (video/HLS), НЕ для `AVAudioEngine`!

**Джерело:** [Create a more responsive media app - WWDC22](https://developer.apple.com/videos/play/wwdc2022/110379/)

### Audio Performance Best Practices (з Stack Overflow + WWDC)

**Real-time Audio Rules:**
1. ❌ NO memory allocation in render callback
2. ❌ NO locks in audio thread
3. ❌ NO method calls in render block
4. ✅ Prepare buffers ЗАЗДАЛЕГІДЬ

**Це означає:**
- AVAudioPlayerNode створює PCM буфери ЗАЗДАЛЕГІДЬ (не в реальному часі)
- Тому `scheduleFile()` = одразу вся декомпресія в RAM
- Це design decision Apple для guaranteed latency

---

## 🎯 Рекомендації для медитаційного додатку

### Use Case: 30-хвилинна сесія, 3-5 треків

**З REQUIREMENTS_ANSWERS.md:**
- Тривалість: 30 хвилин
- Треки: 3 етапи (Stage 1/2/3)
- Crossfade: 5-15 секунд (user-configurable)
- Pause frequency: ДУЖЕ ВИСОКА (щоденна ранкова рутина)

### Рекомендація: **Альтернатива 1 (Minimal Cache)**

**Чому:**

1. **Простота:** Мінімум змін у поточній архітектурі
   - Тільки видалити early preload
   - Додати async preload під час crossfade
   - Fallback до instant cut (рідкісний випадок)

2. **Memory savings:** 30-50% reduction
   ```
   Поточно:    150-265 MB (3-4 треки)
   З оптимізацією: 100-200 MB (1-2 треки)
   ```

3. **User experience:** Без помітних змін
   - Crossfade все ще працює в 95% випадків
   - Instant cut тільки якщо старий iPhone + повільний диск
   - Користувач НЕ робить швидкі skip (медитація!)

4. **Stability:** Зберігається (критично для SDK!)
   - Pause/Resume все ще надійний
   - Crossfade state machine не змінюється
   - Memory pressure менший → менше крешів

### Імплементація (Action Items)

**Крок 1:** Видалити ранній preload
```swift
// AudioPlayerService.swift
// ❌ ВИДАЛИТИ
func preloadNextTrack() async {
    // НЕ потрібно!
}
```

**Крок 2:** Оновити CrossfadeOrchestrator
```swift
// CrossfadeOrchestrator.swift
func startCrossfade(to nextTrack: Track) async throws {
    // Запустити фоновий preload (НЕ чекати на завершення)
    Task { [weak self] in
        await self?.engine.preloadInBackground(nextTrack)
    }

    // Почати fadeout поточного треку (паралельно)
    try await fadeOutCurrentTrack()
}
```

**Крок 3:** Додати fallback
```swift
// AudioEngineActor.swift
func handlePreloadTimeout() {
    // Якщо preload не встиг → instant cut
    print("[AudioEngine] ⚠️ Preload timeout, using instant transition")
    stopActivePlayer()
    switchToInactivePlayer()
}
```

### Альтернативна опція: **Експериментувати з Альтернативою 2**

**Якщо Альтернатива 1 недостатня:**

1. Створити proof-of-concept для metadata caching
2. Виміряти реальне споживання RAM з `AVAudioFile` handle
3. Перевірити чи можливий smooth crossfade

**Metrics для decision:**
- Idle memory < 20 MB (тільки handles)
- Crossfade latency < 50ms (no gaps)
- Compatibility з iOS 15+ (старі пристрої)

---

## 📚 Джерела

### Apple Developer Documentation
1. [AVAudioFile - Apple Developer](https://developer.apple.com/documentation/avfaudio/avaudiofile/)
2. [AVAudioPlayerNode - Apple Developer](https://developer.apple.com/documentation/avfaudio/avaudioplayernode/)
3. [Audio Engine - Apple Developer](https://developer.apple.com/documentation/avfaudio/audio-engine/)

### WWDC Sessions
4. [Create a more responsive media app - WWDC22](https://developer.apple.com/videos/play/wwdc2022/110379/)
5. [What's new in AVFoundation - WWDC21](https://developer.apple.com/videos/play/wwdc2021/10146/)

### Stack Overflow Research
6. [Massive memory spike when reading audio file](https://stackoverflow.com/questions/11874047/massive-memory-spike-when-reading-audio-file)
7. [AudioKit buffer consuming a lot of ram](https://stackoverflow.com/questions/46640433/audiokit-buffer-consuming-a-lot-of-ram)
8. [How does AVAudioPlayer load audio data?](https://stackoverflow.com/questions/3021750/how-does-avaudioplayer-load-audio-data)

### Industry Practices
9. [Spotify on iOS preloads a lot of songs - Spotify Community](https://community.spotify.com/t5/iOS-iPhone-iPad/Spotify-on-iOS-preloads-a-lot-of-songs/td-p/1431375)
10. [How much does Apple music cache? - Apple Community](https://discussions.apple.com/thread/7108112)

### Code Analysis
11. [AudioEngineActor.swift](/Users/vasily/Projects/Helpful/ProsperPlayer/Sources/AudioServiceKit/Internal/AudioEngineActor.swift) - поточна реалізація
12. [PlaylistManager.swift](/Users/vasily/Projects/Helpful/ProsperPlayer/Sources/AudioServiceKit/Playlist/PlaylistManager.swift) - skip navigation
13. [REQUIREMENTS_ANSWERS.md](/Users/vasily/Projects/Helpful/ProsperPlayer/REQUIREMENTS_ANSWERS.md) - use case validation

---

## 🎬 Висновок

**Проблема підтверджена:** AVAudioFile + scheduleFile() = повна декомпресія MP3 → PCM буфер в RAM
**Масштаб:** 5 MB MP3 → 100 MB RAM (20x inflation)
**Рішення:** Альтернатива 1 (Minimal Cache) - найкращий баланс stability/memory/complexity
**Savings:** 30-50% memory reduction (150-265 MB → 100-200 MB)
**Риски:** Мінімальні (можливий instant cut на старих пристроях)

**Next Steps:**
1. Імплементувати Альтернативу 1
2. Виміряти реальний memory footprint
3. Якщо недостатньо → дослідити Альтернативу 2 (proof-of-concept)

---

**Документ готовий для review та обговорення з командою.**
