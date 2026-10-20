#!/bin/bash

set -euo pipefail

usage() {
    cat <<USAGE
Usage:
  $0 STORE_ASSET_DIRECTORY \\
    --expected-version VERSION \\
    --expected-build BUILD \\
    --expected-source-commit FULL_40_CHARACTER_COMMIT

The source commit must be the committed app/UI/test tree used for capture. The
screenshot assets and manifest may be committed later, but the current app and
capture sources must still match that commit exactly.
USAGE
}

if [ "$#" -eq 1 ] && { [ "$1" = '-h' ] || [ "$1" = '--help' ]; }; then
    usage
    exit 0
fi
if [ "$#" -lt 1 ]; then
    usage >&2
    exit 64
fi

asset_directory="${1%/}"
shift
expected_version=""
expected_build=""
expected_source_commit=""

while [ "$#" -gt 0 ]; do
    case "$1" in
        --expected-version)
            expected_version="${2:-}"
            shift 2
            ;;
        --expected-build)
            expected_build="${2:-}"
            shift 2
            ;;
        --expected-source-commit)
            expected_source_commit="${2:-}"
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

if [ -z "$expected_version" ] ||
   [ -z "$expected_build" ] ||
   [ -z "$expected_source_commit" ]; then
    printf '%s\n' 'Expected version, build, and source commit are all required.' >&2
    usage >&2
    exit 64
fi
if ! [[ "$expected_version" =~ ^[0-9]+(\.[0-9]+){1,2}$ ]]; then
    printf 'Invalid expected version: %s\n' "$expected_version" >&2
    exit 64
fi
if ! [[ "$expected_build" =~ ^[1-9][0-9]*$ ]]; then
    printf 'Invalid expected build: %s\n' "$expected_build" >&2
    exit 64
fi
if ! [[ "$expected_source_commit" =~ ^[0-9a-f]{40}$ ]]; then
    printf '%s\n' 'Expected source commit must be 40 lowercase hexadecimal characters.' >&2
    exit 64
fi

manifest="$asset_directory/manifest.json"

if [ ! -d "$asset_directory" ] || [ ! -f "$manifest" ]; then
    printf 'Store asset directory or manifest is missing: %s\n' "$asset_directory" >&2
    exit 1
fi

for tool in file git jq md5 shasum sips; do
    if ! command -v "$tool" > /dev/null 2>&1; then
        printf 'Required screenshot validation tool is unavailable: %s\n' "$tool" >&2
        exit 1
    fi
done

if ! git cat-file -e "$expected_source_commit^{commit}" 2> /dev/null; then
    printf 'Screenshot source commit is not available in this repository: %s\n' \
        "$expected_source_commit" >&2
    exit 1
fi

# Screenshots may be added in a follow-up asset commit, but the app, Widget,
# package model and capture tests must remain byte-for-byte source-equivalent to
# the committed tree named by baseCommit.
capture_source_paths=(
    project.yml
    ThermFlowApp
    ThermFlowWidget
    Packages/ThermFlowCore
    ReleaseUITests
)
capture_input_roots=(
    project.yml
    ThermFlowApp
    ThermFlowWidget
    Packages/ThermFlowCore/Package.swift
    Packages/ThermFlowCore/Sources
    ReleaseUITests
)
capture_source_changes="$(
    git status --porcelain=v1 --untracked-files=all -- "${capture_source_paths[@]}"
)"
if [ -n "$capture_source_changes" ]; then
    printf '%s\n' 'Screenshot capture sources contain tracked or untracked changes.' >&2
    printf '%s\n' 'Commit every app, resource, package and capture-test input before capture.' >&2
    exit 1
fi
while IFS= read -r -d '' capture_input; do
    if [ -L "$capture_input" ]; then
        printf 'Screenshot capture inputs must not be symbolic links: %s\n' \
            "$capture_input" >&2
        exit 1
    fi
    if ! git ls-files --error-unmatch -- "$capture_input" > /dev/null 2>&1; then
        printf 'Screenshot capture input is not tracked by baseCommit: %s\n' \
            "$capture_input" >&2
        exit 1
    fi
