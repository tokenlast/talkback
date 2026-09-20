#!/usr/bin/env bash
# Build Talkback, apply a local signature, and install it in ~/Applications.
# Usage: build-app.sh [--no-install]   (--no-install only builds and signs the app)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SAY_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PKG_DIR="$SAY_DIR/Talkback"
BUILD_DIR="$HOME/dev/talkback-build"
APP_NAME="Talkback.app"
# Keep staged and backup copies out of Spotlight and Launchpad.
STAGE_DIR="$BUILD_DIR/stage.noindex"
APP_DIR="$STAGE_DIR/$APP_NAME"
PYTHON="/opt/homebrew/bin/python3.13"
INSTALL_DIR="$HOME/Applications"
INSTALL=1
[[ "${1:-}" == "--no-install" ]] && INSTALL=0

say() { printf '%s\n' "$*"; }
fail() { printf '[FAILED] %s\n' "$*" >&2; exit 1; }
trash_existing() { [[ ! -e "$1" ]] || /usr/bin/trash "$1"; }

command -v swift >/dev/null || fail "swift was not found (install Xcode)"
[[ -x "$PYTHON" ]] || fail "$PYTHON was not found"

say "1/5 Building the app"
(cd "$PKG_DIR" && swift build -c release --scratch-path "$BUILD_DIR" >/dev/null) || fail "swift build failed"
BIN="$BUILD_DIR/release/Talkback"
[[ -x "$BIN" ]] || fail "Executable not found: $BIN"

say "2/5 Creating the icon"
ICONSET="$BUILD_DIR/AppIcon.iconset"
trash_existing "$ICONSET"; mkdir -p "$ICONSET"
"$PYTHON" "$SCRIPT_DIR/make_icon.py" "$BUILD_DIR/icon-1024.png" >/dev/null
for px in 16 32 128 256 512; do
  sips -z "$px" "$px" "$BUILD_DIR/icon-1024.png" --out "$ICONSET/icon_${px}x${px}.png" >/dev/null
  dbl=$((px * 2))
  sips -z "$dbl" "$dbl" "$BUILD_DIR/icon-1024.png" --out "$ICONSET/icon_${px}x${px}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$BUILD_DIR/AppIcon.icns" || fail "iconutil failed"

say "3/5 Assembling the .app"
trash_existing "$APP_DIR"
mkdir -p "$STAGE_DIR" "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BIN" "$APP_DIR/Contents/MacOS/Talkback"
cp "$PKG_DIR/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$BUILD_DIR/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
mkdir -p "$APP_DIR/Contents/Resources/daemon" "$APP_DIR/Contents/Resources/remote_script/Talkback"
DAEMON_FILES=(daemon.py intent.py intent_en.py voice_gate.py user_commands.py actions.py messages.py snapshot.py bridge_client.py script_bridge_client.py plugin_script.py llm_rewrite.py cli.py)
for source in "${DAEMON_FILES[@]}"; do
  cp "$SAY_DIR/$source" "$APP_DIR/Contents/Resources/daemon/"
done
cp "$SAY_DIR"/remote_script/Talkback/*.py "$APP_DIR/Contents/Resources/remote_script/Talkback/"
cp "$SAY_DIR/LICENSE" "$APP_DIR/Contents/Resources/LICENSE"
cp "$SAY_DIR/COMMANDS.md" "$APP_DIR/Contents/Resources/COMMANDS.md"
printf 'APPL????' > "$APP_DIR/Contents/PkgInfo"
plutil -lint "$APP_DIR/Contents/Info.plist" >/dev/null || fail "Info.plist is invalid"

say "4/5 Applying an ad hoc signature"
codesign --force --deep -s - "$APP_DIR" >/dev/null 2>&1 || fail "codesign failed"
codesign --verify --deep --strict "$APP_DIR" || fail "Signature verification failed"

if [[ "$INSTALL" -eq 1 ]]; then
  say "5/5 Installing in ~/Applications"
  mkdir -p "$INSTALL_DIR"
  if [[ -d "$INSTALL_DIR/$APP_NAME" ]]; then
    trash_existing "$STAGE_DIR/previous/$APP_NAME"
    mkdir -p "$STAGE_DIR/previous"
    mv "$INSTALL_DIR/$APP_NAME" "$STAGE_DIR/previous/$APP_NAME"
  fi
  cp -R "$APP_DIR" "$INSTALL_DIR/$APP_NAME"
  say "Done: $INSTALL_DIR/$APP_NAME (previous version: $STAGE_DIR/previous/$APP_NAME)"
else
  say "5/5 Skipping installation. Built at: $APP_DIR"
fi
