# 🎯 ProsperPlayer v4.0 - FINAL ACTION PLAN

**Created:** 2025-10-12  
**Updated:** With configuration & replacePlaylist fixes  
**Use Case:** Meditation Session Player

---

## 📋 Правильне Розуміння v4.0

### Configuration Flow:
```swift
// ✅ Configuration В КОНСТРУКТОРІ
let config = PlayerConfiguration(crossfadeDuration: 10.0)
let player = AudioPlayerService(configuration: config)

// ✅ Оновлення під час роботи
await player.updateConfiguration(newConfig)
// - Якщо грає → застосується до наступного треку
// - Якщо зупинено → застосується відразу
```

### API Methods:
```swift
// ✅ NO url/config параметри - береться з внутрішнього стану
func startPlaying(fadeDuration: TimeInterval = 0.0) async throws

// ✅ NO crossfadeDuration - береться з configuration
func replacePlaylist(_ tracks: [URL]) async throws
func skipToNext() async throws
func skipToPrevious() async throws

// ✅ Fade параметр ТІЛЬКИ для start/stop
func stop(fadeDuration: TimeInterval = 0.0) async
```

---

## 🚀 PHASE 1: Виправити replacePlaylist()

### Поточний стан (swapPlaylist):
```swift
public func swapPlaylist(
    tracks: [URL],
    crossfadeDuration: TimeInterval = 5.0  // ❌ Зайвий параметр!
) async throws
```

### Що треба:
```swift
public func replacePlaylist(_ tracks: [URL]) async throws {
    // Використовує configuration.crossfadeDuration
    let validDuration = configuration.crossfadeDuration
    // ... rest
}
```

### MCP Commands:

**Step 1: Перевірити поточну сигнатуру**
```javascript
get_symbol_definition({
  path: "Sources/AudioServiceKit/Public/AudioPlayerService.swift",
  symbolName: "swapPlaylist"
})
```

**Step 2: Видалити параметр crossfadeDuration**
```javascript
edit_file({
  path: "Sources/AudioServiceKit/Public/AudioPlayerService.swift",
  edits: [{
    oldText: "public func swapPlaylist(\n        tracks: [URL],\n        crossfadeDuration: TimeInterval = 5.0\n    ) async throws",
    newText: "public func replacePlaylist(_ tracks: [URL]) async throws"
  }],
  dryRun: true
})
```

**Step 3: Замінити validDuration розрахунок**
```javascript
edit_file({
  path: "Sources/AudioServiceKit/Public/AudioPlayerService.swift",
  edits: [{
    oldText: "// Validate and clamp crossfade duration\n        let validDuration = max(1.0, min(30.0, crossfadeDuration))",
    newText: "// Use crossfade duration from configuration\n        let validDuration = configuration.crossfadeDuration"
  }],
  dryRun: true
})
```

---

## 🚀 PHASE 2: Виправити startPlaying()

### Поточний стан:
```swift
public func startPlaying(url: URL, configuration: PlayerConfiguration) async throws
```

### Що треба:
```swift
public func startPlaying(fadeDuration: TimeInterval = 0.0) async throws {
    // URL береться з playlistManager.getCurrentTrack()
    // Configuration вже встановлено в конструкторі/updateConfiguration
    
    guard let url = await playlistManager.getCurrentTrack() else {
        throw AudioPlayerError.noTrackLoaded
    }
    
    // Fade in logic
    if fadeDuration > 0 {
        await audioEngine.setVolume(0.0)
        await audioEngine.startPlaying()
        await audioEngine.fadeVolume(
            from: 0.0, 
            to: configuration.volumeFloat, 
            duration: fadeDuration
        )
    } else {
        await audioEngine.setVolume(configuration.volumeFloat)
        await audioEngine.startPlaying()
    }
    
    // ... rest
}
```

### MCP Commands:

**Step 1: Перевірити поточну реалізацію**
```javascript
get_symbol_definition({
  path: "Sources/AudioServiceKit/Public/AudioPlayerService.swift",
  symbolName: "startPlaying"
})
```

**Step 2: Переписати сигнатуру та тіло**
```javascript
// Це складна зміна - краще зробити через replace_lines
// після аналізу поточного коду
```

---

## 🚀 PHASE 3: Додати skipToNext/Previous

### Перевірити чи є:
```javascript
search_in_file_lines({
  path: "Sources/AudioServiceKit/Public/AudioPlayerService.swift",
  pattern: "func skipToNext|func skipToPrevious",
  useRegex: true,
  limit: 5
})
```

### Якщо НЕМАЄ - додати:

**skipToNext:**
```swift
public func skipToNext() async throws {
    guard let nextURL = await playlistManager.skipToNext() else {
        throw AudioPlayerError.noNextTrack
    }
    // Використовує configuration.crossfadeDuration!
    try await replaceTrack(
        url: nextURL, 
        crossfadeDuration: configuration.crossfadeDuration
    )
}
```

**skipToPrevious:**
```swift
public func skipToPrevious() async throws {
    guard let prevURL = await playlistManager.skipToPrevious() else {
        throw AudioPlayerError.noPreviousTrack
    }
    try await replaceTrack(
        url: prevURL, 
        crossfadeDuration: configuration.crossfadeDuration
    )
}
```

**MCP Command:**
```javascript
insert_lines({
  path: "Sources/AudioServiceKit/Public/AudioPlayerService.swift",
  afterLine: 850,  // Після інших playlist методів
  content: `
    // MARK: - Playlist Navigation
    
    public func skipToNext() async throws {
        guard let nextURL = await playlistManager.skipToNext() else {
            throw AudioPlayerError.noNextTrack
        }
        try await replaceTrack(url: nextURL, crossfadeDuration: configuration.crossfadeDuration)
    }
    
    public func skipToPrevious() async throws {
        guard let prevURL = await playlistManager.skipToPrevious() else {
            throw AudioPlayerError.noPreviousTrack
        }
        try await replaceTrack(url: prevURL, crossfadeDuration: configuration.crossfadeDuration)
    }
  `,
  dryRun: true
})
```

