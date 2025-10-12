# 📋 ProsperPlayer v4.0 - Повний Функціонал

**Фокус:** Meditation/Sleep Audio Player  
**НЕ:** Universal Music Player (Spotify clone)

---

## 🎯 Core Features Overview

| Feature | Status | Meditation Value | Priority |
|---------|--------|------------------|----------|
| **Basic Playback** | ✅ | Essential | Critical |
| **Seamless Crossfade** | ✅ | Prevents meditation break | Critical |
| **Loop with Crossfade** | ✅ | Sleep sounds infinite | Critical |
| **Overlay Player** | ✅ | Rain + music mix | Killer Feature |
| **Volume Control** | ✅ | User + developer control | High |
| **Playlist Management** | ✅ | Session structure | High |
| **Remote Commands** | ✅ | Lock screen control | High |
| **Background Playback** | ✅ | Sleep timer scenarios | Critical |
| **Shuffle Mode** | ❌ | NOT needed (structured) | Skip |
| **Gapless** | ⚪ | Crossfade better | Low |

---

## 1️⃣ Basic Playback Control

### 1.1 Start Playing
**Що робить:**  
Починає відтворення треку з опціональним fade in для м'якого входу.

**Навіщо для meditation:**  
Різкий старт звуку може злякати/відвернути увагу. Fade in дає плавний перехід від тиші до музики.

**Як працює:**
1. Бере поточний трек з PlaylistManager (URL вже завантажений)
2. Налаштовує audio session для background playback
3. Завантажує файл на primary player
4. Запускає з fade in (якщо вказано) або instant start
5. Оновлює Lock Screen info

**API:**
```swift
func startPlaying(fadeDuration: TimeInterval = 0.0) async throws

// Приклади:
await player.startPlaying()                    // Instant start
await player.startPlaying(fadeDuration: 2.0)   // 2s fade in
```

---

### 1.2 Pause / Resume
**Що робить:**  
Призупиняє або відновлює відтворення.

**Навіщо для meditation:**  
Користувач може перервати сесію (телефонний дзвінок, відволікання). Resume продовжує з того ж місця.

**Як працює:**
- **Pause:** Зупиняє playback timer, захоплює поточну позицію, зберігає стан crossfade (якщо активний)
- **Resume:** Продовжує з збереженої позиції, відновлює crossfade state (якщо був), перезапускає timer

**Критична фіча Phase 5:**  
Якщо pause відбувся під час crossfade (наприклад, на 30% прогресу), resume має продовжити crossfade з 30%, а не починати заново!

**API:**
```swift
func pause() async throws
func resume() async throws

// Або для обох систем (main + overlay):
func pauseAll() async
func resumeAll() async
```

---

### 1.3 Stop
**Що робить:**  
Зупиняє відтворення з опціональним fade out.

**Навіщо для meditation:**  
Різке припинення звуку вириває з медитативного стану. Fade out дає плавне завершення.

**Як працює:**
1. Якщо `fadeDuration = 0` → instant stop (mixer volume = 0, engine stop)
2. Якщо `fadeDuration > 0` → fade out active mixer до 0, потім stop
3. Deactivate audio session
4. Clear Now Playing info
5. Reset position

**API:**
```swift
func stop(fadeDuration: TimeInterval = 0.0) async

// Приклади:
await player.stop()                    // Instant stop
await player.stop(fadeDuration: 5.0)   // 5s fade out
```

---

### 1.4 Skip Forward/Backward
**Що робить:**  
Перемотує на ±15 секунд (стандарт для meditation apps).

**Навіщо для meditation:**  
Користувач може хотіти повторити інструкцію чи пропустити частину.

**Як працює:**
1. Отримує поточну позицію
2. Обчислює нову позицію (current ± 15s)
3. Використовує `seekWithFade()` для плавного переходу (БЕЗ click!)
4. Оновлює UI position

**API:**
```swift
func skipForward(by interval: TimeInterval = 15.0) async
func skipBackward(by interval: TimeInterval = 15.0) async
```

