# V4.0 Refactor Plan - Complete Analysis

## 🔍 Executive Summary

**Status**: ❌ CRITICAL - 40+ compilation errors blocking v4.0
**Root Cause**: PlayerConfiguration v4.0 removed 3 properties, but code still uses them
**Impact**: AudioPlayerService, Demo App, Tests all broken
**Fix Complexity**: Medium (systematic replacement, no architecture changes)

---

## 📋 Problem Analysis

### What Changed in v4.0

PlayerConfiguration REMOVED:
```swift
// ❌ DELETED
singleTrackFadeInDuration: TimeInterval
singleTrackFadeOutDuration: TimeInterval  
stopFadeDuration: TimeInterval
```

PlayerConfiguration NOW HAS:
```swift
// ✅ AVAILABLE
crossfadeDuration: TimeInterval  // Unified fade duration
fadeCurve: FadeCurve
repeatMode: RepeatMode
repeatCount: Int?
volume: Int
mixWithOthers: Bool

// ✅ COMPUTED
fadeInDuration: TimeInterval  // = crossfadeDuration * 0.3
volumeFloat: Float
```

### New Design Philosophy

**v3.0 (Old)**:
- Separate fade durations for each use case
- Complex configuration with 5+ fade parameters

**v4.0 (New)**:
- **Single `crossfadeDuration`** for all transitions
- **Auto-calculated** fadeIn (30% of crossfade)
- **Method parameter** for stop fade (not config)

---

## 🚨 All Broken Files

### 1. AudioPlayerService.swift (10 errors)

#### Lines 85-91: Constructor initialization
```swift
// ❌ CURRENT (BROKEN)
self.configuration = PlayerConfiguration(
    crossfadeDuration: configuration.crossfadeDuration,
    fadeCurve: configuration.fadeCurve,
    repeatMode: configuration.repeatMode,
    repeatCount: configuration.repeatCount,
    singleTrackFadeInDuration: configuration.singleTrackFadeInDuration,  // ❌ DOES NOT EXIST
    singleTrackFadeOutDuration: configuration.singleTrackFadeOutDuration, // ❌ DOES NOT EXIST
    volume: configuration.volume,
    stopFadeDuration: configuration.stopFadeDuration  // ❌ DOES NOT EXIST
)

// ✅ FIX: Remove non-existent parameters
self.configuration = PlayerConfiguration(
    crossfadeDuration: configuration.crossfadeDuration,
    fadeCurve: configuration.fadeCurve,
    repeatMode: configuration.repeatMode,
    repeatCount: configuration.repeatCount,
    volume: configuration.volume,
    mixWithOthers: configuration.mixWithOthers
)
```

#### Lines 515-522: setVolume configuration update
```swift
// ❌ CURRENT (BROKEN)
self.configuration = PlayerConfiguration(
    crossfadeDuration: configuration.crossfadeDuration,
    fadeCurve: configuration.fadeCurve,
    repeatMode: configuration.repeatMode,
    repeatCount: configuration.repeatCount,
    singleTrackFadeInDuration: configuration.singleTrackFadeInDuration,  // ❌ DOES NOT EXIST
    singleTrackFadeOutDuration: configuration.singleTrackFadeOutDuration, // ❌ DOES NOT EXIST
    volume: volumeInt,
    stopFadeDuration: configuration.stopFadeDuration,  // ❌ DOES NOT EXIST
    mixWithOthers: configuration.mixWithOthers
)

// ✅ FIX: Remove non-existent parameters
self.configuration = PlayerConfiguration(
    crossfadeDuration: configuration.crossfadeDuration,
    fadeCurve: configuration.fadeCurve,
    repeatMode: configuration.repeatMode,
    repeatCount: configuration.repeatCount,
    volume: volumeInt,
    mixWithOthers: configuration.mixWithOthers
)
```

