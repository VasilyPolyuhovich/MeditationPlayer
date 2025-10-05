# Configuration Reference

**AudioConfiguration parameters and validation**

---

## Structure

```swift
public struct AudioConfiguration: Sendable, Equatable {
    public let crossfadeDuration: TimeInterval
    public let fadeInDuration: TimeInterval
    public let fadeOutDuration: TimeInterval
    public let fadeCurve: FadeCurve
    public let enableLooping: Bool
    public let repeatCount: Int?
}
```

---

## Parameters

### crossfadeDuration

**Type:** `TimeInterval` (Double)  
**Range:** [1.0, 30.0] seconds  
**Default:** 10.0

**Purpose:** Duration for track-to-track and loop crossfades.

**Validation:**
```swift
guard crossfadeDuration >= 1.0 && crossfadeDuration <= 30.0 else {
    throw AudioPlayerError.invalidConfiguration(
        "crossfadeDuration must be in range [1.0, 30.0]"
    )
}
```

**Performance impact:**
- 1s: 100 volume steps (10ms/step)
- 10s: 300 volume steps (33ms/step)
- 30s: 600 volume steps (50ms/step)

**Recommendations:**
```swift
// Quick transitions
AudioConfiguration(crossfadeDuration: 2.0)

// Standard (meditation/ambient)
AudioConfiguration(crossfadeDuration: 10.0)

// Extended (cinematic)
AudioConfiguration(crossfadeDuration: 20.0)
```

---

### fadeInDuration

**Type:** `TimeInterval`  
**Range:** [0.0, 10.0] seconds  
**Default:** 3.0

**Purpose:** Fade from silence at playback start.

**Validation:**
```swift
guard fadeInDuration >= 0.0 && fadeInDuration <= 10.0 else {
    throw AudioPlayerError.invalidConfiguration(
        "fadeInDuration must be in range [0.0, 10.0]"
    )
}
```

**Special cases:**
- `0.0` → Instant start (no fade)
- `>0.0` → Smooth entrance

**Curve interaction:**
```swift
// Natural fade-in
AudioConfiguration(
    fadeInDuration: 3.0,
    fadeCurve: .logarithmic  // Fast start, gentle end
)
```

---

### fadeOutDuration

**Type:** `TimeInterval`  
**Range:** [0.0, 30.0] seconds  
**Default:** 6.0

**Purpose:** Fade to silence before stop.

**Validation:**
```swift
guard fadeOutDuration >= 0.0 && fadeOutDuration <= 30.0 else {
    throw AudioPlayerError.invalidConfiguration(
        "fadeOutDuration must be in range [0.0, 30.0]"
    )
}
```

**Usage:**
```swift
// Quick stop
try await service.finish(fadeDuration: 2.0)

// Gentle ending
try await service.finish(fadeDuration: 15.0)

// Use config default
try await service.finish(fadeDuration: nil)
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
| Crossfading | `.equalPower` | Constant loudness |
| Fade in | `.logarithmic` | Natural attack |
| Fade out | `.exponential` | Smooth decay |
| UI sync | `.sCurve` | Matches animations |

**Example:**
```swift
AudioConfiguration(
    fadeInDuration: 3.0,
    fadeOutDuration: 5.0,
    fadeCurve: .equalPower  // Recommended
)
```

---

### enableLooping

**Type:** `Bool`  
**Default:** `false`

**Purpose:** Enable automatic loop with crossfade.

**Behavior:**
- `true` → Track loops with crossfade at end
- `false` → Single playback, stops at end

**Loop mechanics:**
```swift
// Infinite loop
AudioConfiguration(
    enableLooping: true,
    repeatCount: nil  // Loop forever
)

// Limited repeats
AudioConfiguration(
    enableLooping: true,
    repeatCount: 5  // Loop 5 times
)
```

**Trigger logic:**
```
Loop trigger point: duration - crossfadeDuration - ε

