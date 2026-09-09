#!/bin/bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

usage() {
    cat <<'USAGE'
Usage:
  ./wait_and_complete.sh \
    --submission-id UUID \
    [--notary-profile KEYCHAIN_PROFILE] \
    [--interval SECONDS] \
    [--timeout SECONDS] \
    [--log-output /absolute/path/notary-log.json] \
    [--staple-target /path/to/App.app-or-image.dmg]

Notary authentication must use exactly one method:
  NOTARY_KEYCHAIN_PROFILE (or --notary-profile)
  NOTARY_KEY_PATH + NOTARY_KEY_ID + NOTARY_ISSUER_ID

This utility only monitors one explicit submission and optionally staples one
explicit artifact. It never packages or uploads a release. New submissions
should normally be made through Scripts/release-direct.sh.
USAGE
}

submission_id=""
notary_profile="${NOTARY_KEYCHAIN_PROFILE:-}"
interval=30
timeout=3600
log_output=""
staple_target=""

while [ "$#" -gt 0 ]; do
    case "$1" in
        --submission-id)
            submission_id="${2:-}"
            shift 2
            ;;
        --notary-profile)
            notary_profile="${2:-}"
            shift 2
            ;;
        --interval)
            interval="${2:-}"
            shift 2
            ;;
        --timeout)
            timeout="${2:-}"
            shift 2
            ;;
        --log-output)
            log_output="${2:-}"
            shift 2
            ;;
        --staple-target)
            staple_target="${2:-}"
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

