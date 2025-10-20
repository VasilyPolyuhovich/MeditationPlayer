# План рефакторингу: SoundEffectsPlayerActor → Nodes-based Architecture

**Дата:** 2025-10-20
**Мета:** Усунути окремий AVAudioEngine в SoundEffectsPlayerActor, використовувати nodes основного engine

---

## 📋 PHASE 1: Аналіз поточного стану

### Поточна архітектура SoundEffectsPlayerActor:
```swift
actor SoundEffectsPlayerActor {
    private let audioEngine: AVAudioEngine       // ❌ Окремий engine
    private let playerNode: AVAudioPlayerNode    // Внутрішня нода
    private let mixerNode: AVAudioMixerNode      // Внутрішній мікшер

    init() {
        audioEngine = AVAudioEngine()            // Створює engine
        audioEngine.attach(playerNode)           // Attach nodes
        audioEngine.connect(...)                 // Connect graph
        try audioEngine.start()                  // ❌ Стартує окремий engine!
    }
}
```

### Цільова архітектура (як Overlay):
```swift
actor SoundEffectsPlayerActor {
    private let player: AVAudioPlayerNode        // ✅ Отримує node ззовні
    private let mixer: AVAudioMixerNode          // ✅ З AudioEngineActor

    init(player: AVAudioPlayerNode, mixer: AVAudioMixerNode) {
        self.player = player                     // Використовує передані nodes
        self.mixer = mixer                       // Без власного engine!
    }
}
```

### Проблеми поточної архітектури:

1. **Audio Session конфлікт:**
   - `AudioSessionManager` налаштовує session для основного engine
   - `SoundEffectsPlayerActor.audioEngine.start()` може переналаштувати session
   - Потенційні конфлікти з категорією/опціями

2. **Архітектурна непослідовність:**
   - Overlay використовує ноди основного engine
   - Sound Effects - окремий engine
   - Різна архітектура для схожих задач

3. **Ресурси:**
   - Два окремих `AVAudioEngine` = подвійне споживання ресурсів

---

## 🎯 PHASE 2: Детальний план рефакторингу

### Крок 1: Додати nodes в AudioEngineActor
**Файл:** `Sources/AudioServiceKit/Internal/AudioEngineActor.swift`

**Зміни:**
```swift
// Існуючі:
// playerNodeA, playerNodeB → Main crossfade
// playerNodeC, mixerNodeC → Overlay

// Додати:
private nonisolated(unsafe) let playerNodeD: AVAudioPlayerNode  // ✅ Sound Effects
private nonisolated(unsafe) let mixerNodeD: AVAudioMixerNode    // ✅ Sound Effects
```

**Локація змін:**
- Поля: ~рядок 21 (після playerNodeC/mixerNodeC)
- `init()`: Створити nodes D (~рядок 74)
- `setupAudioGraph()`: Attach nodes D (~рядок 92)
- `setupAudioGraph()`: Connect nodes D → mainMixer (~рядок 110)

---

### Крок 2: Рефакторинг SoundEffectsPlayerActor (конструктор)
**Файл:** `Sources/AudioServiceKit/Internal/SoundEffectsPlayerActor.swift`

**Було:**
```swift
init(cacheLimit: Int = 10) {
    self.cacheLimit = cacheLimit
    self.audioEngine = AVAudioEngine()
    self.playerNode = AVAudioPlayerNode()
    self.mixerNode = AVAudioMixerNode()
    // Setup graph...
    try audioEngine.start()  // ❌
}
```

**Стає:**
```swift
init(
    player: AVAudioPlayerNode,
    mixer: AVAudioMixerNode,
    cacheLimit: Int = 10
) {
    self.cacheLimit = cacheLimit
    self.player = player     // ✅ Отримує ззовні
    self.mixer = mixer       // ✅ Отримує ззовні
    // Видалити: audioEngine setup
    // Видалити: audioEngine.start()
}
```

---

