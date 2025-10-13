# 🎯 ProsperPlayer v4.0 - Master Plan & Context

**ЄДИНЕ ДЖЕРЕЛО ПРАВДИ ПРО v4.0**

**Date:** 2025-10-12  
**Status:** Phase 1 DONE (compilation fix), Phase 2-8 NOT STARTED  
**Critical:** Crossfade ≠ Fade (різні концепції!)

---

## 🔥 КРИТИЧНЕ РОЗУМІННЯ

### v4.0 Філософія (ключова зміна!):

**БУЛО (v3.x):** 5 fade параметрів у конфігурації
```swift
PlayerConfiguration(
    crossfadeDuration: 10.0,
    singleTrackFadeInDuration: 2.0,    // ❌ ВИДАЛЕНО
    singleTrackFadeOutDuration: 3.0,   // ❌ ВИДАЛЕНО
    stopFadeDuration: 3.0,             // ❌ ВИДАЛЕНО
)
```

**СТАЛО (v4.0):** 1 crossfadeDuration + fade в **параметрах методів**
```swift
// Configuration:
PlayerConfiguration(
    crossfadeDuration: 10.0,  // ТІЛЬКИ для track-to-track crossfade
)

// Methods:
await player.startPlaying(fadeDuration: 2.0)    // fade in на старті
await player.stop(fadeDuration: 3.0)            // fade out на зупинці
```

### 🔍 Різниця CROSSFADE vs FADE:

| Тип | Призначення | Тривалість | Архітектура |
|-----|-------------|------------|-------------|
| **CROSSFADE** | Між РІЗНИМИ треками | 5-15s | Dual-player (два треки одночасно) |
| **FADE IN/OUT** | Старт/зупинка ОДНОГО треку | 1-5s | Single-player (volume fade) |

**Приклади:**
```swift
// CROSSFADE (у конфігурації):
crossfadeDuration: 10.0  // Track A → Track B (10s overlap)

// FADE (у параметрах методів):
startPlaying(fadeDuration: 2.0)   // 0 → full volume (2s)
stop(fadeDuration: 3.0)           // full → 0 volume (3s)
seekWithFade(fadeDuration: 0.1)   // анти-click (0.1s)
```

---

## 📊 Що Зроблено vs Що Треба

### ✅ Phase 1: Compilation Fix (DONE)
**Git:** v4-dev branch  
**Коміт:** 217c8fc

**Що зробили:**
- ✅ Видалили з PlayerConfiguration:
  - singleTrackFadeInDuration
  - singleTrackFadeOutDuration
  - stopFadeDuration
- ✅ Видалили метод setSingleTrackFadeDurations()
- ✅ Замінили старі references на crossfadeDuration

**ЩО НЕ ЗРОБИЛИ (це НАСТУПНІ phases!):**
- ❌ Не додали fade параметри в методи
- ❌ Не реалізували overlay delay
- ❌ Не експонували playlist API
- ❌ Не додали queue system

### ❌ Phase 2-8: СПРАВЖНЯ Реалізація v4.0 (NOT DONE)

**Phase 2:** Demo App (оновити під Phase 1)  
**Phase 3:** API Methods - додати fade параметри ⚠️ **КРИТИЧНО!**  
**Phase 4:** Loop Crossfade - auto-adaptation  
**Phase 5:** Pause Crossfade - зберігати state  
**Phase 6:** Volume Management - вибрати архітектуру  
**Phase 7:** Remove Deprecated  
**Phase 8:** Testing  

---

## 🚨 КРИТИЧНІ Проблеми Зараз

### 1. **startPlaying НЕ має fadeDuration параметр**
```swift
// ❌ Поточна реалізація:
func startPlaying(url: URL, configuration: PlayerConfiguration) async throws

// ✅ Має бути (v4.0):
func startPlaying(fadeDuration: TimeInterval = 0.0) async throws
```

**Наслідок:** Користувач НЕ може задати fade in на старті!

### 2. **Single track loop використовує computed property**
```swift
// ❌ loopCurrentTrackWithFade():
let fadeIn = configuration.fadeInDuration  // = crossfade * 0.3
let fadeOut = configuration.crossfadeDuration * 0.7
```

**Проблема:** Fade in/out для loop **ПРИВ'ЯЗАНІ** до crossfade!

**Приклад:**
- Хочу: crossfade 10s (між треками) + fade in 2s (на loop)
- Маю: crossfade 10s → fade in 3s (автоматично 10 * 0.3)
- **НЕМОЖЛИВО налаштувати окремо!**

### 3. **Overlay delay - невідомо чи реалізовано**
**FEATURE_OVERVIEW каже:**
```swift
OverlayConfiguration(
    delayBetweenLoops: 5.0  // Пауза між повторами
)
```

**Треба перевірити:**
- Чи є в коді?
- Чи працює?
- Як називається (loopDelay vs delayBetweenLoops)?

