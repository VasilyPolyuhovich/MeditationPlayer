#!/bin/bash

# iOS Library Test Runner for SPM Package
echo "🧪 Running ProsperPlayer tests on iOS Simulator..."
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

echo "🚀 Running tests on iPhone 16, iOS 18.3.1..."
echo ""

# Use specific device with OS version - this is what actually works!
xcodebuild test \
  -scheme ProsperPlayer-Package \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' \
  -enableCodeCoverage YES \
  | xcpretty 2>/dev/null || xcodebuild test \
  -scheme ProsperPlayer-Package \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' \
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
