#!/bin/bash

set -euo pipefail

DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export DEVELOPER_DIR

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
cd "$repo_root"
# shellcheck source=Scripts/release-config.sh
source "$repo_root/Scripts/release-config.sh"

usage() {
    cat <<'USAGE'
Usage:
  ./release.sh \
    --output-dir /absolute/path \
    --channel Release|Beta \
    --version 1.2.0 \
    --build 3 \
    --team-id TEAM_ID \
    --source-commit FULL_40_CHARACTER_HEAD \
    [--notary-profile KEYCHAIN_PROFILE] \
    [--notary-timeout 30m]

Required environment:
  DIRECT_APP_SIGNING_IDENTITY
  MAS_APP_SIGNING_IDENTITY

Notary authentication must use a keychain profile or:
  NOTARY_KEY_PATH + NOTARY_KEY_ID + NOTARY_ISSUER_ID

Required App Store automatic-provisioning and cloud-signing authentication:
  ASC_KEY_PATH + ASC_KEY_ID + ASC_ISSUER_ID

The Mac App Store pkg is exported by Xcode with app-store-connect automatic
signing; no local installer identity is required. This command produces local
Direct and Mac App Store release artifacts. It does not upload to GitHub or
submit anything to App Store Connect.
USAGE
}

output_base=""
channel=""
version=""
build_number=""
team_id=""
source_commit=""
notary_profile="${NOTARY_KEYCHAIN_PROFILE:-}"
notary_timeout="${NOTARY_WAIT_TIMEOUT:-30m}"

while [ "$#" -gt 0 ]; do
    case "$1" in
        --output-dir)
            output_base="${2:-}"
            shift 2
            ;;
        --channel)
            channel="${2:-}"
            shift 2
            ;;
        --version)
            version="${2:-}"
            shift 2
            ;;
        --build)
            build_number="${2:-}"
            shift 2
            ;;
        --team-id)
            team_id="${2:-}"
            shift 2
            ;;
        --source-commit)
            source_commit="${2:-}"
            shift 2
            ;;
        --notary-profile)
            notary_profile="${2:-}"
            shift 2
            ;;
        --notary-timeout)
            notary_timeout="${2:-}"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            printf 'Unknown argument: %s\n' "$1" >&2
            usage >&2
            exit 64
            ;;
    esac
done

require_value() {
    local label="$1"
    local value="$2"
    if [ -z "$value" ]; then
        printf 'Missing required input: %s\n' "$label" >&2
        exit 64
    fi
}

require_value '--output-dir' "$output_base"
require_value '--channel' "$channel"
require_value '--version' "$version"
require_value '--build' "$build_number"
require_value '--team-id' "$team_id"
require_value '--source-commit' "$source_commit"
require_value 'DIRECT_APP_SIGNING_IDENTITY' "${DIRECT_APP_SIGNING_IDENTITY:-}"
require_value 'MAS_APP_SIGNING_IDENTITY' "${MAS_APP_SIGNING_IDENTITY:-}"

case "$channel" in
    Release|Beta)
        ;;
    *)
        printf '%s\n' '--channel must be exactly Release or Beta.' >&2
        exit 64
        ;;
esac

if ! [[ "$version" =~ ^[0-9]+(\.[0-9]+){1,2}$ ]]; then
    printf '%s\n' 'Version must contain two or three numeric components.' >&2
    exit 64
fi
if ! [[ "$build_number" =~ ^[1-9][0-9]*$ ]]; then
    printf '%s\n' 'Build number must be a positive integer.' >&2
    exit 64
fi
if ! [[ "$team_id" =~ ^[A-Z0-9]{10}$ ]]; then
    printf '%s\n' 'Team ID must contain exactly 10 uppercase letters or digits.' >&2
    exit 64
fi
if ! [[ "$notary_timeout" =~ ^[1-9][0-9]*[smh]?$ ]]; then
    printf '%s\n' '--notary-timeout must be a positive duration such as 30m.' >&2
    exit 64
fi
release_require_explicit_source_commit "$source_commit"

if [ -n "${APPLE_ID:-}" ] || [ -n "${APP_SPECIFIC_PASSWORD:-}" ]; then
    printf '%s\n' 'Legacy Apple-ID password credentials are not accepted.' >&2
    exit 64
fi

