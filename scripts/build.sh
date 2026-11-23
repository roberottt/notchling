#!/bin/bash
# Compila Notchling.app (Apple Silicon e Intel). Solo necesita las Command Line Tools.
#   scripts/build.sh            deja la app en build/
#   scripts/build.sh --install  además la copia a ~/Applications y la abre
set -euo pipefail
cd "$(dirname "$0")/.."

ARGS=(-c release --arch arm64 --arch x86_64)
swift build "${ARGS[@]}"
BINARY="$(swift build "${ARGS[@]}" --show-bin-path)/Notchling"

APP="build/Notchling.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BINARY" "$APP/Contents/MacOS/Notchling"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>local.notchling</string>
    <key>CFBundleExecutable</key><string>Notchling</string>
    <key>CFBundleName</key><string>Notchling</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.1</string>
    <key>CFBundleVersion</key><string>2</string>
    <key>CFBundleDevelopmentRegion</key><string>es</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSAppleEventsUsageDescription</key><string>Notchling selects the exact Terminal or iTerm2 tab of a session when you click it.</string>
</dict>
</plist>
PLIST
codesign --force --sign - "$APP"
echo "Lista: $PWD/$APP"

if [[ "${1:-}" == "--install" ]]; then
    DEST="$HOME/Applications/Notchling.app"
    pkill -x Notchling || true
    sleep 1
    mkdir -p "$HOME/Applications"
    rm -rf "$DEST"
    cp -R "$APP" "$DEST"
    open "$DEST"
    echo "Instalada: $DEST"
fi
