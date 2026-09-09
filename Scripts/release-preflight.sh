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
  Scripts/release-preflight.sh \
    --direct-app PATH \
    --mas-app PATH \
    --mas-installer PATH.pkg \
    --notarization-input PATH.zip \
    --version VERSION \
    --build BUILD \
    --configuration Release|Beta \
    --team-id TEAM_ID \
    --source-commit FULL_40_CHARACTER_HEAD \
    [--notary-profile KEYCHAIN_PROFILE]

Notary credentials are read from the environment, never from command-line flags.
Use one of these credential sets:
  NOTARY_KEYCHAIN_PROFILE (or --notary-profile)
  NOTARY_KEY_PATH + NOTARY_KEY_ID + NOTARY_ISSUER_ID
USAGE
}

direct_app=""
mas_app=""
mas_installer=""
notarization_input=""
expected_version="${RELEASE_VERSION:-}"
expected_build="${RELEASE_BUILD:-}"
configuration=""
team_id="${TEAM_ID:-}"
source_commit=""
notary_profile="${NOTARY_KEYCHAIN_PROFILE:-}"

while [ "$#" -gt 0 ]; do
    case "$1" in
        --direct-app)
            direct_app="${2:-}"
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
        --notarization-input)
            notarization_input="${2:-}"
            shift 2
            ;;
        --version)
            expected_version="${2:-}"
            shift 2
            ;;
        --build)
            expected_build="${2:-}"
            shift 2
            ;;
        --configuration)
            configuration="${2:-}"
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

require_value '--direct-app' "$direct_app"
require_value '--mas-app' "$mas_app"
require_value '--mas-installer' "$mas_installer"
require_value '--notarization-input' "$notarization_input"
require_value '--version' "$expected_version"
require_value '--build' "$expected_build"
require_value '--configuration' "$configuration"
require_value '--team-id' "$team_id"
require_value '--source-commit' "$source_commit"

if ! [[ "$expected_version" =~ ^[0-9]+(\.[0-9]+){1,2}$ ]]; then
    printf '%s\n' 'Release version must contain two or three numeric components.' >&2
    exit 64
fi
if ! [[ "$expected_build" =~ ^[1-9][0-9]*$ ]]; then
    printf '%s\n' 'Release build number must be a positive integer.' >&2
    exit 64
fi
case "$configuration" in Release|Beta) ;; *)
    printf '%s\n' '--configuration must be exactly Release or Beta.' >&2
    exit 64
esac
if ! [[ "$team_id" =~ ^[A-Z0-9]{10}$ ]]; then
    printf '%s\n' 'Team ID must contain exactly 10 uppercase letters or digits.' >&2
    exit 64
fi

if [ -n "${APPLE_ID:-}" ] || [ -n "${APP_SPECIFIC_PASSWORD:-}" ]; then
    printf '%s\n' 'Legacy Apple-ID password credentials are not accepted; use an API key or keychain profile.' >&2
    exit 64
fi

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

direct_app="$(absolute_from_invocation "$direct_app")"
mas_app="$(absolute_from_invocation "$mas_app")"
if [ -n "$mas_installer" ]; then
    mas_installer="$(absolute_from_invocation "$mas_installer")"
fi
notarization_input="$(absolute_from_invocation "$notarization_input")"

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"
release_require_explicit_source_commit "$source_commit"

required_tools=(codesign ditto find git grep lipo pkgutil plutil ruby security stat strings xcrun)
for required_tool in "${required_tools[@]}"; do
    if ! command -v "$required_tool" > /dev/null 2>&1; then
        printf 'Required release tool is unavailable: %s\n' "$required_tool" >&2
        exit 1
    fi
done

if [ ! -d "$DEVELOPER_DIR" ] || [ ! -x "$DEVELOPER_DIR/usr/bin/xcodebuild" ]; then
    printf 'DEVELOPER_DIR does not contain a usable Xcode installation: %s\n' "$DEVELOPER_DIR" >&2
    exit 1
fi

if [ ! -d "$direct_app" ]; then
    printf 'Direct app bundle does not exist: %s\n' "$direct_app" >&2
    exit 1
fi
if [ ! -d "$mas_app" ]; then
    printf 'Mac App Store app bundle does not exist: %s\n' "$mas_app" >&2
    exit 1
fi
if [ -n "$mas_installer" ] && [ ! -s "$mas_installer" ]; then
    printf 'Mac App Store installer does not exist or is empty: %s\n' "$mas_installer" >&2
    exit 1
