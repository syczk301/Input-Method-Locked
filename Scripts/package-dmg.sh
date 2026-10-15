#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "${1:-}" != "--skip-build" ]]; then
  bash build.sh
fi
APP="build/Input Method Locked.app"
codesign --verify --strict "$APP"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")
DMG="build/Input-Method-Locked-$VERSION-universal.dmg"
STAGE=$(mktemp -d "${TMPDIR:-/tmp}/input-method-locked-dmg.XXXXXX")
trap 'rm -rf "$STAGE"' EXIT
ditto "$APP" "$STAGE/Input Method Locked.app"
ln -s /Applications "$STAGE/Applications"
cat > "$STAGE/Read Me.txt" <<'TEXT'
Input Method Locked

1. Drag Input Method Locked.app to Applications.
2. Open the app from Applications. It appears in the menu bar.
3. Choose a global input method, or set an input method for each app.
4. Enable launch at login from the Settings submenu if desired.

macOS 13+. Universal: Apple silicon and Intel.
This build is ad-hoc signed and not notarized by Apple. On first launch,
macOS may require you to allow it in System Settings > Privacy & Security.

将应用拖入 Applications 后打开，在菜单栏中选择全局输入法，
或为不同 App 设置独立输入法。开机自动启动位于“设置”子菜单。

https://github.com/syczk301/Input-Method-Locked
TEXT
hdiutil create -volname "Input Method Locked" -srcfolder "$STAGE" -format UDZO \
  -imagekey zlib-level=9 -fs HFS+ -ov "$DMG"
hdiutil verify "$DMG"
/usr/bin/python3 Scripts/verify-dmg.py "$DMG" "$APP"
(cd build && shasum -a 256 "$(basename "$DMG")" > SHA256SUMS.txt)
echo "Packaged: $PWD/$DMG"
