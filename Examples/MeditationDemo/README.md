# Meditation Demo App

SwiftUI demo application showcasing Prosper Player audio service capabilities.

## Features

- ▶️ Play/Pause/Resume controls
- ⏭ Skip forward/backward (15 seconds)
- 🔊 Volume control
- 📊 Playback position display
- 🎨 Visual state indicators
- 🔄 Real-time state updates

## Setup

1. **Add Sample Audio File**
   - Add an audio file named `sample.mp3` to the app bundle
   - Or modify `ContentView.swift` to use your own audio file

2. **Run the App**
   - Open in Xcode
   - Select iPhone simulator or device
   - Build and run (⌘R)

## Testing Background Playback

1. Start playback in the app
2. Press Home button (or swipe up on devices without Home button)
3. Audio should continue playing
4. Open Control Center to see Lock Screen controls
5. Test play/pause and skip controls from Lock Screen

## Testing Interruptions

### Phone Call Interruption
1. Start playback
2. Receive a phone call (use another device or simulator)
3. Audio should pause automatically
4. After call ends, audio resumes (if system allows)

### Headphone Unplugging
1. Start playback with headphones connected
2. Unplug headphones
3. Audio should pause immediately
4. Plug headphones back in
5. Press play to resume

### Siri Pause
1. Start playback
2. Activate Siri and say "Pause"
3. Audio pauses
4. App should NOT auto-resume after Siri finishes

## Configuration

Modify the configuration in `ContentView.swift`:

```swift
let config = AudioConfiguration(
    crossfadeDuration: 10.0,      // Crossfade duration
    fadeInDuration: 3.0,          // Fade in at start
    fadeOutDuration: 6.0,         // Fade out at end
    volume: volume,               // Initial volume
    repeatCount: nil,             // Infinite loop
    enableLooping: true           // Enable looping
)
```

## UI Components

### Status Display
- Shows current player state with color coding:
  - 🟢 Green = Playing
  - 🔵 Blue = Paused
  - 🟠 Orange = Preparing/Fading Out
  - ⚪️ Gray = Ready
  - 🔴 Red = Error

### Track Info
- Displays track title, artist, and duration
- Updates when new audio file loads

### Progress Bar
- Shows current position and total duration
- Updates 4 times per second for smooth animation

### Control Buttons
- **Skip Backward (-15s)**: Skip back 15 seconds
- **Play/Pause**: Toggle playback
- **Skip Forward (+15s)**: Skip forward 15 seconds
- **Start Demo**: Load and start playing sample audio
- **Stop**: Stop playback completely

### Volume Slider
- Range: 0% to 100%
- Real-time volume adjustment
- Shows current volume percentage

## Architecture

```
MeditationDemo/
├── Sources/
│   ├── MeditationDemoApp.swift    # App entry point
│   └── ContentView.swift          # Main UI
└── Info.plist                      # Background audio capability
```

## State Flow

```
Finished → Preparing → Playing ⇄ Paused
              ↓
         Fading Out
              ↓
           Finished

Any state → Failed (on error)
```

## Troubleshooting

### No Audio Playing
- Check that sample audio file is in bundle
- Verify background audio capability is enabled
- Check device volume is not muted
- Ensure audio session is properly configured

### Background Audio Not Working
- Verify Info.plist has `audio` in UIBackgroundModes
- Check that audio session is active before entering background
- Ensure actual audio is playing (not silent)

### Lock Screen Controls Not Appearing
- Make sure Now Playing info is being updated
- Verify remote command handlers are registered
- Check that audio is actively playing

## Requirements

- iOS 18.0+
- Xcode 16.0+
- Swift 6.0+

## Next Steps

- Add file picker to select custom audio files
- Implement playlist functionality
- Add visualization (waveform, spectrum)
- Support for multiple phases (induction, intentions, returning)
- Theme switching with crossfade

---

Happy coding! 🎵
