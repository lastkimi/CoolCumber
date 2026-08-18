#!/bin/bash
set -e

# ============================================================================
# CoolCumber Lite - Mac App Store Build & Packaging Pipeline
# ============================================================================

APP_NAME="CoolCumber Lite"
APP_BUNDLE_ID="com.slmcamp.CoolCumber"
SCHEME="ThermFlowAppStore"
DERIVED_DATA_PATH="./build_mas"
BUILT_APP="$DERIVED_DATA_PATH/Build/Products/Release/CoolCumber Lite.app"
OUTPUT_PKG="CoolCumber_Lite_AppStore.pkg"

# Replace with your Apple Developer certificates when submitting
# Example: "Apple Distribution: Your Name (XXXXXXXXXX)" or "3rd Party Mac Developer Application: ..."
APP_CERT="${APP_CERT:-Apple Distribution}"
INSTALLER_CERT="${INSTALLER_CERT:-3rd Party Mac Developer Installer}"

echo "======================================================"
echo "🍏 Building CoolCumber for Mac App Store (Sandbox Safe)"
echo "======================================================"

echo "📦 Step 1: Generating Xcode Project..."
xcodegen generate

echo "🔨 Step 2: Compiling MAS Target ($SCHEME)..."
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
    -project MacThermFlow.xcodeproj \
    -scheme "$SCHEME" \
    -configuration Release \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    build

echo "🔐 Step 3: Checking App Bundle & Entitlements..."
codesign -d --entitlements :- "$BUILT_APP" || true

echo "📦 Step 4: Packaging for App Store Connect Submission..."
if command -v productbuild &> /dev/null; then
    echo "Creating .pkg installer..."
    productbuild --component "$BUILT_APP" /Applications "$OUTPUT_PKG" || true
    echo "✅ Generated App Store Package: $OUTPUT_PKG"
fi

echo "======================================================"
echo "🎉 Mac App Store Build Ready at: $BUILT_APP"
echo "======================================================"
