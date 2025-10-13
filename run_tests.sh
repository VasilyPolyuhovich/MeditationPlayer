#!/bin/bash

# iOS Library Test Runner for SPM Package
echo "🧪 Running ProsperPlayer tests on iOS Simulator..."
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# Find available iOS Simulators
echo "📱 Available iOS Simulators:"
xcrun simctl list devices available | grep "iPhone"
echo ""

# Run tests on iOS Simulator
echo "🚀 Running tests..."
xcodebuild test \
  -scheme ProsperPlayer-Package \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -enableCodeCoverage YES \
  | xcpretty || xcodebuild test \
  -scheme ProsperPlayer-Package \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
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
