#!/bin/bash

set -euo pipefail

DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export DEVELOPER_DIR

invocation_directory="$(pwd -P)"
script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=Scripts/release-config.sh
source "$script_directory/release-config.sh"

usage() {
    cat <<'USAGE'
Usage:
  Scripts/release-direct.sh \
    --output-dir /absolute/path \
    --channel Release|Beta \
    --version 1.2.0 \
    --build 3 \
    --team-id TEAM_ID \
    --source-commit FULL_40_CHARACTER_HEAD \
    --mas-app /path/to/CoolCumber.app \
    --mas-installer /path/to/AppStore.pkg \
    [--notary-profile KEYCHAIN_PROFILE] \
    [--notary-timeout 30m]

Required environment:
  DIRECT_APP_SIGNING_IDENTITY  Developer ID Application identity

Notary authentication must use exactly one method:
  NOTARY_KEYCHAIN_PROFILE (or --notary-profile)
  NOTARY_KEY_PATH + NOTARY_KEY_ID + NOTARY_ISSUER_ID

This command creates and validates local artifacts. It never creates or replaces
a GitHub Release.
USAGE
}

output_dir=""
channel=""
version=""
build_number=""
team_id=""
source_commit=""
mas_app=""
mas_installer=""
notary_profile="${NOTARY_KEYCHAIN_PROFILE:-}"
notary_timeout="${NOTARY_WAIT_TIMEOUT:-30m}"

while [ "$#" -gt 0 ]; do
    case "$1" in
        --output-dir)
            output_dir="${2:-}"
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
        --mas-app)
            mas_app="${2:-}"
            shift 2
            ;;
        --mas-installer)
            mas_installer="${2:-}"
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

require_value '--output-dir' "$output_dir"
require_value '--channel' "$channel"
require_value '--version' "$version"
require_value '--build' "$build_number"
require_value '--team-id' "$team_id"
require_value '--source-commit' "$source_commit"
require_value '--mas-app' "$mas_app"
require_value '--mas-installer' "$mas_installer"
require_value 'DIRECT_APP_SIGNING_IDENTITY' "${DIRECT_APP_SIGNING_IDENTITY:-}"

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
    printf '%s\n' '--notary-timeout must be a positive duration such as 1800s, 30m, or 1h.' >&2
    exit 64
fi
case "$DIRECT_APP_SIGNING_IDENTITY" in
    'Developer ID Application:'*)
        ;;
    *)
        printf '%s\n' 'DIRECT_APP_SIGNING_IDENTITY must name a Developer ID Application identity.' >&2
        exit 64
        ;;
esac

if [ -n "${APPLE_ID:-}" ] || [ -n "${APP_SPECIFIC_PASSWORD:-}" ]; then
    printf '%s\n' 'Legacy Apple-ID password credentials are not accepted; use an API key or keychain profile.' >&2
    exit 64
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "$repo_root"
release_require_explicit_source_commit "$source_commit"