#### Lines 548-556: setRepeatMode configuration update
```swift
// ❌ CURRENT (BROKEN)
self.configuration = PlayerConfiguration(
    crossfadeDuration: configuration.crossfadeDuration,
    fadeCurve: configuration.fadeCurve,
    repeatMode: mode,
    repeatCount: configuration.repeatCount,
    singleTrackFadeInDuration: configuration.singleTrackFadeInDuration,  // ❌ DOES NOT EXIST
    singleTrackFadeOutDuration: configuration.singleTrackFadeOutDuration, // ❌ DOES NOT EXIST
    volume: configuration.volume,
    stopFadeDuration: configuration.stopFadeDuration,  // ❌ DOES NOT EXIST
    mixWithOthers: configuration.mixWithOthers
)

// ✅ FIX: Remove non-existent parameters
self.configuration = PlayerConfiguration(
    crossfadeDuration: configuration.crossfadeDuration,
    fadeCurve: configuration.fadeCurve,
    repeatMode: mode,
    repeatCount: configuration.repeatCount,
    volume: configuration.volume,
    mixWithOthers: configuration.mixWithOthers
)
```

#### Lines 619-627: setSingleTrackFadeDurations (ENTIRE METHOD DEPRECATED)
```swift
// ❌ CURRENT (BROKEN)
public func setSingleTrackFadeDurations(
    fadeIn: TimeInterval, 
    fadeOut: TimeInterval
) async throws {
    // Validation...
    
    self.configuration = PlayerConfiguration(
        crossfadeDuration: configuration.crossfadeDuration,
        fadeCurve: configuration.fadeCurve,
        repeatMode: configuration.repeatMode,
        repeatCount: configuration.repeatCount,
        singleTrackFadeInDuration: fadeIn,  // ❌ DOES NOT EXIST
        singleTrackFadeOutDuration: fadeOut, // ❌ DOES NOT EXIST
        volume: configuration.volume,
        stopFadeDuration: configuration.stopFadeDuration,  // ❌ DOES NOT EXIST
        mixWithOthers: configuration.mixWithOthers
    )
}

// ✅ FIX: Replace method entirely with v4.0 approach
@available(*, deprecated, message: "Use crossfade duration instead. Set repeatMode to .singleTrack and adjust crossfadeDuration.")
public func setSingleTrackFadeDurations(
    fadeIn: TimeInterval, 
    fadeOut: TimeInterval
) async throws {
    // Calculate unified crossfade from desired fades
    // In v4.0: fadeIn = crossfade * 0.3, so crossfade = fadeIn / 0.3
    let unifiedCrossfade = max(fadeIn / 0.3, fadeOut)
    
    self.configuration = PlayerConfiguration(
        crossfadeDuration: unifiedCrossfade,
        fadeCurve: configuration.fadeCurve,
        repeatMode: .singleTrack,  // Auto-set to singleTrack
        repeatCount: configuration.repeatCount,
        volume: configuration.volume,
        mixWithOthers: configuration.mixWithOthers
    )
    
    await syncConfigurationToPlaylistManager()
}
```

#### Lines 1093-1094: calculateAdaptedCrossfadeDuration
```swift
// ❌ CURRENT (BROKEN)
private func calculateAdaptedCrossfadeDuration(trackDuration: TimeInterval) -> TimeInterval {
    let configuredFadeIn = configuration.singleTrackFadeInDuration   // ❌ DOES NOT EXIST
    let configuredFadeOut = configuration.singleTrackFadeOutDuration // ❌ DOES NOT EXIST
    
    let maxFadeIn = min(configuredFadeIn, trackDuration * 0.4)
    let maxFadeOut = min(configuredFadeOut, trackDuration * 0.4)
    // ...
}

// ✅ FIX: Use computed fadeInDuration and derive fadeOut
private func calculateAdaptedCrossfadeDuration(trackDuration: TimeInterval) -> TimeInterval {
    // In v4.0: fadeIn = crossfade * 0.3, fadeOut = crossfade * 0.7
    let configuredFadeIn = configuration.fadeInDuration  // ✅ Computed property
    let configuredFadeOut = configuration.crossfadeDuration * 0.7
    
    let maxFadeIn = min(configuredFadeIn, trackDuration * 0.4)
    let maxFadeOut = min(configuredFadeOut, trackDuration * 0.4)
    
    let totalMax = min(maxFadeIn + maxFadeOut, trackDuration * 0.8)
    return totalMax
}
```

