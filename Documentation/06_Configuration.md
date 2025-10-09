# Configuration Reference

**PlayerConfiguration parameters and validation (v2.11.0)**

---

## Overview

PlayerConfiguration provides a simplified, intuitive API for audio playback configuration. Unlike the legacy AudioConfiguration, it uses a single crossfade parameter with automatic fade calculations.

## Structure

```swift
public struct PlayerConfiguration: Sendable {
    public var crossfadeDuration: TimeInterval  // 1.0-30.0s
    public var fadeCurve: FadeCurve            // Algorithm
    public var repeatMode: RepeatMode           // .off, .singleTrack, .playlist
    public var repeatCount: Int?                // nil = infinite
    public var singleTrackFadeInDuration: TimeInterval   // 0.5-10.0s
    public var singleTrackFadeOutDuration: TimeInterval  // 0.5-10.0s
    public var volume: Int                      // 0-100
    public var stopFadeDuration: TimeInterval   // 0.0-10.0s
    public var mixWithOthers: Bool              // Mix with other audio
    
    // Computed properties:
    public var fadeInDuration: TimeInterval {
        crossfadeDuration * 0.3  // 30% of crossfade
    }
    
    public var volumeFloat: Float {
        Float(volume) / 100.0
    }
    
    // Deprecated:
    @available(*, deprecated, message: "Use repeatMode instead")
    public var enableLooping: Bool {
        get { repeatMode == .playlist }
        set { repeatMode = newValue ? .playlist : .off }
    }
}
```

---

## Parameters

### crossfadeDuration

**Type:** `TimeInterval` (Double)  
**Range:** [1.0, 30.0] seconds  
**Default:** 10.0

**Purpose:** Duration for all fade operations:
- Track-to-track crossfades (auto-advance)
- Loop crossfades (same track)
- Manual track switches

**Validation:**
```swift
guard crossfadeDuration >= 1.0 && crossfadeDuration <= 30.0 else {
    throw ConfigurationError.invalidCrossfadeDuration(crossfadeDuration)
}
```

**Auto-calculations:**
- `fadeIn = crossfadeDuration * 0.3` (30%)
- Example: 10s crossfade → 3s fadeIn

**Recommendations:**
```swift
// Quick transitions
PlayerConfiguration(crossfadeDuration: 2.0)

// Standard (meditation/ambient)
PlayerConfiguration(crossfadeDuration: 10.0)

// Extended (cinematic)
PlayerConfiguration(crossfadeDuration: 20.0)
```

---

### fadeCurve

**Type:** `FadeCurve` enum  
**Options:** `.equalPower`, `.linear`, `.logarithmic`, `.exponential`, `.sCurve`  
**Default:** `.equalPower`

**See:** `04_Fade_Curves.md` for detailed analysis.

**Selection matrix:**

| Use Case | Curve | Rationale |
|----------|-------|-----------|
| Crossfading | `.equalPower` | Constant loudness (cos² + sin² = 1) |
| Fade in | `.logarithmic` | Natural attack |
| UI sync | `.sCurve` | Matches animations |

**Example:**
```swift
PlayerConfiguration(
    crossfadeDuration: 10.0,
    fadeCurve: .equalPower  // Recommended
)
```

---

### repeatMode

**Type:** `RepeatMode` enum  
**Options:** `.off`, `.singleTrack`, `.playlist`  
**Default:** `.off`

**Purpose:** Control playback repeat behavior.

**Options:**
```swift
public enum RepeatMode: Sendable {
    case off          // Play once, no repeat
    case singleTrack  // Loop current track with fade in/out
    case playlist     // Loop entire playlist
}
```

**Behavior:**
- `.off` → Play once and stop
- `.singleTrack` → Loop current track with configurable fades
- `.playlist` → Cycle through playlist with crossfades

