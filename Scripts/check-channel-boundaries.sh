#!/bin/bash

set -euo pipefail

script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=Scripts/release-config.sh
source "$script_directory/release-config.sh"

usage() {
    printf 'Usage: %s DIRECT_APP MAS_APP [Debug|Beta|Release]\n' "$0"
}

if [ "$#" -lt 2 ] || [ "$#" -gt 3 ]; then
    usage >&2
    exit 64
fi

direct_app="$1"
mas_app="$2"
configuration="${3:-}"
case "$configuration" in ''|Debug|Beta|Release) ;; *)
    printf 'Invalid build configuration: %s\n' "$configuration" >&2
    exit 64
esac

if [ ! -d "$direct_app" ]; then
    printf 'Direct app bundle does not exist: %s\n' "$direct_app" >&2
    exit 1
fi

if [ ! -d "$mas_app" ]; then
    printf 'Mac App Store app bundle does not exist: %s\n' "$mas_app" >&2
    exit 1
fi

if ! command -v lipo > /dev/null 2>&1; then
    printf '%s\n' 'lipo is required to verify Intel and Apple Silicon release support.' >&2
    exit 1
fi

direct_helper="$direct_app/Contents/Library/LaunchServices/$RELEASE_HELPER_EXECUTABLE_NAME"
direct_launchd="$direct_app/Contents/Library/LaunchDaemons/$RELEASE_HELPER_PLIST_NAME"
legacy_tombstone="$direct_app/Contents/Library/LaunchDaemons/com.coolcumber.helper.plist"

for required_path in "$direct_helper" "$direct_launchd" "$legacy_tombstone"; do
    if [ ! -e "$required_path" ]; then
        printf 'Direct capability is incomplete; missing: %s\n' "$required_path" >&2
        exit 1
    fi
done

for prohibited_path in \
    "$mas_app/Contents/Library/LaunchServices/$RELEASE_HELPER_EXECUTABLE_NAME" \
    "$mas_app/Contents/Library/LaunchDaemons/$RELEASE_HELPER_PLIST_NAME" \
    "$mas_app/Contents/Library/LaunchDaemons/com.coolcumber.helper.plist"; do
    if [ -e "$prohibited_path" ]; then
        printf 'Mac App Store bundle contains a prohibited privileged component: %s\n' "$prohibited_path" >&2
        exit 1
    fi
done

plist_buddy="/usr/libexec/PlistBuddy"
assert_bundle_identifier() {
    local bundle_path="$1"
    local expected_identifier="$2"
    local label="$3"
    local actual_identifier

    actual_identifier="$($plist_buddy -c 'Print :CFBundleIdentifier' "$bundle_path/Contents/Info.plist")"
    if [ "$actual_identifier" != "$expected_identifier" ]; then
        printf '%s bundle identifier mismatch: expected %s, got %s\n' \
            "$label" "$expected_identifier" "$actual_identifier" >&2
        exit 1
    fi
}

assert_beta_window() {
    local app_path="$1"
    local label="$2"
    local starts_at
    local expires_at

    starts_at="$($plist_buddy -c 'Print :CoolCumberBetaStartsAt' "$app_path/Contents/Info.plist" 2> /dev/null || true)"
    expires_at="$($plist_buddy -c 'Print :CoolCumberBetaExpiresAt' "$app_path/Contents/Info.plist" 2> /dev/null || true)"

    if [ "$configuration" = 'Beta' ] || { [ -z "$configuration" ] && [ -n "$starts_at$expires_at" ]; }; then
        if [ "$starts_at" != "$RELEASE_BETA_STARTS_AT" ] ||
           [ "$expires_at" != "$RELEASE_BETA_EXPIRES_AT" ]; then
            printf '%s Beta access window mismatch.\n' "$label" >&2
            exit 1
        fi
    elif [ -n "$starts_at$expires_at" ]; then
        printf '%s %s build must not contain Beta access keys.\n' "$label" "$configuration" >&2
        exit 1
    fi
}

assert_universal_binary() {
    local binary_path="$1"
    local label="$2"
    local architectures

    if [ ! -x "$binary_path" ]; then
        printf '%s executable is missing: %s\n' "$label" "$binary_path" >&2
        exit 1
    fi
    if ! architectures="$(lipo -archs "$binary_path" 2> /dev/null)"; then
        printf '%s is not a valid Mach-O executable: %s\n' "$label" "$binary_path" >&2
        exit 1
    fi
    case " $architectures " in
        *' arm64 '*) ;;
        *)
            printf '%s does not support Apple Silicon (arm64): %s\n' "$label" "$architectures" >&2
            exit 1
            ;;
    esac
    case " $architectures " in
        *' x86_64 '*) ;;
        *)
            printf '%s does not support 2019 Intel Macs (x86_64): %s\n' "$label" "$architectures" >&2
            exit 1
            ;;
    esac
}

