# Swift 6 Concurrency Implementation

## Overview

Prosper Player повністю відповідає **Swift 6 strict concurrency** вимогам, забезпечуючи compile-time гарантії відсутності data races.

---

## 🔒 **Основні Принципи**

### 1. **Actor Isolation**

Всі mutable states ізольовані в Actors:

```swift
// Audio engine operations - actor isolated
actor AudioEngineActor {
    private let engine: AVAudioEngine  // Protected by actor
    private var isEngineRunning = false
    
    func start() throws { /* Safe! */ }
}

// Session management - actor isolated
actor AudioSessionManager {
    private var isConfigured = false  // Protected by actor
    
    func configure() throws { /* Safe! */ }
}

// Main service - actor isolated
public actor AudioPlayerService {
    private var state: PlayerState  // Protected by actor
    
    public func pause() async throws { /* Safe! */ }
}
```

### 2. **Sendable Types**

Всі дані що передаються між actors є Sendable:

```swift
// Value types - implicitly Sendable
public struct AudioConfiguration: Sendable, Equatable {
    public let crossfadeDuration: TimeInterval
    public let fadeCurve: FadeCurve
}

public enum FadeCurve: Sendable, Equatable {
    case equalPower
    case linear
}

public enum PlayerState: Sendable, Equatable {
    case playing
    case paused
}
```

### 3. **@Sendable Closures**

Всі closures що можуть викликатися з різних isolation domains позначені `@Sendable`:

```swift
// Remote command handlers
func setupCommands(
    playHandler: @escaping @Sendable () async -> Void,
    pauseHandler: @escaping @Sendable () async -> Void
) { /* ... */ }

// Session event handlers
func setInterruptionHandler(_ handler: @escaping @Sendable (Bool) -> Void) {
    self.interruptionHandler = handler
}
```

---

## 🚫 **Виправлені Проблеми**

### ❌ **Проблема 1: GameplayKit не є Sendable**

**Старий код (GameplayKit):**
```swift
// GKState не є Sendable!
class PlayingState: GKState {
    weak var context: AudioStateMachineContext?  // ⚠️ Data race!
    
    override func didEnter(from previousState: GKState?) {
        Task {  // ⚠️ Sending closure warning!
            try? await context?.resumePlayback()
        }
    }
}
```

**Проблеми:**
- `GKState` не має `Sendable` conformance
- `Task {}` створює closure що може викликатися з різних threads
- `weak` reference на actor створює race conditions

**Новий код (Custom Actor-safe):**
```swift
// Sendable struct!
struct PlayingState: AudioStateProtocol {
    var playerState: PlayerState { .playing }
    
    func didEnter(from previousState: (any AudioStateProtocol)?, 
                   context: AudioStateMachineContext) async {
        // Direct async call - no Task needed!
        if let prev = previousState, prev.playerState == .paused {
            try? await context.resumePlayback()
        }
        await context.stateDidChange(to: .playing)
    }
}
```

**Переваги:**
- ✅ Struct є Sendable за замовчуванням
- ✅ Direct async call без Task wrapper
- ✅ Context передається як parameter (не зберігається)
- ✅ No data races - guaranteed by compiler

---

### ❌ **Проблема 2: Non-Sendable Closures**

**Старий код:**
```swift
func setupCommands(
    playHandler: @escaping () async -> Void,  // ⚠️ Not Sendable!
    pauseHandler: @escaping () async -> Void
) {
    commandCenter.playCommand.addTarget { [weak self] _ in
        Task {  // ⚠️ Data race potential!
            await self?.playHandler?()
        }
        return .success
    }
}
```

**Новий код:**
```swift
func setupCommands(
    playHandler: @escaping @Sendable () async -> Void,  // ✅ Sendable!
    pauseHandler: @escaping @Sendable () async -> Void
) {
    commandCenter.playCommand.addTarget { [weak self] _ in
        Task { @MainActor in  // ✅ Explicit isolation!
            await self?.playHandler?()
        }
        return .success
    }
}
```

---

### ❌ **Проблема 3: Actor-isolated Property Access**

