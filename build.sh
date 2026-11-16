#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
python3 tools/sparkle/bootstrap.py
APP="${1:-build/输入与滚动.app}"
BUILD_CACHE="${IML_MODULE_CACHE:-${TMPDIR:-/tmp}/input-method-locked-module-cache}"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" build/bin "$BUILD_CACHE"
xcrun swift -module-cache-path "$BUILD_CACHE" Scripts/make-icon.swift build/AppIcon.iconset Resources
/usr/bin/python3 Scripts/pack-icon.py build/AppIcon.iconset "$APP/Contents/Resources/AppIcon.icns"
ARCHS="${IML_ARCHS:-arm64 x86_64}"
BINARIES=()
for ARCH in $ARCHS; do
  xcrun clang -fobjc-arc -O2 -arch "$ARCH" -mmacosx-version-min=13.0 \
    -c Sources/ScrollEngine/ScrollTap.m -o "build/bin/ScrollTap-$ARCH.o"
  xcrun swiftc -swift-version 5 -O -target "$ARCH-apple-macosx13.0" \
    -module-cache-path "$BUILD_CACHE" \
    -import-objc-header Sources/ScrollEngine/ScrollTap.h \
    -F tools/sparkle/vendor -framework Sparkle -Xlinker -rpath -Xlinker @executable_path/../Frameworks -framework AppKit -framework Carbon -framework ServiceManagement \
    -framework IOKit -framework ApplicationServices Sources/*.swift "build/bin/ScrollTap-$ARCH.o" \
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
<key>CFBundleName</key><string>输入与滚动</string>
<key>CFBundleDisplayName</key><string>输入与滚动</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.6.0</string>
<key>CFBundleVersion</key><string>16</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
python3 tools/sparkle/bootstrap.py "$APP"
codesign --force --sign - "$APP"
codesign --verify --strict "$APP"
echo "Built: $PWD/$APP"
