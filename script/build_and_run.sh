#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="Cursor Control"
EXECUTABLE_NAME="CursorControl"
BUNDLE_ID="io.github.cursorcontrol.CursorControl"
MIN_SYSTEM_VERSION="13.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$EXECUTABLE_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
SOURCE_RESOURCES="$ROOT_DIR/Sources/CursorControl/Resources"

cd "$ROOT_DIR"
if pgrep -x "$EXECUTABLE_NAME" >/dev/null 2>&1; then
  pkill -x "$EXECUTABLE_NAME"
  for ((attempt = 0; attempt < 50; attempt++)); do
    if ! pgrep -x "$EXECUTABLE_NAME" >/dev/null 2>&1; then
      break
    fi
    sleep 0.1
  done

  if pgrep -x "$EXECUTABLE_NAME" >/dev/null 2>&1; then
    echo "Cursor Control did not exit before rebuilding." >&2
    exit 1
  fi
fi

swift build
BUILD_BINARY="$(swift build --show-bin-path)/$EXECUTABLE_NAME"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS"
mkdir -p "$APP_RESOURCES"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"
if [ -d "$SOURCE_RESOURCES" ]; then
  cp -R "$SOURCE_RESOURCES/." "$APP_RESOURCES/"
fi

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$EXECUTABLE_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleIconFile</key>
  <string>CursorControlIcon</string>
  <key>CFBundleIconName</key>
  <string>CursorControlIcon</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>LSUIElement</key>
  <false/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>CFBundleVersion</key>
  <string>1.0</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0</string>
  <key>CFBundleSignature</key>
  <string>????</string>
</dict>
</plist>
PLIST

echo -n "APPL????" > "$APP_CONTENTS/PkgInfo"

# Keep one designated identity so macOS Accessibility trust survives local rebuilds.
/usr/bin/codesign \
  --force \
  --sign - \
  --identifier "$BUNDLE_ID" \
  --requirements "=designated => identifier \"$BUNDLE_ID\"" \
  "$APP_BUNDLE"
/usr/bin/codesign --verify --deep --strict "$APP_BUNDLE"

echo "Copying to /Applications..."
rsync -a --delete "$APP_BUNDLE" /Applications/

open_app() {
  /usr/bin/open -n "/Applications/$APP_NAME.app"
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$EXECUTABLE_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 1
    pgrep -x "$EXECUTABLE_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
