#!/bin/bash

set -euo pipefail

CONTROL_ROOT="$(cd "$(dirname "$0")" && pwd -P)"
MACOS_ROOT="$(cd "$CONTROL_ROOT/.." && pwd -P)"
OUTPUT="${1:-$MACOS_ROOT/release/Codex Dream Skin.app}"
CONTENTS="$OUTPUT/Contents"
RESOURCES="$CONTENTS/Resources"
ENGINE="$RESOURCES/Engine"
BUILD_ROOT="${TMPDIR:-/tmp}/codex-dream-skin-control-build.$$"

cleanup() { /bin/rm -rf "$BUILD_ROOT"; }
trap cleanup EXIT

/bin/rm -rf "$OUTPUT"
/bin/mkdir -p "$CONTENTS/MacOS" "$ENGINE" "$BUILD_ROOT/ModuleCache"
/bin/cp "$CONTROL_ROOT/Resources/DreamSkin.icns" "$RESOURCES/DreamSkin.icns"
/bin/cp "$CONTROL_ROOT/Resources/Assets.car" "$RESOURCES/Assets.car"

/usr/bin/xcrun swiftc \
  -parse-as-library \
  -swift-version 5 \
  -O \
  -module-cache-path "$BUILD_ROOT/ModuleCache" \
  -target "$(/usr/bin/uname -m)-apple-macos13.0" \
  -framework SwiftUI \
  -framework AppKit \
  "$CONTROL_ROOT"/Sources/*.swift \
  -o "$CONTENTS/MacOS/CodexDreamSkin"

/usr/bin/xcrun swiftc \
  -swift-version 5 \
  -module-cache-path "$BUILD_ROOT/ModuleCache" \
  "$CONTROL_ROOT/Sources/Localization.swift" \
  "$CONTROL_ROOT/Sources/OnlineWallpaper.swift" \
  "$CONTROL_ROOT/Tests/OnlineWallpaperServiceTests.swift" \
  -o "$BUILD_ROOT/OnlineWallpaperServiceTests"
"$BUILD_ROOT/OnlineWallpaperServiceTests"

/usr/bin/xcrun swiftc \
  -parse-as-library \
  -swift-version 5 \
  -module-cache-path "$BUILD_ROOT/ModuleCache" \
  "$CONTROL_ROOT/Tests/LocalizationTests.swift" \
  -o "$BUILD_ROOT/LocalizationTests"
"$BUILD_ROOT/LocalizationTests" "$CONTROL_ROOT/Resources" "$CONTROL_ROOT/Sources"

/bin/cp "$CONTROL_ROOT/Info.plist" "$CONTENTS/Info.plist"
for localization in "$CONTROL_ROOT"/Resources/*.lproj; do
  /bin/cp -R "$localization" "$RESOURCES/"
  /usr/bin/plutil -lint "$localization/Localizable.strings"
done
for entry in assets scripts presets menubar VERSION LICENSE NOTICE.md; do
  [ -e "$MACOS_ROOT/$entry" ] || continue
  if [ -d "$MACOS_ROOT/$entry" ]; then
    /bin/cp -R "$MACOS_ROOT/$entry" "$ENGINE/$entry"
  else
    /bin/cp "$MACOS_ROOT/$entry" "$ENGINE/$entry"
  fi
done
/bin/cp -R "$MACOS_ROOT/../community" "$ENGINE/community"

/bin/chmod 755 "$CONTENTS/MacOS/CodexDreamSkin"
/bin/chmod 700 "$ENGINE"/scripts/*.sh 2>/dev/null || true
/usr/bin/codesign --force --deep --sign - "$OUTPUT"
/usr/bin/plutil -lint "$CONTENTS/Info.plist"
/usr/bin/codesign --verify --deep --strict "$OUTPUT"

printf 'Built %s\n' "$OUTPUT"
