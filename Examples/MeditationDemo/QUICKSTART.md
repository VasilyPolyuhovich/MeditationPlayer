# MeditationDemo - Quick Start

⚡ **5-Minute Setup Guide**

---

## Prerequisites

- Xcode 15.0+
- iOS 15+ device/simulator
- Swift 6.0

---

## Setup Steps

### 1. Open Project
```bash
cd Examples/MeditationDemo
open MeditationDemo.xcodeproj
```

### 2. Verify Audio Files
Ensure bundle contains:
- ✅ `sample1.mp3`
- ✅ `sample2.mp3`

### 3. Build & Run
```
⌘R (Run)
```

---

## First Run Experience

### UI Overview
```
┌─────────────────────────────────┐
│  [State Badge]  SAMPLE1         │  ← StatusView
│  0:00 / 3:25                    │
│  ████████░░░░░ 60%              │
├─────────────────────────────────┤
│  ◀15  ▶▶  ▶15                   │  ← PlayerControlsView
│  [Stop] [Reset]                 │
│  🔊━━━━━━━━━━ 100%              │
├─────────────────────────────────┤
│  🎵 Track Management            │  ← TrackSwitcherView
│  ☑ Playlist Mode                │
│  [Switch Track]                 │
└─────────────────────────────────┘
```

### Test Flow

1. **Start Playback**
   - Tap ▶ → sample1.mp3 plays with 3s fade-in
   
2. **Playlist Auto-Advance** (default ON)
   - Wait for track end
   - Observe 10s crossfade to sample2.mp3
   - Continues: sample2 → sample1 → sample2...

3. **Manual Switch**
   - Tap "Switch Track" → immediate 10s crossfade

4. **Skip Testing**
   - Tap ◀15 or ▶15 → no clicking sound (fade-enabled)

5. **Configuration**
   - Tap ⚙️ → adjust crossfade duration
   - Change fade curve → hear difference

---

## Key Features Demo

### Feature 1: Playlist Mode ✨
```
[x] Playlist Mode
Auto-advance tracks with crossfade
```
- **ON**: sample1 → sample2 → sample1 (auto)
- **OFF**: single-track loop only

### Feature 2: Crossfade Curves
```
Settings → Curve Algorithm:
- Equal Power (Default) ← Best for music
- Linear               ← Simple
- Logarithmic          ← Fast start
- Exponential          ← Slow start
- S-Curve              ← Smooth extremes
```

### Feature 3: Click-Free Seek
```
Skip ±15s → uses seekWithFade()
100ms fade eliminates buffer clicks
```

---

## Configuration Presets

### Meditation (Default)
```swift
crossfade: 10.0s
fadeIn:     3.0s
fadeOut:    6.0s
curve:     .equalPower
playlist:   true
```

### Quick Transitions
```swift
crossfade:  2.0s
fadeIn:     0.5s
fadeOut:    1.0s
curve:     .linear
playlist:   true
```

### Smooth Loops
```swift
crossfade: 15.0s
fadeIn:     5.0s
fadeOut:   10.0s
curve:     .sCurve
playlist:   false  // single-track
```

---

## Troubleshooting

| Issue | Solution |
|-------|----------|
| No sound | Check volume slider (not muted) |
| Clicking on skip | Verify using `seekWithFade()` |
| Gap in crossfade | Increase buffer delay (2048 samples) |
| Background stops | Enable "audio" in Background Modes |
| Playlist stuck | Check `isCrossfading` flag |

---

## Code Integration (30 seconds)

```swift
// 1. Import
import AudioServiceKit

// 2. Create Service
@State private var service = AudioPlayerService()

// 3. Setup
await service.setup()

// 4. Play
let config = AudioConfiguration(crossfadeDuration: 10.0)
try await service.startPlaying(url: audioURL, configuration: config)
```

**That's it!** 🎉

---

## Next Steps

1. ✅ Run demo → understand UI flow
2. 📖 Read [README.md](README.md) → architecture details
3. 🔍 Study [AudioPlayerViewModel.swift](MeditationDemo/ViewModels/AudioPlayerViewModel.swift) → observer pattern
4. 🛠️ Integrate into your app

---

## Performance Verification

```
Memory:  ~20MB (2 tracks)
CPU:     <10% (30s fade)
Latency:  46ms (sync)
Updates:   2 Hz (position)
```

Run Instruments for validation.

---

**Support:** [Documentation](../../Documentation/)  
**Issues:** [GitHub](https://github.com/yourorg/prosperplayer/issues)
