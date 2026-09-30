#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Set this to your own persistent code-signing identity in your login Keychain.
: "${LOOKFOCUS_SIGNING_IDENTITY:?Set LOOKFOCUS_SIGNING_IDENTITY to your own code-signing certificate name or SHA-1 identity}"
swift build -c release
APP="$PWD/dist/LookFocus.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/LookFocus "$APP/Contents/MacOS/LookFocus"
swift scripts/make-icon.swift "$PWD/dist/LookFocus.iconset"
iconutil --convert icns "$PWD/dist/LookFocus.iconset" --output "$APP/Contents/Resources/LookFocus.icns"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>LookFocus</string>
<key>CFBundleIdentifier</key><string>local.personal.LookFocus</string>
<key>CFBundleName</key><string>LookFocus</string>
<key>CFBundleDisplayName</key><string>LookFocus</string>
<key>CFBundleIconFile</key><string>LookFocus</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.5.0</string>
<key>CFBundleVersion</key><string>10</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><false/>
<key>NSCameraUsageDescription</key><string>LookFocus uses your camera to estimate head direction and focus a calibrated screen or window. Frames stay in memory on this Mac and are never recorded or uploaded.</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
# Keep the same identity across updates so macOS can retain permission approvals.
# Never fall back to ad hoc signing when the identity is unavailable.
codesign --force --sign "$LOOKFOCUS_SIGNING_IDENTITY" --identifier local.personal.LookFocus --timestamp=none "$APP"
codesign --verify --strict "$APP"
printf '%s\n' "$APP"
