# 🚀 PHASE 2 - ФІНАЛЬНИЙ ПЛАН (v4.0)

**Created:** 2025-10-12  
**Status:** Ready to execute  
**Goal:** v4.0 API - immutable config, Float volume, startPlaying(fadeDuration:)

---

## 📋 Зміни:

1. ✅ **PlayerConfiguration** - immutable (`let`) + Float volume
2. ✅ **Видалити fadeInDuration** computed property
3. ✅ **Видалити v3 API** (startPlayingTrack, loadPlaylist з config)
4. ✅ **Новий startPlaying(fadeDuration:)** API
5. ✅ **pendingFadeInDuration** механізм
6. ✅ **Crossfade Spotify-style** (100% + 100%)
7. ✅ **Документація**

---

## 🎯 Ключові рішення:

### Crossfade = Spotify-style (100% + 100%)
```
Crossfade 10s:
- Track 1 fade OUT: 10s (100%)
- Track 2 fade IN:  10s (100%)
- Overlap:          10s

НЕ 30% і 70%! ОБА по crossfadeDuration!
```

### Volume = Float (0.0-1.0)
```swift
// ✅ v4.0
public let volume: Float  // 0.0-1.0 (AVFoundation standard)

// ❌ v3 (old)
public var volume: Int  // 0-100
public var volumeFloat: Float { Float(volume) / 100.0 }
```

### Configuration = Immutable
```swift
// ✅ v4.0 - immutable
public let crossfadeDuration: TimeInterval
public let volume: Float

// ❌ v3 - mutable (можна змінити в будь-який момент)
public var crossfadeDuration: TimeInterval
```

### startPlaying = без url/config параметрів
```swift
// ✅ v4.0
public func startPlaying(fadeDuration: TimeInterval = 0.0) async throws

// ❌ v3
public func startPlaying(url: URL, configuration: PlayerConfiguration) async throws
```

### pendingFadeInDuration = БЕЗ багів
```
Чому працює коректно:
- startPlayingTrack ВИДАЛЕНО (був джерело багів)
- Тільки startPlaying встановлює pendingFadeInDuration
- startEngine читає і очищує одразу
- Crossfade НЕ використовує fadeIn для loop (uses crossfadeDuration)
```

---

## 📝 Крок 1: PlayerConfiguration - immutable + Float volume

**Файл:** `Sources/AudioServiceCore/PlayerConfiguration.swift`

### 1.1 Видалити fadeInDuration (lines 76-79)

```javascript
delete_lines({
  path: "Sources/AudioServiceCore/PlayerConfiguration.swift",
  startLine: 74,
  endLine: 79,
  dryRun: true
})
```

### 1.2 Змінити всі `var` на `let`

```javascript
edit_file({
  path: "Sources/AudioServiceCore/PlayerConfiguration.swift",
  edits: [
    {
      oldText: "    public var crossfadeDuration: TimeInterval",
      newText: "    public let crossfadeDuration: TimeInterval"
    },
    {
      oldText: "    public var fadeCurve: FadeCurve",
      newText: "    public let fadeCurve: FadeCurve"
    },
    {
      oldText: "    public var repeatMode: RepeatMode",
      newText: "    public let repeatMode: RepeatMode"
    },
    {
      oldText: "    public var mixWithOthers: Bool",
      newText: "    public let mixWithOthers: Bool"
    }
  ],
  dryRun: true
})
```

### 1.3 Змінити volume: Int → Float

```javascript
edit_file({
  path: "Sources/AudioServiceCore/PlayerConfiguration.swift",
  edits: [
    {
      oldText: "    /// Volume level (0-100, where 100 is maximum)\n    /// Internally converted to Float 0.0-1.0\n    public var volume: Int",
      newText: "    /// Volume level (0.0 = silent, 1.0 = maximum)\n    /// Standard AVFoundation audio range\n    public let volume: Float"
    }
  ],
  dryRun: true
})
```

### 1.4 Видалити volumeFloat computed property (lines 81-84)

```javascript
delete_lines({
  path: "Sources/AudioServiceCore/PlayerConfiguration.swift",
  startLine: 81,
  endLine: 84,
  dryRun: true
})
```

### 1.5 Оновити init

```javascript
edit_file({
  path: "Sources/AudioServiceCore/PlayerConfiguration.swift",
  edits: [
    {
      oldText: "        crossfadeDuration: TimeInterval = 10.0,\n        fadeCurve: FadeCurve = .equalPower,\n        repeatMode: RepeatMode = .off,\n        volume: Int = 80,\n        mixWithOthers: Bool = false",
      newText: "        crossfadeDuration: TimeInterval = 10.0,\n        fadeCurve: FadeCurve = .equalPower,\n        repeatMode: RepeatMode = .off,\n        volume: Float = 0.8,\n        mixWithOthers: Bool = false"
    }
  ],
  dryRun: true
})
```

### 1.6 Оновити validation

