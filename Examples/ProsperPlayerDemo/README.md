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
│   └── SettingsView.swift              # SDK configuration
├── Components/
│   ├── PlayerControls.swift            # Play/pause/skip
│   ├── PositionTracker.swift           # Progress bar
│   └── CrossfadeVisualizer.swift       # Live crossfade indicator
└── Assets/
    ├── voiceover1.mp3                  # Test audio
    ├── voiceover2.mp3                  # Test audio
    └── voiceover3.mp3                  # Test audio
```

## 🚀 Quick Start

### 1. Add Audio Files

Copy 3 MP3 files to `ProsperPlayerDemo/` and rename them:
- `voiceover1.mp3`
- `voiceover2.mp3`
- `voiceover3.mp3`

> **Tip:** You can copy from `../MeditationDemo/MeditationDemo/MeditationDemo/sample*.mp3`

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

### Playlists View
- Hot swap demonstration
- Crossfade vs silent switch
- Preset playlists
- Current playlist display

### Settings View
- Crossfade duration (1-30s)
- Fade curve selection
- Repeat mode configuration
- SDK technical info

## 📝 Key Code Patterns

### Loading Playlist
```swift
try await viewModel.loadPlaylist(["voiceover1", "voiceover2"])
```

### Hot Swap (with crossfade)
```swift
try await viewModel.replacePlaylist(["voiceover3", "voiceover1"])
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
