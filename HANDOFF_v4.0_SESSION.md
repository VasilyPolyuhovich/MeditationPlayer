# 🧘 ProsperPlayer v4.0 - Session Handoff

**Date:** 2025-10-12  
**Status:** Analysis Complete, Ready for Implementation  
**Focus:** Meditation App (NOT universal music player!)

---

## ✅ КРИТИЧНІ УТОЧНЕННЯ від Користувача

### 1. **Shuffle - НЕ ПОТРІБЕН** ✅
- Медитація = структурована практика
- Phases мають порядок (Induction → Intentions → Returning)
- Shuffle порушує meditation flow
- **Рішення:** Не додавати, забрати з рекомендацій

### 2. **Queue Management - PlaylistManager Перевірено** ✅
**Що Є (достатньо для медитації):**
- `insertTrack(url, at: index)` - є
- `addTrack(url)` - є
- `skipToNext()` / `skipToPrevious()` - є
- `jumpTo(index:)` - є

**Що Треба Додати (wrapper API):**
```swift
func playNext(url: URL) async {
    // insertTrack(url, at: currentIndex + 1)
    // UX: "play this phase next"
}

func getUpcomingQueue() async -> [URL] {
    // Show next 2-3 phases in meditation
}
```

### 3. **Gapless/Crossfade для Медитації** ✅
- КОНЧЕ потрібні плавні переходи
- Без різких змін (перериває медитацію)
- Crossfade ≠ gapless (для медитації crossfade краще!)
- **Рішення:** Crossfade обов'язковий, gapless не потрібен

### 4. **Crossfade Default** ✅
- 10s поставив AI (не real user requirement)
- Реальне налаштування: розробник задає при конфігурації
- **Орієнтир:** Spotify має 0-12s
- **Для медитації:** 5-15s оптимально (довші переходи OK)

### 5. **seekWithFade - ЗАЛИШИТИ** ✅
- Skip створював КЛІК (різкий звук при seek)
- Fade усуває клік
- Слайдер в UI немає в планах (skip ±15s кнопки)
- **Рішення:** Залишити seekWithFade, може знадобиться

### 6. **Volume Architecture** ⚠️ КРИТИЧНО

**Вимоги:**
1. **Стартовий volume:** Розробник встановлює перед playback
2. **Runtime volume:** Користувач змінює через UI (binding потрібен!)
3. **Внутрішня логіка:** 2 mixers + 2 nodes працюють для crossfade
4. **Global Volume:** Регулює ЗАГАЛЬНУ гучність (НЕ чіпає crossfade logic!)
5. **Overlay Volume:** Окремий, незалежний від main player

**Проблема v4.0:**
```swift
// Plan: async method
await service.setVolume(0.8)  

// SwiftUI needs: binding!
@Published var volume: Float  
```

**Рішення (треба вибрати):**

**Option A: Global через mainMixer**
```swift
// Simple approach
mainMixerNode.volume = globalVolume  // 0.0-1.0
mixerA.volume = crossfadeVolA        // crossfade logic
mixerB.volume = crossfadeVolB        // crossfade logic
```

**Option B: Multiply на кожен mixer**
```swift
// Precise approach
mixerA.volume = crossfadeVolA * globalVolume
mixerB.volume = crossfadeVolB * globalVolume
```

**Option C: @Published wrapper + async sync**
```swift
@MainActor class AudioPlayerViewModel {
    @Published var volume: Float = 1.0
    
    func setVolume(_ vol: Float) {
        volume = vol
        Task { await service.setVolume(vol) }
    }
}
```

---

## 🎯 Позиціювання: Meditation App

**Target Apps:**
- ✅ Meditation (Headspace, Calm, Insight Timer)
- ✅ Sleep (Pzizz, Sleep Cycle, Slumber)
- ✅ Ambient/Focus (Noisli, Endel, Brain.fm)