fi
if [ ! -s "$notarization_input" ]; then
    printf 'Notarization input does not exist or is empty: %s\n' "$notarization_input" >&2
    exit 1
fi

if [ -n "$mas_installer" ]; then
    installer_extension="$(printf '%s' "$mas_installer" | tr '[:upper:]' '[:lower:]')"
    case "$installer_extension" in
        *.pkg)
            ;;
        *)
            printf '%s\n' 'Mac App Store installer must be a .pkg file.' >&2
            exit 1
            ;;
    esac
fi

notary_extension="$(printf '%s' "$notarization_input" | tr '[:upper:]' '[:lower:]')"
case "$notary_extension" in
    *.zip)
        ;;
    *)
        printf '%s\n' 'Direct notarization input must be a .zip containing exactly one signed .app bundle.' >&2
        exit 1
        ;;
esac

work_dir="$(mktemp -d "${TMPDIR:-/tmp}/coolcumber-release-preflight.XXXXXX")"
cleanup() {
    rm -rf "$work_dir"
}
trap cleanup EXIT

plist_value() {
    local plist="$1"
    local key="$2"
    /usr/libexec/PlistBuddy -c "Print :$key" "$plist"
}

assert_bundle_version() {
    local bundle="$1"
    local label="$2"
    local info_plist="$bundle/Contents/Info.plist"
    local actual_version
    local actual_build

    if [ ! -f "$info_plist" ]; then
        printf '%s Info.plist is missing: %s\n' "$label" "$info_plist" >&2
        exit 1
    fi

    actual_version="$(plist_value "$info_plist" CFBundleShortVersionString)"
    actual_build="$(plist_value "$info_plist" CFBundleVersion)"
    if [ "$actual_version" != "$expected_version" ]; then
        printf '%s marketing version mismatch: expected %s, got %s\n' "$label" "$expected_version" "$actual_version" >&2
        exit 1
    fi
    if [ "$actual_build" != "$expected_build" ]; then
        printf '%s build number mismatch: expected %s, got %s\n' "$label" "$expected_build" "$actual_build" >&2
        exit 1
    fi
}

assert_export_compliance() {
    local bundle="$1"
    local label="$2"
    local actual

    actual="$(plist_value "$bundle/Contents/Info.plist" ITSAppUsesNonExemptEncryption 2> /dev/null || true)"
    if [ "$actual" != 'false' ]; then
        printf '%s must declare ITSAppUsesNonExemptEncryption=false; got %s\n' \
            "$label" "${actual:-missing}" >&2
        exit 1
    fi
}

assert_source_version() {
    local plist="$1"
    local key="$2"
    local expected="$3"
    local setting_name="$4"
    local actual

    actual="$(plist_value "$plist" "$key")"
    if [ "$actual" != "$expected" ] && [ "$actual" != "\$($setting_name)" ] && [ "$actual" != "\${$setting_name}" ]; then
        printf '%s %s must be %s or reference %s; got %s\n' "$plist" "$key" "$expected" "$setting_name" "$actual" >&2
        exit 1
    fi
}

collect_extensions() {
    local app_bundle="$1"
    local destination="$2"
    : > "$destination"
    if [ -d "$app_bundle/Contents/PlugIns" ]; then
        find "$app_bundle/Contents/PlugIns" -maxdepth 1 -type d -name '*.appex' -print > "$destination"
    fi
    if [ ! -s "$destination" ]; then
        printf 'No embedded extension was found in %s\n' "$app_bundle" >&2
        exit 1
    fi
}

assert_no_storekit_test_configuration() {
    local app_bundle="$1"
    local label="$2"
    if [ -n "$(find "$app_bundle" -type f -name '*.storekit' -print -quit)" ]; then
        printf '%s must not contain a StoreKit test configuration.\n' "$label" >&2
        exit 1
    fi
}

assert_bundle_identifier() {
    local bundle="$1"
    local expected_identifier="$2"
    local label="$3"
    local actual_identifier

    actual_identifier="$(plist_value "$bundle/Contents/Info.plist" CFBundleIdentifier)"
    if [ "$actual_identifier" != "$expected_identifier" ]; then
        printf '%s bundle identifier mismatch: expected %s, got %s\n' \
            "$label" "$expected_identifier" "$actual_identifier" >&2
        exit 1
    fi
}