if [ ! -d "$DEVELOPER_DIR" ] || [ ! -x "$DEVELOPER_DIR/usr/bin/xcodebuild" ]; then
    printf 'DEVELOPER_DIR does not contain a usable Xcode installation: %s\n' "$DEVELOPER_DIR" >&2
    exit 1
fi

api_key_configured=0
if [ -n "${NOTARY_KEY_PATH:-}" ] || [ -n "${NOTARY_KEY_ID:-}" ] || [ -n "${NOTARY_ISSUER_ID:-}" ]; then
    api_key_configured=1
fi
if [ -n "$notary_profile" ] && [ "$api_key_configured" -eq 1 ]; then
    printf '%s\n' 'Configure either a notary keychain profile or an API key, not both.' >&2
    exit 64
fi
if [ -z "$notary_profile" ] && [ "$api_key_configured" -eq 0 ]; then
    printf '%s\n' 'Missing notary authentication. Configure an API key or keychain profile.' >&2
    exit 64
fi
if [ "$api_key_configured" -eq 1 ]; then
    require_value 'NOTARY_KEY_PATH' "${NOTARY_KEY_PATH:-}"
    require_value 'NOTARY_KEY_ID' "${NOTARY_KEY_ID:-}"
    require_value 'NOTARY_ISSUER_ID' "${NOTARY_ISSUER_ID:-}"
fi

require_value 'ASC_KEY_PATH' "${ASC_KEY_PATH:-}"
require_value 'ASC_KEY_ID' "${ASC_KEY_ID:-}"
require_value 'ASC_ISSUER_ID' "${ASC_ISSUER_ID:-}"

case "$output_base" in
    /*)
        ;;
    *)
        printf '%s\n' '--output-dir must be an absolute path outside the Git workspace.' >&2
        exit 64
        ;;
esac

if [ "$output_base" = '/' ] || [ "$output_base" = "${HOME:-}" ]; then
    printf '%s\n' 'Output directory is too broad; provide a dedicated release directory.' >&2
    exit 64
fi
case "$output_base" in
    "$repo_root"|"$repo_root"/*)
        printf '%s\n' 'Release output must be outside the Git workspace.' >&2
        exit 64
        ;;
esac

mkdir -p "$output_base"
output_base="$(cd "$output_base" && pwd -P)"
if [ "$output_base" = '/' ] || [ "$output_base" = "${HOME:-}" ]; then
    printf '%s\n' 'Resolved output directory is too broad.' >&2
    exit 64
fi
case "$output_base" in
    "$repo_root"|"$repo_root"/*)
        printf '%s\n' 'Resolved output directory points inside the Git workspace.' >&2
        exit 64
        ;;
esac

release_root="$output_base/CoolCumber-$version-$build_number-$channel"
if [ -e "$release_root" ]; then
    printf 'Release destination already exists; refusing to overwrite it: %s\n' "$release_root" >&2
    exit 1
fi
mkdir "$release_root"

mas_output="$release_root/mas"
direct_output="$release_root/direct"

"$repo_root/Scripts/release-mas.sh" \
    --output-dir "$mas_output" \
    --channel "$channel" \
    --version "$version" \
    --build "$build_number" \
    --team-id "$team_id" \
    --source-commit "$source_commit"

mas_archive="$mas_output/CoolCumber-MAS.xcarchive"
mas_app="$mas_archive/Products/Applications/CoolCumber.app"
mas_pkg="$mas_output/CoolCumber-$version-$build_number-$channel-AppStore.pkg"
if [ ! -s "$mas_pkg" ]; then
    printf 'Xcode App Store Connect export did not produce the expected pkg: %s\n' "$mas_pkg" >&2
    exit 1
fi

direct_args=(
    --output-dir "$direct_output"
    --channel "$channel"
    --version "$version"
    --build "$build_number"
    --team-id "$team_id"
    --source-commit "$source_commit"
    --mas-app "$mas_app"
    --mas-installer "$mas_pkg"
    --notary-timeout "$notary_timeout"
)
if [ -n "$notary_profile" ]; then
    direct_args+=(--notary-profile "$notary_profile")
fi

"$repo_root/Scripts/release-direct.sh" "${direct_args[@]}"

printf '%s\n' 'Both release channels were produced and locally validated.'
printf 'Release directory: %s\n' "$release_root"
printf '%s\n' 'No GitHub Release was created and nothing was submitted to App Store Connect.'