**NOT Target:**
- ❌ Music streaming (Spotify, Apple Music)
- ❌ Podcast apps (Overcast, Pocket Casts)
- ❌ DJ apps (djay, Serato)

**Унікальні Features (конкурентна перевага):**
1. 🌟 **Overlay Player** - ambient layer (rain + music)
2. 🌟 **Seamless Loop Crossfade** - no gap on repeat
3. 🌟 **Long Crossfades** - 5-15s smooth transitions
4. 🌟 **Dual-Player Architecture** - sample-accurate sync

---

## 📊 PlaylistManager Аналіз

**Структура (actor-isolated):**
```swift
actor PlaylistManager {
    private var tracks: [URL] = []
    private var currentIndex: Int = 0
    private var configuration: PlayerConfiguration
    private var currentRepeatCount: Int = 0
    
    // Playlist Management ✅
    func load(tracks: [URL])
    func addTrack(_ url: URL)
    func insertTrack(_ url: URL, at index: Int)
    func removeTrack(at index: Int) -> Bool
    func moveTrack(from: Int, to: Int) -> Bool
    func clear()
    func replacePlaylist(_ tracks: [URL])
    func getPlaylist() -> [URL]
    
    // Navigation ✅
    func getCurrentTrack() -> URL?
    func getNextTrack() -> URL?              // Logic based on repeatMode
    func shouldAdvanceToNextTrack() -> Bool
    func jumpTo(index: Int) -> URL?
    func skipToNext() -> URL?
    func skipToPrevious() -> URL?
    
    // State ✅
    var isEmpty: Bool
    var isSingleTrack: Bool
    var count: Int
    var repeatCount: Int
}
```

**Логіка repeatMode:**
- `.off` → sequential, stop at end
- `.singleTrack` → return same URL (loop one track)
- `.playlist` → loop whole playlist

**Що працює для медитації:**
- ✅ Structured playlist (phases в порядку)
- ✅ Manual navigation (next phase)
- ✅ Jump to phase (jumpTo index)
- ✅ Replace playlist (switch meditation program)

**Що треба додати (nice to have):**
```swift
// Convenience API
func playNext(_ url: URL) async {
    let nextIndex = currentIndex + 1
    insertTrack(url, at: nextIndex)
}

func getUpcomingQueue(count: Int = 3) -> [URL] {
    // Return next N tracks for UI preview
}
```

---

## 🔧 v4.0 Refactoring Status

### ✅ **Phase 1: Git Setup** (Complete)
- Created v4-dev branch
- Committed previous work

### ✅ **Phase 2: Delete Fade Parameters** (Complete, Not Tested!)
**Deleted from PlayerConfiguration:**
```swift
❌ singleTrackFadeInDuration: TimeInterval
❌ singleTrackFadeOutDuration: TimeInterval
❌ stopFadeDuration: TimeInterval
❌ fadeInDuration: TimeInterval (computed)
❌ volume: Int
```

**Kept:**
```swift
✅ crossfadeDuration: TimeInterval
✅ fadeCurve: FadeCurve
✅ repeatMode: RepeatMode
✅ repeatCount: Int?
✅ mixWithOthers: Bool
```

⚠️ **ВАЖЛИВО:** Компіляція НЕ перевірена! Треба build test.

### ⏳ **Phase 3: Update API Methods** (Next, 2-3h)
**Додати fade параметри до методів:**
```swift
// БУЛО:
func startPlaying(url: URL, configuration: PlayerConfiguration) async throws

// СТАЄ:
func startPlaying(fadeDuration: TimeInterval = 0.0) async throws
func stop(fadeDuration: TimeInterval = 0.0) async
func seekWithFade(to: TimeInterval, fadeDuration: TimeInterval = 0.1) async throws

// Volume:
func setVolume(_ volume: Float) async       // Set global
func getVolume() async -> Float             // Get current

// Queue (nice to have):
func playNext(_ url: URL) async            // Insert after current
func getUpcomingQueue() async -> [URL]     // Preview next tracks
```