```javascript
edit_file({
  path: "Sources/AudioServiceCore/PlayerConfiguration.swift",
  edits: [
    {
      oldText: "        // Volume range check\n        guard volume >= 0 && volume <= 100 else {\n            throw ConfigurationError.invalidVolume(volume)\n        }",
      newText: "        // Volume range check\n        guard volume >= 0.0 && volume <= 1.0 else {\n            throw ConfigurationError.invalidVolume(volume)\n        }"
    }
  ],
  dryRun: true
})
```

### 1.7 Оновити ConfigurationError

```javascript
edit_file({
  path: "Sources/AudioServiceCore/PlayerConfiguration.swift",
  edits: [
    {
      oldText: "    case invalidVolume(Int)",
      newText: "    case invalidVolume(Float)"
    },
    {
      oldText: "        case .invalidVolume(let volume):\n            return \"Invalid volume: \\(volume). Must be between 0 and 100.\"",
      newText: "        case .invalidVolume(let volume):\n            return \"Invalid volume: \\(volume). Must be between 0.0 and 1.0.\""
    }
  ],
  dryRun: true
})
```

### 1.8 Додати crossfade документацію

```javascript
edit_file({
  path: "Sources/AudioServiceCore/PlayerConfiguration.swift",
  edits: [
    {
      oldText: "    /// Duration of crossfade transitions between tracks (1.0-30.0 seconds)\n    /// This value is used for:\n    /// - Auto-advance: Full crossfade at track end\n    /// - Manual switch: Adaptive based on remaining time\n    /// - Track start: fadeIn = crossfadeDuration * 0.3\n    public let crossfadeDuration: TimeInterval",
      newText: "    /// Crossfade duration between tracks (Spotify-style)\n    /// \n    /// Both tracks fade simultaneously over the full duration:\n    /// - Outgoing track: fade OUT from 1.0 to 0.0 over `crossfadeDuration`\n    /// - Incoming track: fade IN from 0.0 to 1.0 over `crossfadeDuration`\n    /// - Total overlap: equals `crossfadeDuration`\n    /// \n    /// Valid range: 1.0-30.0 seconds\n    public let crossfadeDuration: TimeInterval"
    }
  ],
  dryRun: true
})
```

---

## 📝 Крок 2: Видалити v3 API (застарілі методи)

**Файл:** `Sources/AudioServiceKit/Playlist/AudioPlayerService+Playlist.swift`

### 2.1 Видалити loadPlaylist з configuration параметром

```javascript
search_in_file_lines({
  path: "Sources/AudioServiceKit/Playlist/AudioPlayerService+Playlist.swift",
  pattern: "public func loadPlaylist",
  limit: 5
})
// Знайти точні номери рядків, потім:
delete_lines({
  path: "Sources/AudioServiceKit/Playlist/AudioPlayerService+Playlist.swift",
  startLine: 18, // TODO: уточнити після search
  endLine: 53,   // TODO: уточнити після search
  dryRun: true
})
```

### 2.2 Видалити startPlayingTrack

```javascript
delete_lines({
  path: "Sources/AudioServiceKit/Playlist/AudioPlayerService+Playlist.swift",
  startLine: 187, // TODO: уточнити
  endLine: 215,   // TODO: уточнити
  dryRun: true
})
```

---

## 📝 Крок 3: Новий startPlaying API

**Файл:** `Sources/AudioServiceKit/Public/AudioPlayerService.swift`

### 3.1 Додати pendingFadeInDuration (після line 53)

```javascript
insert_lines({
  path: "Sources/AudioServiceKit/Public/AudioPlayerService.swift",
  afterLine: 53,
  content: `
    /// Pending fade-in duration for next startPlaying call
    /// Allows per-call fade-in override without changing configuration
    private var pendingFadeInDuration: TimeInterval?`,
  dryRun: true
})
```

### 3.2 Переписати startPlaying (lines 141-186)

