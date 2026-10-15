#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
APP="build/Input Method Locked.app"
BUILD_CACHE="${IML_MODULE_CACHE:-${TMPDIR:-/tmp}/input-method-locked-module-cache}"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" build/bin "$BUILD_CACHE"
xcrun swift -module-cache-path "$BUILD_CACHE" Scripts/make-icon.swift build/AppIcon.iconset Resources
/usr/bin/python3 Scripts/pack-icon.py build/AppIcon.iconset "$APP/Contents/Resources/AppIcon.icns"
ARCHS="${IML_ARCHS:-arm64 x86_64}"
BINARIES=()
for ARCH in $ARCHS; do
  xcrun swiftc -swift-version 5 -O -target "$ARCH-apple-macosx13.0" \
    -module-cache-path "$BUILD_CACHE" \
    -framework AppKit -framework Carbon -framework ServiceManagement Sources/*.swift \
    -o "build/bin/InputMethodLocked-$ARCH"
  BINARIES+=("build/bin/InputMethodLocked-$ARCH")
done
xcrun lipo -create "${BINARIES[@]}" -output "$APP/Contents/MacOS/InputMethodLocked"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>InputMethodLocked</string>
<key>CFBundleIdentifier</key><string>local.czk.inputlocker.prototype</string>
<key>CFBundleName</key><string>Input Method Locked</string>
<key>CFBundleDisplayName</key><string>Input Method Locked</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.4.1</string>
<key>CFBundleVersion</key><string>6</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
codesign --verify --strict "$APP"
echo "Built: $PWD/$APP"