### 4. **Playlist API не експоновано**
**Є внутрішньо (PlaylistManager):**
- addTrack, insertTrack, removeTrack
- skipToNext, skipToPrevious, jumpTo

**Немає публічно (AudioPlayerService):**
- ❌ Тільки replacePlaylist + getPlaylist

---

## 🎯 План Виправлення

### Етап 1: Детальна Перевірка (1 год)
**Мета:** Зрозуміти ЩО РЕАЛЬНО реалізовано

1. **Перевірити startPlaying:**
   ```
   get_symbol_definition({
     path: "AudioPlayerService.swift",
     symbolName: "startPlaying"
   })
   ```
   Чи є fadeDuration параметр?

2. **Перевірити OverlayConfiguration:**
   ```
   get_symbol_definition({
     path: "OverlayConfiguration.swift",
     symbolName: "OverlayConfiguration"
   })
   ```
   Чи є delayBetweenLoops/loopDelay?

3. **Перевірити OverlayPlayerActor:**
   ```
   analyze_file_structure({
     path: "OverlayPlayerActor.swift"
   })
   ```
   Чи реалізовано delay timer?

4. **Перевірити loopCurrentTrackWithFade:**
   ```
   get_symbol_definition({
     path: "AudioPlayerService.swift",
     symbolName: "loopCurrentTrackWithFade"
   })
   ```
   Як розраховуються fade in/out?

### Етап 2: Вибрати Архітектуру (30 хв)

**Рішення 1: Fade параметри**
- A) В методах (pure v4.0)
- B) В конфігурації (як було)
- C) Гібрид (defaults + override в методах)

**Рішення 2: Volume**
- A) mainMixer only
- B) multiply mixers
- C) @Published wrapper

**Рішення 3: Playlist API**
- A) Експонувати всі методи
- B) Залишити мінімальний (як зараз)
- C) Додати тільки найважливіші

### Етап 3: Реалізація (залежить від рішень)

---

## 📚 Документація (що читати)

### ОСНОВНІ (прочитати ПОВНІСТЮ!):
1. **FEATURE_OVERVIEW_v4.0.md** ←SPEC (що має бути)
2. **DETAILED_V4_REFACTOR_PLAN.md** ← План phases
3. **CODE_VS_FEATURE_ANALYSIS.md** ← Код vs spec
4. **HANDOFF_v4.0_SESSION.md** ← Контекст і рішення

### Допоміжні:
- START_NEXT_CHAT.md - швидкий старт
- QUICK_START_v4.0.md - команди
- Building an iOS Audio Player... (у documents) - технічна база

---

## ✅ Checklist для Наступного Чату

**На початку:**
- [ ] Прочитати V4_MASTER_PLAN.md (ЦЕЙ файл!)
- [ ] Прочитати FEATURE_OVERVIEW_v4.0.md (повністю!)
- [ ] load_session() - завантажити контекст
- [ ] current_project() - перевірити проєкт
- [ ] git_status() - перевірити зміни

**Перед реалізацією:**
- [ ] Виконати Етап 1 (детальна перевірка)
- [ ] Прийняти рішення (Етап 2)
- [ ] Показати план користувачу
- [ ] Дочекатись підтвердження
- [ ] ТІЛЬКИ ТОДІ починати код

**Забороняється:**
- ❌ Починати реалізацію без плану
- ❌ Приймати рішення без користувача
- ❌ Ігнорувати цей документ
- ❌ Створювати нові аналізи без читання старих

---

## 💬 Template для Наступного Чату

```
Привіт! Продовжую ProsperPlayer v4.0.

1. Прочитав V4_MASTER_PLAN.md ✅
2. Прочитав FEATURE_OVERVIEW_v4.0.md ✅
3. Завантажив session ✅

Розумію що:
- Phase 1 = compilation fix (DONE)
- Phases 2-8 = справжня реалізація (NOT DONE)
- Crossfade ≠ Fade (різні концепції!)

План:
[Етап 1: Детальна перевірка - 1 год]
1. Перевірити startPlaying - чи є fadeDuration?
2. Перевірити overlay delay - чи реалізовано?
3. Перевірити loop fade - як розраховується?
4. Перевірити playlist API - що експоновано?

[Етап 2: Рішення - 30 хв]
Разом з тобою вибрати:
- Fade архітектуру (A/B/C)
- Volume архітектуру (A/B/C)
- Playlist API (A/B/C)

[Етап 3: Реалізація]
ТІЛЬКИ після підтвердження плану!

Починаємо з Етапу 1?
```

---

**ВАЖЛИВО:** Цей документ - ЄДИНЕ джерело правди про v4.0. Всі інші документи - допоміжні. Якщо щось суперечить - цей документ має пріоритет.

**Останнє оновлення:** 2025-10-12 18:00  
**Статус:** Phase 1 done, готові до Phase 2-8
