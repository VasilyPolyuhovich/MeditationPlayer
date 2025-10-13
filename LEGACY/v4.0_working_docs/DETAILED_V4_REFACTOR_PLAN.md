# 📋 Детальний План v4.0 Refactor

**Date:** 2025-10-12  
**Task:** Привести код у відповідність з v4.0 концепцією

---

## 🔍 Поточна Ситуація (РЕАЛЬНА)

### ✅ PlayerConfiguration - ПРАВИЛЬНИЙ v4.0
```swift
// Sources/AudioServiceCore/PlayerConfiguration.swift
public struct PlayerConfiguration: Sendable {
    public var crossfadeDuration: TimeInterval  // ✅ ONE fade для всього
    public var fadeCurve: FadeCurve
    public var repeatMode: RepeatMode
    public var repeatCount: Int?
    public var volume: Int
    public var mixWithOthers: Bool
    
    // ✅ Computed (read-only)
    public var fadeInDuration: TimeInterval {
        crossfadeDuration * 0.3
    }
    
    // ❌ DELETED (correct!):
    // - singleTrackFadeInDuration
    // - singleTrackFadeOutDuration  
    // - stopFadeDuration
}
```

### ❌ Код Використовує Неіснуючі Поля

**Проблемні місця:**

#### 1. AudioPlayerService.swift (9 місць):

**Line 88-91:** Initialization
```swift
configuration: PlayerConfiguration(
    // ...
    singleTrackFadeInDuration: configuration.singleTrackFadeInDuration,  // ❌
    singleTrackFadeOutDuration: configuration.singleTrackFadeOutDuration, // ❌
    stopFadeDuration: configuration.stopFadeDuration // ❌
)
```

**Line 370:** stopWithDefaultFade()
```swift
await stop(fadeDuration: configuration.stopFadeDuration) // ❌
```

**Line 380:** finish()
```swift
let duration = fadeDuration ?? configuration.stopFadeDuration // ❌
```

**Line 518-521:** setVolume()
```swift
singleTrackFadeInDuration: configuration.singleTrackFadeInDuration,  // ❌
singleTrackFadeOutDuration: configuration.singleTrackFadeOutDuration, // ❌
stopFadeDuration: configuration.stopFadeDuration // ❌
```

**Line 551-554:** setRepeatMode()
```swift
singleTrackFadeInDuration: configuration.singleTrackFadeInDuration,  // ❌
singleTrackFadeOutDuration: configuration.singleTrackFadeOutDuration, // ❌
stopFadeDuration: configuration.stopFadeDuration // ❌
```

**Line 585-627:** setSingleTrackFadeDurations() - **ВЕСЬ МЕТОД ВИДАЛИТИ**
```swift
public func setSingleTrackFadeDurations(fadeIn: TimeInterval, fadeOut: TimeInterval) // ❌
// Цей метод НЕ потрібен в v4.0!
```

**Line 1093-1094:** calculateAdaptedCrossfadeDuration()
```swift
let configuredFadeIn = configuration.singleTrackFadeInDuration  // ❌
let configuredFadeOut = configuration.singleTrackFadeOutDuration // ❌
```

**Line 1209-1210:** loopCurrentTrackWithFade()
```swift
let configuredFadeIn = configuration.singleTrackFadeInDuration  // ❌
let configuredFadeOut = configuration.singleTrackFadeOutDuration // ❌
```

**Line 1348-1351:** syncConfigurationToPlaylistManager()
```swift
singleTrackFadeInDuration: configuration.singleTrackFadeInDuration,  // ❌
singleTrackFadeOutDuration: configuration.singleTrackFadeOutDuration, // ❌
stopFadeDuration: configuration.stopFadeDuration // ❌
```

#### 2. Tests (PlayerConfigurationTests.swift - 12 місць):
- Всі тести для неіснуючих полів треба видалити/переписати

#### 3. Demo App (MeditationDemo):
- Line 257-258: init з неіснуючими полями

---

## 🎯 v4.0 Концепція

### Що Змінюється:

**v3.x (OLD):**
```swift
// 5 fade параметрів:
- singleTrackFadeInDuration   // для loop fade in
- singleTrackFadeOutDuration  // для loop fade out
- stopFadeDuration            // для stop()
- crossfadeDuration           // для track switch
- fadeInDuration (computed)   // для startPlaying()
```