#### Additional Occurrences (Lines 1197, 1348)
Same pattern - use `configuration.fadeInDuration` (computed) and derive fadeOut.

---

### 2. AudioPlayerViewModel.swift (Demo App) - 6 errors

#### Lines 47-48: Property declarations
```swift
// ❌ CURRENT (BROKEN)
var singleTrackFadeIn: TimeInterval = 2.0
var singleTrackFadeOut: TimeInterval = 2.0

// ✅ FIX: Use single crossfade duration
var crossfadeDuration: TimeInterval = 10.0  // Unified duration
```

#### Lines 189-193: setSingleTrackFadeDurations call
```swift
// ❌ CURRENT (BROKEN)
try await audioService.setSingleTrackFadeDurations(
    fadeIn: singleTrackFadeIn,
    fadeOut: singleTrackFadeOut
)

// ✅ FIX Option 1: Use deprecated method (temporary)
try await audioService.setSingleTrackFadeDurations(
    fadeIn: crossfadeDuration * 0.3,
    fadeOut: crossfadeDuration * 0.7
)

// ✅ FIX Option 2: Set config directly (preferred)
// Remove this call entirely, set crossfade in PlayerConfiguration
```

#### Lines 254-260: Configuration creation
```swift
// ❌ CURRENT (BROKEN)
return PlayerConfiguration(
    crossfadeDuration: crossfadeDuration,
    fadeCurve: selectedCurve,
    repeatMode: repeatMode,
    repeatCount: repeatCount,
    singleTrackFadeInDuration: singleTrackFadeIn,   // ❌ DOES NOT EXIST
    singleTrackFadeOutDuration: singleTrackFadeOut, // ❌ DOES NOT EXIST
    volume: volume,
    mixWithOthers: mixWithOthers
)

// ✅ FIX: Remove non-existent parameters
return PlayerConfiguration(
    crossfadeDuration: crossfadeDuration,
    fadeCurve: selectedCurve,
    repeatMode: repeatMode,
    repeatCount: repeatCount,
    volume: volume,
    mixWithOthers: mixWithOthers
)
```

---

### 3. ConfigurationView.swift (Demo UI) - 12 errors

#### Lines 33-77: Single Track Fade Controls
```swift
// ❌ CURRENT (BROKEN)
VStack {
    HStack {
        Text("Fade In: ")
        Text(String(format: "%.1fs", viewModel.singleTrackFadeIn))
    }
    Slider(value: $viewModel.singleTrackFadeIn, in: 0.5...10.0)
    
    HStack {
        Text("Fade Out: ")
        Text(String(format: "%.1fs", viewModel.singleTrackFadeOut))
    }
    Slider(value: $viewModel.singleTrackFadeOut, in: 0.5...10.0)
}

// ✅ FIX: Replace with unified crossfade control
VStack {
    HStack {
        Text("Crossfade Duration: ")
            .font(.subheadline)
        Spacer()
        Text(String(format: "%.1fs", viewModel.crossfadeDuration))
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .monospacedDigit()
    }
    
    Slider(value: Binding(
        get: { viewModel.crossfadeDuration },
        set: { newValue in
            viewModel.crossfadeDuration = newValue
            // Auto-update configuration
            Task {
                try? await Task.sleep(for: .milliseconds(500))
                await viewModel.updateSingleTrackFadeDurations()
            }
        }
    ), in: 1.0...30.0, step: 0.5)
    .tint(.blue)
    
    // Show computed fade in/out for reference
    HStack {
        Text("Fade In: \(String(format: "%.1fs", viewModel.crossfadeDuration * 0.3))")
            .font(.caption)
            .foregroundStyle(.secondary)
        Spacer()
        Text("Fade Out: \(String(format: "%.1fs", viewModel.crossfadeDuration * 0.7))")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}
```

---

