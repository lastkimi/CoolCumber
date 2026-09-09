#!/bin/bash

# Shared, non-secret release identity and source-integrity helpers.
# Keep product identifiers here so helper migrations cannot leave release gates
# validating a mixture of old and new service names.

readonly RELEASE_PRODUCT_NAME='CoolCumber'
readonly RELEASE_APP_BUNDLE_ID='com.slmcamp.CoolCumber'
readonly RELEASE_WIDGET_BUNDLE_ID='com.slmcamp.CoolCumber.CoolCumberWidget'
readonly RELEASE_APP_GROUP='BSKR6CQ765.com.slmcamp.CoolCumber'
readonly RELEASE_HELPER_SERVICE_ID='com.slmcamp.CoolCumber.helper.v2'
readonly RELEASE_HELPER_EXECUTABLE_NAME='com.slmcamp.CoolCumber.helper.v2'
readonly RELEASE_HELPER_PLIST_NAME='com.slmcamp.CoolCumber.helper.v2.plist'
readonly RELEASE_BETA_STARTS_AT='2026-08-20T00:00:00Z'
readonly RELEASE_BETA_EXPIRES_AT='2026-09-30T00:00:00Z'

release_require_explicit_source_commit() {
    local expected_commit="$1"
    local actual_commit
    local tracked_changes

    if ! [[ "$expected_commit" =~ ^[0-9a-f]{40}$ ]]; then
        printf '%s\n' '--source-commit must be the full, lowercase 40-character HEAD commit.' >&2
        return 64
    fi

    actual_commit="$(git rev-parse --verify HEAD)"
    if [ "$actual_commit" != "$expected_commit" ]; then
        printf 'Source commit mismatch: expected %s, current HEAD is %s\n' \
            "$expected_commit" "$actual_commit" >&2
        return 1
    fi

    tracked_changes="$(git status --porcelain=v1 --untracked-files=no)"
    if [ -n "$tracked_changes" ]; then
        printf '%s\n' 'Release builds require a clean tracked worktree and index.' >&2
        printf '%s\n' 'Commit or restore tracked changes before creating release artifacts.' >&2
        return 1
    fi
}

release_sha256() {
    shasum -a 256 "$1" | awk '{print $1}'
}

release_require_sha256() {
    local expected_sha="$1"
    local artifact_path="$2"
    local actual_sha

    if ! [[ "$expected_sha" =~ ^[0-9a-f]{64}$ ]]; then
        printf '%s\n' 'Expected SHA-256 must be exactly 64 lowercase hexadecimal characters.' >&2
        return 64
    fi
    actual_sha="$(release_sha256 "$artifact_path")"
    if [ "$actual_sha" != "$expected_sha" ]; then
        printf 'Artifact SHA-256 mismatch for %s.\n' "$artifact_path" >&2
        printf 'Expected: %s\nActual:   %s\n' "$expected_sha" "$actual_sha" >&2
        return 1
    fi
}

release_write_manifest() {
    local destination="$1"
    local source_commit="$2"
    local configuration="$3"
    local version="$4"
    local build_number="$5"
    local team_id="$6"
    local artifact_kind="$7"
    local artifact_path="$8"
    local artifact_sha="$9"
    local temporary_plist
    local artifact_size

    temporary_plist="$(mktemp "${TMPDIR:-/tmp}/coolcumber-release-manifest.XXXXXX")"
    artifact_size="$(stat -f '%z' "$artifact_path")"

    plutil -create xml1 "$temporary_plist"
    plutil -insert schemaVersion -integer 1 "$temporary_plist"
    plutil -insert sourceCommit -string "$source_commit" "$temporary_plist"
    plutil -insert configuration -string "$configuration" "$temporary_plist"
    plutil -insert version -string "$version" "$temporary_plist"
    plutil -insert build -string "$build_number" "$temporary_plist"
    plutil -insert teamID -string "$team_id" "$temporary_plist"
    plutil -insert identities -dictionary "$temporary_plist"
    plutil -insert identities.appBundleID -string "$RELEASE_APP_BUNDLE_ID" "$temporary_plist"
    plutil -insert identities.widgetBundleID -string "$RELEASE_WIDGET_BUNDLE_ID" "$temporary_plist"
    plutil -insert identities.helperServiceID -string "$RELEASE_HELPER_SERVICE_ID" "$temporary_plist"
    plutil -insert artifact -dictionary "$temporary_plist"
    plutil -insert artifact.kind -string "$artifact_kind" "$temporary_plist"
    plutil -insert artifact.file -string "$(basename "$artifact_path")" "$temporary_plist"
    plutil -insert artifact.bytes -integer "$artifact_size" "$temporary_plist"
    plutil -insert artifact.sha256 -string "$artifact_sha" "$temporary_plist"
    plutil -convert json -o "$destination" "$temporary_plist"
    rm -f "$temporary_plist"
}

