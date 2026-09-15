#!/bin/bash
# Builds Paper Notes.app and installs it to /Applications.
set -euo pipefail
cd "$(dirname "$0")"
INSTALL_DIR="${INSTALL_DIR:-/Applications}"

EXEC="PaperNotes"
APP="Paper Notes"
BUNDLE="${APP_BUILD_ROOT:-$HOME/Library/Caches/LocalApps/Builds}/$APP.app"

echo "==> Compiling"
export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$PWD/.build/ModuleCache}"
export SWIFTPM_MODULECACHE_OVERRIDE="${SWIFTPM_MODULECACHE_OVERRIDE:-$CLANG_MODULE_CACHE_PATH}"
swift_args=(-c release --jobs "${SWIFT_JOBS:-2}" --cache-path "$PWD/.build/spm-cache")
[ "${SWIFT_DISABLE_SANDBOX:-0}" != "1" ] || swift_args+=(--disable-sandbox)
swift build "${swift_args[@]}"

echo "==> Rendering icon"
rm -rf build/AppIcon.iconset
swift ../tools/MakeReadingIcon.swift paper-notes build/AppIcon.iconset >/dev/null

echo "==> Assembling bundle"
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
cp ".build/release/$EXEC" "$BUNDLE/Contents/MacOS/$EXEC"
iconutil -c icns build/AppIcon.iconset -o "$BUNDLE/Contents/Resources/AppIcon.icns"
# KaTeX + marked, bundled so the preview renders with no network.
cp -R Resources/web "$BUNDLE/Contents/Resources/web"

cat > "$BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$APP</string>
  <key>CFBundleDisplayName</key><string>$APP</string>
  <key>CFBundleIdentifier</key><string>local.papernotes</string>
  <key>CFBundleExecutable</key><string>$EXEC</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.2.5</string>
  <key>CFBundleVersion</key><string>8</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>CFBundleURLTypes</key><array><dict><key>CFBundleURLSchemes</key><array><string>papernotes</string></array><key>CFBundleURLName</key><string>local.papernotes</string></dict></array>
  <key>NSPrincipalClass</key><string>NSApplication</string>

  <!-- Finder right-click → Services → "Add to Paper Notes" -->
  <key>NSServices</key>
  <array>
    <dict>
      <key>NSMenuItem</key>
      <dict><key>default</key><string>Add to Paper Notes</string></dict>
      <key>NSMessage</key><string>addToPaperNotes</string>
      <key>NSPortName</key><string>$EXEC</string>
      <key>NSSendFileTypes</key>
      <array><string>com.adobe.pdf</string></array>
    </dict>
  </array>

  <!-- Finder right-click → Open With → Paper Notes.
       Rank Alternate on purpose: Preview stays the default PDF handler, because
       reading happens there. -->
  <key>CFBundleDocumentTypes</key>
  <array>
    <dict>
      <key>CFBundleTypeName</key><string>PDF</string>
      <key>CFBundleTypeRole</key><string>Viewer</string>
      <key>LSHandlerRank</key><string>Alternate</string>
      <key>LSItemContentTypes</key>
      <array><string>com.adobe.pdf</string></array>
    </dict>
  </array>
</dict>
</plist>
PLIST

# Finder metadata copied into generated bundles prevents macOS code signing.
xattr -cr "$BUNDLE"
plutil -lint "$BUNDLE/Contents/Info.plist" >/dev/null

echo "==> Signing"
# Reuse the stable identity if it exists, so any future TCC grants survive rebuilds.
IDENTITY="${SIGNING_IDENTITY:-}"
if [ -n "$IDENTITY" ]; then
  codesign --force --sign "$IDENTITY" --identifier local.papernotes "$BUNDLE"
else
  codesign --force --sign - "$BUNDLE"
fi

codesign --verify --deep --strict "$BUNDLE"

if [ "${INSTALL:-0}" != "1" ]; then
  echo "Built: $BUNDLE"
  exit 0
fi
mkdir -p "$INSTALL_DIR"
echo "==> Installing to $INSTALL_DIR"
pkill -x "$EXEC" 2>/dev/null || true
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
echo "Done. Notes are stored separately from the app; see dataRoot in the README."
