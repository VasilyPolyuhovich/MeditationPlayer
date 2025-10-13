# Quick Start Guide

Get ProsperPlayerDemo running in 5 minutes!

## Prerequisites

- Xcode 15.0+
- iOS 15.0+ device/simulator
- ProsperPlayer SDK (already in ../../)

## Step 1: Setup Audio Files (30 seconds)

```bash
cd Examples/ProsperPlayerDemo
chmod +x setup.sh
./setup.sh
```

This copies and renames audio files:
- `sample1.mp3` → `voiceover1.mp3`
- `sample2.mp3` → `voiceover2.mp3`
- `sample3.mp3` → `voiceover3.mp3`

## Step 2: Create Xcode Project (2 minutes)

### Option A: Command Line
```bash
# Coming soon: automated Xcode project generation
```

### Option B: Xcode GUI (recommended for now)

1. **Open Xcode**
   ```bash
   open -a Xcode
   ```

2. **Create New Project**
   - File > New > Project
   - iOS > App
   - Product Name: `ProsperPlayerDemo`
   - Interface: SwiftUI
   - Language: Swift
   - Location: `Examples/ProsperPlayerDemo/`

3. **Add SDK Package**
   - File > Add Package Dependencies
   - Add Local: `../../` (navigate to ProsperPlayer root)
   - Select both:
     - ✅ AudioServiceCore
     - ✅ AudioServiceKit

4. **Add Source Files**
   - Drag these folders to Xcode navigator:
     - `App/`
     - `ViewModels/`
     - `Views/`
     - `Components/`
   - ✅ Check "Create groups"
   - ✅ Check "Add to target: ProsperPlayerDemo"

5. **Add Audio Files**
   - Drag `voiceover*.mp3` to project
   - ✅ Check "Copy items if needed"
   - ✅ Check "Add to target: ProsperPlayerDemo"

6. **Delete Default Files**
   - Remove `ContentView.swift` (we have our own)
   - Keep `ProsperPlayerDemoApp.swift` but **replace** with our version from `App/`

## Step 3: Build & Run! (30 seconds)

```bash
⌘R
```

## 🎉 Success!

You should see:
- **Main Screen** with player controls
- **Playlists** button (top right)
- **Settings** button (top right)

### Try These Features:

1. **Basic Playback**
   - Tap Play ▶️
   - Should start playing voiceover1 + voiceover2

2. **Hot Swap**
   - Tap "Playlists"
   - Select "All Three"
   - Tap "Replace Playlist"
   - Watch the smooth crossfade! 🎵

3. **Crossfade Visualization**
   - During crossfade, orange indicator appears
   - Shows volume levels of both tracks
   - Real-time progress bar

4. **Settings**
   - Adjust crossfade duration (1-30s)
   - Try different fade curves
   - Change repeat modes

## 🐛 Troubleshooting

### "No such module 'AudioServiceKit'"
- Make sure you added the package dependency correctly
- Build the project once (⌘B) to compile dependencies

### "Audio files not found"
- Run `./setup.sh` from Examples/ProsperPlayerDemo/
- Check that voiceover*.mp3 are in Xcode's file navigator
- Make sure they're added to target (check inspector)

### "Ambiguous use of 'PlayerViewModel'"
- Make sure you deleted or replaced the default ContentView.swift
- Clean build folder (⌘⇧K) and rebuild

## 📚 Learn More

- **README.md** - Full project documentation
- **Code Comments** - Every file is well-documented
- **../../docs/** - SDK architecture details

## 💡 Tips

- Use iOS Simulator for faster testing
- Enable Xcode Preview for live UI updates
- Check console logs for SDK debug info
- Try different fade curves - Equal Power sounds best!

---

**Need Help?**
Check the main project README or file an issue!
