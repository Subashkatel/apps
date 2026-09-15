#!/bin/bash
# Builds Pomodoro.app and installs it to /Applications.
# Bundle identifier is deliberately unchanged (com.pomodoro.app) so the existing
# preferences at ~/Library/Preferences/com.pomodoro.app.plist carry over.
set -euo pipefail
cd "$(dirname "$0")"
INSTALL_DIR="${INSTALL_DIR:-/Applications}"

APP="Pomodoro"
BUNDLE="${APP_BUILD_ROOT:-$HOME/Library/Caches/LocalApps/Builds}/$APP.app"
RESOURCES="Resources"

echo "==> Compiling"
export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$PWD/.build/ModuleCache}"
export SWIFTPM_MODULECACHE_OVERRIDE="${SWIFTPM_MODULECACHE_OVERRIDE:-$CLANG_MODULE_CACHE_PATH}"
swift_args=(-c release --jobs "${SWIFT_JOBS:-2}" --cache-path "$PWD/.build/spm-cache")
[ "${SWIFT_DISABLE_SANDBOX:-0}" != "1" ] || swift_args+=(--disable-sandbox)
swift build "${swift_args[@]}"

echo "==> Assembling bundle"
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
cp ".build/release/$APP" "$BUNDLE/Contents/MacOS/$APP"

# Reuse the original artwork so the app looks unchanged in the menu bar and Finder.
for res in AppIcon.icns MenuBarIcon.png MenuBarIcon@2x.png; do
  cp "$RESOURCES/$res" "$BUNDLE/Contents/Resources/$res"
done

cat > "$BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$APP</string>
  <key>CFBundleDisplayName</key><string>$APP</string>
  <key>CFBundleIdentifier</key><string>com.pomodoro.app</string>
  <key>CFBundleExecutable</key><string>$APP</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>2.0</string>
  <key>CFBundleVersion</key><string>2</string>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

# Finder metadata copied into generated bundles prevents macOS code signing.
xattr -cr "$BUNDLE"
plutil -lint "$BUNDLE/Contents/Info.plist" >/dev/null

IDENTITY="${SIGNING_IDENTITY:--}"
echo "==> Signing"
codesign --force --sign "$IDENTITY" "$BUNDLE"

codesign --verify --deep --strict "$BUNDLE"

if [ "${INSTALL:-0}" != "1" ]; then
  echo "Built: $BUNDLE"
  exit 0
fi
mkdir -p "$INSTALL_DIR"
echo "==> Installing to $INSTALL_DIR"
pkill -x "$APP" 2>/dev/null || true
sleep 1
STAGED=$(mktemp -d "$INSTALL_DIR/.local-app-install.XXXXXX")
cleanup_install() {
  if [ -e "$STAGED/previous.app" ] && [ ! -e "$INSTALL_DIR/$APP.app" ]; then
    if ! mv "$STAGED/previous.app" "$INSTALL_DIR/$APP.app"; then
      echo "Previous app preserved at $STAGED/previous.app; restore it manually." >&2
      return
    fi
  fi
  rm -rf "$STAGED"
}
trap cleanup_install EXIT
cp -R "$BUNDLE" "$STAGED/$APP.app"
xattr -cr "$STAGED/$APP.app"
codesign --verify --deep --strict "$STAGED/$APP.app"
if [ -e "$INSTALL_DIR/$APP.app" ]; then
  mv "$INSTALL_DIR/$APP.app" "$STAGED/previous.app"
fi
if ! mv "$STAGED/$APP.app" "$INSTALL_DIR/$APP.app"; then
  exit 1
fi
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
  -f "$INSTALL_DIR/$APP.app" 2>/dev/null || true

if [ "${NO_LAUNCH:-1}" != "1" ]; then
  echo "==> Launching"
  open "$INSTALL_DIR/$APP.app"
fi
echo "Done."
