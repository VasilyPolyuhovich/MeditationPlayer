# Аналіз існуючого коду відносно вимог Crossfade/Fade

**Дата:** 2025-10-24  
**Мета:** Зрозуміти що вже реалізовано vs що потрібно додати/виправити

---

## ✅ ЩО ВЖЕ РЕАЛІЗОВАНО

### 1. CrossfadeOrchestrator (Sources/AudioServiceKit/Internal/CrossfadeOrchestrator.swift)

#### Структури даних (ХОРОША АРХІТЕКТУРА!):

**ActiveCrossfadeState** (private struct, line 329):
```swift
- operation: CrossfadeOperation
- startTime: Date
- duration: TimeInterval
- curve: FadeCurve
- fromTrack: Track
- toTrack: Track
- progress: Float

computed:
- elapsed: TimeInterval (час від початку)
- remaining: TimeInterval (час що залишився)
```

**PausedCrossfadeState** (private struct, line 348):
```swift
- progress: Float
- originalDuration: TimeInterval
- curve: FadeCurve
- activeMixerVolume: Float      // ✅ SNAPSHOT!
- inactiveMixerVolume: Float    // ✅ SNAPSHOT!
- activePlayerPosition: TimeInterval   // ✅ SNAPSHOT!
- inactivePlayerPosition: TimeInterval // ✅ SNAPSHOT!
- activePlayer: PlayerNode      // ✅ SNAPSHOT!
- resumeStrategy: ResumeStrategy
- operation: CrossfadeOperation

computed:
- remainingDuration: TimeInterval
```

**ResumeStrategy** (enum, line 365):
```swift
- continueFromProgress  // <50% progress
- quickFinish          // >=50% progress
```

#### Методи (що працює):

1. **startCrossfade()** ✅
   - Rollback існуючого crossfade
   - Валідація активного треку
   - Створення ActiveCrossfadeState
   - Завантаження треку на inactive player
   - Запуск crossfade
   - Progress monitoring

2. **pauseCrossfade()** ✅
   - Зберігає стан в PausedCrossfadeState (volumes, positions, activePlayer)
   - Визначає ResumeStrategy (continueFromProgress | quickFinish)
   - Cancel progress task
   - Повертає PausedCrossfadeSnapshot

3. **resumeCrossfade()** ⚠️ (частково)
   - continueFromProgress: TODO (не реалізовано)
   - quickFinish: працює (1s швидке завершення)

4. **rollbackCurrentCrossfade()** ⚠️
   - Cancel progress task
   - Викликає audioEngine.rollbackCrossfade(0.3s)
   - Очищає activeCrossfade і pausedCrossfade

5. **cancelActiveCrossfade()** ✅
   - Cancel progress task
   - Очищає states
   - Викликає audioEngine.cancelActiveCrossfade()

---

### 2. AudioEngineActor (Sources/AudioServiceKit/Internal/AudioEngineActor.swift)

#### Методи rollback/cancel:

**rollbackCrossfade(rollbackDuration: 0.5)** ❌ ПРОБЛЕМА:
```swift
// Line 314-360
1. Cancel crossfade task
2. Fade IN active player (restore to targetVolume)  // ❌ МАЄ БУТИ FADE OUT!
3. Fade OUT inactive player (to 0.0)
4. Stop inactive player
```

**❌ Не відповідає вимозі:** "При cancel - fade out ОБОХ плеєрів"

**cancelActiveCrossfade()** (line 268):
```swift
- Cancel crossfade task
- Yield .idle to continuation
- Finish continuation
```

**cancelCrossfadeAndStopInactive()** (line 288):
```swift
- Cancel crossfade task
- Stop inactive player
```

---

### 3. PlaybackStateCoordinator

**CoordinatorState** (struct, line 54):
```swift
- activePlayer: PlayerNode
- playbackMode: PlayerState
- activeTrack: Track?
- inactiveTrack: Track?
- activeMixerVolume: Float
- inactiveMixerVolume: Float
- isCrossfading: Bool
- isConsistent: Bool (validation)
```

**Проблема:** Немає збереження позицій ДО операцій для rollback

---

## ❌ ЩО ВІДСУТНЄ (згідно REQUIREMENTS_CROSSFADE_AND_FADE.md)

### Priority 1: КРИТИЧНІ БАГИ

#### 1. Rollback Fade Out Both ❌
**Вимога** (Section 7):
> При скасуванні - ОБИДВА плеєри мають fade out

**Поточний код:**
- rollbackCrossfade(): active fade IN (restore volume), inactive fade OUT

**Наслідок:**
- Click/glitch при швидкому перемиканні треків
- Active player різко змінює volume

#### 2. Position Snapshot ДО операції ❌
**Вимога** (Section 1, 4):
> ЗАЛИШАЄМО в активному плеєрі трек з позицією ДО початку скасованого crossfade

**Поточний код:**
- PausedCrossfadeState: зберігає позиції при PAUSE
- Немає snapshot позиції ДО початку crossfade

**Наслідок:**
- При cancel crossfade - позиція не відновлюється до стану перед операцією
- Користувач "втрачає" частину треку

#### 3. Time Remaining Check ❌
**Вимога** (Section 1, lines 28-45):
```
IF remaining_time >= requested_duration:
    → crossfade з requested_duration
ELSE IF remaining_time >= (requested_duration / 2):
    → crossfade з remaining_time
ELSE:
    → fade out + fade in (без crossfade)
```

**Поточний код:**
- Немає перевірки remaining_time перед crossfade
- Завжди намагається зробити crossfade

**Наслідок:**
- Crossfade може "вийти за межі" треку
- Некоректна поведінка при короткому треку

---

### Priority 2: ВІДСУТНІЙ ФУНКЦІОНАЛ