---

### 1.5 Seek with Fade
**Що робить:**  
Переміщує позицію відтворення з fade для усунення click.

**Навіщо для meditation:**  
**КРИТИЧНО!** Instant seek створює LOUD CLICK (AVFoundation artifact) → порушує медитацію миттєво.

**Як працює:**
1. Fade out поточна позиція (0.1s)
2. Instant seek до нової позиції (під час silence)
3. Fade in з нової позиції (0.1s)
4. Total: 0.2s transition без click

**UI Implementation:**
- Поки немає slider (skip buttons ±15s)
- Але API готовий для майбутнього slider
- Default fade: 0.1s (швидко але smooth)

**API:**
```swift
func seekWithFade(to time: TimeInterval, fadeDuration: TimeInterval = 0.1) async throws

// Використання:
await player.seekWithFade(to: 30.0)                    // Quick seek (0.1s)
await player.seekWithFade(to: 30.0, fadeDuration: 0.2) // Slower (0.2s)
```

---

## 2️⃣ Configuration System

### 2.1 Player Configuration
**Що робить:**  
Визначає базову поведінку плеєра.

**v4.0 Спрощення:**  
БУЛО: 5 fade параметрів → СТАЛО: 1 crossfadeDuration + fade в методах

**Структура:**
```swift
PlayerConfiguration(
    crossfadeDuration: TimeInterval,  // Between tracks (user sets)
    fadeCurve: FadeCurve,            // Linear, EqualPower, Exponential
    repeatMode: RepeatMode,          // .off, .singleTrack, .playlist
    repeatCount: Int?,               // Limit loops (nil = infinite)
    mixWithOthers: Bool              // Mix with other apps audio
)
```

**Параметри:**

**crossfadeDuration (5-15s для meditation):**
- Тривалість crossfade між РІЗНИМИ треками
- Користувач конфігурує (не hardcoded!)
- Орієнтир: Spotify 0-12s
- Для meditation: 10-15s нормально (плавні переходи)

**fadeCurve:**
- `linear` - рівномірна зміна
- `equalPower` - природне звучання (recommended)
- `exponential` - прискорення наприкінці

**repeatMode:**
- `.off` - play once, stop
- `.singleTrack` - loop current track (sleep sounds!)
- `.playlist` - loop whole playlist (session phases)

**mixWithOthers:**
- `true` - мікс з іншими додатками (background music)
- `false` - заглушити інші додатки (focused meditation)

**API:**
```swift
// Get/Set configuration
func getConfiguration() -> PlayerConfiguration
func updateConfiguration(_ config: PlayerConfiguration) async
```

---

### 2.2 Repeat Mode
**Що робить:**  
Визначає що відбувається після завершення треку.

**Modes:**

**`.off` - Play Once:**
- Трек грається 1 раз
- Після завершення → stop
- Use case: single meditation session

**`.singleTrack` - Loop Current:**
- Трек грається в нескінченному циклі
- З **seamless crossfade** на loop point!
- Use case: sleep sounds (ocean waves 30min → loop infinite)

**`.playlist` - Loop Playlist:**
- Всі треки грають послідовно
- Після останнього → повертається до першого
- З crossfade між треками
- Use case: meditation program (3 phases → repeat)

**API:**
```swift
func setRepeatMode(_ mode: RepeatMode) async
func getRepeatMode() -> RepeatMode
func getRepeatCount() -> Int  // Скільки разів зациклено
```

---

## 3️⃣ Seamless Crossfade System

### 3.1 Track Switch Crossfade
**Що робить:**  
Плавний перехід між РІЗНИМИ треками без gap/click.

**Навіщо для meditation:**  
Різкий перехід (track1 stop → track2 start) = meditation broken. Crossfade дає seamless flow.

**Як працює (Dual-Player Architecture):**
1. **Preparation:**
   - PlayerA грає Track 1 (active)
   - PlayerB завантажує Track 2 (inactive)