**Старий код:**
```swift
await sessionManager.setInterruptionHandler { [weak self] shouldResume in
    Task {
        await self?.handleInterruption(shouldResume: shouldResume)
        // ⚠️ self is actor-isolated but captured in non-isolated closure!
    }
}
```

**Новий код:**
```swift
await sessionManager.setInterruptionHandler { [weak self] shouldResume in
    guard let self = self else { return }  // ✅ Unwrap safely
    Task {
        await self.handleInterruption(shouldResume: shouldResume)
        // ✅ Clear isolation boundary
    }
}
```

---

## 📋 **State Machine Architecture**

### Новий Actor-Safe Design

```swift
// Protocol for states - Sendable!
protocol AudioStateProtocol: Sendable {
    var playerState: PlayerState { get }
    func isValidTransition(to state: any AudioStateProtocol) -> Bool
    func didEnter(from previousState: (any AudioStateProtocol)?, 
                   context: AudioStateMachineContext) async
}

// Context - explicit Actor protocol
protocol AudioStateMachineContext: Actor {
    func stateDidChange(to state: PlayerState) async
    func startEngine() async throws
    func stopEngine() async
}

// State machine - actor isolated
actor AudioStateMachine {
    private var currentStateBox: any AudioStateProtocol
    private weak var context: (any AudioStateMachineContext)?
    
    func enter(_ newState: any AudioStateProtocol) async -> Bool {
        guard let context = context else { return false }
        
        await previousState.willExit(to: newState, context: context)
        currentStateBox = newState
        await newState.didEnter(from: previousState, context: context)
        
        return true
    }
}
```

---

## 🧪 **Тестування Concurrency**

### Thread Sanitizer (TSan)

```bash
# Enable in Xcode scheme
Edit Scheme → Run → Diagnostics → Thread Sanitizer ✓
```

### Строгий режим cooperative threading

```bash
# Add environment variable
LIBDISPATCH_COOPERATIVE_POOL_STRICT=1
```

### Compiler flags

```swift
// In Package.swift
swiftSettings: [
    .enableExperimentalFeature("StrictConcurrency")
]
```

---

## ✅ **Гарантії**

З новою реалізацією ми маємо:

1. ✅ **Compile-time data race prevention** - компілятор не дозволить build з data races
2. ✅ **Actor isolation** - всі mutable states захищені
3. ✅ **Sendable types** - безпечна передача даних між actors
4. ✅ **No weak/strong cycles** - правильне управління пам'яттю
5. ✅ **Clear isolation boundaries** - явні межі між actors

---

## 🎯 **Best Practices**

### ✅ **DO**

```swift
// Use actor for mutable state
actor MyService {
    private var state: State
}

// Use Sendable types for data transfer
struct Config: Sendable {
    let value: Int
}

// Use @Sendable for closures
func register(handler: @escaping @Sendable () async -> Void) {}

// Use explicit isolation
Task { @MainActor in
    updateUI()
}
```

### ❌ **DON'T**

```swift
// Don't capture actor strongly in closures
Task {
    await self.method()  // ⚠️ Can create retain cycles
}

// Don't use non-Sendable types across actors
class NonSendable {  // ⚠️ Not thread-safe!
    var value: Int
}

// Don't use weak without guard
weak var service: MyActor?
Task {
    await service?.method()  // ⚠️ Can be nil mid-execution
}
```

---

## 📚 **References**

- [SE-0306: Sendable and @Sendable closures](https://github.com/apple/swift-evolution/blob/main/proposals/0306-actors.md)
- [SE-0302: Concurrency: Actor isolation](https://github.com/apple/swift-evolution/blob/main/proposals/0302-concurrent-value-and-concurrent-closures.md)
- [Swift Concurrency: Behind the Scenes - WWDC 2021](https://developer.apple.com/videos/play/wwdc2021/10254/)
- [Eliminate data races using Swift Concurrency - WWDC 2022](https://developer.apple.com/videos/play/wwdc2022/110351/)

---

**Bottom Line:** Prosper Player тепер має compile-time гарантії відсутності data races завдяки Swift 6 strict concurrency! 🔒
