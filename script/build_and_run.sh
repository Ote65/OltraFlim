#!/bin/zsh
# OltraFlim build / run entry point.
# The machine has Command Line Tools (no Xcode), so the app is compiled
# directly with swiftc and staged into a proper .app bundle.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="OltraFlim"
APP="$ROOT/dist/$APP_NAME.app"
BUILD_DIR="$ROOT/.build"
MODULE_CACHE="$BUILD_DIR/modulecache"
CONFIG="release"
LOGS=0
VERIFY=0
NO_LAUNCH=0

for arg in "$@"; do
  case "$arg" in
    --debug) CONFIG="debug" ;;
    --release) CONFIG="release" ;;
    --logs) LOGS=1 ;;
    --verify) VERIFY=1 ;;
    --no-launch) NO_LAUNCH=1 ;;
    --open=*)
      OPEN_PATH="${arg#--open=}"
      ;;
    *)
      if [[ -e "$arg" ]]; then OPEN_PATH="$arg"; fi
      ;;
  esac
done

mkdir -p "$BUILD_DIR" "$MODULE_CACHE" "$(dirname "$APP")"

if [[ "$NO_LAUNCH" == "0" ]]; then
  pkill -x "$APP_NAME" 2>/dev/null || true
fi

SDK="${OLTRAFLIM_SDK:-$(xcrun --show-sdk-path)}"
ARCH="$(uname -m)"
# This machine has a broken Command Line Tools install: two module maps both
# define SwiftBridging. A local include overlay with a single map fixes the
# Clang importer without touching /Library.
TOOLCHAIN="$BUILD_DIR/toolchain"
mkdir -p "$TOOLCHAIN/include/swift"
if [[ ! -f "$TOOLCHAIN/include/swift/bridging.modulemap" ]]; then
  cp /Library/Developer/CommandLineTools/usr/include/swift/bridging "$TOOLCHAIN/include/swift/"
  cp /Library/Developer/CommandLineTools/usr/include/swift/bridging.modulemap "$TOOLCHAIN/include/swift/"
fi
if [[ ! -d "$TOOLCHAIN/lib/swift" ]]; then
  mkdir -p "$TOOLCHAIN/lib"
  ln -s /Library/Developer/CommandLineTools/usr/lib/swift "$TOOLCHAIN/lib/swift"
fi
SOURCES=()
while IFS= read -r f; do
  SOURCES+=("$f")
done < <(find "$ROOT/Sources/OltraFlim" -name '*.swift' -print | sort)

FLAGS=(
  -parse-as-library
  -target "${ARCH}-apple-macosx14.0"
  -sdk "$SDK"
  -module-name "$APP_NAME"
  -module-cache-path "$MODULE_CACHE"
  -resource-dir "$TOOLCHAIN/lib/swift"
  -Xcc -I"$TOOLCHAIN/include"
  -swift-version 5
  -framework SwiftUI
  -framework AppKit
  -framework Combine
  -framework Metal
  -framework MetalKit
  -framework QuartzCore
  -framework CoreGraphics
  -framework CoreImage
  -framework ImageIO
  -framework UniformTypeIdentifiers
  -framework Foundation
)
if [[ "$CONFIG" == "release" ]]; then
  FLAGS+=(-O)
else
  FLAGS+=(-Onone -g)
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "→ compiling $CONFIG (${#SOURCES} files)"
swiftc "${FLAGS[@]}" "${SOURCES[@]}" -o "$APP/Contents/MacOS/$APP_NAME"

cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp -R "$ROOT/Resources/LUTs" "$APP/Contents/Resources/LUTs"
cp "$ROOT/Resources/catalog.json" "$APP/Contents/Resources/catalog.json"
cp "$ROOT/Resources/Shaders.metal" "$APP/Contents/Resources/Shaders.metal"
if [[ -d "$ROOT/Resources/Sample" ]]; then
  cp -R "$ROOT/Resources/Sample" "$APP/Contents/Resources/Sample"
fi
cp "$ROOT/Resources/LUT_NOTICE.md" "$APP/Contents/Resources/LUT_NOTICE.md"
if [[ -f "$ROOT/Resources/AppIcon.icns" ]]; then
  cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi
if [[ -f "$ROOT/Resources/LogoMark.png" ]]; then
  cp "$ROOT/Resources/LogoMark.png" "$APP/Contents/Resources/LogoMark.png"
fi
if [[ -f "$ROOT/Resources/SPEKTRAFILM_LICENSE.txt" ]]; then
  cp "$ROOT/Resources/SPEKTRAFILM_LICENSE.txt" "$APP/Contents/Resources/SPEKTRAFILM_LICENSE.txt"
fi

codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true

if [[ "$NO_LAUNCH" == "1" ]]; then
  echo "✓ built $APP (not launched)"
  exit 0
fi

echo "→ launching $APP"
if [[ -n "${OPEN_PATH:-}" ]]; then
  open -n "$APP" --args --open "$OPEN_PATH"
else
  open -n "$APP"
fi

if [[ "$VERIFY" == "1" || "$LOGS" == "1" ]]; then
  sleep 2
  pgrep -x "$APP_NAME" >/dev/null && echo "✓ $APP_NAME is running" || echo "✗ $APP_NAME did not start"
fi

if [[ "$LOGS" == "1" ]]; then
  /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\"" &
fi