**v4.0 (NEW):**
```swift
// 1 fade параметр + методи з параметрами:
- crossfadeDuration           // ✅ ONE для всього
- fadeInDuration (computed)   // ✅ = crossfadeDuration * 0.3

// Fade в методах:
startPlaying(fadeDuration: TimeInterval = 0.0)
stop(fadeDuration: TimeInterval? = nil)
finish(fadeDuration: TimeInterval?)
```

### Нова Логіка:

**Single Track Loop Crossfade:**
```swift
// v3.x (OLD):
fadeIn = singleTrackFadeInDuration   // окремий параметр
fadeOut = singleTrackFadeOutDuration // окремий параметр
crossfade = max(fadeIn, fadeOut)     // вибираємо більший

// v4.0 (NEW):
crossfade = configuration.crossfadeDuration  // ONE параметр
// Адаптація:
adaptedCrossfade = min(crossfade, trackDuration * 0.4)
```

**Stop/Finish:**
```swift
// v3.x (OLD):
stop() // використовує stopFadeDuration з config

// v4.0 (NEW):
stop(fadeDuration: 5.0) // параметр методу!
finish(fadeDuration: 3.0)
```

---

## 📝 Детальний План Змін

### Phase 1: AudioPlayerService.swift

#### Step 1.1: Видалити setSingleTrackFadeDurations() метод
**Location:** Lines 585-635

**Action:** DELETE весь метод
```swift
// ❌ DELETE це:
public func setSingleTrackFadeDurations(
    fadeIn: TimeInterval,
    fadeOut: TimeInterval
) async throws {
    // ... весь код
}
```

**Reasoning:** v4.0 не має окремих fade параметрів, використовує crossfadeDuration

---

#### Step 1.2: Fix calculateAdaptedCrossfadeDuration()
**Location:** Lines 1091-1110

**OLD:**
```swift
private func calculateAdaptedCrossfadeDuration(trackDuration: TimeInterval) -> TimeInterval {
    // Get configured fade durations
    let configuredFadeIn = configuration.singleTrackFadeInDuration  // ❌
    let configuredFadeOut = configuration.singleTrackFadeOutDuration // ❌
    
    // Adaptive scaling to track duration (max 40% each = 80% total)
    let maxFadeIn = min(configuredFadeIn, trackDuration * 0.4)
    let maxFadeOut = min(configuredFadeOut, trackDuration * 0.4)
    
    // ... rest
    return max(actualFadeIn, actualFadeOut)
}
```

**NEW:**
```swift
private func calculateAdaptedCrossfadeDuration(trackDuration: TimeInterval) -> TimeInterval {
    // v4.0: Use single crossfadeDuration for loop
    let configuredCrossfade = configuration.crossfadeDuration
    
    // Adaptive scaling: max 40% of track
    let adaptedCrossfade = min(configuredCrossfade, trackDuration * 0.4)
    
    return adaptedCrossfade
}
```

**Reasoning:** v4.0 має ONE crossfadeDuration, не два окремих fade

---

#### Step 1.3: Fix loopCurrentTrackWithFade()
**Location:** Lines 1209-1211

**OLD:**
```swift
let configuredFadeIn = configuration.singleTrackFadeInDuration  // ❌
let configuredFadeOut = configuration.singleTrackFadeOutDuration // ❌
Self.logger.info("[LOOP_CROSSFADE] Starting: configured=(\(configuredFadeIn)s,\(configuredFadeOut)s)")
```

**NEW:**
```swift
let configuredCrossfade = configuration.crossfadeDuration
Self.logger.info("[LOOP_CROSSFADE] Starting: configured=\(configuredCrossfade)s, adapted=\(crossfadeDuration)s")
```

---

#### Step 1.4: Fix stopWithDefaultFade()
**Location:** Lines 369-370

**OLD:**
```swift
public func stopWithDefaultFade() async {
    await stop(fadeDuration: configuration.stopFadeDuration) // ❌
}
```

**NEW v4.0 (Option A - видалити метод):**
```swift
// DELETE метод повністю, використовувати:
// await stop(fadeDuration: 3.0) // explicit
```

**NEW v4.0 (Option B - використати crossfade):**
```swift
public func stopWithDefaultFade() async {
    // Use crossfadeDuration for stop fade
    await stop(fadeDuration: configuration.crossfadeDuration)
}
```

**Reasoning:** stopFadeDuration не існує, використовуємо crossfadeDuration або explicit параметр

---

#### Step 1.5: Fix finish()
**Location:** Line 380

**OLD:**
```swift
let duration = fadeDuration ?? configuration.stopFadeDuration // ❌
```

**NEW:**
```swift
let duration = fadeDuration ?? configuration.crossfadeDuration
```

