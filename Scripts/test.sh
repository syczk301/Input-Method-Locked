#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
BUILD_CACHE="${IML_MODULE_CACHE:-${TMPDIR:-/tmp}/input-method-locked-module-cache}"
mkdir -p "$BUILD_CACHE"
xcrun swiftc -swift-version 5 -module-cache-path "$BUILD_CACHE" \
  Sources/LockPolicy.swift Tests/PolicyTests.swift -o build/policy-tests
build/policy-tests
xcrun swiftc -swift-version 5 -module-cache-path "$BUILD_CACHE" \
  -framework AppKit -framework Carbon Sources/InputSources.swift Sources/InputSourceAccess.swift \
  Sources/LockPolicy.swift Sources/LockController.swift Tests/ControllerTests.swift -o build/controller-tests
build/controller-tests
