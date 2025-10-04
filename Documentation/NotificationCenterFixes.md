# NotificationCenter and MainActor Fixes

## Problems Fixed

### 1. NotificationCenter Non-Sendable Notification Objects
**Problem:** `Notification` objects are not `Sendable`, causing data races when passed to actor-isolated methods.

**File affected:** `AudioSessionManager.swift`

**Errors:**
- "Passing closure as a 'sending' parameter risks causing data races"
- "Closure captures 'notification' which is accessible to code in the current task"
- "Sending task-isolated 'notification' to actor-isolated instance method risks causing data races"

**Solution:** Extract all data from `Notification` synchronously before passing to actor methods.

```swift
// Before (ERROR)
NotificationCenter.default.addObserver(...) { [weak self] notification in
    Task {
        await self?.handleInterruption(notification) // ❌ Non-Sendable object
    }
}

// After (FIXED)
NotificationCenter.default.addObserver(...) { [weak self] notification in
    // Extract Sendable data synchronously
    guard let userInfo = notification.userInfo,
          let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
          let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
        return
    }
    
    let shouldResume: Bool?
    if type == .ended,
       let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
        let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
        shouldResume = options.contains(.shouldResume)
    } else {
        shouldResume = nil
    }
    
    // Now send Sendable data to actor
    Task {
        await self?.handleInterruption(type: type, shouldResume: shouldResume) // ✅
    }
}
```

**Updated method signatures:**
```swift
// Before
private func handleInterruption(_ notification: Notification)
private func handleRouteChange(_ notification: Notification)

// After
private func handleInterruption(type: AVAudioSession.InterruptionType, shouldResume: Bool?)
private func handleRouteChange(reason: AVAudioSession.RouteChangeReason)
```

### 2. MainActor Initializer Called from Actor Context
**Problem:** `RemoteCommandManager.init()` is MainActor-isolated but called from actor context in `AudioPlayerService`.

**File affected:** `RemoteCommandManager.swift`

**Error:**
- "Call to main actor-isolated initializer 'init()' in a synchronous nonisolated context"

**Solution:** Make `init()` nonisolated and properties `nonisolated(unsafe)` since they reference thread-safe shared instances.

```swift
// Before (ERROR)
@MainActor
final class RemoteCommandManager {
    private let commandCenter: MPRemoteCommandCenter  // ❌ MainActor-isolated
    private let nowPlayingCenter: MPNowPlayingInfoCenter  // ❌ MainActor-isolated
    
    init() {  // ❌ Cannot mutate MainActor properties
        self.commandCenter = MPRemoteCommandCenter.shared()
        self.nowPlayingCenter = MPNowPlayingInfoCenter.default()
    }
}

// After (FIXED)
@MainActor
final class RemoteCommandManager {
    nonisolated(unsafe) private let commandCenter: MPRemoteCommandCenter  // ✅
    nonisolated(unsafe) private let nowPlayingCenter: MPNowPlayingInfoCenter  // ✅
    
    nonisolated init() {  // ✅ Can assign nonisolated properties
        self.commandCenter = MPRemoteCommandCenter.shared()
        self.nowPlayingCenter = MPNowPlayingInfoCenter.default()
    }
}
```

## Why These Fixes Work

### NotificationCenter Pattern
The key insight: Extract non-Sendable data in the notification callback (which runs on main queue) and only pass Sendable primitives (enums, optionals) to actor-isolated methods.

**Pattern:**
1. Notification arrives on main queue
2. Extract all needed data synchronously (while on main queue)
3. Convert to Sendable types (enums, primitives)
4. Pass Sendable data to actor via Task

This avoids crossing actor boundaries with non-Sendable Notification objects.

### Nonisolated(unsafe) Pattern
Use `nonisolated(unsafe)` for properties that hold references to thread-safe objects but are in a MainActor class.

**Safe when:**
- The object is a thread-safe singleton (like MediaPlayer framework objects)
- You only access it from MainActor methods (except init)
- The object's methods are internally synchronized

**Pattern:**
```swift
@MainActor
final class Manager {
    nonisolated(unsafe) private let sharedInstance: SomeThreadSafeSingleton
    
    nonisolated init() {
        self.sharedInstance = SomeThreadSafeSingleton.shared()
    }
    
    func doWork() {  // MainActor method
        sharedInstance.performWork()  // Safe - called from MainActor
    }
}
```

## Files Modified
- `AudioSessionManager.swift` - notification handlers
- `RemoteCommandManager.swift` - initializer

## Verification
Build the project:
```bash
swift build
```

Expected result: 
- ✅ No "Sending 'notification' risks causing data races" errors
- ✅ No "Call to main actor-isolated initializer" errors
- ✅ Swift 6 strict concurrency compliant