**Reasoning:** Використовуємо crossfadeDuration як default для finish fade

---

#### Step 1.6: Fix Configuration Updates (4 місця)

**Lines to fix:**
- 88-91 (init)
- 518-521 (setVolume)
- 551-554 (setRepeatMode)
- 1348-1351 (syncConfigurationToPlaylistManager)

**OLD (all 4 places):**
```swift
PlayerConfiguration(
    crossfadeDuration: configuration.crossfadeDuration,
    fadeCurve: configuration.fadeCurve,
    repeatMode: configuration.repeatMode,
    repeatCount: configuration.repeatCount,
    singleTrackFadeInDuration: configuration.singleTrackFadeInDuration,  // ❌
    singleTrackFadeOutDuration: configuration.singleTrackFadeOutDuration, // ❌
    volume: configuration.volume,
    stopFadeDuration: configuration.stopFadeDuration,  // ❌
    mixWithOthers: configuration.mixWithOthers
)
```

**NEW (all 4 places):**
```swift
PlayerConfiguration(
    crossfadeDuration: configuration.crossfadeDuration,
    fadeCurve: configuration.fadeCurve,
    repeatMode: configuration.repeatMode,
    repeatCount: configuration.repeatCount,
    volume: configuration.volume,
    mixWithOthers: configuration.mixWithOthers
)
```

**Note:** Просто видаляємо 3 рядки з неіснуючими полями!

---

### Phase 2: Update Tests

**File:** Tests/AudioServiceKitTests/PlayerConfigurationTests.swift

#### Step 2.1: Delete Old Tests
```swift
// ❌ DELETE всі тести для:
- singleTrackFadeInDuration (lines 19, 126-133)
- singleTrackFadeOutDuration (lines 20, 138-145)
- stopFadeDuration (lines 22, 152-165)
```

#### Step 2.2: Update Valid Tests
```swift
// Line 14-23: Default values test
@Test("Default configuration values")
func testDefaultConfiguration() {
    let config = PlayerConfiguration()
    
    #expect(config.crossfadeDuration == 10.0)
    #expect(config.fadeCurve == .equalPower)
    #expect(config.repeatMode == .off)
    #expect(config.repeatCount == nil)
    // ❌ DELETE: #expect(config.singleTrackFadeInDuration == 3.0)
    // ❌ DELETE: #expect(config.singleTrackFadeOutDuration == 3.0)
    #expect(config.volume == 100)
    // ❌ DELETE: #expect(config.stopFadeDuration == 3.0)
    #expect(config.mixWithOthers == false)
    
    // ✅ ADD: Test computed property
    #expect(config.fadeInDuration == 3.0) // 10.0 * 0.3
}
```

#### Step 2.3: Add New v4.0 Tests
```swift
@Test("fadeInDuration is 30% of crossfade")
func testFadeInDurationComputed() {
    let config = PlayerConfiguration(crossfadeDuration: 20.0)
    #expect(config.fadeInDuration == 6.0) // 20 * 0.3
}

@Test("Loop crossfade uses crossfadeDuration")
func testLoopUsesMainCrossfade() {
    let config = PlayerConfiguration(crossfadeDuration: 15.0)
    // Logic should use config.crossfadeDuration for loops
    #expect(config.crossfadeDuration == 15.0)
}
```

---

### Phase 3: Update Demo App

**File:** Examples/MeditationDemo/.../AudioPlayerViewModel.swift

**Line 252-261:** Fix configuration creation

**OLD:**
```swift
PlayerConfiguration(
    crossfadeDuration: crossfadeDuration,
    fadeCurve: selectedCurve,
    repeatMode: repeatMode,
    repeatCount: repeatCount,
    singleTrackFadeInDuration: singleTrackFadeIn,  // ❌
    singleTrackFadeOutDuration: singleTrackFadeOut, // ❌
    volume: volume,
    mixWithOthers: mixWithOthers
)
```

**NEW:**
```swift
PlayerConfiguration(
    crossfadeDuration: crossfadeDuration,
    fadeCurve: selectedCurve,
    repeatMode: repeatMode,
    repeatCount: repeatCount,
    volume: volume,
    mixWithOthers: mixWithOthers
)
```

**Also in ViewModel:**
- Видалити `@Published var singleTrackFadeIn`
- Видалити `@Published var singleTrackFadeOut`
- Оновити UI (якщо є слайдери для цих параметрів)

---

### Phase 4: Update Documentation