assert_privacy_reason() {
    local manifest="$1"
    local category="$2"
    local reason="$3"
    local index=0
    local actual_category
    local reasons

    while [ "$index" -lt 64 ]; do
        if ! actual_category="$(plist_value "$manifest" "NSPrivacyAccessedAPITypes:$index:NSPrivacyAccessedAPIType" 2> /dev/null)"; then
            break
        fi
        if [ "$actual_category" = "$category" ]; then
            reasons="$(plist_value "$manifest" "NSPrivacyAccessedAPITypes:$index:NSPrivacyAccessedAPITypeReasons")"
            if grep -F -q "$reason" <<< "$reasons"; then
                return
            fi
        fi
        index=$((index + 1))
    done
    printf 'Privacy manifest is missing reason %s for %s: %s\n' "$reason" "$category" "$manifest" >&2
    exit 1
}

assert_bundle_privacy() {
    local app_bundle="$1"
    local label="$2"
    local manifest="$app_bundle/Contents/Resources/PrivacyInfo.xcprivacy"

    if [ ! -s "$manifest" ] || ! plutil -lint "$manifest" > /dev/null; then
        printf '%s is missing a valid PrivacyInfo.xcprivacy.\n' "$label" >&2
        exit 1
    fi
    assert_privacy_reason "$manifest" NSPrivacyAccessedAPICategoryUserDefaults CA92.1
    assert_privacy_reason "$manifest" NSPrivacyAccessedAPICategoryDiskSpace 85F4.1
    assert_privacy_reason "$manifest" NSPrivacyAccessedAPICategoryFileTimestamp C617.1
}

assert_widget_privacy() {
    local widget_bundle="$1"
    local label="$2"
    local manifest="$widget_bundle/Contents/Resources/PrivacyInfo.xcprivacy"
    if [ ! -s "$manifest" ] || ! plutil -lint "$manifest" > /dev/null; then
        printf '%s is missing a valid PrivacyInfo.xcprivacy.\n' "$label" >&2
        exit 1
    fi
}

assert_provisioning_application_identifier() {
    local bundle="$1"
    local expected_identifier="$2"
    local label="$3"
    local stem="$4"
    local profile="$bundle/Contents/embedded.provisionprofile"
    local decoded="$work_dir/$stem-profile.plist"
    local actual_identifier
    local profile_team

    if [ ! -s "$profile" ]; then
        printf '%s is missing embedded.provisionprofile.\n' "$label" >&2
        exit 1
    fi
    if ! security cms -D -i "$profile" > "$decoded"; then
        printf '%s provisioning profile cannot be decoded.\n' "$label" >&2
        exit 1
    fi
    plutil -lint "$decoded" > /dev/null
    profile_team="$(plist_value "$decoded" TeamIdentifier:0)"
    actual_identifier="$(plist_value "$decoded" Entitlements:application-identifier)"
    if [ "$profile_team" != "$team_id" ] || [ "$actual_identifier" != "$team_id.$expected_identifier" ]; then
        printf '%s provisioning identity mismatch: expected %s.%s.\n' \
            "$label" "$team_id" "$expected_identifier" >&2
        exit 1
    fi
}

assert_bundle_version "$direct_app" 'Direct app'
assert_bundle_version "$mas_app" 'Mac App Store app'
assert_export_compliance "$direct_app" 'Direct app'
assert_export_compliance "$mas_app" 'Mac App Store app'
assert_bundle_identifier "$direct_app" "$RELEASE_APP_BUNDLE_ID" 'Direct app'
assert_bundle_identifier "$mas_app" "$RELEASE_APP_BUNDLE_ID" 'Mac App Store app'
assert_bundle_privacy "$direct_app" 'Direct app'
assert_bundle_privacy "$mas_app" 'Mac App Store app'
assert_no_storekit_test_configuration "$direct_app" 'Direct app'
assert_no_storekit_test_configuration "$mas_app" 'Mac App Store app'
assert_source_version "$repo_root/ThermFlowApp/Info.plist" CFBundleShortVersionString "$expected_version" MARKETING_VERSION
assert_source_version "$repo_root/ThermFlowApp/Info.plist" CFBundleVersion "$expected_build" CURRENT_PROJECT_VERSION
assert_source_version "$repo_root/ThermFlowWidget/Info.plist" CFBundleShortVersionString "$expected_version" MARKETING_VERSION
assert_source_version "$repo_root/ThermFlowWidget/Info.plist" CFBundleVersion "$expected_build" CURRENT_PROJECT_VERSION