done < <(find "${capture_input_roots[@]}" \( -type f -o -type l \) -print0)
if ! git diff --quiet "$expected_source_commit" -- "${capture_source_paths[@]}"; then
    printf '%s\n' 'Current app or capture sources differ from the declared screenshot source commit.' >&2
    printf '%s\n' 'Commit the final source, recapture the visible app, and regenerate the manifest.' >&2
    exit 1
fi

jq -e \
    --arg expectedVersion "$expected_version" \
    --arg expectedBuild "$expected_build" \
    --arg expectedCommit "$expected_source_commit" '
    .schemaVersion == 1 and
    .productVersion == $expectedVersion and
    .build == $expectedBuild and
    .baseCommit == $expectedCommit and
    .captureScheme == "CoolCumberScreenshots" and
    .captureTarget == "ThermFlowAppStore" and
    .testSummary == "6 passed, 0 failed, 0 skipped" and
    .requirements.width == 2560 and
    .requirements.height == 1600 and
    .requirements.format == "PNG RGB" and
    .requirements.alpha == false and
    (.assets | length == 6) and
    ([.assets[].file] | unique | length == 6) and
    (all(.assets[];
        (.locale == "en-US" or .locale == "zh-Hans") and
        (.page == "overview" or .page == "history" or .page == "pro") and
        (.file | type == "string") and
        (.sha256 | test("^[0-9a-f]{64}$")) and
        (.md5 | test("^[0-9a-f]{32}$"))
    )) and
    ([.assets[] | select(.locale == "en-US") | .page] | sort == ["history", "overview", "pro"]) and
    ([.assets[] | select(.locale == "zh-Hans") | .page] | sort == ["history", "overview", "pro"])
' "$manifest" > /dev/null

png_count="$(find "$asset_directory" -maxdepth 1 -type f -name '*.png' | wc -l | tr -d ' ')"
if [ "$png_count" -ne 6 ]; then
    printf 'Expected exactly six PNG screenshots; found %s.\n' "$png_count" >&2
    exit 1
fi

while IFS=$'\t' read -r file_name expected_sha expected_md5; do
    case "$file_name" in
        ''|*/*|.*)
            printf 'Screenshot manifest contains an unsafe file name: %s\n' "$file_name" >&2
            exit 1
            ;;
    esac

    image_path="$asset_directory/$file_name"
    if [ ! -f "$image_path" ]; then
        printf 'Screenshot is missing: %s\n' "$image_path" >&2
        exit 1
    fi

    width="$(sips -g pixelWidth "$image_path" | awk '/pixelWidth/{print $2}')"
    height="$(sips -g pixelHeight "$image_path" | awk '/pixelHeight/{print $2}')"
    has_alpha="$(sips -g hasAlpha "$image_path" | awk '/hasAlpha/{print $2}')"
    if [ "$width" != '2560' ] || [ "$height" != '1600' ] || [ "$has_alpha" != 'no' ]; then
        printf 'Screenshot must be opaque 2560x1600 PNG: %s\n' "$image_path" >&2
        exit 1
    fi
    if ! file "$image_path" | grep -Fq 'PNG image data, 2560 x 1600, 8-bit/color RGB'; then
        printf 'Screenshot is not an RGB PNG: %s\n' "$image_path" >&2
        exit 1
    fi

    actual_sha="$(shasum -a 256 "$image_path" | awk '{print $1}')"
    actual_md5="$(md5 -q "$image_path")"
    if [ "$actual_sha" != "$expected_sha" ] || [ "$actual_md5" != "$expected_md5" ]; then
        printf 'Screenshot checksum mismatch: %s\n' "$image_path" >&2
        exit 1
    fi
done < <(jq -r '.assets[] | [.file, .sha256, .md5] | @tsv' "$manifest")

printf 'Store screenshots passed for %s (%s), source %s: 3 en-US + 3 zh-Hans, opaque 2560x1600 RGB PNG.\n' \
    "$expected_version" "$expected_build" "$expected_source_commit"
