#!/bin/bash
set -e

# Configuration
APP_NAME="CoolCumber"
BUNDLE_ID="com.coolcumber.CoolCumber"
TEAM_ID="BSKR6CQ765" # Hangzhou Inkblaze AI Technology Co., Ltd.
CERT_NAME="Developer ID Application: Hangzhou Inkblaze AI Technology Co., Ltd. ($TEAM_ID)"
DMG_NAME="${APP_NAME}.dmg"
BUILD_DIR="build/Build/Products/Release"
APP_PATH="${BUILD_DIR}/${APP_NAME}.app"

echo "========================================"
echo "🍏 CoolCumber Release & Notarization Tool"
echo "========================================"

# 1. Check for Developer ID Certificate
if ! security find-identity -p codesigning -v | grep -q "Developer ID Application"; then
    echo "❌ Error: 'Developer ID Application' certificate not found in keychain!"
    echo "Please log in to https://developer.apple.com, generate a 'Developer ID Application' certificate, and double-click to install it in your Keychain."
    exit 1
fi

# 2. Check for Notarization Credentials
if [ -z "$APPLE_ID" ] || [ -z "$APP_SPECIFIC_PASSWORD" ]; then
    echo "❌ Error: Notarization credentials missing!"
    echo "Please set the APPLE_ID and APP_SPECIFIC_PASSWORD environment variables."
    echo "Example: export APPLE_ID=\"your@email.com\" && export APP_SPECIFIC_PASSWORD=\"xxxx-xxxx-xxxx-xxxx\""
    exit 1
fi

echo "🚀 Step 1: Building project..."
xcodegen generate
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project MacThermFlow.xcodeproj -scheme ThermFlowApp -configuration Release -derivedDataPath build

echo "🔐 Step 2: Code Signing with Hardened Runtime..."
# Sign Helper
codesign --force --options runtime --sign "$CERT_NAME" --timestamp "$APP_PATH/Contents/Library/LaunchServices/com.coolcumber.helper"
# Sign Widget
if [ -d "$APP_PATH/Contents/PlugIns/CoolCumberWidget.appex" ]; then
    codesign --force --options runtime --sign "$CERT_NAME" --timestamp "$APP_PATH/Contents/PlugIns/CoolCumberWidget.appex"
fi
# Sign App
codesign --force --options runtime --sign "$CERT_NAME" --timestamp "$APP_PATH"

echo "📦 Step 3: Compressing App to ZIP for Notarization..."
ZIP_NAME="${APP_NAME}.zip"
rm -f "$ZIP_NAME"
ditto -c -k --keepParent "$APP_PATH" "$ZIP_NAME"

echo "☁️ Step 4: Uploading to Apple Notary Service..."
xcrun notarytool submit "$ZIP_NAME" --apple-id "$APPLE_ID" --password "$APP_SPECIFIC_PASSWORD" --team-id "$TEAM_ID" --wait
rm -f "$ZIP_NAME"

echo "📎 Step 5: Stapling Notarization Ticket..."
xcrun stapler staple "$APP_PATH"

echo "📦 Step 6: Packaging DMG..."
rm -f "$DMG_NAME"
mkdir -p build/dmg
cp -R "$APP_PATH" build/dmg/
hdiutil create -volname "$APP_NAME" -srcfolder build/dmg -ov -format UDZO "$DMG_NAME"
rm -rf build/dmg

echo "✅ Success! $DMG_NAME is fully signed, notarized, stapled, and ready for distribution."
echo "You can now run: gh release upload v1.0.0 $DMG_NAME --clobber"
