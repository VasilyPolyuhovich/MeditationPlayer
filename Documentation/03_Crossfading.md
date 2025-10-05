# Crossfading Implementation

**Algorithm:** Equal-Power Crossfade  
**Synchronization:** Sample-accurate via AVAudioTime

---

## Equal-Power Principle

### Mathematical Foundation

**Power conservation:**
```
P_total = P_out + P_in = constant

Where P = A² (power ∝ amplitude²)
```

**Trigonometric identity:**
```
cos²(θ) + sin²(θ) = 1, ∀θ ∈ ℝ
```

**Application to fading:**
```
fadeOut(t) = cos(t · π/2),  t ∈ [0,1]
fadeIn(t)  = sin(t · π/2),  t ∈ [0,1]

Proof of constant power:
P(t) = fadeOut²(t) + fadeIn²(t)
     = cos²(t·π/2) + sin²(t·π/2)
     = 1  ✓
```

---

## Implementation

### Fade Curve Functions

```swift
enum FadeCurve: Sendable {
    case equalPower
    
    func volume(for progress: Float) -> Float {
        switch self {
        case .equalPower:
            return sin(progress * .pi / 2)  // 0 → 1
        }
    }
    
    func inverseVolume(for progress: Float) -> Float {
        switch self {
        case .equalPower:
            return cos(progress * .pi / 2)  // 1 → 0
        }
    }
}
```

### Adaptive Step Sizing (v2.6.0)

**Issue #9 fix: Duration-aware optimization**

```swift
func fadeVolume(
    mixer: AVAudioMixerNode,
    from: Float,
    to: Float,
    duration: TimeInterval,
    curve: FadeCurve
) async {
    // Adaptive frequency
    let stepsPerSecond: Int
    if duration < 1.0 {
        stepsPerSecond = 100  // 10ms - ultra smooth
    } else if duration < 5.0 {
        stepsPerSecond = 50   // 20ms - smooth
    } else if duration < 15.0 {
        stepsPerSecond = 30   // 33ms - balanced
    } else {
        stepsPerSecond = 20   // 50ms - efficient
    }
    
    let steps = Int(duration * Double(stepsPerSecond))
    let stepTime = duration / Double(steps)
    
    for i in 0...steps {
        let progress = Float(i) / Float(steps)
        
        let curveValue: Float = from < to 
            ? curve.volume(for: progress)
            : curve.inverseVolume(for: progress)
        
        let newVolume = from + (to - from) * curveValue
        mixer.volume = newVolume
        
        try? await Task.sleep(nanoseconds: UInt64(stepTime * 1e9))
    }
    
    mixer.volume = to  // Exact final value
}
```

**Performance:**
| Duration | Steps | Step Time | Improvement |
|----------|-------|-----------|-------------|
| 1s       | 100   | 10ms      | Baseline    |
| 5s       | 250   | 20ms      | 2× faster   |
| 10s      | 300   | 33ms      | 3.3× faster |
| 30s      | 600   | 50ms      | **5× faster** |

---

## Dual-Player Architecture

### Configuration

```
Player A → Mixer A ─┐
                    ├─→ Main Mixer → Output
Player B → Mixer B ─┘

Initial state:
  mixerA.volume = 0.0
  mixerB.volume = 0.0
  mainMixer.volume = 1.0
```

### Crossfade Sequence