### 4. PlayerConfigurationTests.swift (Tests) - 12+ errors

#### All tests referencing deleted properties
```swift
// ❌ CURRENT (BROKEN)
@Test("Default values")
func testDefaultValues() {
    let config = PlayerConfiguration()
    #expect(config.singleTrackFadeInDuration == 3.0)   // ❌ DOES NOT EXIST
    #expect(config.singleTrackFadeOutDuration == 3.0)  // ❌ DOES NOT EXIST
    #expect(config.stopFadeDuration == 3.0)            // ❌ DOES NOT EXIST
}

@Test("Single track fade in clamps to minimum 0.5")
func testSingleTrackFadeInMinClamp() {
    let config = PlayerConfiguration(singleTrackFadeInDuration: 0.2)  // ❌ PARAM DOES NOT EXIST
    #expect(config.singleTrackFadeInDuration == 0.5)                  // ❌ PROPERTY DOES NOT EXIST
}

// Similar for fadeOut, stopFadeDuration tests...

// ✅ FIX: Replace with v4.0 property tests
@Test("Default values v4.0")
func testDefaultValuesV4() {
    let config = PlayerConfiguration()
    #expect(config.crossfadeDuration == 10.0)
    #expect(config.fadeCurve == .equalPower)
    #expect(config.repeatMode == .off)
    #expect(config.volume == 100)
    #expect(config.mixWithOthers == false)
}

@Test("Crossfade duration clamps to minimum 1.0")
func testCrossfadeDurationMinClamp() {
    let config = PlayerConfiguration(crossfadeDuration: 0.5)
    #expect(config.crossfadeDuration == 1.0)
}

@Test("Crossfade duration clamps to maximum 30.0")
func testCrossfadeDurationMaxClamp() {
    let config = PlayerConfiguration(crossfadeDuration: 50.0)
    #expect(config.crossfadeDuration == 30.0)
}

@Test("Computed fadeInDuration is 30% of crossfade")
func testFadeInDurationComputed() {
    let config = PlayerConfiguration(crossfadeDuration: 10.0)
    #expect(config.fadeInDuration == 3.0)  // 10.0 * 0.3
}

// Remove all tests for deleted properties
// @Test("Single track fade in/out clamps") - DELETE
// @Test("Stop fade duration clamps") - DELETE
```

---

## 🛠 Implementation Plan

### Phase 1: Core Library Fix (AudioPlayerService.swift)

**Priority**: 🔴 CRITICAL
**Files**: 1
**Lines to fix**: ~25

1. **Lines 85-91**: Remove singleTrack/stopFade params from init
2. **Lines 515-522**: Same fix in setVolume
3. **Lines 548-556**: Same fix in setRepeatMode  
4. **Lines 619-627**: Deprecate setSingleTrackFadeDurations, add v4.0 logic
5. **Lines 1093-1094**: Use `fadeInDuration` computed property
6. **Lines 1197, 1348**: Same as #5

**Commands**:
```bash
# Replace old params with new ones in 3 places
edit_file_regex({
  path: "Sources/AudioServiceKit/Public/AudioPlayerService.swift",
  pattern: "singleTrackFadeInDuration: configuration\\.singleTrackFadeInDuration,\\s*singleTrackFadeOutDuration: configuration\\.singleTrackFadeOutDuration,\\s*",
  replacement: "",
  flags: "g"
})

edit_file_regex({
  path: "Sources/AudioServiceKit/Public/AudioPlayerService.swift", 
  pattern: "stopFadeDuration: configuration\\.stopFadeDuration,?\\s*",
  replacement: "",
  flags: "g"
})

# Fix calculateAdaptedCrossfadeDuration
replace_lines({
  path: "Sources/AudioServiceKit/Public/AudioPlayerService.swift",
  startLine: 1093,
  endLine: 1094,
  newContent: "        let configuredFadeIn = configuration.fadeInDuration  // Computed: crossfade * 0.3\n        let configuredFadeOut = configuration.crossfadeDuration * 0.7"
})
```

### Phase 2: Demo App Fix