**Examples:**
```swift
// No repeat
PlayerConfiguration(repeatMode: .off)

// Single track loop (meditation)
PlayerConfiguration(
    repeatMode: .singleTrack,
    singleTrackFadeInDuration: 3.0,
    singleTrackFadeOutDuration: 3.0
)

// Playlist loop
PlayerConfiguration(
    repeatMode: .playlist,
    repeatCount: nil  // Infinite
)

// Limited playlist repeats
PlayerConfiguration(
    repeatMode: .playlist,
    repeatCount: 5  // Cycle 5 times
)
```

---

### enableLooping (Deprecated)

**Type:** `Bool`  
**Status:** ⚠️ Deprecated - use `repeatMode` instead

**Migration:**
```swift
// Old
PlayerConfiguration(enableLooping: true)

// New
PlayerConfiguration(repeatMode: .playlist)
```

---

### singleTrackFadeInDuration

**Type:** `TimeInterval`  
**Range:** [0.5, 10.0] seconds  
**Default:** 3.0

**Purpose:** Fade in duration when looping a single track (repeatMode = .singleTrack).

**Validation:**
```swift
guard duration >= 0.5 && duration <= 10.0 else {
    throw ConfigurationError.invalidSingleTrackFadeInDuration(duration)
}
```

**Dynamic Adaptation:**
- Auto-scaled to max 40% of track duration
- Combined with fadeOut limited to 80% total
- Prevents overlap issues on short tracks

**Example:**
```swift
PlayerConfiguration(
    repeatMode: .singleTrack,
    singleTrackFadeInDuration: 2.0,
    singleTrackFadeOutDuration: 2.0
)
```

---

### singleTrackFadeOutDuration

**Type:** `TimeInterval`  
**Range:** [0.5, 10.0] seconds  
**Default:** 3.0

**Purpose:** Fade out duration when looping a single track (repeatMode = .singleTrack).

**Same validation and adaptation rules as fadeInDuration.**

---

### stopFadeDuration

**Type:** `TimeInterval`  
**Range:** [0.0, 10.0] seconds  
**Default:** 3.0

**Purpose:** Fade duration when stopping playback gracefully.

**Usage:**
```swift
// Stop with default fade
await service.stopWithDefaultFade()

// Stop with custom fade
await service.stop(fadeDuration: 5.0)

// Instant stop
await service.stop(fadeDuration: 0.0)
```

---

### mixWithOthers

**Type:** `Bool`  
**Default:** `false`

**Purpose:** Control audio session mixing behavior.

**Behavior:**
- `false` → Interrupts other audio (exclusive playback)
- `true` → Plays alongside other audio sources

**Use Cases:**
```swift
// Exclusive (meditation app)
PlayerConfiguration(mixWithOthers: false)

// Mixed (ambient sounds with music)
PlayerConfiguration(mixWithOthers: true)
```

---

### repeatCount

**Type:** `Int?` (Optional)  
**Range:** > 0 or nil  
**Default:** `nil`

**Purpose:** Limit number of playlist cycles.

**Validation:**
```swift
if let count = repeatCount, count < 0 {
    throw ConfigurationError.invalidRepeatCount(count)
}
```

**Semantics:**
- `nil` → Infinite loop (if `enableLooping = true`)
- `n` → Cycle n times, then stop

**Examples:**
```swift
// Play playlist 3 times
PlayerConfiguration(
    enableLooping: true,
    repeatCount: 3
)

// Infinite (meditation)
PlayerConfiguration(
    enableLooping: true,
    repeatCount: nil
)

// Single playthrough
PlayerConfiguration(
    enableLooping: false
)
```

---

### volume

**Type:** `Int`  
**Range:** [0, 100]  
**Default:** 100

**Purpose:** Master volume level.

**Validation:**
```swift
guard volume >= 0 && volume <= 100 else {
    throw ConfigurationError.invalidVolume(volume)
}
```

**Internal conversion:**
```swift
var volumeFloat: Float {
    Float(max(0, min(100, volume))) / 100.0
}
```