Where ε = 0.1s (tolerance for float precision)
```

---

### repeatCount

**Type:** `Int?` (Optional)  
**Range:** > 0 or nil  
**Default:** `nil`

**Purpose:** Limit number of loop iterations.

**Validation:**
```swift
if let count = repeatCount {
    guard count > 0 else {
        throw AudioPlayerError.invalidConfiguration(
            "repeatCount must be > 0"
        )
    }
}
```

**Semantics:**
- `nil` → Infinite loop (if `enableLooping = true`)
- `n` → Loop n times, then stop with fade-out

**Example:**
```swift
// Play 3 times
AudioConfiguration(
    enableLooping: true,
    repeatCount: 3
)

// Infinite (meditation)
AudioConfiguration(
    enableLooping: true,
    repeatCount: nil
)
```

---

## Validation

### validate() Method

```swift
public func validate() throws {
    // Crossfade duration
    guard crossfadeDuration >= 1.0 && crossfadeDuration <= 30.0 else {
        throw AudioPlayerError.invalidConfiguration(
            "crossfadeDuration must be in range [1.0, 30.0]"
        )
    }
    
    // Fade in duration
    guard fadeInDuration >= 0.0 && fadeInDuration <= 10.0 else {
        throw AudioPlayerError.invalidConfiguration(
            "fadeInDuration must be in range [0.0, 10.0]"
        )
    }
    
    // Fade out duration
    guard fadeOutDuration >= 0.0 && fadeOutDuration <= 30.0 else {
        throw AudioPlayerError.invalidConfiguration(
            "fadeOutDuration must be in range [0.0, 30.0]"
        )
    }
    
    // Repeat count
    if let count = repeatCount {
        guard count > 0 else {
            throw AudioPlayerError.invalidConfiguration(
                "repeatCount must be > 0"
            )
        }
    }
}
```

**Automatic validation:**
```swift
// Called automatically in startPlaying()
try await service.startPlaying(url: url, configuration: config)
// Throws if config invalid
```

---

## Presets

### Default

```swift
AudioConfiguration()
```

**Values:**
- crossfadeDuration: 10.0
- fadeInDuration: 3.0
- fadeOutDuration: 6.0
- fadeCurve: .equalPower
- enableLooping: false
- repeatCount: nil

---

### Meditation/Ambient

```swift
extension AudioConfiguration {
    static var meditation: AudioConfiguration {
        AudioConfiguration(
            crossfadeDuration: 15.0,
            fadeInDuration: 5.0,
            fadeOutDuration: 10.0,
            fadeCurve: .equalPower,
            enableLooping: true,
            repeatCount: nil
        )
    }
}
```

**Characteristics:**
- Extended crossfades (smooth)
- Gentle fade-in/out
- Infinite looping
- Equal-power (no artifacts)

---

### Quick Transitions

```swift
extension AudioConfiguration {
    static var quick: AudioConfiguration {
        AudioConfiguration(
            crossfadeDuration: 2.0,
            fadeInDuration: 1.0,
            fadeOutDuration: 2.0,
            fadeCurve: .sCurve,
            enableLooping: false,
            repeatCount: nil
        )
    }
}
```

**Characteristics:**
- Fast crossfades
- Immediate start/stop
- S-curve (smooth acceleration)
- Single playback

---

### Podcast/Voice

```swift
extension AudioConfiguration {
    static var voice: AudioConfiguration {
        AudioConfiguration(
            crossfadeDuration: 0.5,
            fadeInDuration: 0.0,
            fadeOutDuration: 0.5,
            fadeCurve: .linear,
            enableLooping: false,
            repeatCount: nil
        )
    }
}
```

**Characteristics:**
- Minimal crossfade (0.5s)
- Instant start
- Quick fade-out
- Linear (voice-optimized)

---

## Performance Characteristics

### CPU Impact

**Crossfade duration:**
```
CPU_usage = steps_per_second × duration × overhead_per_step

Example (10s crossfade):
  30 steps/sec × 10s × 0.01% = 3% CPU
```

**Adaptive optimization (v2.6.0):**
```
1s:  100 steps → 1%
10s: 300 steps → 3%
30s: 600 steps → 6%

Old (fixed): 30s = 3000 steps → 30% ❌
New (adaptive): 30s = 600 steps → 6% ✅
```

### Memory Impact

**Looping:**
```
Memory = file_size × (enableLooping ? 2 : 1)