### Крок 3: Оновити AudioPlayerService (створення SoundEffectsPlayer)
**Файл:** `Sources/AudioServiceKit/Public/AudioPlayerService.swift`

**Поточний код (рядок ~142):**
```swift
public init(configuration: PlayerConfiguration = PlayerConfiguration()) {
    // ...
    self.soundEffectsPlayer = SoundEffectsPlayerActor()  // ❌ Без параметрів
}
```

**Проблема:** Nodes ще не існують в `init()`, вони створюються в `setup()` → `audioEngine.setup()`!

**Рішення:** Створити nodes в AudioEngineActor.init() (БЕЗ старту engine)

---

## ⚠️ PHASE 3: Вирішення проблеми ініціалізації

### Опція C: Створити nodes в AudioEngineActor.init() (без setup)
**Це найкраще рішення!**

```swift
actor AudioEngineActor {
    init() {
        // 1. Створити engine
        self.engine = AVAudioEngine()

        // 2. Створити всі nodes
        self.playerNodeA = AVAudioPlayerNode()
        // ... B, C, D

        // 3. Attach та connect (не потребує audio session!)
        setupAudioGraph()  // ✅ Безпечно БЕЗ активації session

        // 4. НЕ стартувати engine тут!
        // engine.start() → буде в setup()
    }

    internal func setup() async {
        // Стартувати engine ПІСЛЯ активації session
        try? engine.start()
        isEngineRunning = true
    }
}
```

**Чому це працює:**
- ✅ Nodes створені в `init()`
- ✅ Graph підключений в `init()`
- ✅ Engine стартує ТІЛЬКИ після session activation
- ✅ `soundEffectsPlayer` може створитись в `AudioPlayerService.init()`

---

## 📝 PHASE 4: Покроковий план виконання

### Крок 1: Рефакторинг AudioEngineActor
- [x] 1.1. Додати `playerNodeD`, `mixerNodeD` (поля)
- [x] 1.2. Створити nodes в `init()`
- [x] 1.3. Attach в `setupAudioGraph()`
- [x] 1.4. Connect в `setupAudioGraph()`
- [x] 1.5. Додати `createSoundEffectsPlayer()` метод (замість getter)

### Крок 2: Перевірити, коли викликається `engine.start()`
- [x] 2.1. Знайти всі виклики `engine.start()`
- [x] 2.2. Переконатись, що він викликається ТІЛЬКИ в `setup()` після session activation

### Крок 3: Рефакторинг SoundEffectsPlayerActor
- [x] 3.1. Змінити конструктор: приймати `player`, `mixer`
- [x] 3.2. Видалити поля: `audioEngine`
- [x] 3.3. Перейменувати: `playerNode` → `player`, `mixerNode` → `mixer`
- [x] 3.4. Видалити: graph setup, `engine.start()`
- [x] 3.5. Оновити всі методи (використовувати `player`/`mixer`)

### Крок 4: Оновити AudioPlayerService
- [x] 4.1. Перетворити `init()` на async
- [x] 4.2. Створити SoundEffectsPlayer через `audioEngine.createSoundEffectsPlayer()`
- [x] 4.3. Викликати `setup()` одразу в async init
- [x] 4.4. Видалити `ensureSetup()` з усіх методів (7 викликів)

### Крок 5: Оновити Demo App
- [x] 5.1. Оновити ProsperPlayerDemoApp для async init
- [x] 5.2. Видалити @State для audioService
- [x] 5.3. Створювати audioService в .task блоці

### Крок 6: Тестування
- [x] 6.1. Build AudioServiceKit framework ✅
- [x] 6.2. Build ProsperPlayerDemo app ✅
- [ ] 6.3. Перевірити sound effects playback (runtime)
- [ ] 6.4. Перевірити LRU cache (runtime)
- [ ] 6.5. Перевірити master volume (runtime)
- [ ] 6.6. Перевірити, що немає audio session конфліктів (runtime)

