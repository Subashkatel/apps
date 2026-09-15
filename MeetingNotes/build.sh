#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
BUILD_ROOT="${APP_BUILD_ROOT:-$HOME/Library/Caches/LocalApps/Builds}"
APP="$BUILD_ROOT/Meeting Notes.app"
SCRATCH="${MEETING_BUILD_PATH:-$PWD/.build}"
export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$SCRATCH/ModuleCache}"
export SWIFTPM_MODULECACHE_OVERRIDE="$CLANG_MODULE_CACHE_PATH"
swift build -c release --jobs "${SWIFT_JOBS:-2}" --disable-sandbox --scratch-path "$SCRATCH" --cache-path "$SCRATCH/spm-cache"
mkdir -p build
swift -module-cache-path "$CLANG_MODULE_CACHE_PATH" Tools/MakeIcon.swift build/AppIcon.iconset
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$SCRATCH/release/MeetingNotes" "$APP/Contents/MacOS/MeetingNotes"
iconutil -c icns build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
cp Resources/Quill-LICENSE "$APP/Contents/Resources/Quill-LICENSE"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>local.meetingnotes</string>
<key>CFBundleName</key><string>Meeting Notes</string>
<key>CFBundleDisplayName</key><string>Meeting Notes</string>
<key>CFBundleExecutable</key><string>MeetingNotes</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>15.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>NSMicrophoneUsageDescription</key><string>Record microphone audio for your meeting notes and animate the recording icon from its volume. Audio is saved on this Mac.</string>
<key>NSAudioCaptureUsageDescription</key><string>Record system audio during online meetings so both sides of the conversation can be transcribed locally.</string>
</dict></plist>
PLIST
xattr -cr "$APP"
plutil -lint "$APP/Contents/Info.plist"
codesign --force --sign "${SIGNING_IDENTITY:--}" --identifier local.meetingnotes "$APP"
codesign --verify --deep --strict "$APP"
if [ "${INSTALL:-0}" = "1" ]; then
  INSTALL_DIR="${INSTALL_DIR:-/Applications}"
  mkdir -p "$INSTALL_DIR"
  STAGE=$(mktemp -d "$INSTALL_DIR/.meetingnotes-install.XXXXXX")
  cp -R "$APP" "$STAGE/Meeting Notes.app"
  codesign --verify --deep --strict "$STAGE/Meeting Notes.app"
  if [ -e "$INSTALL_DIR/Meeting Notes.app" ]; then
    if pgrep -f "$INSTALL_DIR/Meeting Notes.app/Contents/MacOS/MeetingNotes" >/dev/null; then
      echo 'Quit Meeting Notes before installing an update; a recording may be active.' >&2
      rm -rf "$STAGE"
      exit 1
    fi
    mv "$INSTALL_DIR/Meeting Notes.app" "$STAGE/previous.app"
  fi
  if ! mv "$STAGE/Meeting Notes.app" "$INSTALL_DIR/Meeting Notes.app"; then
    if [ -e "$STAGE/previous.app" ]; then mv "$STAGE/previous.app" "$INSTALL_DIR/Meeting Notes.app"; fi
    exit 1
  fi
  rm -rf "$STAGE"
  [ "${NO_LAUNCH:-1}" = "1" ] || open "$INSTALL_DIR/Meeting Notes.app"
fi
printf 'Built: %s\n' "$APP"
