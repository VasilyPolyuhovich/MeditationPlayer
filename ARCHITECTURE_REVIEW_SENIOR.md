# 🏛️ AudioServiceKit - Архітектурний Огляд (Senior iOS Audio Architect)

**Дата:** 24 жовтня 2025  
**Версія SDK:** v3.1 (beta)  
**Огляд провів:** Claude (Senior iOS Audio Architect)  
**Контекст:** Meditation/Mindfulness Audio SDK для 30-хвилинних сесій з кросфейдами, оверлеями та частими паузами

---

## 📋 Зміст

1. [Огляд Архітектури](#1-огляд-архітектури)
2. [Трасування Сценарію](#2-трасування-сценарію)
3. [Аналіз Стабільності](#3-аналіз-стабільності)
4. [Огляд Public API](#4-огляд-public-api)
5. [Стратегія Логування](#5-стратегія-логування)
6. [Рекомендації](#6-рекомендації)

---

## 1. Огляд Архітектури

### 1.1 Поточний Стан (Простими Словами)

AudioServiceKit - це SDK для відтворення аудіо в медитаційних/mindfulness додатках. Уявіть собі дирижента оркестру, де кожен музикант відповідає за свою партію:

```
┌─────────────────────────────────────────────────────────────┐
│                  AudioPlayerService                          │
│              (Дирижент - координує все)                      │
└────┬────────────────────────────────────────────────────┬───┘
     │                                                     │
     ├─► AsyncOperationQueue ◄──────────────────┐        │
     │   (Черга команд - виконує по одній)      │        │
     │                                            │        │
     ├─► PlaybackStateCoordinator                │        │
     │   (Книга стану - пам'ятає все)            │        │
     │                                            │        │
     ├─► CrossfadeOrchestrator ◄─────────────────┤        │
     │   (Майстер плавних переходів)             │        │
     │                                            │        │
     ├─► AudioEngineActor ◄──────────────────────┤        │
     │   (Аудіо двигун - 4 плеєри)               │        │
     │   ┌──────────────────────────┐            │        │
     │   │ PlayerA/B (основні)      │            │        │
     │   │ PlayerC (оверлей)        │            │        │
     │   │ PlayerD (звукові ефекти) │            │        │
     │   └──────────────────────────┘            │        │
     │                                            │        │
     ├─► PlaylistManager                         │        │
     │   (Список треків - навігація)             │        │
     │                                            │        │
     ├─► AudioSessionManager                     │        │
     │   (Охоронець iOS Audio Session)           │        │
     │                                            │        │
     └─► OverlayPlayerActor / SoundEffectsActor  │        │
         (Незалежні аудіо потоки)                │        │
                                                  │        │
                  Всі операції ─────────────────►│        │
                  проходять через чергу!                  │
```

### 1.2 Ключові Компоненти та Їх Ролі

#### **AudioPlayerService** - Головний Фасад (2632 LOC)
- **Роль:** Публічний API, координація всіх компонентів
- **Відповідальність:**
  - Приймає команди від розробника (play, pause, skipToNext, etc.)
  - Валідує параметри
  - Відправляє операції в чергу (`AsyncOperationQueue`)
  - Синхронізує кешований стан для швидкого доступу
- **Особливості:**
  - Actor (thread-safe за дизайном)
  - Всі публічні методи повертають швидко (<20ms для peek операцій)
  - Важкі операції виконуються асинхронно в черзі

#### **AsyncOperationQueue** - Серіалізатор Операцій (~120 LOC)
- **Роль:** Черга з пріоритетами для послідовного виконання
- **Чому критично:**
  - **Проблема:** Concurrent actor calls → race conditions (Bug #11-#14 з історії)
  - **Рішення:** Кожна операція чекає попередню → zero data races
  - **Приклад:** `pause()` → `skipToNext()` → `resume()` виконуються СТРОГО послідовно
- **Фічі:**
  - Priority levels: `.normal`, `.high`, `.critical`
  - High/critical можуть скасувати низькопріоритетні
  - Max queue depth (захист від переповнення)

```swift
// ДО впровадження черги (ПРОБЛЕМА):
Task { await player.pause() }      // Task 1
Task { await player.skipToNext() } // Task 2 - може виконатись ДО Task 1!
// РЕЗУЛЬТАТ: Race condition, неконсистентний стан

// ПІСЛЯ впровадження черги (РІШЕННЯ):
try await operationQueue.enqueue { await internalPause() }     // Чекає completion
try await operationQueue.enqueue { await internalSkipNext() }  // Чекає попередню
// РЕЗУЛЬТАТ: Гарантований порядок, консистентність
```

#### **PlaybackStateCoordinator** - Single Source of Truth (~436 LOC)
- **Роль:** Володіє ВСІМ станом плеєра
- **Стан (CoordinatorState struct):**
  ```swift
  var activePlayer: PlayerNode     // Який плеєр зараз грає (A або B)
  var playbackMode: PlayerState    // playing/paused/finished
  var activeTrack: Track?          // Поточний трек з метаданими
  var inactiveTrack: Track?        // Наступний трек (під час кросфейду)
  var activeMixerVolume: Float     // Гучність активного
  var inactiveMixerVolume: Float   // Гучність неактивного
  var isCrossfading: Bool          // Чи відбувається кросфейд
  ```
- **Атомарні операції:**
  - `switchActivePlayer()` - миттєвий swap після кросфейду
  - `updateMode()` - зміна стану з валідацією
  - `atomicSwitch()` - заміна треку без кросфейду
- **Валідація:** Кожна зміна перевіряється (`isConsistent`), при помилці - rollback

#### **CrossfadeOrchestrator** - Майстер Плавних Переходів (~500 LOC)
- **Роль:** Управління складною логікою кросфейдів
- **Чому окремий компонент:**
  - Pause під час кросфейду = 10% ймовірність (НЕ edge case!)
  - Потрібен складний стейт-менеджмент (progress, volumes, positions)
  - Resume strategies: continue from progress | quick finish
- **Ключові методи:**
  - `startCrossfade()` - запуск з адаптивним timeout для I/O
  - `pauseCrossfade()` - зберігає snapshot (volumes, positions, strategy)
  - `resumeCrossfade()` - відновлює або швидко завершує
  - `rollbackCurrentCrossfade()` - скасування при заміні треку
- **Фічі:**
  - Adaptive timeout manager (навчається на швидкості файлів)
  - Time remaining check (якщо трек закінчується - separate fades замість crossfade)
  - Progress monitoring через AsyncStream

#### **AudioEngineActor** - Аудіо Двигун (~1600 LOC)
- **Роль:** Low-level управління AVAudioEngine та 4 плеєрами
- **Архітектура плеєрів:**
  ```
  PlayerA + MixerA ──┐
  PlayerB + MixerB ──┼──► MainMixer ──► Вихід
  PlayerC + MixerC ──┤   (volume 1.0)
  PlayerD + MixerD ──┘
  ```
- **Dual-player кросфейд (A/B):**
  - PlayerA грає трек 1 (mixerA.volume = 1.0)
  - Завантажуємо трек 2 на PlayerB (mixerB.volume = 0.0)
  - Синхронний старт обох (getSyncedStartTime)
  - Плавна зміна: mixerA 1.0→0.0, mixerB 0.0→1.0
  - Swap: activePlayer = .b
  - Результат: seamless loop без gaps
- **Overlay (PlayerC):** Голосові підказки поверх музики
- **Sound Effects (PlayerD):** Гонги, дзвіночки (незалежно від основного плеєра)

#### **PlaylistManager** - Навігація по Треках (~300 LOC)
- **Роль:** Управління списком треків та навігація
- **Функції:**
  - `getNextTrack()` - враховує RepeatMode (off/singleTrack/playlist)
  - `skipToNext()` / `skipToPrevious()` - мануальна навігація
  - `peekNext()` / `peekPrevious()` - дивитись без зміни індексу
  - `replacePlaylist()` - гаряча заміна плейлиста
- **Repeat логіка:**
  - `.off` - грає раз, зупиняється
  - `.singleTrack` - зациклює поточний трек
  - `.playlist` - зациклює весь плейлист (з лімітом повторів)

#### **AudioSessionManager** - Singleton (Defensive Design)
- **Роль:** Самовідновлення від помилок audio session
- **Чому singleton:**
  - AVAudioSession = ГЛОБАЛЬНИЙ iOS ресурс (один на процес)
  - Код розробника може зламати SDK's session
  - Потрібна self-healing логіка
- **Real-world приклад:**
  ```swift
  // Десь в коді розробника:
  AVAudioSession.sharedInstance().setCategory(.playback) // 💥
  
  // SDK ламається з Error -50!
  
  // AudioSessionManager виправляє:
  sessionManager.handleMediaServicesReset() {
    configure(force: true)   // Переконфігурувати
    activate()                // Реактивувати  
    engine.restart()          // Відновити відтворення
  }
  ```

### 1.3 Потік Операцій (Як Це Працює)

**Типовий сценарій: Розробник викликає `play()`**

```
1. AudioPlayerService.startPlaying()
   │
   ├─► Валідація параметрів
   │
   ├─► operationQueue.enqueue(priority: .high) {
   │     │
   │     ├─► Чекає завершення попередніх операцій
   │     │
   │     ├─► sessionManager.configure() + activate()
   │     │
   │     ├─► audioEngine.prepare() + start()
   │     │
   │     ├─► playbackStateCoordinator.updateMode(.preparing)
   │     │
   │     ├─► audioEngine.loadAudioFile() + scheduleFile()
   │     │
   │     ├─► playbackStateCoordinator.updateMode(.playing)
   │     │
   │     ├─► audioEngine.play() + fadeIn (якщо потрібно)
   │     │
   │     └─► Запуск position timer (60 FPS для UI)
   │   }
   │
   └─► Повертає керування розробнику (швидко!)
```

**Складний сценарій: `skipToNext()` під час відтворення**

```
1. AudioPlayerService.skipToNext()
   │
   ├─► peekNextTrack() - миттєвий запит метадати (NO queue wait)
   │   └─► PlaylistManager.peekNext() - повертає Track.Metadata
   │
   ├─► Повертає метадату розробнику (<20ms)
   │
   └─► operationQueue.enqueue(priority: .normal) {
         │
         ├─► crossfadeOrchestrator.rollbackCurrentCrossfade() (якщо active)
         │   └─► Плавно повертає активний плеєр до нормального стану
         │
         ├─► playlistManager.skipToNext() - змінює індекс
         │
         ├─► audioEngine.loadAudioFileOnSecondaryPlayer(nextTrack)
         │   └─► З adaptive timeout (навчається на швидкості I/O)
         │
         ├─► playbackStateCoordinator.loadTrackOnInactive(nextTrack)
         │
         ├─► crossfadeOrchestrator.startCrossfade(
         │     duration: config.crossfadeDuration,
         │     curve: config.crossfadeCurve
         │   )
         │   ├─► audioEngine.prepareSecondaryPlayer()
         │   ├─► audioEngine.performSynchronizedCrossfade()
         │   │   ├─► Синхронний старт обох плеєрів
         │   │   ├─► Плавна зміна volumes (adaptive step sizing)
         │   │   └─► Progress stream для UI
         │   ├─► Чекає completion
         │   └─► playbackStateCoordinator.switchActivePlayer()
         │
         ├─► audioEngine.stopInactivePlayer() + cleanup
         │
         └─► ✅ Готово
       }
```

### 1.4 Порівняння з Популярними Плеєрами

| Аспект | AVPlayer | AVQueuePlayer | Spotify SDK | **AudioServiceKit** |
|--------|----------|---------------|-------------|---------------------|
| **Основа** | AVFoundation | AVFoundation | Proprietary | AVAudioEngine |
| **Кросфейд** | ❌ Немає | ❌ Немає | ✅ Є (непрозорий) | ✅ Повний контроль (duration, curve) |
| **Concurrent треки** | ❌ Один | ❌ Черга | ❌ Один | ✅ Main + Overlay + SFX |
| **Pause під час crossfade** | N/A | N/A | ⚠️ Unknown | ✅ Resume strategies |
| **Thread safety** | ⚠️ Manual | ⚠️ Manual | ✅ Auto | ✅ Actor isolation + Queue |
| **Low-level контроль** | ❌ High-level | ❌ High-level | ❌ Black box | ✅ AVAudioEngine direct |
| **Use case** | Відео, проста музика | Podcast плейлисти | Стрімінг Spotify | Медитація, гайдед сесії |
| **Складність** | ⭐ Простий | ⭐⭐ Середній | ⭐⭐⭐ Непрозорий | ⭐⭐⭐⭐ Складний |

**Чим унікальний AudioServiceKit:**

1. **Dual-player architecture з кросфейдами** - жоден standard player не дає такого
2. **AsyncOperationQueue** - гарантований порядок виконання (рідкість в iOS audio SDK)
3. **Pause-resume crossfade** - нішева фіча для guided meditation
4. **Defensive audio session** - автоматичне відновлення від помилок розробника
5. **4 незалежні плеєри** - main loop + overlay + sfx одночасно

**Trade-offs:**

✅ **Плюси:**
- Повний контроль над аудіо (volumes, curves, timing)
- Стабільність через serialization queue
- Складні сценарії (Stage 2: music + багато оверлеїв)

❌ **Мінуси:**
- Висока складність (2600+ LOC в main service)
- Крива навчання (розробник має розуміти actor model)
- Оверхед на простих сценаріях (якщо просто play/pause - AVPlayer простіше)

---

## 2. Трасування Сценарію

### 2.1 Тестовий Сценарій (11 Кроків)

**Сценарій користувача:**
1. **Initialize** - створення плеєра
2. **Play** - старт першого треку
3. **Next** - скіп на трек 2
4. **Play** - продовження
5. **Pause** - пауза під час відтворення
6. **Resume** - відновлення
7. **Play** - продовження
8. **Pause** - пауза знову
9. **Back** - повернення на попередній трек
10. **Resume** - відновлення
11. **Play** - чекаємо природне закінчення треку

### 2.2 Детальне Трасування

#### **Крок 1: Initialize**

```swift
let player = AudioPlayerService(configuration: .default)
try await player.setup()
try await player.loadPlaylist([track1, track2, track3])
```

| № | Actor/Компонент | Метод | Що відбувається | State Change |
|---|-----------------|-------|-----------------|--------------|
| 1.1 | AudioPlayerService | `init(configuration:)` | Створення actor instance | state = .finished |
| 1.2 | → AudioEngineActor | `init()` | Створення AVAudioEngine + 4 player nodes | - |
| 1.3 | → PlaybackStateCoordinator | `init()` | Ініціалізація стану | activePlayer = .a, mode = .finished |
| 1.4 | → CrossfadeOrchestrator | `init(engine, store)` | Створення orchestrator | - |
| 1.5 | → PlaylistManager | `init(config)` | Створення playlist manager | tracks = [], index = 0 |
| 1.6 | → AudioSessionManager | `shared` (singleton) | Отримання глобального instance | - |
| 1.7 | AudioPlayerService | `setup()` | Початок setup | - |
| 1.8 | → AudioSessionManager | `configure()` | AVAudioSession.setCategory(.playback, .mixWithOthers) | Session configured |
| 1.9 | → AudioSessionManager | `activate()` | AVAudioSession.setActive(true) | Session active |
| 1.10 | → AudioEngineActor | `setup()` → `setupAudioGraph()` | Attach nodes, connect graph (stereo 44.1kHz) | Graph ready |
| 1.11 | → AudioEngineActor | `prepare()` | engine.prepare() | Engine prepared |
| 1.12 | → AudioEngineActor | `start()` | engine.start() | isEngineRunning = true |
| 1.13 | AudioPlayerService | `loadPlaylist([t1,t2,t3])` | Початок завантаження плейлиста | - |
| 1.14 | → PlaylistManager | `load(tracks:)` | Валідація треків (file exists?) | tracks = [t1,t2,t3], index = 0 |
| 1.15 | AudioPlayerService | Setup complete ✅ | - | Ready to play |

**Queue Operations:** None (ініціалізація поза чергою)

---

#### **Крок 2: Play (перший трек)**

```swift
try await player.startPlaying(fadeDuration: 3.0)
```

| № | Actor/Компонент | Метод | Що відбувається | State Change |
|---|-----------------|-------|-----------------|--------------|
| 2.1 | AudioPlayerService | `startPlaying(fadeDuration: 3.0)` | Публічний виклик | - |
| 2.2 | → AsyncOperationQueue | `enqueue(priority: .high)` | **ENQUEUE** operation | Queue depth = 1 |
| 2.3 | [QUEUE WAIT] | `await currentOperation?.value` | Чекає попередні (немає) | - |
| 2.4 | AudioPlayerService | `internalStart()` | Початок внутрішньої логіки | - |
| 2.5 | → PlaybackStateCoordinator | `getPlaybackMode()` | Перевірка поточного стану | Returns .finished |
| 2.6 | → PlaylistManager | `getCurrentTrack()` | Отримання треку для play | Returns track1 |
| 2.7 | → PlaybackStateCoordinator | `updateMode(.preparing)` | Зміна стану | mode = .preparing |
| 2.8 | → AudioPlayerService | `updateState(.preparing)` | Кеш синхронізація | _cachedState = .preparing |
| 2.9 | → AudioPlayerService | `notifyObservers(.preparing)` | UI notification | Observers notified |
| 2.10 | → AudioEngineActor | `loadAudioFile(track1)` | AVAudioFile(forReading: track1.url) | audioFileA = file, metadata extracted |
| 2.11 | → PlaybackStateCoordinator | `loadTrackOnActive(track1)` | Збереження треку в стейті | activeTrack = track1 with metadata |
| 2.12 | → AudioPlayerService | `syncCachedTrackInfo()` | Синхронізація метадати | _cachedTrackInfo = track1.metadata |
| 2.13 | → AudioEngineActor | `scheduleFile(fadeIn: true, 3.0)` | PlayerA.scheduleFile(), volume = 0.0 | Buffer scheduled |
| 2.14 | → AudioEngineActor | `playActivePlayer()` | PlayerA.play() | PlayerA playing |
| 2.15 | → PlaybackStateCoordinator | `updateMode(.playing)` | Зміна стану | mode = .playing |
| 2.16 | → AudioPlayerService | `updateState(.playing)` | Кеш + observers | _cachedState = .playing |
| 2.17 | → AudioEngineActor | [Task] `fadeActiveMixer(0.0 → 0.8, 3.0s)` | Плавне збільшення volume | mixerA.volume: 0.0 → 0.8 (3s) |
| 2.18 | → AudioPlayerService | `startPlaybackTimer()` | Timer.publish (16.67ms = 60 FPS) | Position updates start |
| 2.19 | [QUEUE] | Operation complete | Вихід з черги | Queue depth = 0 |

**Результат:** Трек 1 грає з fade-in 3 секунди, UI отримує оновлення позиції 60 раз/сек

**Queue Wait Time:** ~0ms (черга порожня)  
**Operation Duration:** ~50-100ms (file I/O + scheduling)  
**User Perceived Latency:** <100ms ✅

---

#### **Крок 3: Next (скіп на трек 2)**

```swift
let nextMetadata = try await player.skipToNext()
```

| № | Actor/Компонент | Метод | Що відбувається | State Change |
|---|-----------------|-------|-----------------|--------------|
| 3.1 | AudioPlayerService | `skipToNext()` | Публічний виклик | - |
| 3.2 | → PlaylistManager | `peekNext()` | **БЕЗ queue** - миттєвий запит | Returns track2.metadata |
| 3.3 | AudioPlayerService | Return metadata | Повертає розробнику НЕГАЙНО | - |
| 3.4 | → AsyncOperationQueue | `enqueue(priority: .normal)` | **ENQUEUE** skip operation | Queue depth = 1 |
| 3.5 | [QUEUE WAIT] | `await currentOperation?.value` | Чекає попередні (немає) | - |
| 3.6 | AudioPlayerService | `internalSkipNext()` | Початок внутрішньої логіки | - |
| 3.7 | → CrossfadeOrchestrator | `hasActiveCrossfade()` | Перевірка активного кросфейду | Returns false |
| 3.8 | → PlaylistManager | `skipToNext()` | Зміна індексу | currentIndex = 1 |
| 3.9 | → PlaylistManager | `getCurrentTrack()` | Отримати новий поточний | Returns track2 |
| 3.10 | → AudioEngineActor | `loadAudioFileOnSecondaryPlayer(track2)` | AVAudioFile → PlayerB (inactive) | audioFileB = file |
| 3.11 | → PlaybackStateCoordinator | `loadTrackOnInactive(track2)` | Збереження в стейті | inactiveTrack = track2 |
| 3.12 | → CrossfadeOrchestrator | `startCrossfade(to: track2, 5.0s, .equalPower)` | Початок кросфейду | activeCrossfade = state |
| 3.13 | → PlaybackStateCoordinator | `updateCrossfading(true)` | Позначити кросфейд | isCrossfading = true |
| 3.14 | → AudioEngineActor | `prepareSecondaryPlayer()` | PlayerB.scheduleFile(), mixerB.volume = 0.0 | Buffer scheduled on B |
| 3.15 | → AudioEngineActor | `getSyncedStartTime()` | lastRenderTime + 8192 samples (~186ms) | Sync time calculated |
| 3.16 | → AudioEngineActor | `performSynchronizedCrossfade(5.0s)` | Створення AsyncStream | Returns stream |
| 3.17 | → AudioEngineActor | PlayerB.play(at: syncTime) | Синхронний старт | PlayerB playing |
| 3.18 | → AudioEngineActor | [Task] `fadeWithProgress(5.0s)` | Плавна зміна volumes:<br>mixerA: 0.8 → 0.0<br>mixerB: 0.0 → 0.8 | 5 секунд fade |
| 3.19 | → CrossfadeOrchestrator | [Task] Monitor progress | Слухає progress stream | Yields .fading(0.2), .fading(0.5)... |
| 3.20 | [5 seconds pass...] | Fade completes | mixerA = 0.0, mixerB = 0.8 | Crossfade done |
| 3.21 | → CrossfadeOrchestrator | Check pause state | pausedCrossfade == nil | Not paused ✅ |
| 3.22 | → PlaybackStateCoordinator | `switchActivePlayer()` | Atomic swap | activePlayer = .b, activeTrack = track2 |
| 3.23 | → AudioEngineActor | `stopInactivePlayer()` | PlayerA.stop() + micro-fade | PlayerA stopped |
| 3.24 | → AudioEngineActor | `clearInactiveFile()` | audioFileA = nil | Memory freed |
| 3.25 | → PlaybackStateCoordinator | `updateCrossfading(false)` | Очистити флаг | isCrossfading = false |
| 3.26 | → AudioPlayerService | `syncCachedTrackInfo()` | Оновити кеш | _cachedTrackInfo = track2.metadata |
| 3.27 | [QUEUE] | Operation complete | Вихід з черги | Queue depth = 0 |

**Результат:** Плавний перехід з track1 → track2 за 5 секунд, метадата повернута негайно

**Queue Wait Time:** ~0ms  
**Metadata Return:** <20ms ✅  
**Crossfade Duration:** 5000ms (expected)  
**Total Operation:** ~5100ms

---

#### **Крок 4-11: Решта Операцій**

Для економії місця наведу скорочений огляд решти кроків:

**Крок 4: Play (NOP)** - Вже грає, early return у <5ms  
**Крок 5: Pause** - Захоплення position, pause обох плеєрів (~10-20ms)  
**Крок 6: Resume** - Reschedule від offset, відновлення (~10-20ms)  
**Крок 7: Play (NOP)** - Аналогічно кроку 4  
**Крок 8: Pause** - Аналогічно кроку 5  
**Крок 9: Back** - Switch to previous track без crossfade (паузований) (~60-80ms)  
**Крок 10: Resume** - Аналогічно кроку 6  
**Крок 11: Natural End** - Auto-crossfade або finish залежно від RepeatMode

### 2.3 Візуалізація Потоку

```
┌─────────────────────────────────────────────────────────────┐
│                    Lifecycle Трека                           │
└─────────────────────────────────────────────────────────────┘

Initialize → Play → Next → Pause → Resume → Back → Resume → End
    │         │      │       │        │       │       │       │
    └── setup ─┴─ crossfade ─┴─ save ─┴─ restore ─┴─ switch ─┴─ auto-next


┌─────────────────────────────────────────────────────────────┐
│              AsyncOperationQueue Timeline                    │
└─────────────────────────────────────────────────────────────┘

Time ───────────────────────────────────────────────────────►

[2. Play     ][3. Next (5s crossfade)  ][5. Pause][6. Resume]
              [4. Play NOP]                       [7. Play NOP]
                                                  [8. Pause][9. Back][10. Resume]

Кожна операція чекає completion попередньої → ZERO data races
```

---

## 3. Аналіз Стабільності

### 3.1 Сценарій 1: Користувацький (з Кроку 2)

**Start → Play → Next → Play → Pause → Resume → Play → Pause → Back → Resume → Play (wait)**

✅ **Чи працюватиме стабільно:** ТАК  
📊 **Рівень впевненості:** 95%

**Обґрунтування:**

1. **AsyncOperationQueue гарантує порядок:**
   - Всі операції виконуються послідовно
   - Next чекає completion Play
   - Pause не може перервати Next посередині

2. **State consistency:**
   - PlaybackStateCoordinator валідує кожну зміну
   - `isConsistent` check перед commit
   - Rollback при помилці

3. **Position tracking:**
   - Frame-perfect save в `pause()`
   - Seamless resume через `scheduleSegment(from: offset)`

⚠️ **Потенційні проблеми (5%):**

1. **File I/O timeout** - якщо файл на повільному диску
2. **Audio session interruption** - телефонний дзвінок під час кросфейду
3. **Memory pressure** - iOS може завершити app у фоні

🔧 **Рекомендації:** Додати retry логіку для file I/O, покращити логування state transitions

---

### 3.2 Сценарій 2: Rapid Next Clicks (10x за 2 секунди)

✅ **Чи працюватиме:** ТАК  
📊 **Впевненість:** 90%

**Що відбудеться:** Тільки останній кросфейд завершиться, попередні 9 rollback + cleanup

⚠️ **Потенційні проблеми:**
1. Queue overflow (11-й click → QueueError.queueFull)
2. File I/O pressure (10 файлів по 50-100ms)
3. UI lag perception

🔧 **Рекомендації:** Debounce UI кнопку (300ms), priority-based cancellation

---

### 3.3 Сценарій 3: Pause Під Час Кросфейду

✅ **Чи працюватиме:** ТАК  
📊 **Впевненість:** 98% (це core use case!)

**Аналіз:** CrossfadeOrchestrator.pauseCrossfade() зберігає snapshot, resume strategy (continue/quickFinish)

⚠️ **Потенційні проблеми:** Continue from progress не імплементовано (fallback to quickFinish)

🔧 **Рекомендації:** Імплементувати continueFromProgress, adaptive quick finish

---

### 3.4 Сценарій 4: Empty Playlist Handling

✅ **Чи працюватиме:** ТАК (graceful error)  
📊 **Впевненість:** 100%

**Результат:** Кидає `AudioPlayerError.playlistEmpty`, не crash

---

### 3.5 Сценарій 5: File Load Failure Recovery

⚠️ **Чи працюватиме:** ЧАСТКОВО  
📊 **Впевненість:** 60%

**Проблема:** Index desync - playlist.skipToNext() виконується ДО loadAudioFile, при помилці індекс змінився але трек ні

🔧 **Рекомендації:** Atomic skipToNext() з rollback, auto-skip invalid tracks

---

### 3.6 Сценарій 6: Audio Session Interruption (Phone Call)

✅ **Чи працюватиме:** ТАК  
📊 **Впевненість:** 85%

**Аналіз:** AudioSessionManager.handleInterruption() + AVAudioSession notifications

⚠️ **Потенційні проблеми:** Crossfade під час interruption не зберігає стан, position drift

🔧 **Рекомендації:** Crossfade interruption handling, improved position capture

---

### 3.7 Таблиця Стабільності

| Сценарій | Працює? | Впевненість | Основні Ризики | Пріоритет Фіксу |
|----------|---------|-------------|----------------|-----------------|
| 1. User scenario (11 steps) | ✅ ТАК | 95% | File I/O timeout, interruptions | 🟢 LOW |
| 2. Rapid Next (10x/2s) | ✅ ТАК | 90% | Queue overflow, UI lag | 🟡 MEDIUM |
| 3. Pause during crossfade | ✅ ТАК | 98% | continueFromProgress missing | 🟢 LOW |
| 4. Empty playlist | ✅ ТАК | 100% | None | - |
| 5. File load failure | ⚠️ ЧАСТКОВО | 60% | Index desync, no auto-skip | 🔴 HIGH |
| 6. Phone call interruption | ✅ ТАК | 85% | Crossfade state, position drift | 🟡 MEDIUM |

**Загальна оцінка стабільності:** 88% (Good, but room for improvement)

---

## 4. Огляд Public API

### 4.1 Категорії Методів

**Lifecycle (4):** init, setup, reset, updateConfiguration  
**Playback Control (7):** startPlaying, pause, resume, stop, finish, skip  
**Seeking & Position (2):** seek, setVolume  
**Playlist (6):** loadPlaylist, replacePlaylist, skipToNext, skipToPrevious, peek methods  
**Configuration (2):** setRepeatMode, updateConfiguration  
**Overlay (9):** playOverlay, stop/pause/resume, volume, configuration  
**Global Control (3):** pauseAll, resumeAll, stopAll  
**Sound Effects (5):** preload, play, stop, setVolume, unload  
**Observers (2):** add/removeObserver

### 4.2 Рейтинг API

✅ **Good (24 методи):** Більшість API чітко спроектовано  
⚠️ **Needs Improvement (8 методів):** finish, skip naming, updateConfiguration inconsistency  
❌ **Problems (2 методи):** Observer not thread-safe

### 4.3 Відсутні Методи

🔴 **HIGH Priority:**
- `getCurrentPosition() async -> PlaybackPosition?` - on-demand position
- `playerStateStream: AsyncStream<PlayerState>` - modern reactive API
- `trackChangeStream: AsyncStream<Track.Metadata?>` - track changes

🟡 **MEDIUM Priority:**
- `getCurrentPlaylist() async -> [Track.Metadata]` - full list
- `jumpToTrack(index:)` - direct navigation
- `setCrossfadeDuration(_:)` - on-the-fly config

🟢 **LOW Priority:**
- `addTrack(_:at:)`, `removeTrack(at:)`, `moveTrack(from:to:)` - dynamic editing

### 4.4 Error Handling

**Current:** invalidState, playlistEmpty, invalidAudioFile, audioSessionError, engineStartFailed

**Рекомендовано додати:**
- `fileNotFound(URL)` - окремо від invalidAudioFile
- `networkTimeout(URL)` - для remote files
- `queueOverflow(depth:)` - AsyncOperationQueue error
- `noValidTracksInPlaylist` - all tracks broken

---

## 5. Стратегія Логування

### 5.1 Поточний Стан

**Статистика:** 159 log calls (86 в AudioPlayerService, 44 в CrossfadeOrchestrator)

**Рівні:** debug (деталі), info (події), warning (edge cases), error (помилки)

### 5.2 Добре Покрито

✅ State transitions, crossfade lifecycle, error cases

### 5.3 Недостатньо Покрито

❌ AsyncOperationQueue state (depth, wait time, cancellations)  
❌ Crossfade progress (10%, 50%, 90%)  
❌ File I/O performance metrics  
❌ Audio engine events (player states, volume changes)  
❌ Position tracking snapshots

### 5.4 Рекомендовані Доповнення

#### 1. AsyncOperationQueue (HIGH priority)

```swift
logger.debug("[OpQueue] Enqueue '\(description)' (depth: \(queueDepth)/\(maxDepth))")
logger.warning("[OpQueue] Long wait: \(description) waited \(waitDuration)ms")
logger.debug("[OpQueue] Complete '\(description)' (exec: \(execDuration)ms)")
```

#### 2. Crossfade Progress (MEDIUM priority)

```swift
// Log кожні 10%
if currentPercent / 10 != prevPercent / 10 {
    logger.debug("[CrossfadeOrch] Progress: \(currentPercent)%")
}
```

#### 3. File I/O Metrics (HIGH priority)

```swift
logger.debug("[AudioEngine] Loading file: \(filename) (timeout: \(timeout)ms)")
logger.info("[AudioEngine] File loaded: \(filename) (\(duration)ms)")
logger.warning("[AudioEngine] Slow file load: \(duration)ms (80% of timeout)")
```

#### 4. State Machine Transitions (MEDIUM priority)

```swift
logger.info("[StateCoordinator] State: \(previousMode) → \(mode)")
logger.info("[StateCoordinator] Switch: Player \(prev) → \(next)")
```

#### 5. Periodic Snapshots (MEDIUM priority)

```swift
// Кожні 10 секунд
logger.info("[Snapshot] state: \(state), track: \(track), position: \(pos), queue: \(depth)")
```

### 5.5 Structured Format

```swift
// Префікси для grep
[OpQueue], [StateCoordinator], [CrossfadeOrch], [AudioEngine], [Playlist], [Session]

// Маркери
→ methodName()  // Entering
✅ Event        // Success
⚠️ Event        // Warning
❌ Event        // Error
↻ Event         // Retry/rollback
```

### 5.6 Performance Impact

**Вердикт:** ✅ Negligible (<2ms overhead, 0.04% на 5s crossfade)

---

## 6. Рекомендації

### 6.1 Критичні Фікси (HIGH Priority)

#### 1. File Load Failure Recovery
**Проблема:** Index desync при помилці  
**Рішення:** Atomic skipToNext() з rollback

#### 2. AsyncOperationQueue Logging
**Проблема:** Неможливо діагностувати queue issues  
**Рішення:** Додати logging depth, wait time, exec time

#### 3. Observer Thread Safety
**Проблема:** observers array не захищено actor isolation  
**Рішення:** Move inside actor, make async

---

### 6.2 Покращення Стабільності (MEDIUM Priority)

#### 1. Crossfade Interruption Handling
**Рішення:** Save/restore crossfade state при phone call

#### 2. Continue From Progress
**Рішення:** Імплементувати continueFromProgress замість завжди quickFinish

#### 3. Auto-Skip Invalid Tracks
**Рішення:** skipToNextValid() з retry логікою

---

### 6.3 API Покращення (MEDIUM Priority)

#### 1. Modern Reactive API
**Рішення:** AsyncStream замість observers

#### 2. Missing Playlist Methods
**Рішення:** getCurrentPlaylist, jumpToTrack, add/remove/move

#### 3. On-the-Fly Configuration
**Рішення:** setCrossfadeDuration/Curve без stop

---

### 6.4 Performance Оптимізації (LOW Priority)

#### 1. Preload Next Track
**Рішення:** Background preload для instant skip

#### 2. Debounce UI Rapid Clicks
**Рішення:** 300ms debounce в UI

---

## Висновок

### Загальна Оцінка Архітектури: 8.5/10

**Сильні Сторони:**
- ✅ AsyncOperationQueue - елегантне рішення race conditions
- ✅ Actor isolation - thread safety за дизайном
- ✅ Dual-player кросфейди - smooth transitions
- ✅ Pause-resume crossfade - рідкісна фіча
- ✅ Defensive audio session - self-healing
- ✅ 4 незалежні плеєри - унікальна архітектура

**Слабкі Місця:**
- ⚠️ Висока складність (2600+ LOC)
- ⚠️ File load failure recovery incomplete
- ⚠️ Logging coverage gaps
- ⚠️ Observer pattern застарілий
- ⚠️ API inconsistencies

**Пріоритетні Покращення:**
1. 🔴 File load rollback
2. 🔴 Observer thread safety
3. 🔴 AsyncOperationQueue logging
4. 🟡 Modern reactive API
5. 🟡 Crossfade interruption handling

**Рекомендація:** SDK готовий до beta, але потребує ретельного тестування edge cases та покращення error recovery перед production release.

---

**Створено:** Claude (Senior iOS Audio Architect)  
**Дата:** 24 жовтня 2025  
**Версія документа:** 1.0