2. **Crossfade:**
   - Calculate sync time (sample-accurate!)
   - PlayerB starts at exact time
   - MixerA: volume 1.0 → 0.0 (fade out Track 1)
   - MixerB: volume 0.0 → 1.0 (fade in Track 2)
   - Duration: `crossfadeDuration` (user configured)

3. **Switch:**
   - PlayerB тепер active
   - PlayerA тепер inactive (готовий для наступного треку)

**Результат:**  
Zero gap, zero click, seamless transition!

**API:**
```swift
// Automatic при playlist advance
// Або manual:
func replaceTrack(url: URL, crossfadeDuration: TimeInterval = 5.0) async throws
```

---

### 3.2 Single Track Loop Crossfade
**Що робить:**  
Seamless loop одного треку з crossfade між кінцем і початком.

**Навіщо для meditation:**  
Sleep sounds (rain, ocean, white noise) мають loop infinite БЕЗ gap. Стандартні плеєри мають short silence на loop point → порушує сон!

**Як працює:**
1. **Track plays до trigger point:**
   - Monitor position кожні 0.5s
   - Trigger = `duration - crossfadeDuration`
   - Наприклад: 60s track, 10s crossfade → trigger at 50s

2. **Loop crossfade starts:**
   - PlayerA грає кінець треку (50s → 60s)
   - PlayerB завантажує ТОЙ САМИЙ файл, грає початок (0s → 10s)
   - Sample-accurate sync
   - Crossfade 10s

3. **Switch players:**
   - PlayerB тепер active (грає трек з 10s позиції)
   - PlayerA тепер inactive
   - На наступному loop - навпаки

**Auto-Adaptation (Phase 4):**  
Короткий трек (15s) + довгий crossfade (10s) = 67% overlap = каша!

**Рішення:**
```
maxCrossfade = trackDuration * 0.4  // Max 40% track
actualCrossfade = min(configured, maxCrossfade)

// Examples:
// 15s track + 10s config → 6s actual (40%)
// 60s track + 10s config → 10s actual (as configured)
```

**API:**
```swift
// Automatic при repeatMode = .singleTrack
// Configuration via:
PlayerConfiguration(
    crossfadeDuration: 10.0,      // Used for loop
    repeatMode: .singleTrack
)
```

---

### 3.3 Crossfade Progress Tracking
**Що робить:**  
Дозволяє UI відображати прогрес crossfade.

**Навіщо:**  
Користувач/developer бачить що відбувається transition (debug, UI feedback).

**Як працює:**
1. Crossfade starts → emit progress updates
2. Progress: `0.0` (start) → `1.0` (complete)
3. Interval: кожні 0.1s (10 updates per second)
4. Completion callback

**API:**
```swift
// Observer pattern:
protocol AudioPlayerObserver {
    func player(_ player: AudioPlayerService, 
                didUpdateCrossfadeProgress progress: CrossfadeProgress)
}

struct CrossfadeProgress {
    let progress: Float           // 0.0-1.0
    let playerAVolume: Float      // Fading out
    let playerBVolume: Float      // Fading in
    let remainingDuration: TimeInterval
}

// Usage:
player.addObserver(myObserver)
```

---

## 4️⃣ Volume Control

### 4.1 Global Volume
**Що робить:**  
Регулює ЗАГАЛЬНУ гучність всіх audio (main player).

**Архітектура (Critical!):**

**Three-Level System:**

1. **Initial Volume (Developer):**
   - Встановлюється перед playback
   - Library configuration level
   
2. **Runtime Volume (User):**
   - UI control (slider/buttons)
   - Змінюється під час playback
   - Needs SwiftUI binding!
   
3. **Internal Mixers (System):**
   - PlayerA mixer (crossfade source)
   - PlayerB mixer (crossfade target)
   - Main mixer (global volume)

**Як працює (Dual-Mixer Coordination):**

**Option A: mainMixer only (RECOMMENDED для meditation):**
```
mainMixer.volume = globalVolume  // User control (0.0-1.0)
mixerA.volume = crossfadeVolA    // Crossfade logic (independent)
mixerB.volume = crossfadeVolB    // Crossfade logic (independent)

Result = globalVolume * (mixerA + mixerB)
```