direct_extensions="$work_dir/direct-extensions.txt"
mas_extensions="$work_dir/mas-extensions.txt"
collect_extensions "$direct_app" "$direct_extensions"
collect_extensions "$mas_app" "$mas_extensions"

while IFS= read -r extension; do
    assert_bundle_version "$extension" 'Direct embedded extension'
    assert_bundle_identifier "$extension" "$RELEASE_WIDGET_BUNDLE_ID" 'Direct embedded extension'
    assert_widget_privacy "$extension" 'Direct embedded extension'
done < "$direct_extensions"
while IFS= read -r extension; do
    assert_bundle_version "$extension" 'Mac App Store embedded extension'
    assert_bundle_identifier "$extension" "$RELEASE_WIDGET_BUNDLE_ID" 'Mac App Store embedded extension'
    assert_widget_privacy "$extension" 'Mac App Store embedded extension'
done < "$mas_extensions"

"$repo_root/Scripts/check-project-boundaries.rb" "$repo_root/project.yml" "$expected_version" "$expected_build"
"$repo_root/Scripts/check-channel-boundaries.sh" "$direct_app" "$mas_app" "$configuration"

signature_details=""
load_signature_details() {
    local signed_path="$1"
    if ! signature_details="$(codesign -d --verbose=4 "$signed_path" 2>&1)"; then
        printf 'Unable to inspect code signature: %s\n' "$signed_path" >&2
        exit 1
    fi
}

assert_signature_team() {
    local signed_path="$1"
    local label="$2"

    if ! codesign --verify --strict --verbose=2 "$signed_path"; then
        printf '%s has an invalid code signature: %s\n' "$label" "$signed_path" >&2
        exit 1
    fi
    load_signature_details "$signed_path"
    if ! grep -F -q "TeamIdentifier=$team_id" <<< "$signature_details"; then
        printf '%s is not signed by Team ID %s: %s\n' "$label" "$team_id" "$signed_path" >&2
        exit 1
    fi
    if grep -F -q 'Signature=adhoc' <<< "$signature_details"; then
        printf '%s uses an ad-hoc signature: %s\n' "$label" "$signed_path" >&2
        exit 1
    fi
}

assert_direct_signature() {
    local signed_path="$1"
    local label="$2"
    assert_signature_team "$signed_path" "$label"
    if ! grep -F -q 'Authority=Developer ID Application:' <<< "$signature_details"; then
        printf '%s must use a Developer ID Application certificate: %s\n' "$label" "$signed_path" >&2
        exit 1
    fi
    if ! grep -q 'flags=.*runtime' <<< "$signature_details"; then
        printf '%s must enable Hardened Runtime: %s\n' "$label" "$signed_path" >&2
        exit 1
    fi
}

assert_mas_signature() {
    local signed_path="$1"
    local label="$2"
    assert_signature_team "$signed_path" "$label"
    if grep -F -q 'Authority=Apple Distribution:' <<< "$signature_details"; then
        return
    fi
    if grep -F -q 'Authority=3rd Party Mac Developer Application:' <<< "$signature_details"; then
        return
    fi
    printf '%s must use an Apple Distribution certificate: %s\n' "$label" "$signed_path" >&2
    exit 1
}

assert_signature_identifier() {
    local signed_path="$1"
    local expected_identifier="$2"
    local label="$3"
    load_signature_details "$signed_path"
    if ! grep -F -q "Identifier=$expected_identifier" <<< "$signature_details"; then
        printf '%s code-signing identifier must be %s: %s\n' \
            "$label" "$expected_identifier" "$signed_path" >&2
        exit 1
    fi
}

direct_helper="$direct_app/Contents/Library/LaunchServices/$RELEASE_HELPER_EXECUTABLE_NAME"
assert_direct_signature "$direct_app" 'Direct app'
assert_direct_signature "$direct_helper" 'Direct privileged helper'
assert_signature_identifier "$direct_app" "$RELEASE_APP_BUNDLE_ID" 'Direct app'
assert_signature_identifier "$direct_helper" "$RELEASE_HELPER_SERVICE_ID" 'Direct privileged helper'
while IFS= read -r extension; do
    assert_direct_signature "$extension" 'Direct embedded extension'
    assert_signature_identifier "$extension" "$RELEASE_WIDGET_BUNDLE_ID" 'Direct embedded extension'
done < "$direct_extensions"

