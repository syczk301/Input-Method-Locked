#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
xcrun clang -fobjc-arc -framework AppKit -framework IOKit \
  -framework ApplicationServices Tests/ScrollTapTests.m -o build/scroll-tap-tests
build/scroll-tap-tests