**Приклад:**
- User sets volume to 80% → `mainMixer.volume = 0.8`
- Crossfade: mixerA (1.0→0.0), mixerB (0.0→1.0)
- Output: 80% of crossfade blend ✅

**SwiftUI Integration Challenge:**
```swift
// Problem:
await service.setVolume(0.8)  // Async method, can't bind!

// Solution (ViewModel wrapper):
@MainActor
class AudioPlayerViewModel: ObservableObject {
    @Published var volume: Float = 1.0
    
    func setVolume(_ value: Float) {
        volume = value
        Task { await service.setVolume(value) }
    }
}

// SwiftUI:
Slider(value: $viewModel.volume, in: 0...1)
```

**API:**
```swift
func setVolume(_ volume: Float) async  // 0.0-1.0
func getVolume() async -> Float
```

---

### 4.2 Overlay Volume
**Що робить:**  
Окремий volume control для overlay player.

**Незалежність:**
- Overlay має свій mixer
- НЕ залежить від main player volume
- Користувач регулює окремо

**Use Case:**
- Main track (meditation voice): 100%
- Overlay (rain sounds): 30%
- User hears: full voice + subtle rain

**API:**
```swift
func setOverlayVolume(_ volume: Float) async  // 0.0-1.0
```

---

## 5️⃣ Playlist & Queue Management

### 5.1 Playlist Loading
**Що робить:**  
Завантажує список треків для відтворення.

**Структура Meditation Session:**
```
Phase 1: Induction (5min)    - grounding, breath focus
Phase 2: Intentions (10min)  - visualization, affirmations  
Phase 3: Returning (5min)    - gradual return, closing
```

**Як працює:**
1. Developer передає масив URLs
2. PlaylistManager зберігає список
3. Встановлює currentIndex = 0
4. `currentTrackURL` вказує на перший трек

**API:**
```swift
func loadPlaylist(_ tracks: [URL]) async

// Usage:
await player.loadPlaylist([
    inductionURL,    // Phase 1
    intentionsURL,   // Phase 2
    returningURL     // Phase 3
])
```

---

### 5.2 Playlist Operations
**Що робить:**  
Маніпуляції зі списком треків.

**Available Operations:**

**Add Track:**
```swift
func addTrack(_ url: URL) async
// Додає в кінець списку
```

**Insert Track:**
```swift
func insertTrack(_ url: URL, at index: Int) async
// Вставляє на конкретну позицію
```

**Remove Track:**
```swift
func removeTrack(at index: Int) async throws
// Видаляє за індексом
```

**Move Track:**
```swift
func moveTrack(from: Int, to: Int) async throws
// Змінює порядок
```

**Replace Playlist:**
```swift
func replacePlaylist(_ tracks: [URL]) async throws
// Замінює весь список з crossfade до першого треку
// Використовує configuration.crossfadeDuration (не передається параметром!)
```

---

### 5.3 Navigation
**Що робить:**  
Переміщення по playlist.

**Methods:**

**Skip to Next:**
```swift
func skipToNext() async throws
// Crossfade до наступного треку
```

**Skip to Previous:**
```swift
func skipToPrevious() async throws
// Crossfade до попереднього
```

**Jump to Index:**
```swift
func jumpTo(index: Int) async throws
// Crossfade до конкретного треку
```

**Get Current:**
```swift
func getCurrentTrack() -> URL?
// Поточний трек URL
```

---

### 5.4 Queue System (Phase 3 - Verify!)
**Що робить:**  
Динамічна черга "play next" (як Spotify).

**Треба перевірити чи є в PlaylistManager:**

**Play Next:**
```swift
func playNext(_ url: URL) async
// Insert після поточного треку
// Use case: "Play this phase next"
```

**Get Upcoming:**
```swift
func getUpcomingQueue() async -> [URL]
// Показує наступні 2-3 треки
// For UI preview
```