**UI-friendly:**
```swift
// Direct slider binding
Slider(value: $volume, in: 0...100, step: 1)

// No Float conversion needed
```

---

### fadeInDuration (Computed)

**Type:** `TimeInterval` (read-only)  
**Formula:** `crossfadeDuration * 0.3`

**Purpose:** Automatic fade from silence at track start.

**Examples:**
- `crossfade: 10s` → `fadeIn: 3s`
- `crossfade: 15s` → `fadeIn: 4.5s`
- `crossfade: 3s` → `fadeIn: 0.9s`

**Rationale:**
- 30% provides natural entrance
- Scales with crossfade duration
- No manual tuning required

---

## Validation

### validate() Method

```swift
public func validate() throws {
    // Crossfade duration
    if crossfadeDuration < 1.0 || crossfadeDuration > 30.0 {
        throw ConfigurationError.invalidCrossfadeDuration(crossfadeDuration)
    }
    
    // Volume range
    if volume < 0 || volume > 100 {
        throw ConfigurationError.invalidVolume(volume)
    }
    
    // RepeatCount
    if let count = repeatCount, count < 0 {
        throw ConfigurationError.invalidRepeatCount(count)
    }
}
```

**Automatic validation:**
```swift
// Called automatically in loadPlaylist()
try await service.loadPlaylist(tracks, configuration: config)
// Throws ConfigurationError if invalid
```

---

## Presets

### Default

```swift
PlayerConfiguration()
```

**Values:**
- crossfadeDuration: 10.0
- fadeCurve: .equalPower
- repeatMode: .off
- repeatCount: nil
- volume: 100
- fadeInDuration: 3.0 (auto)
- stopFadeDuration: 3.0
- mixWithOthers: false

---

### Meditation/Ambient

```swift
extension PlayerConfiguration {
    static var meditation: PlayerConfiguration {
        PlayerConfiguration(
            crossfadeDuration: 15.0,
            fadeCurve: .equalPower,
            repeatMode: .singleTrack,
            repeatCount: nil,
            singleTrackFadeInDuration: 4.0,
            singleTrackFadeOutDuration: 4.0,
            volume: 80
        )
        // fadeInDuration = 4.5s (auto)
    }
}
```

---

### Quick Transitions

```swift
extension PlayerConfiguration {
    static var quick: PlayerConfiguration {
        PlayerConfiguration(
            crossfadeDuration: 2.0,
            fadeCurve: .sCurve,
            repeatMode: .off,
            repeatCount: nil,
            volume: 100
        )
        // fadeInDuration = 0.6s (auto)
    }
}
```

---

## Migration from AudioConfiguration

### Old API (v2.10.1)

```swift
// AudioConfiguration (deprecated - REMOVED in v3.1)
AudioConfiguration(
    crossfadeDuration: 10.0,
    fadeInDuration: 3.0,      // Manual
    fadeOutDuration: 6.0,     // Manual
    volume: 0.8,              // Float 0.0-1.0
    enableLooping: true,
    repeatCount: nil,
    fadeCurve: .equalPower
)
```

### New API (v2.11.0)

```swift
// PlayerConfiguration (current)
PlayerConfiguration(
    crossfadeDuration: 10.0,
    fadeCurve: .equalPower,
    repeatMode: .playlist,    // Instead of enableLooping
    repeatCount: nil,
    volume: 80,               // Int 0-100
    stopFadeDuration: 3.0,
    mixWithOthers: false
)
// fadeIn auto = 3.0s (30%)
```

**Benefits:**
- ✅ Simpler API (fewer parameters)
- ✅ Auto-calculated fadeIn (scales properly)
- ✅ UI-friendly volume (0-100)
- ✅ Removed unused fadeOut

---

## Performance Characteristics

### CPU Impact