release_write_mas_manifest() {
    local destination="$1"
    local source_commit="$2"
    local configuration="$3"
    local version="$4"
    local build_number="$5"
    local team_id="$6"
    local archive_path="$7"
    local archive_sha="$8"
    local package_path="$9"
    local package_sha="${10}"
    local temporary_plist

    temporary_plist="$(mktemp "${TMPDIR:-/tmp}/coolcumber-mas-manifest.XXXXXX")"
    plutil -create xml1 "$temporary_plist"
    plutil -insert schemaVersion -integer 1 "$temporary_plist"
    plutil -insert sourceCommit -string "$source_commit" "$temporary_plist"
    plutil -insert configuration -string "$configuration" "$temporary_plist"
    plutil -insert version -string "$version" "$temporary_plist"
    plutil -insert build -string "$build_number" "$temporary_plist"
    plutil -insert teamID -string "$team_id" "$temporary_plist"
    plutil -insert identities -dictionary "$temporary_plist"
    plutil -insert identities.appBundleID -string "$RELEASE_APP_BUNDLE_ID" "$temporary_plist"
    plutil -insert identities.widgetBundleID -string "$RELEASE_WIDGET_BUNDLE_ID" "$temporary_plist"
    plutil -insert identities.helperServiceID -string "$RELEASE_HELPER_SERVICE_ID" "$temporary_plist"
    plutil -insert artifacts -dictionary "$temporary_plist"
    plutil -insert artifacts.archive -dictionary "$temporary_plist"
    plutil -insert artifacts.archive.kind -string mas-xcarchive-zip "$temporary_plist"
    plutil -insert artifacts.archive.file -string "$(basename "$archive_path")" "$temporary_plist"
    plutil -insert artifacts.archive.bytes -integer "$(stat -f '%z' "$archive_path")" "$temporary_plist"
    plutil -insert artifacts.archive.sha256 -string "$archive_sha" "$temporary_plist"
    plutil -insert artifacts.package -dictionary "$temporary_plist"
    plutil -insert artifacts.package.kind -string mas-reviewed-pkg "$temporary_plist"
    plutil -insert artifacts.package.file -string "$(basename "$package_path")" "$temporary_plist"
    plutil -insert artifacts.package.bytes -integer "$(stat -f '%z' "$package_path")" "$temporary_plist"
    plutil -insert artifacts.package.sha256 -string "$package_sha" "$temporary_plist"
    plutil -convert json -o "$destination" "$temporary_plist"
    rm -f "$temporary_plist"
}

release_manifest_value() {
    local manifest_path="$1"
    local key_path="$2"
    plutil -extract "$key_path" raw -o - "$manifest_path"
}

release_assert_manifest() {
    local manifest_path="$1"
    local artifact_path="$2"
    local expected_sha="$3"
    local expected_kind="$4"
    local manifest_file

    if [ ! -s "$manifest_path" ]; then
        printf 'Release manifest is missing or empty: %s\n' "$manifest_path" >&2
        return 1
    fi
    if ! release_manifest_value "$manifest_path" schemaVersion > /dev/null 2>&1; then
        printf 'Release manifest is invalid: %s\n' "$manifest_path" >&2
        return 1
    fi

    if [ "$(release_manifest_value "$manifest_path" schemaVersion)" != '1' ] ||
       [ "$(release_manifest_value "$manifest_path" artifact.kind)" != "$expected_kind" ] ||
       [ "$(release_manifest_value "$manifest_path" artifact.sha256)" != "$expected_sha" ] ||
       [ "$(release_manifest_value "$manifest_path" identities.appBundleID)" != "$RELEASE_APP_BUNDLE_ID" ] ||
       [ "$(release_manifest_value "$manifest_path" identities.widgetBundleID)" != "$RELEASE_WIDGET_BUNDLE_ID" ] ||
       [ "$(release_manifest_value "$manifest_path" identities.helperServiceID)" != "$RELEASE_HELPER_SERVICE_ID" ]; then
        printf '%s\n' 'Release manifest identity or artifact metadata does not match this pipeline.' >&2
        return 1
    fi

    manifest_file="$(release_manifest_value "$manifest_path" artifact.file)"
    if [ "$manifest_file" != "$(basename "$artifact_path")" ]; then
        printf 'Release manifest artifact filename mismatch: expected %s, got %s\n' \
            "$(basename "$artifact_path")" "$manifest_file" >&2
        return 1
    fi
}

release_assert_mas_manifest() {
    local manifest_path="$1"
    local archive_path="$2"
    local archive_sha="$3"
    local package_path="$4"
    local package_sha="$5"

    if [ ! -s "$manifest_path" ] ||
       ! release_manifest_value "$manifest_path" schemaVersion > /dev/null 2>&1; then
        printf 'MAS release manifest is missing or invalid: %s\n' "$manifest_path" >&2
        return 1
    fi
    if [ "$(release_manifest_value "$manifest_path" schemaVersion)" != '1' ] ||
       [ "$(release_manifest_value "$manifest_path" artifacts.archive.kind)" != 'mas-xcarchive-zip' ] ||
       [ "$(release_manifest_value "$manifest_path" artifacts.archive.sha256)" != "$archive_sha" ] ||
       [ "$(release_manifest_value "$manifest_path" artifacts.archive.file)" != "$(basename "$archive_path")" ] ||
       [ "$(release_manifest_value "$manifest_path" artifacts.package.kind)" != 'mas-reviewed-pkg' ] ||
       [ "$(release_manifest_value "$manifest_path" artifacts.package.sha256)" != "$package_sha" ] ||
       [ "$(release_manifest_value "$manifest_path" artifacts.package.file)" != "$(basename "$package_path")" ] ||
       [ "$(release_manifest_value "$manifest_path" identities.appBundleID)" != "$RELEASE_APP_BUNDLE_ID" ] ||
       [ "$(release_manifest_value "$manifest_path" identities.widgetBundleID)" != "$RELEASE_WIDGET_BUNDLE_ID" ] ||
       [ "$(release_manifest_value "$manifest_path" identities.helperServiceID)" != "$RELEASE_HELPER_SERVICE_ID" ]; then
        printf '%s\n' 'MAS manifest metadata does not match the sealed archive, reviewed package, or product identity.' >&2
        return 1
    fi
}
