#!/bin/bash
# Builds VoiceBridge.app. Installation, launch and model download are separate steps.
set -euo pipefail
cd "$(dirname "$0")"
INSTALL_DIR="${INSTALL_DIR:-/Applications}"

APP="VoiceBridge"
BUNDLE="${APP_BUILD_ROOT:-$HOME/Library/Caches/LocalApps/Builds}/$APP.app"

echo "==> Compiling"
export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$PWD/.build/ModuleCache}"
export SWIFTPM_MODULECACHE_OVERRIDE="${SWIFTPM_MODULECACHE_OVERRIDE:-$CLANG_MODULE_CACHE_PATH}"
swift_args=(-c release --jobs "${SWIFT_JOBS:-2}" --cache-path "$PWD/.build/spm-cache")
[ "${SWIFT_DISABLE_SANDBOX:-0}" != "1" ] || swift_args+=(--disable-sandbox)
swift build "${swift_args[@]}"

echo "==> Rendering icon"
rm -rf build/AppIcon.iconset
swift Tools/MakeIcon.swift build/AppIcon.iconset >/dev/null

echo "==> Assembling bundle"
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
cp ".build/release/$APP" "$BUNDLE/Contents/MacOS/$APP"
iconutil -c icns build/AppIcon.iconset -o "$BUNDLE/Contents/Resources/AppIcon.icns"

cat > "$BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$APP</string>
  <key>CFBundleDisplayName</key><string>Voice Bridge</string>
  <key>CFBundleIdentifier</key><string>local.voicebridge</string>
  <key>CFBundleExecutable</key><string>$APP</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.1</string>
  <key>CFBundleVersion</key><string>2</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <!-- Both prompts are required: one to record, one to drive iTerm2. -->
  <key>NSMicrophoneUsageDescription</key>
  <string>VoiceBridge records your voice locally to transcribe it into your terminal.</string>
  <key>NSAppleEventsUsageDescription</key>
  <string>VoiceBridge types the transcribed text into your iTerm2 session.</string>
</dict>
</plist>
PLIST

# Finder metadata copied into generated bundles prevents macOS code signing.
xattr -cr "$BUNDLE"
plutil -lint "$BUNDLE/Contents/Info.plist" >/dev/null

# A fixed certificate gives a designated requirement of
#   identifier "local.voicebridge" and certificate root = H"..."
# which survives rebuilds, so the Accessibility grant is not invalidated every
# time. Ad-hoc signing keys TCC to the binary hash instead, which is why this app
# kept losing its permission. Run Tools/make-signing-identity.sh to create it.
IDENTITY="${SIGNING_IDENTITY:-}"
if [ -n "$IDENTITY" ]; then
  echo "==> Signing with '$IDENTITY' (stable — TCC grant survives)"
  codesign --force --sign "$IDENTITY" --identifier local.voicebridge "$BUNDLE"
else
  echo "==> Signing (ad-hoc) — WARNING: this invalidates the Accessibility grant."
  echo "    Set SIGNING_IDENTITY to a local signing identity to preserve grants across rebuilds."
  codesign --force --sign - "$BUNDLE"
fi

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
cat <<'NOTE'
Done. Double-tap Control to dictate.

  Turn off the built-in Dictation shortcut first, or both will fire:
    System Settings › Keyboard › Dictation › Shortcut → Off

  No menu bar icon by design. Useful commands:
    /Applications/VoiceBridge.app/Contents/MacOS/VoiceBridge --status
    /Applications/VoiceBridge.app/Contents/MacOS/VoiceBridge --enable-login-item
    pkill -x VoiceBridge          # quit
NOTE