```swift
// 1. Prepare secondary player
func prepareSecondaryPlayer() {
    let file = getInactiveAudioFile()
    let player = getInactivePlayerNode()
    let mixer = getInactiveMixerNode()
    
    mixer.volume = 0.0
    player.scheduleFile(file, at: nil)
    // DON'T start yet
}

// 2. Calculate sync time
func getSyncedStartTime() -> AVAudioTime? {
    guard let lastRenderTime = activePlayer.lastRenderTime else { 
        return nil 
    }
    
    let bufferSamples: AVAudioFramePosition = 2048
    let startSampleTime = lastRenderTime.sampleTime + bufferSamples
    
    return AVAudioTime(
        sampleTime: startSampleTime,
        atRate: lastRenderTime.sampleRate
    )
}

// 3. Synchronized crossfade
func performSynchronizedCrossfade(
    duration: TimeInterval,
    curve: FadeCurve
) async {
    let syncTime = getSyncedStartTime()
    
    // Start at exact sample time
    inactivePlayer.play(at: syncTime)
    
    // Wait for player to start (50ms)
    try? await Task.sleep(nanoseconds: 50_000_000)
    
    // Parallel fades
    async let fadeOut = fadeActiveMixer(from: 1.0, to: 0.0, 
                                        duration: duration, curve: curve)
    async let fadeIn = fadeInactiveMixer(from: 0.0, to: 1.0, 
                                         duration: duration, curve: curve)
    
    await fadeOut
    await fadeIn
}

// 4. Cleanup
func finalizeCrossfade() {
    stopActivePlayer()
    resetInactiveMixer()  // volume = 0.0
    switchActivePlayer()
}
```

---

## Sample-Accurate Synchronization

### Timing Calculation

**Buffer delay formula:**
```
t_start = t_render + N_buffer / f_s

Where:
  t_render = last render time (samples)
  N_buffer = buffer size (samples)
  f_s = sample rate (Hz)
```

**Example @ 44.1kHz:**
```
N_buffer = 2048 samples
f_s = 44100 Hz
Δt = 2048 / 44100 ≈ 46.4 ms
```

### AVAudioTime Construction

```swift
let syncTime = AVAudioTime(
    sampleTime: lastRenderTime.sampleTime + 2048,
    atRate: 44100.0
)

player.play(at: syncTime)
```

**Precision:** ± 1 sample = 0.023ms @ 44.1kHz

---

## Perceptual Analysis

### Loudness Perception

**Stevens' Power Law:**
```
L_perceived = k · I^α

Where:
  L = perceived loudness
  I = intensity (power)
  α ≈ 0.3 (for sound)
  k = constant
```

**Linear fade error:**
```
At t = 0.5 (midpoint):
  A_out = 0.5, A_in = 0.5
  P_total = 0.5² + 0.5² = 0.5
  L_perceived ∝ 0.5^0.3 ≈ 0.76
  
Perceived drop: ~24% ❌
```

**Equal-power correction:**
```
At t = 0.5:
  A_out = cos(π/4) ≈ 0.707
  A_in = sin(π/4) ≈ 0.707
  P_total = 0.707² + 0.707² = 1.0
  L_perceived ∝ 1.0^0.3 = 1.0
  
Perceived drop: 0% ✓
```

---

## Loop Crossfading

### Trigger Detection (Issue #8 Fix)

**Epsilon tolerance for float precision:**
```swift
private let triggerTolerance: TimeInterval = 0.1  // 100ms

func shouldTriggerLoopCrossfade(_ position: PlaybackPosition) -> Bool {
    guard configuration.enableLooping else { return false }
    guard !isLoopCrossfadeInProgress else { return false }
    guard state == .playing else { return false }
    
    let triggerPoint = position.duration - configuration.crossfadeDuration
    
    // IEEE 754 safety: use tolerance
    return position.currentTime >= (triggerPoint - triggerTolerance) && 
           position.currentTime < position.duration
}
```

**Rationale:**
- IEEE 754 errors: typ. < 0.001s
- 100ms tolerance: 100× safety margin
- Prevents missed triggers: 49.9999 ≠ 50.0

### Loop Sequence