**Meditation Context:**  
Можливо НЕ критично (structured sessions), але nice to have для flexibility.

---

## 6️⃣ Overlay Player (Killer Feature!)

### 6.1 Overlay Concept
**Що робить:**  
Незалежний audio layer для ambient sounds.

**Унікальність:**  
**ЖОДЕН інший плеєр не має цього!** Spotify/Apple Music = 1 audio stream. Хочеш rain + music → потрібно 2 apps!

**ProsperPlayer:**
- Main player: Meditation track (voice guide)
- Overlay player: Ambient layer (rain, ocean, nature)
- Mix seamlessly в одному додатку

**Use Cases:**

1. **Meditation:**
   - Main: Guided voice meditation
   - Overlay: Soft rain sounds
   - Result: Immersive experience

2. **Sleep:**
   - Main: Sleep story / podcast
   - Overlay: White noise / ocean waves
   - Result: Better sleep quality

3. **Focus:**
   - Main: Lofi music
   - Overlay: Cafe ambience
   - Result: Productive environment

---

### 6.2 Overlay Operations

**Start Overlay:**
```swift
func startOverlay(url: URL, configuration: OverlayConfiguration) async throws

struct OverlayConfiguration {
    let volume: Float                      // Initial volume (0.0-1.0)
    let loopMode: LoopMode                // .once, .count(3), .infinite
    let fadeInDuration: TimeInterval
    let fadeOutDuration: TimeInterval
    let delayBetweenLoops: TimeInterval   // ⭐ Pause between repeats
}
```

**Use Case 1: Continuous Rain (no delay)**
```swift
let config = OverlayConfiguration(
    volume: 0.3,
    loopMode: .infinite,
    fadeInDuration: 2.0,
    fadeOutDuration: 2.0,
    delayBetweenLoops: 0.0        // Instant repeat
)
await player.startOverlay(url: rainURL, configuration: config)

// Result: rain → rain → rain (seamless loop)
```

**Use Case 2: Ocean Waves with Pause** ⭐
```swift
let config = OverlayConfiguration(
    volume: 0.4,
    loopMode: .infinite,
    fadeInDuration: 1.0,
    fadeOutDuration: 2.0,
    delayBetweenLoops: 5.0        // ⭐ 5s silence between loops
)
await player.startOverlay(url: oceanWavesURL, configuration: config)

// Result: 
// wave sound (30s) → fade out (2s) → silence (5s) → fade in (1s) → wave sound (30s) → ...
```

**Use Case 3: Singing Bowl (sparse repeats)**
```swift
let config = OverlayConfiguration(
    volume: 0.6,
    loopMode: .count(5),           // Only 5 times
    fadeInDuration: 0.5,
    fadeOutDuration: 3.0,
    delayBetweenLoops: 30.0       // ⭐ 30s pause between bells
)
await player.startOverlay(url: singingBowlURL, configuration: config)

// Result:
// bell (10s) → fade out (3s) → silence (30s) → fade in (0.5s) → bell (10s) → ...
// Total: 5 bells with natural spacing
```

**Stop Overlay:**
```swift
func stopOverlay() async
// Fade out + stop (uses fadeOutDuration)
```

**Pause/Resume Overlay:**
```swift
func pauseOverlay() async
func resumeOverlay() async
```

**Replace Overlay:**
```swift
func replaceOverlay(url: URL) async throws
// Crossfade rain → ocean sounds
```

**Volume Control:**
```swift
func setOverlayVolume(_ volume: Float) async
// Adjust overlay independently
```

**Get State:**
```swift
func getOverlayState() async -> OverlayState

enum OverlayState {
    case idle
    case playing(url: URL, volume: Float)
    case paused(url: URL, position: TimeInterval)
}
```

---

### 6.3 Delay Between Loops - How It Works ⭐

**Що робить:**  
Додає nature-inspired паузу між повторами overlay.