if ! [[ "$submission_id" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]; then
    printf '%s\n' '--submission-id must be an explicit notarization submission UUID.' >&2
    exit 64
fi
if ! [[ "$interval" =~ ^[0-9]+$ ]] || [ "$interval" -lt 10 ] || [ "$interval" -gt 300 ]; then
    printf '%s\n' '--interval must be between 10 and 300 seconds.' >&2
    exit 64
fi
if ! [[ "$timeout" =~ ^[0-9]+$ ]] || [ "$timeout" -lt "$interval" ] || [ "$timeout" -gt 86400 ]; then
    printf '%s\n' '--timeout must be at least one interval and no more than 86400 seconds.' >&2
    exit 64
fi

if [ -n "${APPLE_ID:-}" ] || [ -n "${APP_SPECIFIC_PASSWORD:-}" ]; then
    printf '%s\n' 'Legacy Apple-ID password credentials are not accepted; use an API key or keychain profile.' >&2
    exit 64
fi

required_tools=(date grep plutil sleep stat xcrun)
for required_tool in "${required_tools[@]}"; do
    if ! command -v "$required_tool" > /dev/null 2>&1; then
        printf 'Required notarization tool is unavailable: %s\n' "$required_tool" >&2
        exit 1
    fi
done

notary_args=()
api_key_configured=0
if [ -n "${NOTARY_KEY_PATH:-}" ] || [ -n "${NOTARY_KEY_ID:-}" ] || [ -n "${NOTARY_ISSUER_ID:-}" ]; then
    api_key_configured=1
fi
if [ -n "$notary_profile" ] && [ "$api_key_configured" -eq 1 ]; then
    printf '%s\n' 'Configure either a notary keychain profile or an API key, not both.' >&2
    exit 64
fi

if [ -n "$notary_profile" ]; then
    notary_args=(--keychain-profile "$notary_profile")
elif [ "$api_key_configured" -eq 1 ]; then
    if [ -z "${NOTARY_KEY_PATH:-}" ] || [ -z "${NOTARY_KEY_ID:-}" ] || [ -z "${NOTARY_ISSUER_ID:-}" ]; then
        printf '%s\n' 'NOTARY_KEY_PATH, NOTARY_KEY_ID, and NOTARY_ISSUER_ID must be provided together.' >&2
        exit 64
    fi
    case "$NOTARY_KEY_PATH" in
        /*)
            ;;
        *)
            printf '%s\n' 'NOTARY_KEY_PATH must be an absolute path outside the Git workspace.' >&2
            exit 64
            ;;
    esac
    if [ ! -r "$NOTARY_KEY_PATH" ]; then
        printf '%s\n' 'NOTARY_KEY_PATH is not readable.' >&2
        exit 1
    fi
    key_directory="$(cd "$(dirname "$NOTARY_KEY_PATH")" && pwd -P)"
    notary_key_absolute="$key_directory/$(basename "$NOTARY_KEY_PATH")"
    case "$notary_key_absolute" in
        "$repo_root"/*)
            printf '%s\n' 'The notary API key must be stored outside the Git workspace.' >&2
            exit 64
            ;;
    esac
    if ! grep -q 'BEGIN PRIVATE KEY' "$notary_key_absolute"; then
        printf '%s\n' 'NOTARY_KEY_PATH does not contain a recognizable private key.' >&2
        exit 1
    fi
    notary_key_mode="$(stat -f '%Lp' "$notary_key_absolute")"
    case "$notary_key_mode" in
        400|600)
            ;;
        *)
            printf '%s\n' 'NOTARY_KEY_PATH permissions must be 400 or 600.' >&2
            exit 1
            ;;
    esac
    if ! [[ "$NOTARY_KEY_ID" =~ ^[A-Z0-9]{10}$ ]]; then
        printf '%s\n' 'NOTARY_KEY_ID must be a 10-character App Store Connect key ID.' >&2
        exit 64
    fi
    if ! [[ "$NOTARY_ISSUER_ID" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]; then
        printf '%s\n' 'NOTARY_ISSUER_ID must be an App Store Connect issuer UUID.' >&2
        exit 64
    fi
    notary_args=(--key "$notary_key_absolute" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID")
else
    printf '%s\n' 'Missing notary authentication. Configure an API key or keychain profile.' >&2
    exit 64
fi

if [ -n "$log_output" ]; then
    case "$log_output" in
        /*)
            ;;
        *)
            printf '%s\n' '--log-output must be an absolute path outside the Git workspace.' >&2
            exit 64
            ;;
    esac
    case "$log_output" in
        "$repo_root"|"$repo_root"/*)
            printf '%s\n' 'Notary log output must be outside the Git workspace.' >&2
            exit 64
            ;;
    esac
    if [ -e "$log_output" ]; then
        printf 'Refusing to overwrite existing notary log: %s\n' "$log_output" >&2
        exit 1
    fi
    mkdir -p "$(dirname "$log_output")"
    log_directory="$(cd "$(dirname "$log_output")" && pwd -P)"
    log_output="$log_directory/$(basename "$log_output")"
    if [ "$log_directory" = '/' ] || [ "$log_directory" = "${HOME:-}" ]; then
        printf '%s\n' 'Resolved notary log directory is too broad.' >&2
        exit 64
    fi
    case "$log_output" in
        "$repo_root"|"$repo_root"/*)
            printf '%s\n' 'Resolved notary log output points inside the Git workspace.' >&2
            exit 64
            ;;
    esac
fi

if [ -n "$staple_target" ]; then
    if [ ! -e "$staple_target" ]; then
        printf 'Staple target does not exist: %s\n' "$staple_target" >&2
        exit 1
    fi
    case "$staple_target" in
        *.app|*.dmg|*.pkg)
            ;;
        *)
            printf '%s\n' '--staple-target must be an app, dmg, or pkg.' >&2
            exit 64
            ;;
    esac
    if [ -d "$staple_target" ]; then
        staple_target="$(cd "$staple_target" && pwd -P)"
    else
        staple_directory="$(cd "$(dirname "$staple_target")" && pwd -P)"
        staple_target="$staple_directory/$(basename "$staple_target")"
    fi
    case "$staple_target" in
        "$repo_root"|"$repo_root"/*)
            printf '%s\n' 'Staple target must be outside the Git workspace.' >&2
            exit 64
            ;;
    esac
fi

status_file="$(mktemp "${TMPDIR:-/tmp}/coolcumber-notary-status.XXXXXX")"
cleanup() {
    rm -f "$status_file"
}
trap cleanup EXIT

start_time="$(date +%s)"
while true; do
    xcrun notarytool info "$submission_id" \
        "${notary_args[@]}" \
        --output-format json > "$status_file"
    status="$(plutil -extract status raw "$status_file")"

    case "$status" in
        Accepted)
            printf 'Notarization submission %s was accepted.\n' "$submission_id"
            if [ -n "$staple_target" ]; then
                xcrun stapler staple "$staple_target"
                xcrun stapler validate "$staple_target"
                printf 'Stapled and validated: %s\n' "$staple_target"
            fi
            exit 0
            ;;
        Invalid|Rejected)
            printf 'Notarization submission %s failed with status %s.\n' "$submission_id" "$status" >&2
            if [ -n "$log_output" ]; then
                xcrun notarytool log "$submission_id" \
                    "${notary_args[@]}" \
                    "$log_output"
                printf 'Notary log saved to: %s\n' "$log_output" >&2
            fi
            exit 1
            ;;
        'In Progress')
            ;;
        *)
            printf 'Unexpected notarization status: %s\n' "$status" >&2
            exit 1
            ;;
    esac

    now="$(date +%s)"
    elapsed=$((now - start_time))
    if [ "$elapsed" -ge "$timeout" ]; then
        printf 'Timed out after %s seconds while waiting for submission %s.\n' "$timeout" "$submission_id" >&2
        exit 1
    fi
    printf 'Submission %s is still in progress (%s seconds elapsed).\n' "$submission_id" "$elapsed"
    sleep "$interval"
done