---

## 🚨 PHASE 5: Потенційні ризики

1. **Nodes не готові в init():**
   - ✅ Вирішено: створюємо nodes в `AudioEngineActor.init()`

2. **Engine.start() викликається рано:**
   - ⚠️ Перевірити: start ТІЛЬКИ в `setup()` після session

3. **Concurrency проблеми (nonisolated unsafe):**
   - ✅ Nodes створюються раз, передаються в actor
   - ✅ Actor ізолює доступ

4. **Breaking changes API:**
   - ⚠️ `SoundEffectsPlayerActor.init()` змінює сигнатуру
   - ✅ Це internal API, не публічний

---

## ✅ PHASE 6: Чеклист перед виконанням

- [ ] Переконатись, що `AudioEngineActor.init()` НЕ викликає `engine.start()`
- [ ] Переконатись, що nodes можна створити БЕЗ активного audio session
- [ ] Переконатись, що `SoundEffectsPlayerActor` не має публічного API (тільки через `AudioPlayerService`)
- [ ] Створити backup поточного коду (git commit)
- [ ] Підготувати rollback plan

---

## 📊 Підсумок змін

| Компонент | Було | Стає |
|-----------|------|------|
| **AudioEngineActor** | 3 пари nodes (A, B, C) | 4 пари nodes (A, B, C, D) |
| **SoundEffectsPlayerActor** | Власний AVAudioEngine | Використовує nodes ззовні |
| **AudioPlayerService.init()** | Створює `SoundEffectsPlayerActor()` | Передає nodes від `audioEngine` |
| **Audio Session** | 2 окремих engines | 1 shared engine ✅ |

---

## 🔄 Хід робіт

### 2025-10-20 - Початок рефакторингу
- ✅ План створено
- ✅ Файл збережено
- ✅ Рефакторинг виконано

---

## ✅ PHASE 7: Результати виконання (2025-10-20)

### 🎯 Виконані зміни:

#### 1. AudioEngineActor (Sources/AudioServiceKit/Internal/AudioEngineActor.swift)

**Додано поля для Sound Effects (рядок ~21):**
```swift
internal nonisolated(unsafe) let playerNodeD: AVAudioPlayerNode
internal nonisolated(unsafe) let mixerNodeD: AVAudioMixerNode
```

**Створення nodes в init() (рядок ~74):**
```swift
self.playerNodeD = AVAudioPlayerNode()
self.mixerNodeD = AVAudioMixerNode()
```

**Attach в setupAudioGraph() (рядок ~92):**
```swift
engine.attach(playerNodeD)
engine.attach(mixerNodeD)
```

**Connect в setupAudioGraph() (рядок ~110):**
```swift
engine.connect(playerNodeD, to: mixerNodeD, format: format)
engine.connect(mixerNodeD, to: engine.mainMixerNode, format: format)
```

**Додано метод createSoundEffectsPlayer() (рядок ~1405):**
```swift
func createSoundEffectsPlayer(cacheLimit: Int = 10) -> SoundEffectsPlayerActor {
    return SoundEffectsPlayerActor(
        player: playerNodeD,
        mixer: mixerNodeD,
        cacheLimit: cacheLimit
    )
}
```

#### 2. SoundEffectsPlayerActor (Sources/AudioServiceKit/Internal/SoundEffectsPlayerActor.swift)

**Видалено окремий AVAudioEngine:**
```swift
// ВИДАЛЕНО:
// private nonisolated(unsafe) let audioEngine: AVAudioEngine
// private nonisolated(unsafe) let playerNode: AVAudioPlayerNode
// private nonisolated(unsafe) let mixerNode: AVAudioMixerNode

// ДОДАНО:
private nonisolated(unsafe) let player: AVAudioPlayerNode
private nonisolated(unsafe) let mixer: AVAudioMixerNode
```

