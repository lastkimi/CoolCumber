#!/bin/bash

set -euo pipefail

DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export DEVELOPER_DIR

script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
repo_root="$(cd "$script_directory/.." && pwd -P)"
# shellcheck source=Scripts/release-config.sh
source "$script_directory/release-config.sh"
invocation_directory="$(pwd -P)"

usage() {
    cat <<'USAGE'
Build and seal a Mac App Store release (never uploads):
  Scripts/release-mas.sh \
    --output-dir /absolute/path \
    --channel Release|Beta \
    --version 1.2.0 \
    --build 3 \
    --team-id TEAM_ID \
    --source-commit FULL_40_CHARACTER_HEAD

Upload the already reviewed, sealed archive (never rebuilds):
  Scripts/release-mas.sh \
    --upload-existing-archive /absolute/path/CoolCumber-MAS.xcarchive.zip \
    --archive-sha256 64_LOWERCASE_HEX \
    --reviewed-pkg /absolute/path/CoolCumber-AppStore.pkg \
    --pkg-sha256 64_LOWERCASE_HEX \
    --manifest /absolute/path/release-manifest.json \
    --manifest-sha256 64_LOWERCASE_HEX \
    --upload-result-dir /absolute/empty/path

Build mode requires:
  MAS_APP_SIGNING_IDENTITY

Both modes require App Store Connect API authentication:
  ASC_KEY_PATH + ASC_KEY_ID + ASC_ISSUER_ID

Upload mode uses Xcode's supported app-store-connect export with
destination=upload. It reuses the sealed xcarchive bound into the manifest;
it does not invoke xcodegen, archive, build, altool, or Transporter.
USAGE
}

output_dir=""
channel=""
version=""
build_number=""
team_id=""
source_commit=""
upload_archive=""
archive_sha=""
reviewed_pkg=""
package_sha=""
manifest_path=""
manifest_sha=""
upload_result_dir=""

while [ "$#" -gt 0 ]; do
    case "$1" in
        --output-dir) output_dir="${2:-}"; shift 2 ;;
        --channel) channel="${2:-}"; shift 2 ;;
        --version) version="${2:-}"; shift 2 ;;
        --build) build_number="${2:-}"; shift 2 ;;
        --team-id) team_id="${2:-}"; shift 2 ;;
        --source-commit) source_commit="${2:-}"; shift 2 ;;
        --upload-existing-archive) upload_archive="${2:-}"; shift 2 ;;
        --archive-sha256) archive_sha="${2:-}"; shift 2 ;;
        --reviewed-pkg) reviewed_pkg="${2:-}"; shift 2 ;;
        --pkg-sha256) package_sha="${2:-}"; shift 2 ;;
        --manifest) manifest_path="${2:-}"; shift 2 ;;
        --manifest-sha256) manifest_sha="${2:-}"; shift 2 ;;
        --upload-result-dir) upload_result_dir="${2:-}"; shift 2 ;;
        --upload)
            printf '%s\n' '--upload is intentionally unsupported: build first, review, then use --upload-existing-archive with explicit SHA-256 values.' >&2
            exit 64
            ;;
        -h|--help) usage; exit 0 ;;
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