```javascript
replace_lines({
  path: "Sources/AudioServiceKit/Public/AudioPlayerService.swift",
  startLine: 141,
  endLine: 186,
  newContent: `    /// Start playback with optional fade-in
    ///
    /// Plays the current track from playlist with configurable fade-in.
    /// Uses track from \`playlistManager.getCurrentTrack()\`.
    ///
    /// - Parameter fadeDuration: Fade-in duration in seconds (0.0 = no fade, instant start)
    /// - Throws:
    ///   - \`AudioPlayerError.noTrackLoaded\` if playlist is empty
    ///   - \`AudioPlayerError.invalidState\` if cannot transition to playing
    ///   - \`AudioPlayerError.fileNotFound\` if track file doesn't exist
    ///
    /// - Note: Configuration must be set via initializer or \`updateConfiguration()\`
    /// - Note: fadeDuration is independent from crossfade between tracks
    public func startPlaying(fadeDuration: TimeInterval = 0.0) async throws {
        // Get current track from playlist
        guard let url = await playlistManager.getCurrentTrack() else {
            throw AudioPlayerError.noTrackLoaded
        }
        
        // Store fade-in duration for startEngine()
        pendingFadeInDuration = fadeDuration > 0 ? fadeDuration : nil
        
        // Validate configuration
        try configuration.validate()
        
        // Sync configuration with playlist manager
        await syncConfigurationToPlaylistManager()
        
        // Reset loop tracking
        self.currentTrackURL = url
        self.currentRepeatCount = 0
        self.isLoopCrossfadeInProgress = false
        self.isTrackReplacementInProgress = false
        
        // Configure audio session
        try await sessionManager.configure(mixWithOthers: configuration.mixWithOthers)
        try await sessionManager.activate()
        
        // Prepare audio engine
        try await audioEngine.prepare()
        
        // Load audio file
        let trackInfo = try await audioEngine.loadAudioFile(url: url)
        self.currentTrack = trackInfo
        
        // Enter preparing state
        let success = await stateMachine.enterPreparing()
        Logger.state.assertTransition(
            success,
            from: state.description,
            to: "preparing"
        )
        
        guard success else {
            throw AudioPlayerError.invalidState(
                current: state.description,
                attempted: "start playing"
            )
        }
        
        // Update now playing info
        await updateNowPlayingInfo()
        
        // Start playback timer
        startPlaybackTimer()
    }`,
  dryRun: true
})
```

### 3.3 Оновити startEngine() (lines 1513-1520)

```javascript
replace_lines({
  path: "Sources/AudioServiceKit/Public/AudioPlayerService.swift",
  startLine: 1513,
  endLine: 1520,
  newContent: `    func startEngine() async throws {
        try await audioEngine.start()
        
        // Use pending fade-in if set, otherwise no fade (instant start)
        let fadeInDuration = pendingFadeInDuration ?? 0.0
        let shouldFadeIn = fadeInDuration > 0
        
        await audioEngine.scheduleFile(
            fadeIn: shouldFadeIn,
            fadeInDuration: fadeInDuration,
            fadeCurve: configuration.fadeCurve
        )
        
        // Clear pending fade after use
        pendingFadeInDuration = nil
    }`,
  dryRun: true
})
```

---

## 📝 Крок 4: Замінити volumeFloat на volume

```javascript
bulk_replace_in_files({
  files: [
    "Sources/AudioServiceKit/Public/AudioPlayerService.swift",
    "Sources/AudioServiceKit/Internal/AudioEngineActor.swift"
  ],
  pattern: "configuration.volumeFloat",
  replacement: "configuration.volume",
  useRegex: false,
  dryRun: true
})
```

---

## 📝 Крок 5: Оновити crossfade логіку (Spotify-style)

### 5.1 Знайти всі місця з fadeIn/fadeOut у crossfade

```javascript
search_code({
  pattern: "fadeInDuration|fadeOutDuration",
  extensions: [".swift"],
  limit: 50
})
```

### 5.2 Замінити на правильну логіку

Для кожного crossfade місця:

```swift
// ❌ Видалити:
let fadeIn = configuration.fadeInDuration
let fadeOut = configuration.fadeOutDuration

// ✅ Додати:
// Spotify-style crossfade: both tracks fade over full duration
let crossfade = configuration.crossfadeDuration
await oldTrack.fadeVolume(to: 0.0, duration: crossfade)
await newTrack.fadeVolume(to: 1.0, duration: crossfade)
```

---

## 📝 Крок 6: Git commit

```javascript
git_add({ files: [
  "Sources/AudioServiceCore/PlayerConfiguration.swift",
  "Sources/AudioServiceKit/Public/AudioPlayerService.swift",
  "Sources/AudioServiceKit/Playlist/AudioPlayerService+Playlist.swift"
]})

git_commit({ message: "Phase 2: v4.0 API - immutable config, Float volume, startPlaying(fadeDuration:)" })
```

---

## 🎯 Очікувані результати:

✅ `PlayerConfiguration` - immutable (`let`)  
✅ `volume: Float` (0.0-1.0)  
✅ `fadeInDuration` - видалено  
✅ v3 API (`loadPlaylist(config:)`, `startPlayingTrack`) - видалено  
✅ `startPlaying(fadeDuration:)` - новий API  
✅ `pendingFadeInDuration` - працює коректно (без startPlayingTrack)  
✅ Crossfade - Spotify-style (100% + 100%)  
✅ Документація оновлена  

---

## 🔥 Критичні моменти:

1. **Crossfade ≠ fadeIn!** 
   - Crossfade = 100% overlap між двома треками
   - fadeIn = холодний старт одного треку

2. **pendingFadeInDuration безпечний** бо:
   - startPlayingTrack видалено (був джерело багів)
   - Тільки startPlaying() встановлює
   - startEngine() читає і очищує одразу

3. **Immutable config** = безпека:
   - Не можна випадково змінити під час playback
   - Щоб змінити - тільки через updateConfiguration()

4. **Float volume** = стандарт AVFoundation:
   - 0.0-1.0 (не 0-100)
   - Без конверсії при кожному виклику
