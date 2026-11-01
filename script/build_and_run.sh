#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
MODE="${1:-run}"
case "$MODE" in run|--build|--verify|--debug|--logs|--telemetry) ;; *) echo 'Usage: build_and_run.sh [--build|--verify|--debug|--logs|--telemetry]' >&2; exit 2 ;; esac
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"
APP="$ROOT_DIR/dist/StudSync.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/StudSync" "$APP/Contents/MacOS/StudSync"
for resource in "$BIN_DIR"/*.bundle; do
    if [[ -d "$resource" ]]; then cp -R "$resource" "$APP/Contents/Resources/"; fi
done
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>StudSync</string>
<key>CFBundleIdentifier</key><string>com.gnagster.StudSync</string>
<key>CFBundleName</key><string>StudSync</string>
<key>CFBundleDisplayName</key><string>StudSync</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>15.0</string>
<key>LSUIElement</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>CFBundleDevelopmentRegion</key><string>en</string>
<key>CFBundleLocalizations</key><array><string>en</string><string>de</string></array>
</dict></plist>
PLIST
# Only strip copied build metadata from the app we just generated.
xattr -cr "$APP"
codesign --force --deep --sign - --identifier com.gnagster.StudSync "$APP"
if [[ "$MODE" == --build ]]; then exit 0; fi
pkill -x StudSync >/dev/null 2>&1 || true
case "$MODE" in
  --debug) lldb -- "$APP/Contents/MacOS/StudSync" ;;
  --logs) open -n "$APP"; /usr/bin/log stream --info --style compact --predicate 'process == "StudSync"' ;;
  --telemetry) open -n "$APP"; /usr/bin/log stream --info --style compact --predicate 'subsystem == "com.gnagster.StudSync"' ;;
  --verify) open -n "$APP"; sleep 2; pgrep -x StudSync >/dev/null ;;
  run) open -n "$APP" ;;
esac