assert_mas_signature "$mas_app" 'Mac App Store app'
assert_signature_identifier "$mas_app" "$RELEASE_APP_BUNDLE_ID" 'Mac App Store app'
while IFS= read -r extension; do
    assert_mas_signature "$extension" 'Mac App Store embedded extension'
    assert_signature_identifier "$extension" "$RELEASE_WIDGET_BUNDLE_ID" 'Mac App Store embedded extension'
done < "$mas_extensions"

extract_entitlements() {
    local signed_path="$1"
    local destination="$2"
    local diagnostics="$3"
    if ! codesign -d --entitlements :- "$signed_path" > "$destination" 2> "$diagnostics"; then
        printf 'Unable to extract entitlements from: %s\n' "$signed_path" >&2
        exit 1
    fi
}

assert_entitlement_true() {
    local signed_path="$1"
    local entitlement="$2"
    local label="$3"
    local stem="$4"
    local plist="$work_dir/$stem-entitlements.plist"
    local diagnostics="$work_dir/$stem-entitlements.log"
    local value

    extract_entitlements "$signed_path" "$plist" "$diagnostics"
    if ! plutil -lint "$plist" > /dev/null; then
        printf '%s has no valid entitlements plist: %s\n' "$label" "$signed_path" >&2
        exit 1
    fi
    if ! value="$(plist_value "$plist" "$entitlement" 2> "$diagnostics")"; then
        printf '%s is missing required entitlement %s\n' "$label" "$entitlement" >&2
        exit 1
    fi
    if [ "$value" != 'true' ]; then
        printf '%s entitlement %s must be true\n' "$label" "$entitlement" >&2
        exit 1
    fi
}

assert_entitlement_not_true() {
    local signed_path="$1"
    local entitlement="$2"
    local label="$3"
    local stem="$4"
    local plist="$work_dir/$stem-entitlements.plist"
    local diagnostics="$work_dir/$stem-entitlements.log"
    local value

    extract_entitlements "$signed_path" "$plist" "$diagnostics"
    if plutil -lint "$plist" > /dev/null 2>&1; then
        if value="$(plist_value "$plist" "$entitlement" 2> "$diagnostics")"; then
            if [ "$value" = 'true' ]; then
                printf '%s must not enable entitlement %s\n' "$label" "$entitlement" >&2
                exit 1
            fi
        fi
    fi
}

assert_entitlement_absent() {
    local signed_path="$1"
    local entitlement="$2"
    local label="$3"
    local stem="$4"
    local plist="$work_dir/$stem-entitlements.plist"
    local diagnostics="$work_dir/$stem-entitlements.log"
    local value

    extract_entitlements "$signed_path" "$plist" "$diagnostics"
    if plutil -lint "$plist" > /dev/null 2>&1; then
        if value="$(plist_value "$plist" "$entitlement" 2> "$diagnostics")"; then
            printf '%s must not contain entitlement %s\n' "$label" "$entitlement" >&2
            exit 1
        fi
    fi
}

assert_entitlement_contains() {
    local signed_path="$1"
    local entitlement="$2"
    local expected_value="$3"
    local label="$4"
    local stem="$5"
    local plist="$work_dir/$stem-entitlements.plist"
    local diagnostics="$work_dir/$stem-entitlements.log"
    local value

    extract_entitlements "$signed_path" "$plist" "$diagnostics"
    if ! value="$(plist_value "$plist" "$entitlement" 2> "$diagnostics")"; then
        printf '%s is missing required entitlement %s\n' "$label" "$entitlement" >&2
        exit 1
    fi
    if ! grep -F -q "$expected_value" <<< "$value"; then
        printf '%s entitlement %s must contain %s\n' "$label" "$entitlement" "$expected_value" >&2
        exit 1
    fi
}

app_group="$RELEASE_APP_GROUP"
assert_entitlement_not_true "$direct_app" com.apple.security.app-sandbox 'Direct app' direct-app
assert_entitlement_not_true "$direct_app" com.apple.security.get-task-allow 'Direct app' direct-app-debug
assert_entitlement_contains "$direct_app" com.apple.security.application-groups "$app_group" 'Direct app' direct-app-groups
assert_entitlement_not_true "$direct_helper" com.apple.security.get-task-allow 'Direct privileged helper' direct-helper
assert_entitlement_true "$mas_app" com.apple.security.app-sandbox 'Mac App Store app' mas-app-sandbox
assert_entitlement_absent "$mas_app" com.apple.security.network.client 'Mac App Store app' mas-app-network
assert_entitlement_contains "$mas_app" com.apple.security.application-groups "$app_group" 'Mac App Store app' mas-app-groups
assert_entitlement_not_true "$mas_app" com.apple.security.get-task-allow 'Mac App Store app' mas-app-debug
assert_entitlement_absent "$mas_app" com.apple.security.temporary-exception.mach-lookup.global-name 'Mac App Store app' mas-app-mach-exception
assert_entitlement_absent "$mas_app" com.apple.security.temporary-exception.files.absolute-path.read-write 'Mac App Store app' mas-app-files-exception
assert_entitlement_absent "$mas_app" com.apple.security.cs.disable-library-validation 'Mac App Store app' mas-app-library-validation