**Новий конструктор:**
```swift
init(
    player: AVAudioPlayerNode,
    mixer: AVAudioMixerNode,
    cacheLimit: Int = 10
) {
    self.player = player
    self.mixer = mixer
    self.cacheLimit = cacheLimit
    mixer.volume = 0.0
}
```

**Видалено:**
- Setup audio graph коду
- `audioEngine.start()` виклики
- Власний AVAudioEngine

**Оновлено всі методи:**
- Всі `playerNode` → `player`
- Всі `mixerNode` → `mixer`

#### 3. AudioPlayerService (Sources/AudioServiceKit/Public/AudioPlayerService.swift)

**Перетворено init() на async (рядок 154):**
```swift
public init(configuration: PlayerConfiguration = PlayerConfiguration()) async {
    self._state = .finished
    self.configuration = configuration
    self.audioEngine = AudioEngineActor()
    self.sessionManager = AudioSessionManager.shared
    self.playlistManager = PlaylistManager(configuration: configuration)
    
    // ✅ Створення через метод actor (вирішує Sendable проблему)
    self.soundEffectsPlayer = await audioEngine.createSoundEffectsPlayer()
    
    // ✅ Setup викликається ОДРАЗУ
    await setup()
}
```

**Видалено:**
- Метод `ensureSetup()` повністю
- 7 викликів `await ensureSetup()` з методів:
  - `loadPlaylist()`
  - `startPlaying()`
  - `play()`
  - `pause()`
  - `resume()`
  - `setSoundEffectsVolume()`
  - `preloadSoundEffects()`

#### 4. ProsperPlayerDemoApp (Examples/ProsperPlayerDemo/ProsperPlayerDemo/App/ProsperPlayerDemoApp.swift)

**Оновлено для async init:**
```swift
// БУЛО:
@State private var audioService = AudioPlayerService()
@State private var viewModel: PlayerViewModel?

var body: some View {
    // ...
}
.task {
    viewModel = await PlayerViewModel(audioService: audioService)
}

// СТАЛО:
@State private var viewModel: PlayerViewModel?

var body: some View {
    // ...
}
.task {
    let audioService = await AudioPlayerService()  // ✅ async init
    viewModel = await PlayerViewModel(audioService: audioService)
}
```

---

### 🚧 Вирішена проблема: Swift 6 Sendable Concurrency

**Проблема:**
При спробі створити `SoundEffectsPlayerActor` в `AudioPlayerService.init()` отримували помилку:
```
error: non-sendable type 'AVAudioPlayerNode' of property 'playerNodeD' cannot exit nonisolated(unsafe) context
error: non-sendable type 'AVAudioMixerNode' of property 'mixerNodeD' cannot exit nonisolated(unsafe) context
```

**Спроби вирішення:**
1. ❌ **Спроба 1:** Створити nonisolated getter методи
   - Не працює: Swift 6 блокує повернення non-Sendable типів

2. ❌ **Спроба 2:** Прямий доступ до `audioEngine.playerNodeD/mixerNodeD` в async init
   - Не працює: Той самий Sendable error при crossing actor boundaries

3. ✅ **Рішення:** Створити метод `createSoundEffectsPlayer()` всередині `AudioEngineActor`
   - Працює! Nodes створюються в тому самому actor context
   - Паттерн скопійовано з `OverlayPlayerActor`
   - Виклик: `await audioEngine.createSoundEffectsPlayer()`

**Чому це працює:**
- Метод викликається ВСЕРЕДИНІ `AudioEngineActor` (actor-isolated context)
- Nodes доступні без crossing actor boundaries
- `SoundEffectsPlayerActor` створюється і повертається як Sendable actor
- Swift 6 дозволяє передавати actors між isolation domains

---

### 📊 Результати тестування

**Build статус:**
- ✅ AudioServiceKit framework: **BUILD SUCCEEDED**
- ✅ ProsperPlayerDemo app: **BUILD SUCCEEDED**