---

## 🚀 PHASE 4: Fix Loop Crossfade

### calculateAdaptedCrossfadeDuration()

**Поточна (WRONG):**
```swift
let configuredFadeIn = configuration.fadeInDuration  // computed ❌
let configuredFadeOut = configuration.crossfadeDuration * 0.7
```

**Виправити:**
```swift
let configuredCrossfade = configuration.crossfadeDuration
let maxCrossfade = trackDuration * 0.4
let adaptedCrossfade = min(configuredCrossfade, maxCrossfade)
return adaptedCrossfade
```

**MCP Command:**
```javascript
replace_lines({
  path: "Sources/AudioServiceKit/Public/AudioPlayerService.swift",
  startLine: 1092,
  endLine: 1110,
  newContent: `    private func calculateAdaptedCrossfadeDuration(trackDuration: TimeInterval) -> TimeInterval {
        // v4.0: Use full crossfadeDuration for loop
        let configuredCrossfade = configuration.crossfadeDuration
        let maxCrossfade = trackDuration * 0.4
        let adaptedCrossfade = min(configuredCrossfade, maxCrossfade)
        
        Self.logger.debug("Adapted loop crossfade: configured=\\(configuredCrossfade)s, track=\\(trackDuration)s, adapted=\\(adaptedCrossfade)s")
        
        return adaptedCrossfade
    }`,
  dryRun: true
})
```

### loopCurrentTrackWithFade() log

**MCP Command:**
```javascript
edit_file({
  path: "Sources/AudioServiceKit/Public/AudioPlayerService.swift",
  edits: [{
    oldText: "let configuredFadeIn = configuration.fadeInDuration\n        let configuredFadeOut = configuration.crossfadeDuration * 0.7\n        Self.logger.info(\"[LOOP_CROSSFADE] Starting loop crossfade: track=\\(trackDuration)s, configured=(\\(configuredFadeIn)s,\\(configuredFadeOut)s), adapted=\\(crossfadeDuration)s\")",
    newText: "let configuredCrossfade = configuration.crossfadeDuration\n        Self.logger.info(\"[LOOP_CROSSFADE] Starting loop crossfade: track=\\(trackDuration)s, configured=\\(configuredCrossfade)s, adapted=\\(crossfadeDuration)s\")"
  }],
  dryRun: true
})
```

---

## 🚀 PHASE 5: Verify & Test

### Step 1: Git Status
```javascript
git_status()
```

### Step 2: Review Changes
```javascript
git_diff({ 
  file: "Sources/AudioServiceKit/Public/AudioPlayerService.swift",
  preview: true,
  maxLines: 200
})
```

### Step 3: Build & Test
```bash
swift build
swift test
```

### Step 4: Commit
```javascript
git_add({ 
  files: [
    "Sources/AudioServiceKit/Public/AudioPlayerService.swift",
    "FEATURE_OVERVIEW_v4.0.md"
  ] 
})

git_commit({ 
  message: "feat: v4.0 API - config in constructor, replacePlaylist without crossfadeDuration param, fix loop crossfade" 
})
```

---

## 📝 Execution Order

**Start Here:**

### 1. PHASE 1: replacePlaylist (найпростіше)
- [ ] Check swapPlaylist signature
- [ ] Remove crossfadeDuration parameter
- [ ] Use configuration.crossfadeDuration
- [ ] Verify & test

### 2. PHASE 3: Add skipToNext/Previous
- [ ] Check if exists
- [ ] Add if missing
- [ ] Use configuration.crossfadeDuration

### 3. PHASE 4: Fix Loop Crossfade  
- [ ] Fix calculateAdaptedCrossfadeDuration
- [ ] Fix loopCurrentTrackWithFade log

### 4. PHASE 2: startPlaying (найскладніше - в кінці!)
- [ ] Analyze current implementation
- [ ] Rewrite signature
- [ ] Get URL from playlistManager
- [ ] Add fade in logic
- [ ] Test thoroughly

### 5. PHASE 5: Final verification
- [ ] Build успішний
- [ ] Tests проходять
- [ ] Git commit

---

## ✅ Success Criteria

- [ ] `replacePlaylist(_ tracks: [URL])` БЕЗ crossfadeDuration
- [ ] `skipToNext()` / `skipToPrevious()` існують
- [ ] Loop використовує повний crossfadeDuration
- [ ] `startPlaying(fadeDuration:)` БЕЗ url/config
- [ ] Configuration в конструкторі + updateConfiguration метод
- [ ] Код компілюється
- [ ] Тести проходять
- [ ] FEATURE_OVERVIEW виправлено ✅

---

## 🎯 Key Points

### Configuration:
- ✅ В конструкторі: `AudioPlayerService(configuration:)`
- ✅ Оновлення: `updateConfiguration(_:)` 
- ✅ Застосування: наступний трек (якщо грає) або відразу (якщо стоп)

### Crossfade:
- ✅ З configuration: replacePlaylist, skipToNext, loop
- ✅ Параметр методу: НЕ використовується для playlist операцій

### Fade:
- ✅ Параметр методу: startPlaying, stop
- ✅ Різниця: fade = one player volume, crossfade = dual player overlap

---

**Ready to start?**  
Скажи "go" і починаємо з PHASE 1! 🚀