### ⏳ **Phase 4: Fix Loop Crossfade** (2-3h)
**Auto-adapt crossfade для коротких треків:**
```swift
private func loopCurrentTrackWithFade() async {
    let trackDuration = currentTrack?.duration ?? 0
    let maxCrossfade = trackDuration * 0.4  // Max 40%
    let actualCrossfade = min(configuration.crossfadeDuration, maxCrossfade)
    
    // Use actualCrossfade for smooth loop
}
```

### ⏳ **Phase 5: Pause Crossfade (Variant A)** (3-4h)
**Save & Continue crossfade state:**
```swift
private struct CrossfadeState: Sendable {
    let progress: Float
    let remainingDuration: TimeInterval
    let playerAVolume: Float
    let playerBVolume: Float
}

func pause() async {
    if isCrossfading {
        savedCrossfadeState = CrossfadeState(...)
    }
    await audioEngine.pauseBothPlayers()
}

func resume() async {
    if let saved = savedCrossfadeState {
        await continueCrossfade(from: saved)
    }
}
```

### ⏳ **Phase 6: Volume Management** (1h)
**Треба вирішити архітектуру!**

### ⏳ **Phase 7: Remove Deprecated** (1h)
### ⏳ **Phase 8: Testing** (2h)

**Total:** 12-18h

---

## 🚨 Критичні Рішення (треба прийняти)

### **1. Volume Architecture** (Option A, B, or C?)
- [ ] Option A: mainMixer.volume (simple)
- [ ] Option B: multiply mixers (precise)  
- [ ] Option C: @Published wrapper (SwiftUI friendly)

**Рекомендація:** Option C (SwiftUI ecosystem standard)

### **2. Queue API** (wrapper чи direct?)
- [ ] Add playNext() wrapper
- [ ] Or use insertTrack() directly

**Рекомендація:** Add wrapper (better UX)

### **3. Default Crossfade Duration**
- [ ] 5s (Spotify-like, short)
- [ ] 10s (current AI default)
- [ ] 15s (meditation optimal)

**Рекомендація:** 10s (good for meditation, user configurable)

---

## 📂 Ключові Файли

**Planning:**
- `.claude/planning/V4.0_CLEAN_PLAN.md` - master plan
- `.claude/planning/PLAYER_CONFIGURATION_GUIDE.md` - v3.1 config (old)
- `.claude/planning/FEATURE_PLAN_v3.1.md` - v3.1 features (old)

**Core Code:**
- `Sources/AudioServiceCore/PlayerConfiguration.swift` - config struct
- `Sources/AudioServiceKit/Playlist/PlaylistManager.swift` - queue logic ✅
- `Sources/AudioServiceKit/Public/AudioPlayerService.swift` - public API
- `Sources/AudioServiceKit/Internal/AudioEngineActor.swift` - dual-player engine

**Docs:**
- `CHANGELOG.md` - version 2.10.0 (transactional crossfade pattern)
- `README.md` - current v2.11.0 status
- `Temp/` - ЗАСТАРІЛО (ігнорувати, v2.x-v3.x docs)

---

## ⚡ Швидкий Старт Нового Чату

```
Привіт! Продовжую v4.0 refactoring ProsperPlayer.

Проєкт: /Users/vasily/Projects/Helpful/ProsperPlayer
Фокус: Meditation App (НЕ universal music player!)

Прочитай: HANDOFF_v4.0_SESSION.md

Поточний стан:
✅ Phase 1-2 complete (git + delete params)
⚠️ Компіляція НЕ перевірена!
⏳ Phase 3 next: Update API methods

Критичні рішення потрібні:
1. Volume architecture (Option A/B/C?)
2. Queue wrapper API (playNext?)
3. Default crossfade (5s/10s/15s?)

Що робимо?
```

---

**End of Handoff** 🚀

**Next Developer:** Read this file, verify Phase 2 compilation, continue Phase 3!