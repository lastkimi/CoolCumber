#!/bin/bash

set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

if [ "$#" -gt 1 ]; then
    printf 'Usage: %s [DERIVED_DATA_DIRECTORY]\n' "$0" >&2
    exit 64
fi

temporary_derived_data=0
if [ "$#" -eq 1 ]; then
    derived_data_root="$1"
    mkdir -p "$derived_data_root"
else
    derived_data_root="$(mktemp -d "${TMPDIR:-/tmp}/coolcumber-derived-data.XXXXXX")"
    temporary_derived_data=1
fi

cleanup() {
    if [ "$temporary_derived_data" -eq 1 ]; then
        rm -rf "$derived_data_root"
    fi
}
trap cleanup EXIT

if ! command -v xcodegen > /dev/null 2>&1; then
    printf '%s\n' 'xcodegen is required. Install it with: brew install xcodegen' >&2
    exit 1
fi

xcodegen generate --spec project.yml

xcodebuild \
    -project MacThermFlow.xcodeproj \
    -scheme ThermFlowApp \
    -configuration Debug \
    -destination 'generic/platform=macOS' \
    -derivedDataPath "$derived_data_root/direct" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY= \
    COMPILER_INDEX_STORE_ENABLE=NO \
    build

xcodebuild \
    -project MacThermFlow.xcodeproj \
    -scheme ThermFlowAppStore \
    -configuration Debug \
    -destination 'generic/platform=macOS' \
    -derivedDataPath "$derived_data_root/mas" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY= \
    COMPILER_INDEX_STORE_ENABLE=NO \
    build

direct_app="$derived_data_root/direct/Build/Products/Debug/CoolCumber.app"
mas_app="$derived_data_root/mas/Build/Products/Debug/CoolCumber Lite.app"

"$repo_root/Scripts/check-channel-boundaries.sh" "$direct_app" "$mas_app"
"$repo_root/Scripts/check-project-boundaries.rb" "$repo_root/project.yml"

printf 'Unsigned Direct and Mac App Store builds passed. DerivedData: %s\n' "$derived_data_root"
