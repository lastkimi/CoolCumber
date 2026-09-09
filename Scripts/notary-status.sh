#!/bin/bash

set -euo pipefail

usage() {
    cat <<'USAGE'
Usage:
  Scripts/notary-status.sh \
    --submission-id UUID \
    --result /absolute/path/result.json \
    [--timeout 30m] \
    [--notary-profile KEYCHAIN_PROFILE]

Authentication uses either a keychain profile or:
  NOTARY_KEY_PATH + NOTARY_KEY_ID + NOTARY_ISSUER_ID

This resumes polling an existing submission. It never resubmits an artifact.
USAGE
}

submission_id=""
result_path=""
timeout_value="${NOTARY_WAIT_TIMEOUT:-30m}"
notary_profile="${NOTARY_KEYCHAIN_PROFILE:-}"

while [ "$#" -gt 0 ]; do
    case "$1" in
        --submission-id) submission_id="${2:-}"; shift 2 ;;
        --result) result_path="${2:-}"; shift 2 ;;
        --timeout) timeout_value="${2:-}"; shift 2 ;;
        --notary-profile) notary_profile="${2:-}"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) printf 'Unknown argument: %s\n' "$1" >&2; usage >&2; exit 64 ;;
    esac
done

if ! [[ "$submission_id" =~ ^[0-9a-fA-F-]{36}$ ]]; then
    printf '%s\n' '--submission-id must be the UUID returned by notarytool submit.' >&2
    exit 64
fi
case "$result_path" in /*) ;; *)
    printf '%s\n' '--result must be an absolute path.' >&2
    exit 64
esac
if ! [[ "$timeout_value" =~ ^[1-9][0-9]*[smh]?$ ]]; then
    printf '%s\n' '--timeout must be a positive duration such as 30m.' >&2
    exit 64
fi
if [ -e "$result_path" ]; then
    printf 'Refusing to overwrite an existing status result: %s\n' "$result_path" >&2
    exit 1
fi
mkdir -p "$(dirname "$result_path")"

api_key_configured=0
if [ -n "${NOTARY_KEY_PATH:-}" ] || [ -n "${NOTARY_KEY_ID:-}" ] || [ -n "${NOTARY_ISSUER_ID:-}" ]; then
    api_key_configured=1
fi
if [ -n "$notary_profile" ] && [ "$api_key_configured" -eq 1 ]; then
    printf '%s\n' 'Configure either a keychain profile or an API key, not both.' >&2
    exit 64
fi
if [ -n "$notary_profile" ]; then
    notary_args=(--keychain-profile "$notary_profile")
elif [ "$api_key_configured" -eq 1 ]; then
    if [ -z "${NOTARY_KEY_PATH:-}" ] || [ -z "${NOTARY_KEY_ID:-}" ] || [ -z "${NOTARY_ISSUER_ID:-}" ]; then
        printf '%s\n' 'NOTARY_KEY_PATH, NOTARY_KEY_ID, and NOTARY_ISSUER_ID must all be set.' >&2
        exit 64
    fi
    case "$NOTARY_KEY_PATH" in /*.p8) ;; *)
        printf '%s\n' 'NOTARY_KEY_PATH must be an absolute .p8 path.' >&2
        exit 64
    esac
    if [ ! -r "$NOTARY_KEY_PATH" ]; then
        printf '%s\n' 'NOTARY_KEY_PATH is not readable.' >&2
        exit 1
    fi
    notary_args=(--key "$NOTARY_KEY_PATH" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID")
else
    printf '%s\n' 'Missing notary authentication.' >&2
    exit 64
fi

if ! xcrun notarytool wait "$submission_id" \
    "${notary_args[@]}" \
    --timeout "$timeout_value" \
    --output-format json > "$result_path"; then
    printf 'Submission %s is still processing or could not be queried; partial result: %s\n' \
        "$submission_id" "$result_path" >&2
    exit 75
fi

status="$(plutil -extract status raw -o - "$result_path")"
printf 'Notarization submission %s status: %s\n' "$submission_id" "$status"
if [ "$status" != 'Accepted' ]; then
    exit 1
fi