**Навіщо для meditation:**  
- **Природність:** В природі звуки не постійні (хвиля → тиша → хвиля)
- **Не overwhelm:** Постійний ambient може бути занадто інтенсивним
- **Breathing space:** Пауза дає mind "rest" від стимуляції
- **Variety:** Динаміка тиші/звуку = більш engaging

**Timeline приклад (ocean waves):**
```
0:00  - Start overlay (fade in 1s)
0:01  - Ocean wave playing (30s)
0:31  - End wave (fade out 2s)
0:33  - SILENCE (5s delay) ← ⭐ delayBetweenLoops
0:38  - Next wave (fade in 1s)
0:39  - Ocean wave playing (30s)
...repeat...
```

**Технічна реалізація:**
1. Overlay file закінчується
2. Fade out (fadeOutDuration)
3. Timer чекає (delayBetweenLoops)
4. Fade in (fadeInDuration)
5. Overlay file починається знову

**Особливості:**
- Якщо `delayBetweenLoops = 0.0` → instant loop (як зараз)
- Якщо `> 0` → natural pause between loops
- Works з `.infinite` і `.count(N)` modes
- Delay НЕ включає fade durations (додається окремо)

---

### 6.4 Overlay Independence
**Критично:**

**Overlay НЕ залежить від main player:**
- Main track crossfade → overlay продовжує грати
- Playlist swap → overlay не зупиняється
- Main pause → overlay грає (unless `pauseAll()`)
- Separate audio graph, окремий mixer

**Global Control (обидва разом):**
```swift
func pauseAll() async     // Pause main + overlay
func resumeAll() async    // Resume main + overlay  
func stopAll() async      // Stop main + overlay
```

---

## 7️⃣ Background Playback & Remote Controls

### 7.1 Background Playback
**Що робить:**  
Audio грає коли app в background (Lock Screen, Home Screen).

**Налаштування:**
1. `Info.plist` має `UIBackgroundModes: ["audio"]`
2. Audio session category: `.playback`
3. Session активується перед playback

**Scenarios:**
- User locks phone → audio продовжує
- User switches to другий app → audio продовжує
- Sleep timer → audio грає всю ніч

**Обов'язково для meditation!**

---

### 7.2 Lock Screen Controls
**Що робить:**  
Управління з Lock Screen (iOS Control Center).

**Available Commands:**
- Play/Pause ▶️⏸️
- Skip Forward (+15s) ⏭️
- Skip Backward (-15s) ⏮️
- (Optional: Next/Previous track)

**Now Playing Info:**
- Track title
- Artist name  
- Artwork (cover image)
- Duration
- Current position
- Playback rate (1.0 = playing, 0.0 = paused)

**Implementation:**
```swift
// MPRemoteCommandCenter - registers handlers
// MPNowPlayingInfoCenter - updates display

// Updates every second for accurate progress
```

---

### 7.3 Interruption Handling
**Що робить:**  
Реагує на системні переривання (phone call, Siri, alarm).

**Interruption Types:**

**Begin (audio deactivated):**
- Phone call incoming
- Alarm triggered
- Siri activated
- FaceTime call

**Action:** Auto-pause, save position

**End (interruption finished):**
- Check `shouldResume` flag
- If YES → auto-resume playback
- If NO → залишити paused (user paused via Siri)

**Edge Case:**  
Siri pause має `shouldResume = false` → НЕ auto-resume (user explicitly paused voice)

---

### 7.4 Route Change Handling
**Що робить:**  
Реагує на зміну audio output (headphones plug/unplug).

**Scenarios:**

**Headphones Unplugged:**
```
User removes headphones
→ Pause immediately
→ Prevent sound from speaker (privacy!)
```

**Headphones Plugged In:**
```
User connects headphones
→ Continue playing (don't interrupt)
→ Or stay paused (if was paused)
```

**Bluetooth Connect/Disconnect:**
```
Similar to wired headphones
→ Pause on disconnect
→ Continue on connect
```

**Critical for meditation:**  
Auto-pause on unplug prevents embarrassing moments (meditation audio loud in public!)

