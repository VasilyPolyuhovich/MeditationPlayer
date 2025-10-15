# 🎯 ProsperPlayer v4.0 - Master Plan & Philosophy

**КОНЦЕПЦІЇ ТА ФІЛОСОФІЯ v4.0**

**Date:** 2025-10-13  
**Status:** ➡️ See [V4_FINAL_ACTION_PLAN.md](V4_FINAL_ACTION_PLAN.md) for current phase status  
**Critical:** Crossfade ≠ Fade (різні концепції!)

---

## 🔥 КЛЮЧОВІ КОНЦЕПЦІЇ v4.0

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

---

## 🔍 CROSSFADE vs FADE - Фундаментальна Різниця

| Тип | Призначення | Тривалість | Архітектура |
|-----|-------------|------------|-------------|
| **CROSSFADE** | Між РІЗНИМИ треками | 5-15s | Dual-player (два треки одночасно) |
| **FADE IN/OUT** | Старт/зупинка ОДНОГО треку | 1-5s | Single-player (volume fade) |

### Приклади Використання:

```swift
// CROSSFADE (у конфігурації):
crossfadeDuration: 10.0  // Track A → Track B (10s overlap)
                         // Використовується автоматично при:
                         // - skipToNext()
                         // - skipToPrevious() 
                         // - replacePlaylist()
                         // - loop transition

// FADE (у параметрах методів):
startPlaying(fadeDuration: 2.0)   // 0 → full volume (2s)
stop(fadeDuration: 3.0)           // full → 0 volume (3s)
seekWithFade(fadeDuration: 0.1)   // анти-click (0.1s)
```

---

## 🎯 Чому Саме Так?

### 1. **Configuration = Глобальна Поведінка**
```swift
crossfadeDuration: 10.0  // Всі track-to-track переходи однакові
repeatMode: .playlist    // Як плеєр працює з плейлистом
fadeCurve: .equalPower   // Тип кривої для всіх fadeів
```

**Ратіонал:** Користувач один раз налаштовує "характер" плеєра і він працює консистентно.

### 2. **Method Parameters = Контекстна Поведінка**
```swift
startPlaying(fadeDuration: 2.0)  // Різний fade in в різних ситуаціях
stop(fadeDuration: 3.0)          // Може бути 0s (instant) або 5s (smooth)
```

**Ратіонал:** Деякі операції потребують різного fade залежно від контексту (наприклад: cold start vs resume).

### 3. **Immutable Configuration = Thread Safety**
```swift
// ❌ v3.x:
config.crossfadeDuration = 15.0  // Небезпечно під час playback!

// ✅ v4.0:
let config = PlayerConfiguration(...)  // Створюється один раз
await player.updateConfiguration(newConfig)  // Безпечна заміна через actor
```

**Ратіонал:** Swift 6 strict concurrency вимагає immutable Sendable структури.

---

## 📐 Архітектурні Рішення

### 1. **Dual-Player для Crossfade**

```
┌─────────────┐
│  PlayerA    │ ──→ MixerA ──→ ┐
└─────────────┘                │
                               ├──→ MainMixer ──→ Output
┌─────────────┐                │
│  PlayerB    │ ──→ MixerB ──→ ┘
└─────────────┘
```

**Чому не один плеєр?**
- AVAudioPlayerNode не підтримує real-time scheduling двох файлів одночасно
- Crossfade = 100% + 100% overlap (Spotify-style)
- Потрібно незалежне управління volume для кожного треку

### 2. **Actor Isolation для Swift 6**

```swift
public actor AudioPlayerService {
    // Всі operations serialized
    // Data race safety гарантована компілятором
}
```

**Чому actor?**
- AVAudioEngine НЕ thread-safe
- Swift 6 strict concurrency вимагає ізоляції
- Async/await API природно підходить для аудіо операцій

### 3. **Configuration Immutability**

```swift
public struct PlayerConfiguration: Sendable {
    public let crossfadeDuration: TimeInterval  // let, not var!
    public let fadeCurve: FadeCurve
    public let repeatMode: RepeatMode
    // ...
}
```

**Чому immutable?**
- Sendable conformance (Swift 6 requirement)
- Predictable behavior - конфігурація не змінюється "під ногами"
- Thread-safe by design
- Зміни через `updateConfiguration()` - явні та контрольовані

### 4. **Volume Architecture** (Hybrid Implementation)

```
PlayerA → MixerA (crossfade * targetVolume) ──┐
                                              ├──→ MainMixer (targetVolume) → Output
PlayerB → MixerB (crossfade * targetVolume) ──┘

OverlayPlayer → OverlayMixer (independent) → Output
```

**Як працює:**

1. **Master Volume (`targetVolume`)** - глобальне обмеження для основного плеєра
   - Зберігається в `AudioEngineActor.targetVolume`
   - Встановлюється через `setVolume(_ volume: Float)`
   - Діапазон: 0.0 - 1.0

2. **MainMixer.volume** - дублює targetVolume (backup layer)
   ```swift
   engine.mainMixerNode.volume = targetVolume
   ```