#### 4. Fade operations для pause/resume/skip ❌
**Вимоги** (Sections 5, 6):
- Pause: fade out 0.3s → stop
- Resume: fade in 0.3s → continue
- Skip: fade out 0.3s → seek → fade in 0.3s

**Поточний код:**
- Немає fade operations для цих операцій
- Немає централізованої fade логіки

#### 5. Next/Prev під час fade ❌
**Вимога** (Section 4):
> Next/Prev під час fade in/out: fade скасовується, fade out активного, новий трек з fade in

**Поточний код:**
- Немає tracking fade operations (окрім crossfade)

#### 6. Pause під час fade ❌
**Вимога** (Section 3):
> Pause під час fade: fade скасовується, позиція відновлюється до стану ДО fade

**Поточний код:**
- Немає tracking fade operations для pause

#### 7. Skip forward/backward ❌
**Вимога** (Section 6):
> Skip: fade out 0.3s → seek → fade in 0.3s

**Поточний код:**
- Немає skip forward/backward методів з fades

---

### Priority 3: ARCHITECTURE GAPS

#### 8. State Machine для operations ❌
**Вимога** (Section 10, Must Have #2):
> State Machine - відстежувати crossfade vs fade in/out

**Поточний код:**
- ActiveCrossfadeState: тільки для crossfade
- Немає tracking для fade in/out/skip operations

**Проблема:**
- Не можемо визначити чи треба скасувати fade чи crossfade
- Не можемо відновити позиції різних операцій

#### 9. Debounce для rapid Next/Prev ❌
**Вимога** (з user clarification):
> 1 секунда debounce - чекаємо 1s після останнього кліку перед crossfade

**Поточний код:**
- Немає debounce логіки
- Кожен Next/Prev одразу rollback + новий crossfade

**Наслідок:**
- Багато rollback операцій при швидкому кліканні
- Нестабільна робота (описано в user bug report)

---

## 🔧 ЩО ТРЕБА ВИПРАВИТИ/ДОДАТИ

### Мінімальні зміни (Phase 1):

#### 1.1 Виправити rollbackCrossfade() в AudioEngineActor
**Файл:** `Sources/AudioServiceKit/Internal/AudioEngineActor.swift:314`

**Зміна:**
```swift
// BEFORE (line 337-344):
if currentActiveVolume < targetVolume {
    await fadeVolume(mixer: activeMixer, from: currentActiveVolume, to: targetVolume, ...)
}

// AFTER:
// Fade out BOTH players on cancel
await fadeVolume(mixer: activeMixer, from: currentActiveVolume, to: 0.0, ...)
```

**Вплив:** CrossfadeOrchestrator.rollbackCurrentCrossfade() → стане плавним

---

#### 1.2 Додати Position Snapshot ДО crossfade
**Файл:** `Sources/AudioServiceKit/Internal/CrossfadeOrchestrator.swift`

**Зміна:** В ActiveCrossfadeState додати:
```swift
private struct ActiveCrossfadeState {
    // ... existing fields ...
    
    // NEW: Position snapshot BEFORE crossfade
    let snapshotActivePosition: TimeInterval
    let snapshotInactivePosition: TimeInterval
}
```

**Використання:** При rollback - відновлюємо позиції зі snapshot

---

#### 1.3 Додати Time Remaining Check helper
**Файл:** Новий `Sources/AudioServiceKit/Internal/TimeRemainingHelper.swift`

**Функція:**
```swift
enum CrossfadeDecision {
    case fullCrossfade(duration: TimeInterval)
    case reducedCrossfade(duration: TimeInterval)
    case separateFades(fadeOutDuration: TimeInterval, fadeInDuration: TimeInterval)
}

func decideCrossfadeStrategy(
    trackPosition: TimeInterval,
    trackDuration: TimeInterval,
    requestedDuration: TimeInterval
) -> CrossfadeDecision
```

**Вплив:** startCrossfade() → перевіряє remaining_time перед операцією

---

### Більші зміни (Phase 2-3):

#### 2.1 Централізована Fade Logic
- Створити FadeOrchestrator або розширити існуючий
- fade in/out для pause/resume/skip

#### 2.2 Debounce для Next/Prev
- Task з delay 1.0s
- Cancel при новому кліку

#### 2.3 Skip Forward/Backward
- fade out 0.3s → seek → fade in 0.3s

---

## 📊 ВИСНОВКИ

### Хороша новина ✅:
1. **PausedCrossfadeState** - вже snapshot (volumes, positions)!
2. **ActiveCrossfadeState** - вже tracking (progress, time)!
3. **ResumeStrategy** - вже є логіка (<50% vs >=50%)
4. Архітектура готова до розширення

### Погана новина ❌:
1. rollbackCrossfade() працює неправильно (fade in замість fade out)
2. Snapshot тільки при PAUSE, немає snapshot ДО операції
3. Немає time remaining check
4. Немає fade operations окрім crossfade
5. Немає debounce

### Рекомендація:
**НЕ створювати нові файли/структури!**
Розширити існуючі:
- PausedCrossfadeState → OperationSnapshot (універсальний)
- ActiveCrossfadeState → додати snapshotPositions
- Виправити rollbackCrossfade()
- Додати helper для time check

**Мінімальні зміни → максимальний результат**

---

## 🚦 PLAN FORWARD

### Phase 1 (2h): Critical Bugs
1. Fix rollbackCrossfade() - fade out both
2. Add position snapshot BEFORE crossfade
3. Add time remaining check

### Phase 2 (2h): Fade Operations
1. Centralized fade logic
2. Pause/Resume with fades
3. Skip with fades

### Phase 3 (2h): Debounce + Integration
1. Debounce for rapid Next/Prev
2. Next/Prev during fade
3. Pause during fade

**Total:** 6h (realistic estimate)