```swift
func startLoopCrossfade() async {
    isLoopCrossfadeInProgress = true
    
    // 1. Check if should finish
    let shouldFinish = checkShouldFinishAfterLoop()
    
    // 2. Prepare loop on secondary
    await audioEngine.prepareLoopOnSecondaryPlayer()
    
    // 3. Synchronized crossfade
    await audioEngine.performSynchronizedCrossfade(
        duration: configuration.crossfadeDuration,
        curve: configuration.fadeCurve
    )
    
    // 4. Cleanup
    await audioEngine.stopActivePlayer()
    await audioEngine.resetInactiveMixer()
    await audioEngine.switchActivePlayer()
    
    // 5. Update count
    currentRepeatCount += 1
    
    // 6. Finish if limit reached
    if shouldFinish {
        try? await finish(fadeDuration: configuration.fadeOutDuration)
    } else {
        isLoopCrossfadeInProgress = false
    }
}
```

---

## Energy Conservation Proof

**Theorem:** Equal-power crossfade maintains constant energy.

**Proof:**
```
Let:
  E(t) = total energy at time t
  A_out(t) = fadeOut amplitude
  A_in(t) = fadeIn amplitude
  
Given:
  A_out(t) = cos(t·π/2)
  A_in(t) = sin(t·π/2)
  
Energy:
  E(t) = A_out²(t) + A_in²(t)
       = cos²(t·π/2) + sin²(t·π/2)
       = 1  (by trigonometric identity)
       
Therefore: E(t) = constant, ∀t ∈ [0,1]  QED
```

---

## Frequency Response

**Crossfade does not affect frequency content:**

```
H_out(f,t) = cos(t·π/2) · X_out(f)
H_in(f,t)  = sin(t·π/2) · X_in(f)

Where X(f) is frequency spectrum.

Magnitude response:
|H_total(f,t)|² = |H_out|² + |H_in|²
                = [cos²(t·π/2) + sin²(t·π/2)] · |X(f)|²
                = |X(f)|²
                
No spectral coloration ✓
```

---

## Performance Metrics

### CPU Usage

**Old implementation (fixed 10ms):**
```
Duration: 30s
Steps: 3000
CPU: ~3% (3000 timer callbacks)
```

**New implementation (adaptive):**
```
Duration: 30s  
Steps: 600
CPU: ~0.6% (600 timer callbacks)
Improvement: 5× reduction
```

### Memory

**Per crossfade:**
- Active file: ~10MB (typical)
- Inactive file: ~10MB (loaded during crossfade)
- Peak: ~20MB (both files in memory)
- Post-crossfade: ~10MB (old file released)

---

## Testing

### Unit Test: Power Conservation

```swift
@Test
func testEqualPowerMaintainsEnergy() {
    let curve = FadeCurve.equalPower
    let steps = 100
    
    for i in 0...steps {
        let t = Float(i) / Float(steps)
        let fadeOut = curve.inverseVolume(for: t)
        let fadeIn = curve.volume(for: t)
        
        let totalPower = fadeOut * fadeOut + fadeIn * fadeIn
        
        #expect(abs(totalPower - 1.0) < 0.001)  // 0.1% tolerance
    }
}
```

### Integration Test: Synchronization

```swift
@Test
func testCrossfadeSynchronization() async throws {
    let service = AudioPlayerService()
    await service.setup()
    
    let config = AudioConfiguration(crossfadeDuration: 2.0)
    try await service.startPlaying(url: trackA, configuration: config)
    
    // Measure crossfade timing
    let start = Date()
    try await service.replaceTrack(url: trackB, crossfadeDuration: 2.0)
    let elapsed = Date().timeIntervalSince(start)
    
    // Should complete within 2.0s ± 100ms
    #expect(abs(elapsed - 2.0) < 0.1)
}
```

---

## References

- [Equal-Power Panning Laws - AES](https://www.aes.org/e-lib/browse.cfm?elib=7217)
- [Constant-Power Crossfading - CCRMA](https://ccrma.stanford.edu/~jos/pasp/Constant_Power_Panning.html)
- [Psychoacoustics - Stevens' Power Law](https://en.wikipedia.org/wiki/Stevens%27s_power_law)
- WWDC 2014-502: AVAudioEngine in Practice
- Digital Signal Processing - Proakis & Manolakis (4th ed.)