3. **MixerA/B volumes** - динамічні для crossfade/fade ефектів
   ```swift
   // Під час crossfade - скалюються до targetVolume:
   activeMixer.volume = curve.inverseVolume(progress) * targetVolume  // fade out
   inactiveMixer.volume = curve.volume(progress) * targetVolume       // fade in
   
   // Коли НЕ crossfading - дорівнюють targetVolume:
   getActiveMixerNode().volume = targetVolume
   ```

4. **Overlay Volume** - повністю незалежний
   ```swift
   await audioEngine.setOverlayVolume(0.5)  // Окремий контроль
   ```

**Переваги архітектури:**
- ✅ Crossfade завжди респектує user volume (множиться на targetVolume)
- ✅ MainMixer як safety layer - гарантує обмеження навіть при багах
- ✅ Overlay повністю незалежний - ambient звуки не впливають на основний плеєр
- ✅ Один параметр (`targetVolume`) контролює весь основний плеєр

---

## 🔗 Meditation App Use Case

### Типовий Сценарій:

```swift
// 1. Налаштування сесії
let config = PlayerConfiguration(
    crossfadeDuration: 10.0,   // Плавні переходи між фазами
    fadeCurve: .equalPower,
    repeatMode: .playlist,     // Loop всієї медитації
    volume: 0.8
)

// 2. Завантаження фаз медитації
let session = [induction, intentions, returning]
try await player.loadPlaylist(session)

// 3. Старт з м'яким входом
try await player.startPlaying(fadeDuration: 2.0)

// 4. Під час медитації - всі переходи автоматичні з 10s crossfade:
//    induction → intentions (10s crossfade)
//    intentions → returning (10s crossfade)
//    returning → induction (10s loop crossfade)

// 5. Кінець медитації
await player.stop(fadeDuration: 3.0)
```

### Чому Це Важливо:

- **Zero glitches** - будь-який клік перериває медитацію
- **Long crossfades** - 5-15s нормально для медитації (vs 1-3s для музики)
- **Seamless loops** - sleep sounds повинні грати нескінченно без gap
- **Простий API** - розробник один раз налаштовує, все працює автоматично

---

## 📊 Breaking Changes Summary

### Видалено з Configuration:

```swift
❌ singleTrackFadeInDuration: TimeInterval
❌ singleTrackFadeOutDuration: TimeInterval  
❌ stopFadeDuration: TimeInterval
❌ fadeInDuration: TimeInterval (computed property)
❌ volume: Int  // Замінено на Float
❌ enableLooping: Bool  // Замінено на repeatMode
```

### Змінено API:

```swift
// ❌ v3.x:
func startPlaying(url: URL, configuration: PlayerConfiguration) async throws
func loadPlaylist(configuration: PlayerConfiguration) async throws

// ✅ v4.0:
func loadPlaylist(_ tracks: [URL]) async throws
func startPlaying(fadeDuration: TimeInterval = 0.0) async throws
func stop(fadeDuration: TimeInterval = 0.0) async
```

### Детальний Migration Guide:
📖 Дивись [V4_FINAL_ACTION_PLAN.md](V4_FINAL_ACTION_PLAN.md) Phase 8 для повного гайду

---

## 🤔 Важливі Архітектурні Питання

### 1. **Volume Architecture** ✅ РЕАЛІЗОВАНО
📖 Дивись секцію "Volume Architecture (Hybrid Implementation)" вище

### 2. **Queue Management**
📖 Аналіз PlaylistManager в [HANDOFF_v4.0_SESSION.md](HANDOFF_v4.0_SESSION.md) - PlaylistManager Аналіз

### 3. **Overlay Player Delay**
📖 Специфікація в [FEATURE_OVERVIEW_v4.0.md](FEATURE_OVERVIEW_v4.0.md) - Overlay Player

---

## 📚 Навігація по Документах

### Для Розуміння Концепцій:
- 📖 **V4_MASTER_PLAN.md** (цей файл) - філософія та архітектурні рішення

### Для Реалізації:
- 📋 **[V4_FINAL_ACTION_PLAN.md](V4_FINAL_ACTION_PLAN.md)** - поточний статус фаз та детальні плани
- 📖 **[FEATURE_OVERVIEW_v4.0.md](FEATURE_OVERVIEW_v4.0.md)** - повна специфікація функціоналу

### Для Контексту:
- 📝 **[HANDOFF_v4.0_SESSION.md](HANDOFF_v4.0_SESSION.md)** - критичні рішення та деталі архітектури
- 🚀 **[START_NEXT_CHAT.md](START_NEXT_CHAT.md)** - швидкий старт для нових чатів

---

## 💡 Ключові Принципи

1. **Crossfade ≠ Fade** - різні концепції, різне призначення
2. **Configuration = Global** - задається один раз, працює скрізь
3. **Parameters = Contextual** - різні значення в різних ситуаціях
4. **Immutability = Safety** - Swift 6 concurrency compliance
5. **Meditation First** - архітектура оптимізована для meditation apps

---

**Останнє оновлення:** 2025-10-13  
**Статус фаз:** Дивись [V4_FINAL_ACTION_PLAN.md](V4_FINAL_ACTION_PLAN.md)

---

*Цей документ пояснює ЧОМУ v4.0 працює саме так. Для ПОТОЧНОГО СТАТУСУ та ЩО ТРЕБА РОБИТИ дивись V4_FINAL_ACTION_PLAN.md*
