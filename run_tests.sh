#!/bin/bash

# iOS Library Test Runner for SPM Package
echo "🧪 Running ProsperPlayer tests on iOS Simulator..."
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# Find first available iOS iPhone Simulator and get its ID
echo "🔍 Finding available iOS Simulator..."

# Get first iPhone simulator ID (Shutdown is OK - xcodebuild will boot it)
DEVICE_ID=$(xcrun simctl list devices | \
  grep "iPhone" | \
  head -1 | \
  sed 's/.*(\([A-F0-9-]*\)).*/\1/')

if [ -z "$DEVICE_ID" ]; then
  echo -e "${RED}❌ No iOS Simulator found!${NC}"
  echo "Please install Xcode and iOS Simulator"
  exit 1
fi

# Get device name for display
DEVICE_NAME=$(xcrun simctl list devices | grep "$DEVICE_ID" | sed 's/^[[:space:]]*\(.*\) ([A-F0-9-]*).*/\1/')

echo "📱 Using: $DEVICE_NAME"
echo "🆔 ID: $DEVICE_ID"
echo ""

# Run tests with device ID (xcodebuild will boot simulator if needed)
echo "🚀 Running tests..."
xcodebuild test \
  -scheme ProsperPlayer-Package \
  -destination "platform=iOS Simulator,id=$DEVICE_ID" \
  -enableCodeCoverage YES \
  | xcpretty 2>/dev/null || xcodebuild test \
  -scheme ProsperPlayer-Package \
  -destination "platform=iOS Simulator,id=$DEVICE_ID" \
  -enableCodeCoverage YES

# Check exit code
if [ ${PIPESTATUS[0]} -eq 0 ]; then
    echo ""
    echo -e "${GREEN}✅ All tests passed!${NC}"
    exit 0
else
    echo ""
    echo -e "${RED}❌ Tests failed!${NC}"
    exit 1
fi