During crossfade: 2 × file_size
After crossfade: 1 × file_size (old released)
```

---

## Constraints

### Hard Limits

| Parameter | Min | Max | Reason |
|-----------|-----|-----|--------|
| crossfadeDuration | 1.0s | 30.0s | Perceptual/performance |
| fadeInDuration | 0.0s | 10.0s | UX (instant start allowed) |
| fadeOutDuration | 0.0s | 30.0s | UX (instant stop allowed) |
| repeatCount | 1 | ∞ | Logical minimum |

### Soft Recommendations

| Parameter | Recommended | Rationale |
|-----------|-------------|-----------|
| crossfadeDuration | 5-15s | Balance smooth/efficiency |
| fadeInDuration | 2-5s | Natural entrance |
| fadeOutDuration | 3-10s | Gentle exit |

---

## Edge Cases

### Zero Durations

**fadeInDuration = 0:**
```swift
// Instant start (no ramp)
mixer.volume = 1.0
player.play()
```

**fadeOutDuration = 0:**
```swift
// Instant stop
mixer.volume = 0.0
player.stop()
```

### Maximum Duration

**30s crossfade:**
- 600 volume steps
- 50ms per step
- ~6% CPU usage
- Smooth, imperceptible

### Loop Edge

**Crossfade starts at:**
```
t = duration - crossfadeDuration - 0.1

Example (60s track, 10s crossfade):
  Trigger at t = 49.9s (not 50.0 exactly)
  
Reason: Float precision tolerance (Issue #8 fix)
```

---

## Testing

### Valid Configurations

```swift
@Test
func testValidConfiguration() throws {
    let config = AudioConfiguration(
        crossfadeDuration: 5.0,
        fadeInDuration: 2.0,
        fadeOutDuration: 3.0,
        fadeCurve: .equalPower,
        enableLooping: true,
        repeatCount: 10
    )
    
    try config.validate()  // Should not throw
}
```

### Invalid Configurations

```swift
@Test
func testInvalidCrossfadeDuration() {
    let config = AudioConfiguration(
        crossfadeDuration: 0.5  // Too short!
    )
    
    #expect(throws: AudioPlayerError.invalidConfiguration) {
        try config.validate()
    }
}

@Test
func testInvalidRepeatCount() {
    let config = AudioConfiguration(
        enableLooping: true,
        repeatCount: 0  // Must be > 0!
    )
    
    #expect(throws: AudioPlayerError.invalidConfiguration) {
        try config.validate()
    }
}
```

---

## Best Practices

### DO ✅

```swift
// Use presets for common scenarios
let config = AudioConfiguration.meditation

// Validate before use (automatic in startPlaying)
try config.validate()

// Choose appropriate fade curve
let config = AudioConfiguration(
    fadeCurve: .equalPower  // For crossfading
)

// Limit loop iterations for battery
let config = AudioConfiguration(
    enableLooping: true,
    repeatCount: 100  // Stop after 100 loops
)
```

### DON'T ❌

```swift
// Extremely short crossfades (audible artifacts)
AudioConfiguration(crossfadeDuration: 0.1)  // Too short!

// Excessively long fades (waste CPU)
AudioConfiguration(fadeOutDuration: 60.0)  // Too long!

// Linear curve for music (power dip)
AudioConfiguration(fadeCurve: .linear)  // Use equalPower!

// Zero repeat count (invalid)
AudioConfiguration(
    enableLooping: true,
    repeatCount: 0  // ❌ Throws error
)
```

---

## Summary

**Key points:**

1. ✅ All parameters have validated ranges
2. ✅ Adaptive step sizing optimizes performance
3. ✅ Equal-power curve recommended for audio
4. ✅ Infinite looping supported (repeatCount: nil)
5. ✅ Configuration immutable after creation

**Recommended default:**
```swift
AudioConfiguration(
    crossfadeDuration: 10.0,
    fadeInDuration: 3.0,
    fadeOutDuration: 6.0,
    fadeCurve: .equalPower,
    enableLooping: true,
    repeatCount: nil
)
```