---

## 8️⃣ Advanced Features

### 8.1 Audio Session Management
**Що робить:**  
Налаштовує AVAudioSession для правильної роботи.

**Configuration:**
- Category: `.playback` (для background)
- Mode: `.default` або `.spokenAudio` (для meditation voice)
- Options: `.mixWithOthers` (якщо потрібно)

**Session Lifecycle:**
1. Configure перед playback
2. Activate коли грає
3. Deactivate коли stop/finished
4. Handle interruptions
5. Handle route changes

---

### 8.2 Crossfade Auto-Adaptation (Phase 4)
**Що робить:**  
Автоматично адаптує crossfade для коротких треків.

**Problem:**
```
15s track + 10s crossfade = 67% overlap = каша звуку!
```

**Solution:**
```
Rule: Max 40% of track duration for crossfade

15s track + 10s config:
  maxCrossfade = 15s * 0.4 = 6s
  actualCrossfade = min(10s, 6s) = 6s ✅

60s track + 10s config:
  maxCrossfade = 60s * 0.4 = 24s
  actualCrossfade = min(10s, 24s) = 10s ✅
```

**Transparent:**  
User бачить що адаптація відбулася (через ValidationFeedback - майбутнє).

---

### 8.3 Pause Crossfade State (Phase 5)
**Що робить:**  
Зберігає прогрес crossfade при паузі.

**Problem:**
```
Crossfade at 30% progress
→ User pauses
→ Resume → crossfade resets to 0% (jarring!)
```

**Solution:**
```swift
struct CrossfadeState {
    let progress: Float              // 0.3 (30%)
    let totalDuration: TimeInterval  // 10.0s
    let playerAVolume: Float         // 0.7
    let playerBVolume: Float         // 0.3
    let remainingDuration: TimeInterval  // 7.0s left
}

pause() {
    if isCrossfading {
        savedState = CrossfadeState(current values)
    }
}

resume() {
    if let saved = savedState {
        continueCrossfade(from: saved)  // Resume from 30%!
    }
}
```

**Result:**  
Smooth pause/resume навіть під час crossfade.

---

### 8.4 State Machine
**Що робить:**  
Формальне управління станами playback (GameplayKit).

**States:**
- `Finished` - initial/stopped
- `Preparing` - loading file
- `Playing` - active playback
- `Paused` - temporarily stopped
- `FadingOut` - fade out before stop
- `Failed` - error occurred

**Valid Transitions:**
```
Finished → Preparing → Playing
Playing → Paused → Playing
Playing → FadingOut → Finished
Any → Failed
```

**Benefits:**
- Prevents invalid operations (play while playing)
- Clear state transitions
- Easier debugging

---

## 9️⃣ Error Handling & Validation

### 9.1 Error Types
```swift
enum AudioPlayerError: Error {
    case invalidState(message: String)
    case fileNotFound(url: URL)
    case invalidAudioFile(url: URL)
    case audioSessionError(underlying: Error)
    case engineError(underlying: Error)
    case crossfadeInProgress
    case noTrackLoaded
}
```

### 9.2 Validation (Phase 3+)
**ValidationFeedback System (future):**
```swift
struct ValidationFeedback {
    let warnings: [ValidationWarning]
    let adaptations: [Adaptation]
}

enum ValidationWarning {
    case crossfadeAdaptedForShortTrack(configured: TimeInterval, actual: TimeInterval)
    case totalFadeExceedsRecommended(total: TimeInterval, track: TimeInterval)
}

struct Adaptation {
    let parameter: String
    let configuredValue: TimeInterval
    let actualValue: TimeInterval
    let reason: String
}
```

**Usage:**
```swift
let feedback = await player.setConfiguration(config)
for adaptation in feedback.adaptations {
    print("Adapted: \(adaptation.parameter)")
    print("Reason: \(adaptation.reason)")
}
```

---

## 🎯 What Makes ProsperPlayer Unique

### ✅ Killer Features (NO ONE else has):

