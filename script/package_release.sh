#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Cursor Control"
EXECUTABLE_NAME="CursorControl"
BUNDLE_ID="io.github.cursorcontrol.CursorControl"
MIN_SYSTEM_VERSION="13.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="${DIST_DIR:-$ROOT_DIR/dist}"
VERSION="${VERSION:-1.0.0}"
BUNDLE_VERSION="${BUNDLE_VERSION:-$VERSION}"
PACKAGE_NAME="${PACKAGE_NAME:-CursorControl-$VERSION-macOS}"
PACKAGE_DIR="$DIST_DIR/$PACKAGE_NAME"
APP_BUNDLE="$PACKAGE_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$EXECUTABLE_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
SOURCE_RESOURCES="$ROOT_DIR/Sources/CursorControl/Resources"
ZIP_PATH="$DIST_DIR/$PACKAGE_NAME.zip"
SHA_PATH="$ZIP_PATH.sha256"

cd "$ROOT_DIR"

echo "Building $EXECUTABLE_NAME $VERSION for release..."
swift build -c release
BUILD_BINARY="$(swift build -c release --show-bin-path)/$EXECUTABLE_NAME"

if [[ ! -f "$BUILD_BINARY" ]]; then
  echo "Built executable not found at: $BUILD_BINARY" >&2
  exit 1
fi

echo "Preparing release folder..."
rm -rf "$PACKAGE_DIR" "$ZIP_PATH" "$SHA_PATH"
mkdir -p "$APP_MACOS" "$APP_RESOURCES"

cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"

if [[ -d "$SOURCE_RESOURCES" ]]; then
  cp -R "$SOURCE_RESOURCES/." "$APP_RESOURCES/"
fi

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>$EXECUTABLE_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleDisplayName</key>
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
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>CFBundleVersion</key>
  <string>$BUNDLE_VERSION</string>
  <key>CFBundleShortVersionString</key>
  <string>$VERSION</string>
  <key>CFBundleSignature</key>
  <string>????</string>
</dict>
</plist>
PLIST

echo -n "APPL????" >"$APP_CONTENTS/PkgInfo"

echo "Applying ad-hoc signature..."
/usr/bin/codesign \
  --force \
  --sign - \
  --identifier "$BUNDLE_ID" \
  --requirements "=designated => identifier \"$BUNDLE_ID\"" \
  "$APP_BUNDLE"

/usr/bin/codesign --verify --deep --strict "$APP_BUNDLE"

if [[ -f "$ROOT_DIR/README_INSTALL.txt" ]]; then
  cp "$ROOT_DIR/README_INSTALL.txt" "$PACKAGE_DIR/"
else
  cat >"$PACKAGE_DIR/README_INSTALL.txt" <<README
To install Cursor Control, move Cursor Control.app to your Applications folder.

This release is ad-hoc signed and not Apple-notarized. On first launch, macOS may
block the app. Use System Settings > Privacy & Security > Open Anyway, or
Control-click the app and choose Open if that option is available.
README
fi

echo "Creating $ZIP_PATH..."
(
  cd "$DIST_DIR"
  zip -q -r -X "$(basename "$ZIP_PATH")" "$PACKAGE_NAME" -x "*/.*" -x "__MACOSX"
)

shasum -a 256 "$ZIP_PATH" >"$SHA_PATH"

echo "Release package ready:"
echo "$ZIP_PATH"
echo "$SHA_PATH"
echo ""
echo "Note: this package is ad-hoc signed and not Apple-notarized."