direct_extension_index=0
while IFS= read -r extension; do
    assert_entitlement_contains "$extension" com.apple.security.application-groups "$app_group" 'Direct embedded extension' "direct-extension-$direct_extension_index-groups"
    direct_extension_index=$((direct_extension_index + 1))
done < "$direct_extensions"

extension_index=0
while IFS= read -r extension; do
    assert_entitlement_true "$extension" com.apple.security.app-sandbox 'Mac App Store embedded extension' "mas-extension-$extension_index-sandbox"
    assert_entitlement_contains "$extension" com.apple.security.application-groups "$app_group" 'Mac App Store embedded extension' "mas-extension-$extension_index-groups"
    assert_entitlement_not_true "$extension" com.apple.security.get-task-allow 'Mac App Store embedded extension' "mas-extension-$extension_index-debug"
    assert_entitlement_absent "$extension" com.apple.security.temporary-exception.mach-lookup.global-name 'Mac App Store embedded extension' "mas-extension-$extension_index-mach-exception"
    extension_index=$((extension_index + 1))
done < "$mas_extensions"

assert_provisioning_application_identifier "$direct_app" "$RELEASE_APP_BUNDLE_ID" 'Direct app' direct-app
assert_provisioning_application_identifier "$mas_app" "$RELEASE_APP_BUNDLE_ID" 'Mac App Store app' mas-app
direct_profile_index=0
while IFS= read -r extension; do
    assert_provisioning_application_identifier "$extension" "$RELEASE_WIDGET_BUNDLE_ID" 'Direct embedded extension' "direct-extension-$direct_profile_index"
    direct_profile_index=$((direct_profile_index + 1))
done < "$direct_extensions"
mas_profile_index=0
while IFS= read -r extension; do
    assert_provisioning_application_identifier "$extension" "$RELEASE_WIDGET_BUNDLE_ID" 'Mac App Store embedded extension' "mas-extension-$mas_profile_index"
    mas_profile_index=$((mas_profile_index + 1))
done < "$mas_extensions"

if [ -n "$mas_installer" ]; then
"$script_directory/validate-mas-pkg.sh" \
    --pkg "$mas_installer" \
    --version "$expected_version" \
    --build "$expected_build" \
    --team-id "$team_id"
if ! installer_signature="$(pkgutil --check-signature "$mas_installer" 2>&1)"; then
    printf 'Mac App Store installer signature is invalid: %s\n' "$mas_installer" >&2
    exit 1
fi
if ! grep -F -q "$team_id" <<< "$installer_signature"; then
    printf 'Mac App Store installer is not signed by Team ID %s\n' "$team_id" >&2
    exit 1
fi
if grep -F -q '3rd Party Mac Developer Installer:' <<< "$installer_signature"; then
    :
elif grep -F -q 'Mac Installer Distribution:' <<< "$installer_signature"; then
    :
else
    printf '%s\n' 'Mac App Store installer must use an App Store installer distribution certificate.' >&2
    exit 1
fi

expanded_installer="$work_dir/expanded-installer"
if ! pkgutil --expand-full "$mas_installer" "$expanded_installer"; then
    printf 'Unable to expand Mac App Store installer payload: %s\n' "$mas_installer" >&2
    exit 1
fi

installer_apps="$work_dir/installer-apps.txt"
find "$expanded_installer" -type d -name '*.app' -print > "$installer_apps"
installer_app_count="$(awk 'END { print NR + 0 }' "$installer_apps")"
if [ "$installer_app_count" -ne 1 ]; then
    printf 'Mac App Store installer must contain exactly one app bundle; found %s\n' "$installer_app_count" >&2
    exit 1
fi