**Crossfade duration:**
```
CPU_usage = adaptive_steps × overhead

Example (10s crossfade):
  300 steps × 0.01% = 3% CPU
```

**Adaptive optimization (v2.6.0):**
```
1s:  100 steps → 1%
10s: 300 steps → 3%
30s: 600 steps → 6%
```

### Memory Impact

**Playlist looping:**
```
Memory = 2 × file_size (during crossfade)

Post-crossfade: old file released
```

---

## Constraints

### Hard Limits

| Parameter | Min | Max | Reason |
|-----------|-----|-----|--------|
| crossfadeDuration | 1.0s | 30.0s | Perceptual/performance |
| volume | 0 | 100 | UI range |
| repeatCount | 1 | ∞ | Logical minimum |

### Soft Recommendations

| Parameter | Recommended | Rationale |
|-----------|-------------|-----------|
| crossfadeDuration | 5-15s | Balance smooth/efficiency |
| volume | 70-100 | Normal listening range |
| fadeIn (auto) | 1.5-4.5s | Natural entrance |

---

## Edge Cases

### Minimum Values

**1s crossfade:**
```swift
PlayerConfiguration(crossfadeDuration: 1.0)
// fadeIn = 0.3s (very quick)
```

**0% volume:**
```swift
PlayerConfiguration(volume: 0)
// Muted playback (still works)
```

### Maximum Values

**30s crossfade:**
```swift
PlayerConfiguration(crossfadeDuration: 30.0)
// fadeIn = 9s (very smooth)
// 600 volume steps
// ~6% CPU
```

---

## Testing

### Valid Configuration

```swift
@Test
func testValidConfiguration() throws {
    let config = PlayerConfiguration(
        crossfadeDuration: 10.0,
        fadeCurve: .equalPower,
        enableLooping: true,
        repeatCount: 5,
        volume: 80
    )
    
    try config.validate()  // Should not throw
    
    // Auto-calculated
    #expect(config.fadeInDuration == 3.0)
}
```

### Invalid Configurations

```swift
@Test
func testInvalidCrossfade() {
    let config = PlayerConfiguration(
        crossfadeDuration: 0.5  // Too short!
    )
    
    #expect(throws: ConfigurationError.self) {
        try config.validate()
    }
}

@Test
func testInvalidVolume() {
    let config = PlayerConfiguration(
        volume: 150  // Too high!
    )
    
    #expect(throws: ConfigurationError.self) {
        try config.validate()
    }
}
```

---

## Best Practices

### DO ✅

```swift
// Use default preset
let config = PlayerConfiguration()

// Use auto-calculated fadeIn
// fadeIn = crossfadeDuration * 0.3

// Volume as Int (0-100)
PlayerConfiguration(volume: 80)

// Infinite looping
PlayerConfiguration(
    repeatMode: .playlist,
    repeatCount: nil
)
```

### DON'T ❌

```swift
// Extremely short crossfades
PlayerConfiguration(crossfadeDuration: 0.5)  // ❌ Too short!

// Invalid volume range
PlayerConfiguration(volume: -10)  // ❌ Negative!
PlayerConfiguration(volume: 150)  // ❌ Too high!

// Negative repeat count
PlayerConfiguration(repeatCount: -1)  // ❌ Invalid!
```

---

## Summary

**Key improvements in v2.11.0:**

1. ✅ Single crossfade parameter (simpler)
2. ✅ Auto-calculated fadeIn (30% of crossfade)
3. ✅ Volume as Int 0-100 (UI-friendly)
4. ✅ Removed unused fadeOut parameter
5. ✅ Playlist-first design

**Recommended default:**
```swift
PlayerConfiguration(
    crossfadeDuration: 10.0,
    fadeCurve: .equalPower,
    repeatMode: .playlist,
    repeatCount: nil,
    volume: 100,
    stopFadeDuration: 3.0,
    mixWithOthers: false
)
// fadeInDuration = 3.0s (auto)
```
