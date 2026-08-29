#!/bin/bash
# Packages the SwiftPM binary as a menu-bar agent bundle.
# A real bundle is required for LSUIElement and for SMAppService login items.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGURATION="${1:-release}"
APP="$ROOT/dist/Shark.app"

cd "$ROOT"
swift build -c "$CONFIGURATION"
BINARY="$(swift build -c "$CONFIGURATION" --show-bin-path)/Shark"

ICON="$ROOT/Assets/icon/AppIcon.icns"
MENUBAR="$ROOT/Assets/icon/MenuBar.pdf"
if [[ ! -f "$ICON" || ! -f "$MENUBAR" ]]; then
    echo "Missing Assets/icon/AppIcon.icns or MenuBar.pdf" >&2
    exit 1
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY" "$APP/Contents/MacOS/Shark"
cp "$ICON" "$APP/Contents/Resources/AppIcon.icns"
cp "$MENUBAR" "$APP/Contents/Resources/MenuBar.pdf"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>Shark</string>
    <key>CFBundleDisplayName</key>
    <string>Shark</string>
    <key>CFBundleExecutable</key>
    <string>Shark</string>
    <key>CFBundleIdentifier</key>
    <string>com.o98k.shark</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSDesktopFolderUsageDescription</key>
    <string>The terminal needs access to your Desktop, like any other terminal.</string>
    <key>NSDocumentsFolderUsageDescription</key>
    <string>The terminal needs access to your Documents folder, like any other terminal.</string>
    <key>NSDownloadsFolderUsageDescription</key>
    <string>The terminal needs access to your Downloads folder, like any other terminal.</string>
    <key>NSRemovableVolumesUsageDescription</key>
    <string>The terminal needs access to removable volumes, like any other terminal.</string>
    <key>NSNetworkVolumesUsageDescription</key>
    <string>The terminal needs access to network volumes, like any other terminal.</string>
</dict>
</plist>
PLIST

IDENTITY="$("$ROOT/Scripts/ensure-signing-identity.sh")"
codesign --force --sign "$IDENTITY" "$APP" >/dev/null
echo "Signed with $IDENTITY"

echo "Built $APP"