1. **Overlay Player** 🌟
   - Independent ambient layer
   - Rain + music in одному app
   - Separate volume/loop control
   - **Delay between loops** - natural pauses (хвиля → тиша → хвиля)

2. **Seamless Loop Crossfade** 🌟
   - NO gap on loop point
   - Sleep sounds infinite smooth
   - Other players have silence gap

3. **Dual-Player Architecture** ⚡
   - Sample-accurate crossfade
   - Zero glitches EVER
   - Professional DJ quality

4. **Long Crossfades** 🎵
   - 1-30s range (others: 0-12s)
   - Perfect for meditation (10-15s normal)
   - Customizable per use case

### ❌ Intentionally Missing (meditation focus):

1. **NO Shuffle** - structured sessions only
2. **NO Gapless mode** - crossfade better for meditation
3. **NO Equalizer** - simplicity for mindfulness
4. **NO Speed control** - natural pace important

---

## 📊 Complete API Summary

### Core Playback
```swift
func startPlaying(fadeDuration: TimeInterval = 0.0) async throws
func pause() async throws
func resume() async throws
func stop(fadeDuration: TimeInterval = 0.0) async
func skipForward(by interval: TimeInterval = 15.0) async
func skipBackward(by interval: TimeInterval = 15.0) async
func seekWithFade(to: TimeInterval, fadeDuration: TimeInterval = 0.1) async throws
```

### Configuration
```swift
func getConfiguration() -> PlayerConfiguration
func updateConfiguration(_ config: PlayerConfiguration) async
func setRepeatMode(_ mode: RepeatMode) async
func getRepeatMode() -> RepeatMode
func getRepeatCount() -> Int
```

### Volume
```swift
func setVolume(_ volume: Float) async
func getVolume() async -> Float
func setOverlayVolume(_ volume: Float) async
```

### Playlist
```swift
func loadPlaylist(_ tracks: [URL]) async
func addTrack(_ url: URL) async
func insertTrack(_ url: URL, at index: Int) async
func removeTrack(at index: Int) async throws
func moveTrack(from: Int, to: Int) async throws
func skipToNext() async throws
func skipToPrevious() async throws
func jumpTo(index: Int) async throws
func replacePlaylist(_ tracks: [URL], crossfadeDuration: TimeInterval = 5.0) async throws
func getPlaylist() async -> [URL]
```

### Overlay
```swift
func startOverlay(url: URL, configuration: OverlayConfiguration) async throws
func stopOverlay() async
func pauseOverlay() async
func resumeOverlay() async
func replaceOverlay(url: URL) async throws
func getOverlayState() async -> OverlayState
```

### Global Control
```swift
func pauseAll() async
func resumeAll() async
func stopAll() async
```

### Observation
```swift
func addObserver(_ observer: AudioPlayerObserver)
func removeAllObservers()

protocol AudioPlayerObserver {
    func player(_ player: AudioPlayerService, didChangeState state: PlayerState)
    func player(_ player: AudioPlayerService, didUpdatePosition position: PlaybackPosition)
    func player(_ player: AudioPlayerService, didUpdateCrossfadeProgress progress: CrossfadeProgress)
    func player(_ player: AudioPlayerService, didEncounterError error: AudioPlayerError)
}
```

---

## ✅ Same Page Checklist

**Перевір:**
- [x] Meditation focus зрозумілий (NOT Spotify clone)
- [x] NO shuffle потрібен (structured sessions)
- [x] Seamless crossfade критичний (breaks meditation)
- [x] Overlay player - killer feature (rain + music)
- [x] **Overlay delay between loops** - natural pauses ⭐
- [x] Volume dual-mixer architecture зрозумілий
- [x] seekWithFade prevents click (critical!)
- [x] Crossfade user configurable (5-15s range)
- [x] Queue nice to have (check PlaylistManager)

---

**Документ оновлено:** 2025-10-12  
**Версія:** v4.0 Complete Feature Overview  
**Статус:** ✅ Майже ідеальне розуміння функціоналу!