#!/bin/bash

set -euo pipefail

DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export DEVELOPER_DIR

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

temporary_derived_data=0
derived_data_root=""
configuration="Debug"

# Preserve the original one-positional-argument interface for local callers,
# while allowing CI to compile every declared configuration explicitly.
if [ "$#" -eq 1 ] && [[ "$1" != --* ]]; then
    derived_data_root="$1"
    shift
fi
while [ "$#" -gt 0 ]; do
    case "$1" in
        --derived-data)
            derived_data_root="${2:-}"
            shift 2
            ;;
        --configuration)
            configuration="${2:-}"
            shift 2
            ;;
        -h|--help)
            printf 'Usage: %s [DERIVED_DATA_DIRECTORY] [--configuration Debug|Beta|Release]\n' "$0"
            exit 0
            ;;
        *)
            printf 'Unknown argument: %s\n' "$1" >&2
            exit 64
            ;;
    esac
done

case "$configuration" in Debug|Beta|Release) ;; *)
    printf '%s\n' '--configuration must be Debug, Beta, or Release.' >&2
    exit 64
esac

if [ -n "$derived_data_root" ]; then
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

if [ ! -d "$DEVELOPER_DIR" ] || [ ! -x "$DEVELOPER_DIR/usr/bin/xcodebuild" ]; then
    printf 'DEVELOPER_DIR does not contain a usable Xcode installation: %s\n' "$DEVELOPER_DIR" >&2
    exit 1
fi

if ! command -v xcodegen > /dev/null 2>&1; then
    printf '%s\n' 'xcodegen is required. Install it with: brew install xcodegen' >&2
    exit 1
fi

xcodegen generate --spec project.yml

xcodebuild \
    -project MacThermFlow.xcodeproj \
    -scheme ThermFlowApp \
    -configuration "$configuration" \
    -destination 'generic/platform=macOS' \
    -jobs 1 \
    -derivedDataPath "$derived_data_root/direct" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY= \
    COMPILER_INDEX_STORE_ENABLE=NO \
    'ARCHS=arm64 x86_64' \
    ONLY_ACTIVE_ARCH=NO \
    build

xcodebuild \
    -project MacThermFlow.xcodeproj \
    -scheme ThermFlowAppStore \
    -configuration "$configuration" \
    -destination 'generic/platform=macOS' \
    -jobs 1 \
    -derivedDataPath "$derived_data_root/mas" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY= \
    COMPILER_INDEX_STORE_ENABLE=NO \
    'ARCHS=arm64 x86_64' \
    ONLY_ACTIVE_ARCH=NO \
    build

direct_app="$derived_data_root/direct/Build/Products/$configuration/CoolCumber.app"
mas_app="$derived_data_root/mas/Build/Products/$configuration/CoolCumber.app"

"$repo_root/Scripts/check-channel-boundaries.sh" "$direct_app" "$mas_app" "$configuration"
"$repo_root/Scripts/check-project-boundaries.rb" "$repo_root/project.yml"

printf 'Unsigned %s Direct and Mac App Store builds passed. DerivedData: %s\n' "$configuration" "$derived_data_root"
