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
    public var enableLooping: Bool              // Playlist cycle
    public var repeatCount: Int?                // nil = infinite
    public var volume: Int                      // 0-100
    
    // Auto-calculated:
    public var fadeInDuration: TimeInterval {
        crossfadeDuration * 0.3  // 30% of crossfade
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

### enableLooping

**Type:** `Bool`  
**Default:** `true`

**Purpose:** Enable automatic playlist cycling.

**Behavior:**
- `true` → Playlist cycles with crossfades
- `false` → Play once and stop

**Loop mechanics:**
```swift
// Infinite playlist loop
PlayerConfiguration(
    enableLooping: true,
    repeatCount: nil  // Loop forever
)

// Limited repeats
PlayerConfiguration(
    enableLooping: true,
    repeatCount: 5  // Cycle 5 times
)
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
- enableLooping: true
- repeatCount: nil
- volume: 100
- fadeInDuration: 3.0 (auto)

---

### Meditation/Ambient

```swift
extension PlayerConfiguration {
    static var meditation: PlayerConfiguration {
        PlayerConfiguration(
            crossfadeDuration: 15.0,
            fadeCurve: .equalPower,
            enableLooping: true,
            repeatCount: nil,
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
            enableLooping: false,
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
// AudioConfiguration (deprecated)
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
    // fadeIn auto = 3.0s (30%)
    // fadeOut removed (not used)
    volume: 80,               // Int 0-100
    enableLooping: true,
    repeatCount: nil,
    fadeCurve: .equalPower
)
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
    enableLooping: true,
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
    enableLooping: true,
    repeatCount: nil,
    volume: 100
)
// fadeInDuration = 3.0s (auto)
```