**Priority**: 🟡 HIGH  
**Files**: 2
**Lines to fix**: ~35

#### AudioPlayerViewModel.swift
```bash
# Remove old properties, add new
replace_lines({
  path: "Examples/.../AudioPlayerViewModel.swift",
  startLine: 47,
  endLine: 48,
  newContent: "    var crossfadeDuration: TimeInterval = 10.0  // Unified v4.0 fade duration"
})

# Fix buildConfiguration
replace_lines({
  path: "Examples/.../AudioPlayerViewModel.swift",
  startLine: 254,
  endLine: 260,
  newContent: """
        return PlayerConfiguration(
            crossfadeDuration: crossfadeDuration,
            fadeCurve: selectedCurve,
            repeatMode: repeatMode,
            repeatCount: repeatCount,
            volume: volume,
            mixWithOthers: mixWithOthers
        )
"""
})

# Deprecate setSingleTrackFadeDurations call or remove
# Lines 189-193
```

#### ConfigurationView.swift
```bash
# Replace fade in/out sliders with single crossfade slider
# Lines 33-77 - see detailed fix above
```

### Phase 3: Tests Fix

**Priority**: 🟢 MEDIUM
**Files**: 1  
**Lines to fix**: ~40

```bash
# Delete all tests for removed properties
# Add new tests for v4.0 properties
# See detailed test fixes above
```

---

## ✅ Validation Checklist

After implementing all fixes:

- [ ] **Build Success**: `swift build` completes without errors
- [ ] **Test Success**: All tests pass
- [ ] **Demo App**: Runs without crashes
- [ ] **API Compatibility**: Deprecated methods still work (with warnings)
- [ ] **Documentation**: README updated with v4.0 migration guide

---

## 📊 Impact Summary

| Component | Errors | Lines to Fix | Complexity |
|-----------|--------|--------------|------------|
| AudioPlayerService.swift | 10 | ~25 | Medium |
| AudioPlayerViewModel.swift | 6 | ~15 | Low |
| ConfigurationView.swift | 12 | ~20 | Low |
| PlayerConfigurationTests.swift | 12+ | ~40 | Low |
| **TOTAL** | **40+** | **~100** | **Medium** |

---

## 🔄 Migration Strategy

### For Library Users

**v3.x Code (Old)**:
```swift
let config = PlayerConfiguration(
    crossfadeDuration: 10.0,
    singleTrackFadeInDuration: 2.0,
    singleTrackFadeOutDuration: 3.0,
    stopFadeDuration: 2.0
)

try await player.setSingleTrackFadeDurations(fadeIn: 2.0, fadeOut: 3.0)
```

**v4.0 Code (New)**:
```swift
// Unified crossfade for all transitions
let config = PlayerConfiguration(
    crossfadeDuration: 10.0,  // Used for ALL fades
    repeatMode: .singleTrack  // Enable loop with fade
)

// No need for setSingleTrackFadeDurations
// Fade in/out calculated automatically:
// - fadeIn = crossfade * 0.3 (e.g., 3.0s for 10s crossfade)
// - fadeOut = crossfade * 0.7 (e.g., 7.0s for 10s crossfade)

// Stop fade is now a method parameter:
await player.stop(fadeDuration: 2.0)  // Optional fade on stop
```

---

## 🎯 Execution Order

1. ✅ Create this plan (DONE)
2. 🔄 **Fix AudioPlayerService.swift** (Core library)
3. 🔄 **Fix Demo App** (ViewModel + View)
4. 🔄 **Fix Tests** (Update test cases)
5. 🔄 **Verify Build** (`swift build`)
6. 🔄 **Run Tests** (`swift test`)
7. 🔄 **Update README** (Migration guide)

---

## 📝 Notes

- **No breaking changes to public API** (except deprecated methods)
- **Backward compatibility** via deprecated wrapper methods
- **Simplified user experience** - one duration instead of three
- **Auto-calculated fades** - fadeIn = 30% of crossfade

---

**Ready to execute?** Start with Phase 1: AudioPlayerService.swift