**Warnings:** Тільки compilation warnings (unused await, try), не критичні

**Runtime testing:** Очікується наступним етапом

---

### 🎉 Підсумок

**Досягнуто:**
1. ✅ Усунуто окремий AVAudioEngine в SoundEffectsPlayerActor
2. ✅ SoundEffectsPlayerActor тепер використовує nodes основного engine (як Overlay)
3. ✅ Усунуто потенційні Audio Session конфлікти
4. ✅ Єдиний shared AVAudioEngine для всієї системи
5. ✅ AudioPlayerService.init() тепер async з immediate setup
6. ✅ Усунуто lazy initialization pattern (ensureSetup видалено)
7. ✅ Вирішено Swift 6 Sendable concurrency issues
8. ✅ Архітектурна консистентність (Overlay + SoundEffects = однаковий паттерн)

**Наступні кроки:**
1. [x] Runtime тестування на симуляторі - ✅ працює, але тихо
2. [x] Commit змін - ✅ v4.1.3 створено
3. [x] Виявлено проблему: звук грає через ear speaker замість loudspeaker
4. [x] Застосувати зміни до Prosper app - ✅ виконано

---

## ✅ PHASE 8: Виправлення Audio Routing + Throwing Init (v4.1.4)

### 📅 Дата: 2025-10-20 (продовження)

### 🐛 Проблема 1: Тихий звук (ear speaker замість loudspeaker)

**Симптоми:**
- Звук грає, але ледве чутний
- З `.playAndRecord` категорією iOS використовує ear speaker (для дзвінків)
- Потрібен loudspeaker (для музики)

**Діагностика:**
```swift
// PlayerConfiguration.swift - було:
public static let defaultAudioSessionOptions: [AVAudioSession.CategoryOptions] = [
    .mixWithOthers,
    .allowBluetoothA2DP,
    .allowAirPlay
    // ❌ Відсутня .defaultToSpeaker опція!
]
```

**Рішення:**
```swift
public static let defaultAudioSessionOptions: [AVAudioSession.CategoryOptions] = [
    .mixWithOthers,
    .allowBluetoothA2DP,
    .allowAirPlay,
    .defaultToSpeaker    // ✅ Використовує loudspeaker для .playAndRecord
]
```

**Файл:** `Sources/AudioServiceCore/PlayerConfiguration.swift` (lines 44-49)

---

### 🐛 Проблема 2: Неправильний error case

**Помилка компіляції:**
```
Type 'AudioPlayerError' has no member 'engineSetupFailed'
```

**Рішення:**
```swift
// AudioEngineActor.swift:113
// БУЛО:
throw AudioPlayerError.engineSetupFailed(reason: "Failed to create stereo audio format")

// СТАЛО:
throw AudioPlayerError.engineStartFailed(reason: "Failed to create stereo audio format")
```

**Файл:** `Sources/AudioServiceKit/Internal/AudioEngineActor.swift` (line 113)

---

### 🏗️ Проблема 3: Відсутність error propagation

**До рефакторингу:**
- `AudioEngineActor.setup()` - не throws
- `AudioPlayerService.setup()` - не throws  
- `AudioPlayerService.init()` - не throws
- Помилки створення stereo format **ігноруються**!

**Після рефакторингу:**
```swift
// AudioEngineActor.swift
func setup() throws {              // ✅ throws додано
    try setupAudioGraph()          // ✅ propagates errors
}

private func setupAudioGraph() throws {  // ✅ throws додано
    // ...
    guard let format = AVAudioFormat(...) else {
        throw AudioPlayerError.engineStartFailed(...)  // ✅ error thrown
    }
}

// AudioPlayerService.swift
internal func setup() async throws {    // ✅ throws додано
    // ...
    try await audioEngine.setup()       // ✅ propagates errors
}

public init(...) async throws {         // ✅ throws додано
    // ...
    try await setup()                    // ✅ propagates errors
}
```

