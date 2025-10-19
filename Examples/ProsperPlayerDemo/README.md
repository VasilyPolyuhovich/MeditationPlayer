# ProsperPlayer SDK Demo

**Technical showcase for ProsperPlayer SDK v4.0**

A clean, focused demonstration of all SDK capabilities - **not** a production meditation app, but a developer's guide to SDK integration.

## 🎯 Purpose

This demo showcases:
- ✅ Actor-isolated audio service (Swift 6)
- ✅ Dual-player crossfade architecture
- ✅ Hot playlist swapping with seamless transitions
- ✅ Live crossfade visualization
- ✅ Real-time position tracking
- ✅ Configurable fade curves
- ✅ Repeat modes (off, single track, playlist)
- ✅ Sound Effects with LRU cache & auto-preload
- ✅ Overlay player for ambient sounds
- ✅ Background playback ready

## 📁 Project Structure

```
ProsperPlayerDemo/
├── App/
│   └── ProsperPlayerDemoApp.swift      # Entry point
├── ViewModels/
│   └── PlayerViewModel.swift           # Main coordinator
├── Views/
│   ├── MainView.swift                  # Player UI
│   ├── PlaylistsView.swift             # Hot swap demo
│   ├── OverlayView.swift               # Ambient overlay demo
│   ├── SoundEffectsView.swift          # Sound effects demo
│   └── SettingsView.swift              # SDK configuration
├── Components/
│   ├── PlayerControls.swift            # Play/pause/skip
│   ├── PositionTracker.swift           # Progress bar
│   └── CrossfadeVisualizer.swift       # Live crossfade indicator
└── Resources/
    ├── sample1.mp3                     # Main track
    ├── sample2.mp3                     # Main track
    ├── sample3.mp3                     # Main track
    ├── sample4.mp3                     # Main track
    ├── voiceover1.mp3                  # Overlay track
    ├── voiceover2.mp3                  # Overlay track
    ├── voiceover3.mp3                  # Overlay track
    ├── bell.mp3                        # Sound effect (add manually)
    ├── gong.mp3                        # Sound effect (add manually)
    └── count_down.mp3                  # Sound effect (add manually)
```

## 🚀 Quick Start

### 1. Add Audio Files

**Main Tracks (already included):**
- `sample1.mp3`, `sample2.mp3`, `sample3.mp3`, `sample4.mp3`

**Overlay Tracks (already included):**
- `voiceover1.mp3`, `voiceover2.mp3`, `voiceover3.mp3`

**Sound Effects (add manually):**
- `bell.mp3` - Short bell sound (1-2 seconds)
- `gong.mp3` - Meditation gong (2-3 seconds)
- `count_down.mp3` - 3-2-1 countdown (3-5 seconds)

> **See:** `SOUND_EFFECTS_SETUP.md` for detailed instructions

### 2. Create Xcode Project

```bash
# From ProsperPlayerDemo directory
open -a Xcode
# File > New > Project > iOS > App
# Name: ProsperPlayerDemo
# Interface: SwiftUI
# Language: Swift
```

### 3. Add SDK Package

In Xcode:
1. File > Add Package Dependencies
2. Enter local path: `../../` (ProsperPlayer root)
3. Select both targets:
   - AudioServiceCore
   - AudioServiceKit

### 4. Add Source Files

Drag all folders to Xcode project:
- App/
- ViewModels/
- Views/
- Components/

### 5. Add Audio Files to Bundle

1. Drag `voiceover*.mp3` files to project
2. Check "Copy items if needed"
3. Add to target: ProsperPlayerDemo

### 6. Run!

```bash
⌘R
```

## 🎨 Features Demo

### Main Screen
- Real-time playback state
- Position tracking with progress bar
- Volume control
- Play/pause/skip buttons
- Live crossfade indicator (when active)
- Quick access to all features

### Playlists View
- Hot swap demonstration
- Crossfade vs silent switch
- Preset playlists
- Current playlist display

### Sound Effects View
- 3 preloaded sound effects (bell, gong, countdown)
- Instant playback with zero latency
- LRU cache visualization
- Auto-preload demonstration
- One-tap triggers for meditation timers

### Overlay View
- Ambient sound playback
- Independent volume control
- Loop configuration (infinite, count, once)
- Dynamic loop delay adjustment
- Simultaneous playback with main track

### Settings View
- Crossfade duration (1-30s)
- Fade curve selection
- Repeat mode configuration
- Volume fade settings
- SDK technical info

## 📝 Key Code Patterns

### Loading Playlist
```swift
try await viewModel.loadPlaylist(["voiceover1", "voiceover2"])
```

### Hot Swap (with crossfade)
```swift
try await viewModel.replacePlaylist(["sample3", "sample1"])
```

### Sound Effects (instant playback)
```swift
// Auto-preloaded on app launch
try await viewModel.playSoundEffect(named: "bell")

// Stop current effect
await viewModel.stopSoundEffect()
```

### Overlay Player (ambient sounds)
```swift
// Play with custom configuration
try await viewModel.playOverlay("voiceover1")

// Stop overlay
await viewModel.stopOverlay()
```

### Observing State
```swift
func playerStateDidChange(_ state: PlayerState) async {
    self.state = state
}

func crossfadeProgressDidUpdate(_ progress: CrossfadeProgress) async {
    self.crossfadeProgress = progress
}
```

## 🔧 Configuration

All SDK settings are in `SettingsView`:

- **Crossfade Duration:** 1-30 seconds
- **Fade Curves:** Linear, Equal Power, Logarithmic, Exponential, S-Curve
- **Repeat Modes:** Off, Single Track, Playlist

## 📚 Learn More

See main project documentation:
- `../../README.md` - Complete SDK guide
- `../../CHANGELOG.md` - Version history
- `../../docs/` - Detailed architecture docs

---

**Version:** 1.0.0  
**SDK:** ProsperPlayer v4.0.0  
**Swift:** 6.0  
**iOS:** 15.0+
