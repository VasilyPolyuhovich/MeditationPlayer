#!/bin/bash

# ProsperPlayerDemo - Quick Setup Script

set -e

echo "🚀 ProsperPlayerDemo Setup"
echo "=========================="
echo ""

# Check if we're in the right directory
if [ ! -d "ProsperPlayerDemo" ]; then
    echo "❌ Error: Run this script from Examples/ProsperPlayerDemo/"
    exit 1
fi

echo "📂 Copying audio files..."

# Source path
SOURCE="../MeditationDemo/MeditationDemo/MeditationDemo"

# Check if source exists
if [ ! -d "$SOURCE" ]; then
    echo "❌ Error: MeditationDemo not found at $SOURCE"
    exit 1
fi

# Copy and rename MP3 files
if [ -f "$SOURCE/sample1.mp3" ]; then
    cp "$SOURCE/sample1.mp3" "ProsperPlayerDemo/voiceover1.mp3"
    echo "✅ voiceover1.mp3"
else
    echo "⚠️  sample1.mp3 not found"
fi

if [ -f "$SOURCE/sample2.mp3" ]; then
    cp "$SOURCE/sample2.mp3" "ProsperPlayerDemo/voiceover2.mp3"
    echo "✅ voiceover2.mp3"
else
    echo "⚠️  sample2.mp3 not found"
fi

if [ -f "$SOURCE/sample3.mp3" ]; then
    cp "$SOURCE/sample3.mp3" "ProsperPlayerDemo/voiceover3.mp3"
    echo "✅ voiceover3.mp3"
else
    echo "⚠️  sample3.mp3 not found"
fi

echo ""
echo "✅ Setup complete!"
echo ""
echo "📝 Next steps:"
echo "   1. Open Xcode"
echo "   2. Create new iOS App project named 'ProsperPlayerDemo'"
echo "   3. Add package dependency: ../../ (ProsperPlayer root)"
echo "   4. Add all source files to project"
echo "   5. Add voiceover*.mp3 to bundle"
echo "   6. Build and run!"
echo ""
echo "📖 See README.md for detailed instructions"