absolute_from_invocation() {
    case "$1" in
        /*) printf '%s\n' "$1" ;;
        *) printf '%s/%s\n' "$invocation_directory" "$1" ;;
    esac
}

validate_release_values() {
    case "$channel" in Release|Beta) ;; *)
        printf '%s\n' 'Configuration must be exactly Release or Beta.' >&2
        exit 64
    esac
    if ! [[ "$version" =~ ^[0-9]+(\.[0-9]+){1,2}$ ]] ||
       ! [[ "$build_number" =~ ^[1-9][0-9]*$ ]] ||
       ! [[ "$team_id" =~ ^[A-Z0-9]{10}$ ]]; then
        printf '%s\n' 'Version, build, or Team ID has an invalid format.' >&2
        exit 64
    fi
}

validate_asc_key() {
    local key_directory
    local key_mode

    require_value 'ASC_KEY_PATH' "${ASC_KEY_PATH:-}"
    require_value 'ASC_KEY_ID' "${ASC_KEY_ID:-}"
    require_value 'ASC_ISSUER_ID' "${ASC_ISSUER_ID:-}"
    case "$ASC_KEY_PATH" in /*) ;; *)
        printf '%s\n' 'ASC_KEY_PATH must be absolute and outside the Git workspace.' >&2
        exit 64
    esac
    if [ ! -r "$ASC_KEY_PATH" ]; then
        printf '%s\n' 'ASC_KEY_PATH is not readable.' >&2
        exit 1
    fi
    key_directory="$(cd "$(dirname "$ASC_KEY_PATH")" && pwd -P)"
    asc_key_absolute="$key_directory/$(basename "$ASC_KEY_PATH")"
    case "$asc_key_absolute" in "$repo_root"/*)
        printf '%s\n' 'ASC_KEY_PATH must remain outside the Git workspace.' >&2
        exit 64
    esac
    case "$asc_key_absolute" in *.p8) ;; *)
        printf '%s\n' 'ASC_KEY_PATH must reference a .p8 file.' >&2
        exit 64
    esac
    key_mode="$(stat -f '%Lp' "$asc_key_absolute")"
    case "$key_mode" in 400|600) ;; *)
        printf '%s\n' 'ASC_KEY_PATH permissions must be 400 or 600.' >&2
        exit 1
    esac
    if ! [[ "$ASC_KEY_ID" =~ ^[A-Z0-9]{10}$ ]] ||
       ! [[ "$ASC_ISSUER_ID" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]; then
        printf '%s\n' 'ASC key ID or issuer ID has an invalid format.' >&2
        exit 64
    fi
    provisioning_args=(
        -allowProvisioningUpdates
        -authenticationKeyPath "$asc_key_absolute"
        -authenticationKeyID "$ASC_KEY_ID"
        -authenticationKeyIssuerID "$ASC_ISSUER_ID"
    )
}

validate_output_directory() {
    local candidate="$1"
    local require_empty="$2"

    candidate="$(absolute_from_invocation "$candidate")"
    if [ "$candidate" = '/' ] || [ "$candidate" = "${HOME:-}" ]; then
        printf '%s\n' 'Output directory is too broad.' >&2
        exit 64
    fi
    case "$candidate" in "$repo_root"|"$repo_root"/*)
        printf '%s\n' 'Release output must be outside the Git workspace.' >&2
        exit 64
    esac
    if [ -e "$candidate" ]; then
        if [ ! -d "$candidate" ]; then
            printf 'Output path is not a directory: %s\n' "$candidate" >&2
            exit 1
        fi
        if [ "$require_empty" -eq 1 ] &&
           [ -n "$(find "$candidate" -mindepth 1 -maxdepth 1 -print -quit)" ]; then
            printf 'Output directory must be empty: %s\n' "$candidate" >&2
            exit 1
        fi
    else
        mkdir -p "$candidate"
    fi
    (cd "$candidate" && pwd -P)
}

if [ -n "${APPLE_ID:-}" ] || [ -n "${APP_SPECIFIC_PASSWORD:-}" ]; then
    printf '%s\n' 'Legacy Apple-ID password credentials are not accepted.' >&2
    exit 64
fi
if [ ! -d "$DEVELOPER_DIR" ] || [ ! -x "$DEVELOPER_DIR/usr/bin/xcodebuild" ]; then
    printf 'DEVELOPER_DIR does not contain usable Xcode: %s\n' "$DEVELOPER_DIR" >&2
    exit 1
fi
required_tools=(codesign ditto git lipo pkgutil plutil security shasum stat xcodebuild)
if [ -z "$upload_archive" ]; then
    required_tools+=(xcodegen)
fi
for required_tool in "${required_tools[@]}"; do
    if ! command -v "$required_tool" > /dev/null 2>&1; then
        printf 'Required release tool is unavailable: %s\n' "$required_tool" >&2
        exit 1
    fi
done

cd "$repo_root"
asc_key_absolute=""
provisioning_args=()

if [ -n "$upload_archive" ]; then
    require_value '--archive-sha256' "$archive_sha"
    require_value '--reviewed-pkg' "$reviewed_pkg"
    require_value '--pkg-sha256' "$package_sha"
    require_value '--manifest' "$manifest_path"
    require_value '--manifest-sha256' "$manifest_sha"
    require_value '--upload-result-dir' "$upload_result_dir"
    if [ -n "$output_dir$channel$version$build_number$team_id$source_commit" ]; then
        printf '%s\n' 'Upload-existing mode reads release metadata from the manifest; do not pass build-mode arguments.' >&2
        exit 64
    fi

    upload_archive="$(absolute_from_invocation "$upload_archive")"
    reviewed_pkg="$(absolute_from_invocation "$reviewed_pkg")"
    manifest_path="$(absolute_from_invocation "$manifest_path")"
    upload_result_dir="$(validate_output_directory "$upload_result_dir" 1)"
    for sealed_input in "$upload_archive" "$reviewed_pkg" "$manifest_path"; do
        if [ ! -s "$sealed_input" ]; then
            printf 'Sealed upload input is missing or empty: %s\n' "$sealed_input" >&2
            exit 1
        fi
        if [ -L "$sealed_input" ]; then
            printf 'Sealed upload inputs must not be symbolic links: %s\n' "$sealed_input" >&2
            exit 64
        fi
    done
    upload_archive="$(cd "$(dirname "$upload_archive")" && pwd -P)/$(basename "$upload_archive")"
    reviewed_pkg="$(cd "$(dirname "$reviewed_pkg")" && pwd -P)/$(basename "$reviewed_pkg")"
    manifest_path="$(cd "$(dirname "$manifest_path")" && pwd -P)/$(basename "$manifest_path")"
    for sealed_input in "$upload_archive" "$reviewed_pkg" "$manifest_path"; do
        case "$sealed_input" in "$repo_root"|"$repo_root"/*)
            printf 'Sealed release inputs must remain outside the Git workspace: %s\n' "$sealed_input" >&2
            exit 64
        esac
    done

    release_require_sha256 "$archive_sha" "$upload_archive"
    release_require_sha256 "$package_sha" "$reviewed_pkg"
    release_require_sha256 "$manifest_sha" "$manifest_path"
    release_assert_mas_manifest "$manifest_path" "$upload_archive" "$archive_sha" "$reviewed_pkg" "$package_sha"

    source_commit="$(release_manifest_value "$manifest_path" sourceCommit)"
    channel="$(release_manifest_value "$manifest_path" configuration)"
    version="$(release_manifest_value "$manifest_path" version)"
    build_number="$(release_manifest_value "$manifest_path" build)"
    team_id="$(release_manifest_value "$manifest_path" teamID)"
    validate_release_values
    release_require_explicit_source_commit "$source_commit"

    "$script_directory/validate-mas-pkg.sh" \
        --pkg "$reviewed_pkg" \
        --version "$version" \
        --build "$build_number" \
        --team-id "$team_id"

    extraction_root="$(mktemp -d "${TMPDIR:-/tmp}/coolcumber-upload-archive.XXXXXX")"
    cleanup_upload() { rm -rf "$extraction_root"; }
    trap cleanup_upload EXIT
    ditto -x -k "$upload_archive" "$extraction_root"
    archives_file="$extraction_root/archives.txt"
    find "$extraction_root" -maxdepth 2 -type d -name '*.xcarchive' -print > "$archives_file"
    archive_count="$(awk 'END {print NR + 0}' "$archives_file")"
    if [ "$archive_count" -ne 1 ]; then
        printf 'Sealed archive ZIP must contain exactly one xcarchive; found %s.\n' "$archive_count" >&2
        exit 1
    fi
    archive_path="$(sed -n '1p' "$archives_file")"
    archived_app="$archive_path/Products/Applications/$RELEASE_PRODUCT_NAME.app"
    "$script_directory/validate-mas-pkg.sh" \
        --app "$archived_app" \
        --version "$version" \
        --build "$build_number" \
        --team-id "$team_id"

    # Last possible gate before network state changes: prove every reviewed
    # input is still byte-for-byte identical.
    release_require_sha256 "$archive_sha" "$upload_archive"
    release_require_sha256 "$package_sha" "$reviewed_pkg"
    release_require_sha256 "$manifest_sha" "$manifest_path"
    validate_asc_key

    upload_options="$upload_result_dir/ExportOptions-AppStoreUpload.plist"
    upload_export_path="$upload_result_dir/XcodeUpload"
    upload_log="$upload_result_dir/xcodebuild-upload.log"
    plutil -create xml1 "$upload_options"
    plutil -insert method -string app-store-connect "$upload_options"
    plutil -insert destination -string upload "$upload_options"
    plutil -insert signingStyle -string automatic "$upload_options"
    plutil -insert teamID -string "$team_id" "$upload_options"
    plutil -insert stripSwiftSymbols -bool true "$upload_options"
    plutil -insert uploadSymbols -bool true "$upload_options"
    plutil -insert manageAppVersionAndBuildNumber -bool false "$upload_options"

    if ! xcodebuild \
        -exportArchive \
        -archivePath "$archive_path" \
        -exportPath "$upload_export_path" \
        -exportOptionsPlist "$upload_options" \
        "${provisioning_args[@]}" > "$upload_log" 2>&1; then
        printf 'Xcode App Store Connect upload failed; inspect %s\n' "$upload_log" >&2
        exit 1
    fi

    release_require_sha256 "$archive_sha" "$upload_archive"
    release_require_sha256 "$package_sha" "$reviewed_pkg"
    release_require_sha256 "$manifest_sha" "$manifest_path"
    printf '%s\n' 'The sealed xcarchive was uploaded with Xcode; no build or archive step ran.'
    printf 'Upload log: %s\n' "$upload_log"
    exit 0
fi

require_value '--output-dir' "$output_dir"
require_value '--channel' "$channel"
require_value '--version' "$version"
require_value '--build' "$build_number"
require_value '--team-id' "$team_id"
require_value '--source-commit' "$source_commit"
require_value 'MAS_APP_SIGNING_IDENTITY' "${MAS_APP_SIGNING_IDENTITY:-}"
if [ -n "$archive_sha$reviewed_pkg$package_sha$manifest_path$manifest_sha$upload_result_dir" ]; then
    printf '%s\n' 'Upload-existing arguments cannot be combined with build mode.' >&2
    exit 64
fi
validate_release_values
release_require_explicit_source_commit "$source_commit"
validate_asc_key

case "$MAS_APP_SIGNING_IDENTITY" in
    'Apple Distribution:'*|'3rd Party Mac Developer Application:'*) ;;
    *)
        printf '%s\n' 'MAS_APP_SIGNING_IDENTITY must name an Apple Distribution identity.' >&2
        exit 64
        ;;
esac
if ! security find-identity -v -p codesigning | grep -F -q "$MAS_APP_SIGNING_IDENTITY"; then
    printf '%s\n' 'The requested Mac App Store signing identity is not installed.' >&2
    exit 1
fi

output_dir="$(validate_output_directory "$output_dir" 1)"
"$script_directory/check-project-boundaries.rb" "$repo_root/project.yml" "$version" "$build_number"
xcodegen generate --spec "$repo_root/project.yml"

archive_path="$output_dir/$RELEASE_PRODUCT_NAME-MAS.xcarchive"
derived_data="$output_dir/DerivedData"
export_dir="$output_dir/AppStoreExport"
export_options="$output_dir/ExportOptions-AppStoreConnect.plist"
pkg_path="$output_dir/$RELEASE_PRODUCT_NAME-$version-$build_number-$channel-AppStore.pkg"
archive_zip="$output_dir/$RELEASE_PRODUCT_NAME-$version-$build_number-$channel-MAS.xcarchive.zip"
manifest_path="$output_dir/release-manifest.json"

build_settings=(
    "DEVELOPMENT_TEAM=$team_id"
    'CODE_SIGN_STYLE=Automatic'
    "CODE_SIGN_IDENTITY=$MAS_APP_SIGNING_IDENTITY"
    "MARKETING_VERSION=$version"
    "CURRENT_PROJECT_VERSION=$build_number"
)
xcodebuild \
    -project "$repo_root/MacThermFlow.xcodeproj" \
    -scheme ThermFlowAppStore \
    -configuration "$channel" \
    -destination 'generic/platform=macOS' \
    -jobs 1 \
    -archivePath "$archive_path" \
    -derivedDataPath "$derived_data" \
    "${provisioning_args[@]}" \
    "${build_settings[@]}" \
    archive

archived_app="$archive_path/Products/Applications/$RELEASE_PRODUCT_NAME.app"
"$script_directory/validate-mas-pkg.sh" \
    --app "$archived_app" \
    --version "$version" \
    --build "$build_number" \
    --team-id "$team_id"

plutil -create xml1 "$export_options"
plutil -insert method -string app-store-connect "$export_options"
plutil -insert destination -string export "$export_options"
plutil -insert signingStyle -string automatic "$export_options"
plutil -insert teamID -string "$team_id" "$export_options"
plutil -insert stripSwiftSymbols -bool true "$export_options"
plutil -insert uploadSymbols -bool true "$export_options"
plutil -insert manageAppVersionAndBuildNumber -bool false "$export_options"

xcodebuild \
    -exportArchive \
    -archivePath "$archive_path" \
    -exportPath "$export_dir" \
    -exportOptionsPlist "$export_options" \
    "${provisioning_args[@]}"

packages_file="$output_dir/exported-packages.txt"
find "$export_dir" -maxdepth 2 -type f -name '*.pkg' -print > "$packages_file"
package_count="$(awk 'END {print NR + 0}' "$packages_file")"
if [ "$package_count" -ne 1 ]; then
    printf 'App Store export must contain exactly one pkg; found %s.\n' "$package_count" >&2
    exit 1
fi
mv "$(sed -n '1p' "$packages_file")" "$pkg_path"

"$script_directory/validate-mas-pkg.sh" \
    --pkg "$pkg_path" \
    --version "$version" \
    --build "$build_number" \
    --team-id "$team_id"

ditto -c -k --sequesterRsrc --keepParent "$archive_path" "$archive_zip"
sealed_check_root="$(mktemp -d "${TMPDIR:-/tmp}/coolcumber-sealed-archive-check.XXXXXX")"
cleanup_sealed_check() { rm -rf "$sealed_check_root"; }
trap cleanup_sealed_check EXIT
ditto -x -k "$archive_zip" "$sealed_check_root"
sealed_archives_file="$sealed_check_root/archives.txt"
find "$sealed_check_root" -maxdepth 2 -type d -name '*.xcarchive' -print > "$sealed_archives_file"
sealed_archive_count="$(awk 'END {print NR + 0}' "$sealed_archives_file")"
if [ "$sealed_archive_count" -ne 1 ]; then
    printf 'Sealed archive ZIP must contain exactly one xcarchive; found %s.\n' "$sealed_archive_count" >&2
    exit 1
fi
sealed_archive="$(sed -n '1p' "$sealed_archives_file")"
"$script_directory/validate-mas-pkg.sh" \
    --app "$sealed_archive/Products/Applications/$RELEASE_PRODUCT_NAME.app" \
    --version "$version" \
    --build "$build_number" \
    --team-id "$team_id"
cleanup_sealed_check
trap - EXIT

archive_sha="$(release_sha256 "$archive_zip")"
package_sha="$(release_sha256 "$pkg_path")"
printf '%s  %s\n' "$archive_sha" "$(basename "$archive_zip")" > "$archive_zip.sha256"
printf '%s  %s\n' "$package_sha" "$(basename "$pkg_path")" > "$pkg_path.sha256"
release_write_mas_manifest \
    "$manifest_path" "$source_commit" "$channel" "$version" "$build_number" "$team_id" \
    "$archive_zip" "$archive_sha" "$pkg_path" "$package_sha"
manifest_sha="$(release_sha256 "$manifest_path")"
printf '%s  %s\n' "$manifest_sha" "$(basename "$manifest_path")" > "$manifest_path.sha256"
chmod 0444 "$archive_zip" "$pkg_path" "$manifest_path"

instructions_path="$output_dir/UPLOAD-INSTRUCTIONS.txt"
{
    printf '%s\n' 'No upload was performed. Review the sealed archive, exported package, checksums, and manifest.'
    printf '%s\n' 'Upload only these exact bytes with:'
    printf 'Scripts/release-mas.sh --upload-existing-archive %q --archive-sha256 %s --reviewed-pkg %q --pkg-sha256 %s --manifest %q --manifest-sha256 %s --upload-result-dir /absolute/empty/path\n' \
        "$archive_zip" "$archive_sha" "$pkg_path" "$package_sha" "$manifest_path" "$manifest_sha"
} > "$instructions_path"

printf '%s\n' 'Mac App Store release artifacts are sealed and fully validated; nothing was uploaded.'
printf 'Sealed archive: %s\nReviewed package: %s\nManifest: %s\n' \
    "$archive_zip" "$pkg_path" "$manifest_path"