installer_app="$(sed -n '1p' "$installer_apps")"
assert_bundle_version "$installer_app" 'Mac App Store installer app'
assert_export_compliance "$installer_app" 'Mac App Store installer app'
assert_bundle_identifier "$installer_app" "$RELEASE_APP_BUNDLE_ID" 'Mac App Store installer app'
assert_bundle_privacy "$installer_app" 'Mac App Store installer app'
assert_mas_signature "$installer_app" 'Mac App Store installer app'
assert_entitlement_true "$installer_app" com.apple.security.app-sandbox 'Mac App Store installer app' installer-app-sandbox
assert_entitlement_absent "$installer_app" com.apple.security.network.client 'Mac App Store installer app' installer-app-network
assert_entitlement_contains "$installer_app" com.apple.security.application-groups "$app_group" 'Mac App Store installer app' installer-app-groups
assert_entitlement_not_true "$installer_app" com.apple.security.get-task-allow 'Mac App Store installer app' installer-app-debug
assert_entitlement_absent "$installer_app" com.apple.security.temporary-exception.mach-lookup.global-name 'Mac App Store installer app' installer-app-mach-exception
assert_entitlement_absent "$installer_app" com.apple.security.temporary-exception.files.absolute-path.read-write 'Mac App Store installer app' installer-app-files-exception
installer_extensions="$work_dir/installer-extensions.txt"
collect_extensions "$installer_app" "$installer_extensions"
installer_extension_index=0
while IFS= read -r extension; do
    assert_bundle_version "$extension" 'Mac App Store installer embedded extension'
    assert_bundle_identifier "$extension" "$RELEASE_WIDGET_BUNDLE_ID" 'Mac App Store installer embedded extension'
    assert_widget_privacy "$extension" 'Mac App Store installer embedded extension'
    assert_mas_signature "$extension" 'Mac App Store installer embedded extension'
    assert_entitlement_true "$extension" com.apple.security.app-sandbox 'Mac App Store installer embedded extension' "installer-extension-$installer_extension_index-sandbox"
    assert_entitlement_contains "$extension" com.apple.security.application-groups "$app_group" 'Mac App Store installer embedded extension' "installer-extension-$installer_extension_index-groups"
    assert_entitlement_not_true "$extension" com.apple.security.get-task-allow 'Mac App Store installer embedded extension' "installer-extension-$installer_extension_index-debug"
    assert_entitlement_absent "$extension" com.apple.security.temporary-exception.mach-lookup.global-name 'Mac App Store installer embedded extension' "installer-extension-$installer_extension_index-mach-exception"
    installer_extension_index=$((installer_extension_index + 1))
done < "$installer_extensions"
installer_bundle_id="$(plist_value "$installer_app/Contents/Info.plist" CFBundleIdentifier)"
mas_bundle_id="$(plist_value "$mas_app/Contents/Info.plist" CFBundleIdentifier)"
if [ "$installer_bundle_id" != "$mas_bundle_id" ]; then
    printf 'Mac App Store installer bundle identifier mismatch: expected %s, got %s\n' "$mas_bundle_id" "$installer_bundle_id" >&2
    exit 1
fi
"$repo_root/Scripts/check-channel-boundaries.sh" "$direct_app" "$installer_app" "$configuration"
fi

if ! xcrun --find notarytool > "$work_dir/notarytool-path.txt"; then
    printf '%s\n' 'notarytool is unavailable in the selected Xcode installation.' >&2
    exit 1
fi
if ! xcrun notarytool --help > "$work_dir/notarytool-help.txt"; then
    printf '%s\n' 'notarytool could not be started.' >&2
    exit 1
fi

if [ -n "$notary_profile" ]; then
    :
