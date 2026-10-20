#!/bin/bash
set -euo pipefail

script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
source "$script_directory/release-config.sh"
: "${SRCROOT:?Xcode source root is required}"
: "${DERIVED_FILE_DIR:?Xcode derived file directory is required}"
: "${CONFIGURATION:?Xcode configuration is required}"

# Generate a declared input to ProcessInfoPlistFile. Never change an app bundle
# after processing or signing: that can erase dates or invalidate its signature.
mkdir -p "$DERIVED_FILE_DIR"
generated_info="$DERIVED_FILE_DIR/CoolCumber-BuildInfo.plist"
cp "$SRCROOT/ThermFlowApp/Info.plist" "$generated_info"
if [ "$CONFIGURATION" = Beta ]; then
    /usr/libexec/PlistBuddy -c "Add :CoolCumberBetaStartsAt string $RELEASE_BETA_STARTS_AT" "$generated_info"
    /usr/libexec/PlistBuddy -c "Add :CoolCumberBetaExpiresAt string $RELEASE_BETA_EXPIRES_AT" "$generated_info"
fi
plutil -lint "$generated_info"
