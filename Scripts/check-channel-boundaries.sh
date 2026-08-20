#!/bin/bash

set -euo pipefail

usage() {
    printf 'Usage: %s DIRECT_APP MAS_APP\n' "$0"
}

if [ "$#" -ne 2 ]; then
    usage >&2
    exit 64
fi

direct_app="$1"
mas_app="$2"

if [ ! -d "$direct_app" ]; then
    printf 'Direct app bundle does not exist: %s\n' "$direct_app" >&2
    exit 1
fi

if [ ! -d "$mas_app" ]; then
    printf 'Mac App Store app bundle does not exist: %s\n' "$mas_app" >&2
    exit 1
fi

direct_helper="$direct_app/Contents/Library/LaunchServices/com.coolcumber.helper"
direct_launchd="$direct_app/Contents/Library/LaunchDaemons/com.coolcumber.helper.plist"
direct_launchd_fallback="$direct_app/Contents/Library/LaunchDaemons/com.coolcumber.helper-fallback.plist"

for required_path in "$direct_helper" "$direct_launchd" "$direct_launchd_fallback"; do
    if [ ! -e "$required_path" ]; then
        printf 'Direct capability is incomplete; missing: %s\n' "$required_path" >&2
        exit 1
    fi
done

for prohibited_path in \
    "$mas_app/Contents/Library/LaunchServices/com.coolcumber.helper" \
    "$mas_app/Contents/Library/LaunchDaemons/com.coolcumber.helper.plist" \
    "$mas_app/Contents/Library/LaunchDaemons/com.coolcumber.helper-fallback.plist"; do
    if [ -e "$prohibited_path" ]; then
        printf 'Mac App Store bundle contains a prohibited privileged component: %s\n' "$prohibited_path" >&2
        exit 1
    fi
done

plist_buddy="/usr/libexec/PlistBuddy"
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

direct_strings="$(mktemp "${TMPDIR:-/tmp}/coolcumber-direct-strings.XXXXXX")"
mas_strings="$(mktemp "${TMPDIR:-/tmp}/coolcumber-mas-strings.XXXXXX")"

cleanup() {
    rm -f "$direct_strings" "$mas_strings"
}
trap cleanup EXIT

strings "$direct_executable" > "$direct_strings"
strings "$mas_executable" > "$mas_strings"

if ! grep -F -q 'com.coolcumber.helper' "$direct_strings"; then
    printf '%s\n' 'Direct executable does not contain the expected privileged helper service identifier.' >&2
    exit 1
fi

prohibited_markers=(
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