**Оновлено в reset():**
```swift
public func reset() async {
    // ...
    try? await audioEngine.setup()  // ✅ Optional try (reset не повинен падати)
}
```

---

### 📦 Зміни в Prosper App

**1. DI Containers - async throws factories:**

```swift
// Container+Infrastructure.swift
@MainActor
func createAudioPlayerService(_ config: PlayerConfiguration) async throws -> AudioPlayerService {
    try await AudioPlayerService(configuration: config)  // ✅ throws propagated
}

// Container+Practice.swift
@MainActor
func createPracticePlayer() async throws -> PracticePlayer {
    let audioService = try await createAudioPlayerService(.practice)
    return await PracticePlayer(audioService: audioService)
}

@MainActor
func practiceViewModel(_ model: PracticeSettingsModel) async throws -> PracticeViewModel {
    await PracticeViewModel(
        model: model,
        useCase: self.practiceUseCase(),
        player: try await self.createPracticePlayer()  // ✅ throws propagated
    )
}

// + аналогічно QuickPractice, MeditationPractice
```

**2. AsyncFactoryView - error handling UI:**

```swift
// NEW FILE: Prosper/ProsperUI/NavigationManager/AsyncFactoryView.swift
struct AsyncFactoryView<Content: View>: View {
    @State private var content: Content?
    @State private var error: Error?  // ✅ Error state
    let factory: @MainActor () async throws -> Content  // ✅ Throws support
    
    var body: some View {
        if let content = content {
            content
        } else if let error = error {
            // ✅ Error UI with icon + message
            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.largeTitle)
                    .foregroundColor(.red)
                Text("Failed to load view")
                    .font(.headline)
                Text(error.localizedDescription)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
        } else {
            ProgressView()
                .task {
                    do {
                        content = try await factory()  // ✅ Error catching
                    } catch {
                        self.error = error
                    }
                }
        }
    }
}
```

**3. NavigationRoute - async throws calls:**

```swift
case .practice(let model):
    AsyncFactoryView {
        try await Container.shared.practiceScreen(model)  // ✅ throws
    }

case .quickPractice(let model):
    AsyncFactoryView {
        try await Container.shared.quickPracticeScreen(model)  // ✅ throws
    }

case .meditationPracticeView(let forYouMeditationDetail):
    AsyncFactoryView {
        try await Container.shared.meditationPracticeView(forYouMeditationDetail)  // ✅ throws
    }
```

---

### 📊 Результати v4.1.4

**Git commits:**
1. `afead24` - Fix: Route audio to loudspeaker instead of ear speaker
2. `d509240` - Fix: Use correct error case .engineStartFailed
3. `a2aa566` - Make AudioPlayerService.init() throwing

**Prosper App commits:**
1. `0c5ad46` - Support throwing AudioPlayerService.init()
2. `4268de6` - Update view models for async AudioPlayerService init
3. `8d0294b` - Add AsyncFactoryView to Xcode project

**Tag:** `v4.1.4` - Release v4.1.4 - Fix loudspeaker routing and throwing init

**Build статус:**
- ✅ ProsperPlayer package: BUILD SUCCEEDED
- ✅ Prosper app: BUILD SUCCEEDED (pending package update)

---

### 🔍 Bell Sounds Investigation

**Виявлено:** Функція `playBellSound()` існує в PracticePlayer але **ніколи не викликається**!

**Історія:**
- Стара архітектура (GroupedAudioPlayer) грала bell sounds автоматично
- Нова архітектура (AudioPlayerService) - функція є, але не інтегрована

**Bell sounds логіка з GroupedAudioPlayer:**

1. **Count Out Bell** (`count_out_taps_and_bell`):
   - ⏰ За **6 секунд** до кінця кожного intention (крім останнього)
   - 🎯 Сигнал переходу між intentions
   - ⚙️ Константа: `Configuration.Practice.countoutStartInterval = 6 sec`

