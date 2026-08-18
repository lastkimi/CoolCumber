#!/bin/bash
# Configuration
SUBMISSION_ID="96220566-4047-4b5a-a2f4-79974227113c"
APP_NAME="CoolCumber"
DMG_NAME="${APP_NAME}.dmg"
APP_PATH="build/Build/Products/Release/${APP_NAME}.app"

echo "⏳ Starting polling for Apple Notary Service submission: $SUBMISSION_ID"

while true; do
    echo "🔍 Checking status at $(date)..."
    STATUS_OUT=$(xcrun notarytool info "$SUBMISSION_ID" --apple-id "$APPLE_ID" --password "$APP_SPECIFIC_PASSWORD" --team-id "BSKR6CQ765" 2>&1)
    
    if echo "$STATUS_OUT" | grep -q "status: Accepted"; then
        echo "🎉 Notarization ACCEPTED!"
        break
    elif echo "$STATUS_OUT" | grep -q "status: Invalid"; then
        echo "❌ Notarization FAILED!"
        echo "$STATUS_OUT"
        # Try to fetch log
        xcrun notarytool log "$SUBMISSION_ID" --apple-id "$APPLE_ID" --password "$APP_SPECIFIC_PASSWORD" --team-id "BSKR6CQ765" log.json
        echo "Log saved to log.json"
        exit 1
    elif echo "$STATUS_OUT" | grep -q "Error"; then
        echo "⚠️ Network error or rate limit, retrying in 30s... (Details: $STATUS_OUT)"
    else
        echo "⏳ Still In Progress..."
    fi
    
    sleep 30
done

echo "📎 Stapling notarization ticket to $APP_PATH..."
xcrun stapler staple "$APP_PATH"

echo "📦 Packaging final DMG..."
rm -f "$DMG_NAME"
mkdir -p build/dmg
cp -R "$APP_PATH" build/dmg/
hdiutil create -volname "$APP_NAME" -srcfolder build/dmg -ov -format UDZO "$DMG_NAME"
rm -rf build/dmg

echo "🚀 Uploading to GitHub Release..."
gh release upload v1.0.0 "$DMG_NAME" --clobber

echo "✅ All done! Release successfully updated."