assert_widget_bundle() {
    local app_path="$1"
    local label="$2"
    local widget_path="$app_path/Contents/PlugIns/CoolCumberWidget.appex"
    local widget_executable_name

    if [ ! -d "$widget_path" ]; then
        printf '%s is missing the CoolCumber widget extension.\n' "$label" >&2
        exit 1
    fi
    assert_bundle_identifier \
        "$widget_path" \
        "$RELEASE_WIDGET_BUNDLE_ID" \
        "$label widget"
    widget_executable_name="$($plist_buddy -c 'Print :CFBundleExecutable' "$widget_path/Contents/Info.plist")"
    assert_universal_binary \
        "$widget_path/Contents/MacOS/$widget_executable_name" \
        "$label widget"
}

assert_bundle_identifier "$direct_app" "$RELEASE_APP_BUNDLE_ID" 'Direct app'
assert_bundle_identifier "$mas_app" "$RELEASE_APP_BUNDLE_ID" 'Mac App Store app'
assert_beta_window "$direct_app" 'Direct app'
assert_beta_window "$mas_app" 'Mac App Store app'

direct_executable_name="$($plist_buddy -c 'Print :CFBundleExecutable' "$direct_app/Contents/Info.plist")"
mas_executable_name="$($plist_buddy -c 'Print :CFBundleExecutable' "$mas_app/Contents/Info.plist")"
direct_executable="$direct_app/Contents/MacOS/$direct_executable_name"
mas_executable="$mas_app/Contents/MacOS/$mas_executable_name"

if [ ! -x "$direct_executable" ]; then
    printf 'Direct executable is missing or not executable: %s\n' "$direct_executable" >&2
    exit 1
fi

if [ ! -x "$mas_executable" ]; then
    printf 'Mac App Store executable is missing or not executable: %s\n' "$mas_executable" >&2
    exit 1
fi

assert_universal_binary "$direct_executable" 'Direct app'
assert_universal_binary "$mas_executable" 'Mac App Store app'
assert_universal_binary "$direct_helper" 'Direct privileged helper'
assert_widget_bundle "$direct_app" 'Direct app'
assert_widget_bundle "$mas_app" 'Mac App Store app'

direct_helper_strings="$(mktemp "${TMPDIR:-/tmp}/coolcumber-direct-helper-strings.XXXXXX")"
mas_strings="$(mktemp "${TMPDIR:-/tmp}/coolcumber-mas-strings.XXXXXX")"

cleanup() {
    rm -f "$direct_helper_strings" "$mas_strings"
}
trap cleanup EXIT

strings "$direct_helper" > "$direct_helper_strings"
strings "$mas_executable" > "$mas_strings"

if ! grep -F -q "$RELEASE_HELPER_SERVICE_ID" "$direct_helper_strings"; then
    printf '%s\n' 'Direct helper does not contain the expected privileged service identifier.' >&2
    exit 1
fi

if [ "$($plist_buddy -c 'Print :Label' "$direct_launchd")" != "$RELEASE_HELPER_SERVICE_ID" ] ||
   [ "$($plist_buddy -c "Print :MachServices:$RELEASE_HELPER_SERVICE_ID" "$direct_launchd")" != 'true' ] ||
   [ "$($plist_buddy -c 'Print :BundleProgram' "$direct_launchd")" != "Contents/Library/LaunchServices/$RELEASE_HELPER_EXECUTABLE_NAME" ]; then
    printf '%s\n' 'Direct launchd registration does not match the embedded helper.' >&2
    exit 1
fi

if [ "$($plist_buddy -c 'Print :Label' "$legacy_tombstone")" != 'com.coolcumber.helper' ] ||
   [ "$($plist_buddy -c 'Print :BundleProgram' "$legacy_tombstone")" != "Contents/Library/LaunchServices/$RELEASE_HELPER_EXECUTABLE_NAME" ] ||
   $plist_buddy -c 'Print :MachServices' "$legacy_tombstone" > /dev/null 2>&1; then
    printf '%s\n' 'Legacy helper cleanup tombstone must be inert and point at the v2 tool.' >&2
    exit 1
fi

for release_app in "$direct_app" "$mas_app"; do
    if [ -n "$(find "$release_app" -type f -name '*.storekit' -print -quit)" ]; then
        printf 'Release app contains a prohibited StoreKit test configuration: %s\n' "$release_app" >&2
        exit 1
    fi
done

prohibited_markers=(
    "$RELEASE_HELPER_SERVICE_ID"
    'com.coolcumber.helper'
    '/Library/PrivilegedHelperTools'
    '/Library/LaunchDaemons'
    'api.github.com/repos/'
    'releases/latest/download'
)

for marker in "${prohibited_markers[@]}"; do
    if grep -F -q "$marker" "$mas_strings"; then
        printf 'Mac App Store executable contains a Direct-only capability marker: %s\n' "$marker" >&2
        exit 1
    fi
done

printf '%s\n' 'Built-product channel boundary check passed.'