elif [ -n "${NOTARY_KEY_PATH:-}" ] || [ -n "${NOTARY_KEY_ID:-}" ] || [ -n "${NOTARY_ISSUER_ID:-}" ]; then
    require_value 'NOTARY_KEY_PATH' "${NOTARY_KEY_PATH:-}"
    require_value 'NOTARY_KEY_ID' "${NOTARY_KEY_ID:-}"
    require_value 'NOTARY_ISSUER_ID' "${NOTARY_ISSUER_ID:-}"
    notary_key_path="$(absolute_from_invocation "$NOTARY_KEY_PATH")"
    if [ ! -r "$notary_key_path" ]; then
        printf '%s\n' 'NOTARY_KEY_PATH does not point to a readable private key.' >&2
        exit 1
    fi
    key_directory="$(cd "$(dirname "$notary_key_path")" && pwd -P)"
    key_absolute_path="$key_directory/$(basename "$notary_key_path")"
    case "$key_absolute_path" in
        "$repo_root"/*)
            printf '%s\n' 'The App Store Connect private key must be stored outside the Git workspace.' >&2
            exit 1
            ;;
    esac
    case "$key_absolute_path" in
        *.p8)
            ;;
        *)
            printf '%s\n' 'NOTARY_KEY_PATH must reference a .p8 key without reading or exposing its contents.' >&2
            exit 1
            ;;
    esac
    key_mode="$(stat -f '%Lp' "$notary_key_path")"
    case "$key_mode" in
        400|600)
            ;;
        *)
            printf '%s\n' 'NOTARY_KEY_PATH permissions must be 400 or 600.' >&2
            exit 1
            ;;
    esac
    if ! [[ "$NOTARY_KEY_ID" =~ ^[A-Z0-9]{10}$ ]]; then
        printf '%s\n' 'NOTARY_KEY_ID must be a 10-character App Store Connect key ID.' >&2
        exit 1
    fi
    if ! [[ "$NOTARY_ISSUER_ID" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]; then
        printf '%s\n' 'NOTARY_ISSUER_ID must be an App Store Connect issuer UUID.' >&2
        exit 1
    fi
else
    printf '%s\n' 'Missing notary credentials. Configure a keychain profile or App Store Connect API key.' >&2
    exit 1
fi

notary_extract="$work_dir/notary-input"
mkdir -p "$notary_extract"
if ! ditto -x -k "$notarization_input" "$notary_extract"; then
    printf 'Notarization ZIP is corrupt or unreadable: %s\n' "$notarization_input" >&2
    exit 1
fi

notary_apps="$work_dir/notary-apps.txt"
find "$notary_extract" -maxdepth 2 -type d -name '*.app' -print > "$notary_apps"
notary_app_count="$(awk 'END { print NR + 0 }' "$notary_apps")"
if [ "$notary_app_count" -ne 1 ]; then
    printf 'Notarization ZIP must contain exactly one app bundle; found %s\n' "$notary_app_count" >&2
    exit 1
fi

notary_app="$(sed -n '1p' "$notary_apps")"
assert_bundle_version "$notary_app" 'Notarization app'
assert_export_compliance "$notary_app" 'Notarization app'
assert_bundle_identifier "$notary_app" "$RELEASE_APP_BUNDLE_ID" 'Notarization app'
assert_bundle_privacy "$notary_app" 'Notarization app'
assert_no_storekit_test_configuration "$notary_app" 'Notarization app'
assert_direct_signature "$notary_app" 'Notarization app'
notary_extensions="$work_dir/notary-extensions.txt"
collect_extensions "$notary_app" "$notary_extensions"
while IFS= read -r extension; do
    assert_bundle_version "$extension" 'Notarization embedded extension'
    assert_bundle_identifier "$extension" "$RELEASE_WIDGET_BUNDLE_ID" 'Notarization embedded extension'
    assert_widget_privacy "$extension" 'Notarization embedded extension'
    assert_direct_signature "$extension" 'Notarization embedded extension'
done < "$notary_extensions"

direct_bundle_id="$(plist_value "$direct_app/Contents/Info.plist" CFBundleIdentifier)"
notary_bundle_id="$(plist_value "$notary_app/Contents/Info.plist" CFBundleIdentifier)"
if [ "$notary_bundle_id" != "$direct_bundle_id" ]; then
    printf 'Notarization app bundle identifier mismatch: expected %s, got %s\n' "$direct_bundle_id" "$notary_bundle_id" >&2
    exit 1
fi

if [ ! -x "$notary_app/Contents/Library/LaunchServices/$RELEASE_HELPER_EXECUTABLE_NAME" ]; then
    printf '%s\n' 'Notarization app is missing its signed privileged helper.' >&2
    exit 1
fi
assert_direct_signature "$notary_app/Contents/Library/LaunchServices/$RELEASE_HELPER_EXECUTABLE_NAME" 'Notarization privileged helper'
"$repo_root/Scripts/check-channel-boundaries.sh" "$notary_app" "$mas_app" "$configuration"

if [ -n "$mas_installer" ]; then
    printf '%s\n' 'Release preflight passed: versions, channel boundaries, signatures, entitlements, installer, and notarization inputs are valid.'
else
    printf '%s\n' 'Release preflight passed: versions, channel boundaries, signatures, entitlements, and notarization inputs are valid; no MAS installer was supplied.'
fi