#### Step 4.1: Update FEATURE_OVERVIEW_v4.0.md
```markdown
// ✅ Confirm this is already correct:
v4.0 Спрощення:
БУЛО: 5 fade параметрів → СТАЛО: 1 crossfadeDuration + fade в методах
```

#### Step 4.2: Update API Examples
```swift
// Example: Stop with fade
await player.stop(fadeDuration: 5.0) // ✅ explicit parameter

// Example: Finish with fade  
await player.finish(fadeDuration: 3.0) // ✅ explicit parameter

// Example: Loop uses crossfadeDuration
let config = PlayerConfiguration(crossfadeDuration: 10.0)
// Loop will use 10s crossfade (or adapted if track short)
```

---

## ✅ Checklist (Step by Step)

### Phase 1: AudioPlayerService.swift
- [ ] 1.1 Delete `setSingleTrackFadeDurations()` method (lines 585-635)
- [ ] 1.2 Rewrite `calculateAdaptedCrossfadeDuration()` (lines 1091-1110)
- [ ] 1.3 Fix `loopCurrentTrackWithFade()` debug log (lines 1209-1211)
- [ ] 1.4 Fix/Delete `stopWithDefaultFade()` (lines 369-370)
- [ ] 1.5 Fix `finish()` (line 380)
- [ ] 1.6 Fix init (lines 88-91)
- [ ] 1.7 Fix setVolume (lines 518-521)
- [ ] 1.8 Fix setRepeatMode (lines 551-554)
- [ ] 1.9 Fix syncConfigurationToPlaylistManager (lines 1348-1351)

### Phase 2: Tests
- [ ] 2.1 Delete tests for removed fields
- [ ] 2.2 Update default values test
- [ ] 2.3 Add new v4.0 tests

### Phase 3: Demo App
- [ ] 3.1 Fix AudioPlayerViewModel configuration
- [ ] 3.2 Remove fade in/out properties from ViewModel
- [ ] 3.3 Update UI if needed

### Phase 4: Documentation
- [ ] 4.1 Verify FEATURE_OVERVIEW
- [ ] 4.2 Update API examples
- [ ] 4.3 Update inline docs

### Phase 5: Verification
- [ ] 5.1 Build project (verify compilation)
- [ ] 5.2 Run tests (verify all pass)
- [ ] 5.3 Manual testing (verify behavior)
- [ ] 5.4 Git commit with clear message

---

## 🔥 Critical Notes

### 1. stopFadeDuration Decision
**Options:**
- **A) Delete stopWithDefaultFade()** - користувач використовує explicit `stop(fadeDuration:)`
- **B) Use crossfadeDuration** - `stop(fadeDuration: configuration.crossfadeDuration)`

**Recommendation:** Option A (видалити) - більш explicit v4.0 API

### 2. Loop Crossfade Logic
**v4.0 behavior:**
- Використовує `crossfadeDuration` для loop
- Адаптує до max 40% track duration
- NO separate fadeIn/fadeOut

### 3. Backward Compatibility
**Breaking changes:**
- ❌ `setSingleTrackFadeDurations()` - DELETED
- ❌ `stopWithDefaultFade()` - DELETE або change default
- ❌ Configuration fields - REMOVED

**Migration for users:**
```swift
// OLD (v3.x):
config.singleTrackFadeInDuration = 2.0
config.singleTrackFadeOutDuration = 3.0
await player.setSingleTrackFadeDurations(fadeIn: 2.0, fadeOut: 3.0)

// NEW (v4.0):
config.crossfadeDuration = 10.0  // ONE parameter for all
await player.stop(fadeDuration: 5.0) // explicit in method
```

---

## ⏱️ Estimated Time

| Phase | Task | Time |
|-------|------|------|
| 1 | AudioPlayerService fixes | 1.5h |
| 2 | Tests update | 0.5h |
| 3 | Demo app update | 0.5h |
| 4 | Documentation | 0.5h |
| 5 | Verification | 1h |
| **Total** | **4 hours** |

---

## 🚀 After Completion

### What Works:
- ✅ v4.0 clean API (ONE crossfadeDuration)
- ✅ Code compiles
- ✅ All tests pass
- ✅ Demo app works
- ✅ Ready for v4.0 release

### Next Steps:
1. Git commit: "refactor: v4.0 - simplify fade configuration to single crossfadeDuration"
2. Update CHANGELOG.md
3. Full integration testing
4. 🚀 Ship v4.0!

---

**Ready to start?** 💪

Рекомендую починати з Phase 1.1 (delete method) - найпростіший крок для розігріву!