2. **Bowl Sound** (`induction_end_bowl`):
   - ⏰ За **1 секунду** до закінчення фази
   - 📍 Грає 2 рази:
     - В кінці **induction** фази (перед intentions)
     - В кінці **всіх intentions** (перед returning)
   - ⚙️ Константа: `Configuration.Practice.endBowlInterval = 1 sec`

**Код з GroupedAudioPlayer (lines 319-359):**
```swift
let bowlSoundTimes: [TimeInterval] = [
    intentionStart - endBowlInterval,      // В кінці induction
    returnSequenceStart - endBowlInterval  // В кінці intentions
]

var lastOffset = intentionStart - countoutStartInterval
var countOutTimes: [TimeInterval] = []

intentions.enumerated().forEach { index, intention in
    lastOffset += TimeInterval(intention.duration)
    countOutTimes.append(lastOffset)  // За 6 сек до кінця intention
}

if let fileURL = Bundle.main.url(forResource: "count_out_taps_and_bell", ...) {
    let countOutChannel = AudioChannel(
        assetURL: fileURL,
        behavior: .staggered(countOutTimes),  // Грає в певні моменти
        defaultVolume: Float(countoutVolume)
    )
}

if let fileURL = Bundle.main.url(forResource: "induction_end_bowl", ...) {
    let channel = AudioChannel(
        assetURL: fileURL,
        behavior: .staggered(bowlSoundTimes),  // Грає 2 рази
        defaultVolume: Float(countoutVolume)
    )
}
```

**Поточна реалізація в PracticePlayer (готова але не використовується):**
```swift
func playBellSound(url: URL, volume: Float) async {
    do {
        guard let effect = try await SoundEffect(
            url: url,
            fadeIn: 0.0,
            fadeOut: 0.3,  // Короткий fade out для природного звуку
            volume: volume
        ) else {
            log.error("Failed to create SoundEffect for bell sound")
            return
        }
        
        currentBellEffect = effect
        await audioService.playSoundEffect(effect, fadeDuration: 0.0)
    } catch {
        log.error("Failed to play bell sound: \(error)")
    }
}
```

**Що потрібно зробити:**
1. Додати в PracticeViewModel логіку відслідковування фаз і elapsed time
2. Викликати `player.playBellSound()` в потрібні моменти:
   - Bowl sound за 1 сек до кінця induction
   - Count out bell за 6 сек до кінця кожного intention (крім останнього)
   - Bowl sound за 1 сек до кінця всіх intentions
3. Перевірити наявність аудіо файлів:
   - `count_out_taps_and_bell.m4a` (або .mp3)
   - `induction_end_bowl.m4a` (або .mp3)

---

### 🐛 Виявлена проблема: Log Spam

**Проблема:**
- Функція `calculateAdaptedCrossfadeDuration` викликається кожні 0.5 секунд
- 76+ log entries під час playback
- Локація: `AudioPlayerService.swift:1767` в `shouldTriggerLoopCrossfade()`

**Рішення:**
- Видалити або зменшити частоту debug logging
- Використовувати log level (debug/trace) замість info

---

### ✅ Підсумок v4.1.4

**Виправлено:**
1. ✅ Loudspeaker routing (`.defaultToSpeaker` опція)
2. ✅ Error propagation (throwing init chain)
3. ✅ Правильний error case (`.engineStartFailed`)
4. ✅ Prosper app DI containers (async throws)
5. ✅ AsyncFactoryView з error UI

**Знайдено але не виправлено:**
1. ⚠️ Bell sounds не грають (функція є, інтеграції немає)
2. ⚠️ Log spam від `calculateAdaptedCrossfadeDuration`

**Наступні кроки:**
1. [ ] Тестування v4.1.4 на пристрої - чи звук нормальної гучності
2. [ ] Імплементація bell sounds в PracticeViewModel
3. [ ] Фікс log spam
4. [ ] Розглянути додавання `.duckOthers` опції (user suggestion)