absolute_from_invocation() {
    local candidate="$1"
    case "$candidate" in
        /*)
            printf '%s\n' "$candidate"
            ;;
        *)
            printf '%s/%s\n' "$invocation_directory" "$candidate"
            ;;
    esac
}

output_dir="$(absolute_from_invocation "$output_dir")"
mas_app="$(absolute_from_invocation "$mas_app")"
if [ -n "$mas_installer" ]; then
    mas_installer="$(absolute_from_invocation "$mas_installer")"
fi

if [ "$output_dir" = '/' ] || [ "$output_dir" = "${HOME:-}" ]; then
    printf '%s\n' 'Output directory is too broad; provide a dedicated release directory.' >&2
    exit 64
fi
case "$output_dir" in
    "$repo_root"|"$repo_root"/*)
        printf '%s\n' 'Release output must be outside the Git workspace.' >&2
        exit 64
        ;;
esac

if [ ! -d "$mas_app" ]; then
    printf 'Mac App Store counterpart app is missing: %s\n' "$mas_app" >&2
    exit 1
fi
mas_app="$(cd "$mas_app" && pwd -P)"
case "$mas_app" in
    "$repo_root"|"$repo_root"/*)
        printf '%s\n' 'Mac App Store counterpart artifacts must be outside the Git workspace.' >&2
        exit 64
        ;;
esac
if [ -n "$mas_installer" ]; then
    if [ ! -s "$mas_installer" ]; then
        printf 'Mac App Store counterpart installer is missing: %s\n' "$mas_installer" >&2
        exit 1
    fi
    mas_installer_directory="$(cd "$(dirname "$mas_installer")" && pwd -P)"
    mas_installer="$mas_installer_directory/$(basename "$mas_installer")"
    case "$mas_installer" in
        "$repo_root"|"$repo_root"/*)
            printf '%s\n' 'Mac App Store counterpart artifacts must be outside the Git workspace.' >&2
            exit 64
            ;;
    esac
fi

if [ -e "$output_dir" ]; then
    if [ ! -d "$output_dir" ]; then
        printf 'Output path exists and is not a directory: %s\n' "$output_dir" >&2
        exit 1
    fi
    existing_output="$(find "$output_dir" -mindepth 1 -maxdepth 1 -print -quit)"
    if [ -n "$existing_output" ]; then
        printf 'Output directory must be empty: %s\n' "$output_dir" >&2
        exit 1
    fi
else
    mkdir -p "$output_dir"
fi

output_dir="$(cd "$output_dir" && pwd -P)"
if [ "$output_dir" = '/' ] || [ "$output_dir" = "${HOME:-}" ]; then
    printf '%s\n' 'Resolved output directory is too broad.' >&2
    exit 64
fi
case "$output_dir" in
    "$repo_root"|"$repo_root"/*)
        printf '%s\n' 'Resolved output directory points inside the Git workspace.' >&2
        exit 64
        ;;
esac

if [ ! -d "$DEVELOPER_DIR" ] || [ ! -x "$DEVELOPER_DIR/usr/bin/xcodebuild" ]; then
    printf 'DEVELOPER_DIR does not contain a usable Xcode installation: %s\n' "$DEVELOPER_DIR" >&2
    exit 1
fi

required_tools=(codesign ditto git hdiutil plutil security shasum spctl stat xcodebuild xcodegen xcrun)
for required_tool in "${required_tools[@]}"; do
    if ! command -v "$required_tool" > /dev/null 2>&1; then
        printf 'Required release tool is unavailable: %s\n' "$required_tool" >&2
        exit 1
    fi
done

codesigning_identities="$(security find-identity -v -p codesigning)"
if ! grep -F "$DIRECT_APP_SIGNING_IDENTITY" <<< "$codesigning_identities" > /dev/null; then
    printf '%s\n' 'The requested Developer ID Application identity is not installed.' >&2
    exit 1
fi

notary_args=()
preflight_notary_args=()
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
    preflight_notary_args=(--notary-profile "$notary_profile")
elif [ "$api_key_configured" -eq 1 ]; then
    require_value 'NOTARY_KEY_PATH' "${NOTARY_KEY_PATH:-}"
    require_value 'NOTARY_KEY_ID' "${NOTARY_KEY_ID:-}"
    require_value 'NOTARY_ISSUER_ID' "${NOTARY_ISSUER_ID:-}"
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
    case "$notary_key_absolute" in
        *.p8)
            ;;
        *)
            printf '%s\n' 'NOTARY_KEY_PATH must reference a .p8 key without placing its contents on the command line.' >&2
            exit 1
            ;;
    esac
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
    export NOTARY_KEY_PATH="$notary_key_absolute"
    notary_args=(--key "$notary_key_absolute" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID")
else
    printf '%s\n' 'Missing notary authentication. Configure an API key or keychain profile.' >&2
    exit 64
fi

provisioning_args=()
if [ -n "${ASC_KEY_PATH:-}" ] || [ -n "${ASC_KEY_ID:-}" ] || [ -n "${ASC_ISSUER_ID:-}" ]; then
    require_value 'ASC_KEY_PATH' "${ASC_KEY_PATH:-}"
    require_value 'ASC_KEY_ID' "${ASC_KEY_ID:-}"
    require_value 'ASC_ISSUER_ID' "${ASC_ISSUER_ID:-}"
    case "$ASC_KEY_PATH" in
        /*)
            ;;
        *)
            printf '%s\n' 'ASC_KEY_PATH must be an absolute path outside the Git workspace.' >&2
            exit 64
            ;;
    esac
    if [ ! -r "$ASC_KEY_PATH" ]; then
        printf '%s\n' 'ASC_KEY_PATH is not readable.' >&2
        exit 1
    fi
    asc_key_directory="$(cd "$(dirname "$ASC_KEY_PATH")" && pwd -P)"
    asc_key_absolute="$asc_key_directory/$(basename "$ASC_KEY_PATH")"
    case "$asc_key_absolute" in
        "$repo_root"/*)
            printf '%s\n' 'The App Store Connect API key must be stored outside the Git workspace.' >&2
            exit 64
            ;;
    esac
    case "$asc_key_absolute" in
        *.p8)
            ;;
        *)
            printf '%s\n' 'ASC_KEY_PATH must reference a .p8 key without placing its contents on the command line.' >&2
            exit 1
            ;;
    esac
    asc_key_mode="$(stat -f '%Lp' "$asc_key_absolute")"
    case "$asc_key_mode" in
        400|600)
            ;;
        *)
            printf '%s\n' 'ASC_KEY_PATH permissions must be 400 or 600.' >&2
            exit 1
            ;;
    esac
    if ! [[ "$ASC_KEY_ID" =~ ^[A-Z0-9]{10}$ ]]; then
        printf '%s\n' 'ASC_KEY_ID must be a 10-character App Store Connect key ID.' >&2
        exit 64
    fi
    if ! [[ "$ASC_ISSUER_ID" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]; then
        printf '%s\n' 'ASC_ISSUER_ID must be an App Store Connect issuer UUID.' >&2
        exit 64
    fi
    provisioning_args=(
        -allowProvisioningUpdates
        -authenticationKeyPath "$asc_key_absolute"
        -authenticationKeyID "$ASC_KEY_ID"
        -authenticationKeyIssuerID "$ASC_ISSUER_ID"
    )
fi

"$repo_root/Scripts/check-project-boundaries.rb" "$repo_root/project.yml" "$version" "$build_number"
xcodegen generate --spec "$repo_root/project.yml"

archive_path="$output_dir/CoolCumber-Direct.xcarchive"
derived_data="$output_dir/DerivedData"
export_dir="$output_dir/Export"
export_options="$output_dir/ExportOptions-DeveloperID.plist"
notary_zip="$output_dir/CoolCumber-$version-$build_number-$channel-notary.zip"
dmg_path="$output_dir/CoolCumber-$version-$build_number-$channel.dmg"
build_configuration="$channel"

build_settings=(
    "DEVELOPMENT_TEAM=$team_id"
    'CODE_SIGN_STYLE=Automatic'
    "CODE_SIGN_IDENTITY=$DIRECT_APP_SIGNING_IDENTITY"
    "MARKETING_VERSION=$version"
    "CURRENT_PROJECT_VERSION=$build_number"
)
xcodebuild \
    -project "$repo_root/MacThermFlow.xcodeproj" \
    -scheme ThermFlowApp \
    -configuration "$build_configuration" \
    -destination 'generic/platform=macOS' \
    -jobs 1 \
    -archivePath "$archive_path" \
    -derivedDataPath "$derived_data" \
    "${provisioning_args[@]}" \
    "${build_settings[@]}" \
    archive

plutil -create xml1 "$export_options"
plutil -insert method -string developer-id "$export_options"
plutil -insert destination -string export "$export_options"
plutil -insert signingStyle -string automatic "$export_options"
plutil -insert signingCertificate -string "$DIRECT_APP_SIGNING_IDENTITY" "$export_options"
plutil -insert teamID -string "$team_id" "$export_options"
plutil -insert stripSwiftSymbols -bool true "$export_options"
plutil -insert manageAppVersionAndBuildNumber -bool false "$export_options"

xcodebuild \
    -exportArchive \
    -archivePath "$archive_path" \
    -exportPath "$export_dir" \
    -exportOptionsPlist "$export_options" \
    "${provisioning_args[@]}"

exported_apps="$output_dir/exported-apps.txt"
find "$export_dir" -maxdepth 2 -type d -name '*.app' -print > "$exported_apps"
exported_app_count="$(awk 'END { print NR + 0 }' "$exported_apps")"
if [ "$exported_app_count" -ne 1 ]; then
    printf 'Developer ID export must contain exactly one app; found %s\n' "$exported_app_count" >&2
    exit 1
fi
direct_app="$(sed -n '1p' "$exported_apps")"

codesign --verify --deep --strict --verbose=2 "$direct_app"
if ! direct_signature_details="$(codesign -d --verbose=4 "$direct_app" 2>&1)"; then
    printf '%s\n' 'Unable to inspect the exported Direct app signature.' >&2
    exit 1
fi
if ! grep -F 'Authority=Developer ID Application:' <<< "$direct_signature_details" > /dev/null; then
    printf '%s\n' 'Exported Direct app is not signed with Developer ID Application.' >&2
    exit 1
fi
if ! grep -F 'Timestamp=' <<< "$direct_signature_details" > /dev/null; then
    printf '%s\n' 'Exported Direct app signature has no secure timestamp.' >&2
    exit 1
fi
direct_helper="$direct_app/Contents/Library/LaunchServices/$RELEASE_HELPER_EXECUTABLE_NAME"
if ! helper_signature_details="$(codesign -d --verbose=4 "$direct_helper" 2>&1)"; then
    printf '%s\n' 'Unable to inspect the exported privileged helper signature.' >&2
    exit 1
fi
if ! grep -F 'Timestamp=' <<< "$helper_signature_details" > /dev/null; then
    printf '%s\n' 'Exported privileged helper signature has no secure timestamp.' >&2
    exit 1
fi
ditto -c -k --keepParent "$direct_app" "$notary_zip"

preflight_args=(
    --direct-app "$direct_app"
    --mas-app "$mas_app"
    --notarization-input "$notary_zip"
    --version "$version"
    --build "$build_number"
    --configuration "$channel"
    --team-id "$team_id"
    --source-commit "$source_commit"
)
if [ -n "$mas_installer" ]; then
    preflight_args+=(--mas-installer "$mas_installer")
fi
preflight_args+=("${preflight_notary_args[@]}")
"$repo_root/Scripts/release-preflight.sh" "${preflight_args[@]}"

submit_and_require_accepted() {
    local input_path="$1"
    local result_stem="$2"
    local label="$3"
    local submission_path="$output_dir/$result_stem-submission.json"
    local wait_path="$output_dir/$result_stem-result.json"
    local resumed_wait_path="$output_dir/$result_stem-resumed-result.json"
    local recovery_path="$output_dir/$result_stem-RECOVERY.txt"
    local submission_id
    local status

    if ! xcrun notarytool submit "$input_path" \
        "${notary_args[@]}" \
        --no-wait \
        --output-format json > "$submission_path"; then
        printf '%s notarization upload failed; inspect %s\n' "$label" "$submission_path" >&2
        exit 1
    fi
    if ! submission_id="$(plutil -extract id raw -o - "$submission_path" 2> /dev/null)" ||
       ! [[ "$submission_id" =~ ^[0-9a-fA-F-]{36}$ ]]; then
        printf '%s notarization did not return a recoverable submission ID; inspect %s\n' "$label" "$submission_path" >&2
        exit 1
    fi

    {
        printf 'Submission ID: %s\n' "$submission_id"
        printf 'Input: %s\n' "$input_path"
        printf 'Input SHA-256: %s\n' "$(release_sha256 "$input_path")"
        printf 'Status command: Scripts/notary-status.sh --submission-id %s --result %q --timeout %s' \
            "$submission_id" "$resumed_wait_path" "$notary_timeout"
        if [ -n "$notary_profile" ]; then
            printf ' --notary-profile %q' "$notary_profile"
        fi
        printf '\n'
    } > "$recovery_path"

    if ! xcrun notarytool wait "$submission_id" \
        "${notary_args[@]}" \
        --timeout "$notary_timeout" \
        --output-format json > "$wait_path"; then
        printf '%s notarization did not complete locally within %s; do not resubmit it.\n' "$label" "$notary_timeout" >&2
        printf 'Recover with submission ID %s; instructions: %s\n' "$submission_id" "$recovery_path" >&2
        exit 75
    fi
    status="$(plutil -extract status raw -o - "$wait_path")"
    if [ "$status" != 'Accepted' ]; then
        printf '%s notarization was not accepted; status: %s\n' "$label" "$status" >&2
        exit 1
    fi
}

submit_and_require_accepted "$notary_zip" notary-app 'Application'
xcrun stapler staple "$direct_app"
xcrun stapler validate "$direct_app"

dmg_staging="$(mktemp -d "${TMPDIR:-/tmp}/coolcumber-dmg-staging.XXXXXX")"
cleanup() {
    rm -rf "$dmg_staging"
}
trap cleanup EXIT

ditto "$direct_app" "$dmg_staging/CoolCumber.app"
ln -s /Applications "$dmg_staging/Applications"
hdiutil create \
    -volname "CoolCumber $channel" \
    -srcfolder "$dmg_staging" \
    -format UDZO \
    "$dmg_path"
hdiutil verify "$dmg_path"
codesign --force --sign "$DIRECT_APP_SIGNING_IDENTITY" --timestamp "$dmg_path"
codesign --verify --strict --verbose=2 "$dmg_path"

submit_and_require_accepted "$dmg_path" notary-dmg 'Disk image'
xcrun stapler staple "$dmg_path"
xcrun stapler validate "$dmg_path"
spctl --assess --verbose=2 --type execute "$direct_app"
spctl --assess --verbose=2 --type open --context context:primary-signature "$dmg_path"
codesign --verify --deep --strict --verbose=2 "$direct_app"
codesign --verify --strict --verbose=2 "$dmg_path"
hdiutil verify "$dmg_path"
shasum -a 256 "$dmg_path" > "$dmg_path.sha256"
dmg_sha="$(release_sha256 "$dmg_path")"
manifest_path="$output_dir/release-manifest.json"
release_write_manifest \
    "$manifest_path" "$source_commit" "$channel" "$version" "$build_number" "$team_id" \
    direct-notarized-dmg "$dmg_path" "$dmg_sha"
manifest_sha="$(release_sha256 "$manifest_path")"
printf '%s  %s\n' "$manifest_sha" "$(basename "$manifest_path")" > "$manifest_path.sha256"

instructions_path="$output_dir/PUBLISH-INSTRUCTIONS.txt"
{
    printf '%s\n' 'No GitHub Release was created or modified.'
    printf 'Channel: %s\n' "$channel"
    printf 'Notarized DMG: %s\n' "$dmg_path"
    printf 'Developer ID archive: %s\n' "$archive_path"
    printf 'Release manifest: %s\n' "$manifest_path"
    if [ -n "$mas_installer" ]; then
        printf 'Validated Mac App Store package: %s\n' "$mas_installer"
    else
        printf '%s\n' 'No Mac App Store package was supplied; package payload checks were not applicable to this Direct-only run.'
    fi
    printf '%s\n' 'Review the checksum and notarization result JSON files before manually publishing the DMG.'
} > "$instructions_path"

printf '%s\n' 'Direct release artifacts are signed, notarized, stapled, and locally validated.'
printf 'DMG: %s\n' "$dmg_path"
printf '%s\n' 'No GitHub Release was created or replaced.'
