#!/bin/bash

set -euo pipefail

script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=Scripts/release-config.sh
source "$script_directory/release-config.sh"

usage() {
    cat <<'USAGE'
Usage:
  Scripts/validate-mas-pkg.sh \
    --pkg /absolute/path/to/AppStore.pkg \
    --version 1.2.0 \
    --build 3 \
    --team-id TEAM_ID

This command is read-only with respect to the package. It expands a temporary
copy and validates the exact payload that would be uploaded.

  Scripts/validate-mas-pkg.sh \
    --app /absolute/path/to/CoolCumber.app \
    --version 1.2.0 \
    --build 3 \
    --team-id TEAM_ID
USAGE
}

pkg_path=""
app_input=""
expected_version=""
expected_build=""
team_id=""

while [ "$#" -gt 0 ]; do
    case "$1" in
        --pkg)
            pkg_path="${2:-}"
            shift 2
            ;;
        --app)
            app_input="${2:-}"
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
        --team-id)
            team_id="${2:-}"
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

require_value '--version' "$expected_version"
require_value '--build' "$expected_build"
require_value '--team-id' "$team_id"

if { [ -z "$pkg_path" ] && [ -z "$app_input" ]; } ||
   { [ -n "$pkg_path" ] && [ -n "$app_input" ]; }; then
    printf '%s\n' 'Provide exactly one of --pkg or --app.' >&2
    exit 64
fi
if [ -n "$pkg_path" ]; then
    case "$pkg_path" in
        /*) ;;
        *)
            printf '%s\n' '--pkg must be an absolute path.' >&2
            exit 64
            ;;
    esac
    case "$(printf '%s' "$pkg_path" | tr '[:upper:]' '[:lower:]')" in
        *.pkg) ;;
        *)
            printf '%s\n' '--pkg must reference a .pkg file.' >&2
            exit 64
            ;;
    esac
    if [ ! -s "$pkg_path" ]; then
        printf 'Package does not exist or is empty: %s\n' "$pkg_path" >&2
        exit 1
    fi
else
    case "$app_input" in
        /*) ;;
        *)
            printf '%s\n' '--app must be an absolute path.' >&2
            exit 64
            ;;
    esac
    if [ ! -d "$app_input" ]; then
        printf 'App bundle does not exist: %s\n' "$app_input" >&2
        exit 1
    fi
fi
if ! [[ "$expected_version" =~ ^[0-9]+(\.[0-9]+){1,2}$ ]] ||
   ! [[ "$expected_build" =~ ^[1-9][0-9]*$ ]] ||
   ! [[ "$team_id" =~ ^[A-Z0-9]{10}$ ]]; then
    printf '%s\n' 'Version, build, or Team ID has an invalid format.' >&2
    exit 64
fi

required_tools=(codesign find grep lipo pkgutil plutil security strings)
for required_tool in "${required_tools[@]}"; do
    if ! command -v "$required_tool" > /dev/null 2>&1; then
        printf 'Required package-validation tool is unavailable: %s\n' "$required_tool" >&2
        exit 1
    fi
done

work_dir="$(mktemp -d "${TMPDIR:-/tmp}/coolcumber-mas-validation.XXXXXX")"
cleanup() {
    rm -rf "$work_dir"
}
trap cleanup EXIT

plist_value() {
    /usr/libexec/PlistBuddy -c "Print :$2" "$1"
}

assert_equal() {
    local actual="$1"
    local expected="$2"
    local label="$3"
    if [ "$actual" != "$expected" ]; then
        printf '%s mismatch: expected %s, got %s\n' "$label" "$expected" "$actual" >&2
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
    case " $architectures " in *' arm64 '*) ;; *)
        printf '%s is missing arm64: %s\n' "$label" "$architectures" >&2
        exit 1
    esac
    case " $architectures " in *' x86_64 '*) ;; *)
        printf '%s is missing x86_64: %s\n' "$label" "$architectures" >&2
        exit 1
    esac
}

signature_details=""
assert_mas_signature() {
    local signed_path="$1"
    local label="$2"
    if ! codesign --verify --strict --verbose=2 "$signed_path"; then
        printf '%s has an invalid code signature: %s\n' "$label" "$signed_path" >&2
        exit 1
    fi
    if ! signature_details="$(codesign -d --verbose=4 "$signed_path" 2>&1)"; then
        printf 'Unable to inspect %s signature.\n' "$label" >&2
        exit 1
    fi
    if ! grep -F -q "TeamIdentifier=$team_id" <<< "$signature_details"; then
        printf '%s signature Team ID does not match %s.\n' "$label" "$team_id" >&2
        exit 1
    fi
    if ! grep -F -q 'Authority=Apple Distribution:' <<< "$signature_details" &&
       ! grep -F -q 'Authority=3rd Party Mac Developer Application:' <<< "$signature_details"; then
        printf '%s is not signed with an App Store distribution identity.\n' "$label" >&2
        exit 1
    fi
}

assert_signature_identifier() {
    local signed_path="$1"
    local expected_identifier="$2"
    local label="$3"
    local details
    details="$(codesign -d --verbose=4 "$signed_path" 2>&1)"
    if ! grep -F -q "Identifier=$expected_identifier" <<< "$details"; then
        printf '%s code-signing identifier must be %s.\n' "$label" "$expected_identifier" >&2
        exit 1
    fi
}

extract_entitlements() {
    local signed_path="$1"
    local destination="$2"
    if ! codesign -d --entitlements :- "$signed_path" > "$destination" 2> /dev/null; then
        printf 'Unable to extract entitlements from %s.\n' "$signed_path" >&2
        exit 1
    fi
    plutil -lint "$destination" > /dev/null
}

assert_signed_entitlements() {
    local signed_path="$1"
    local expected_bundle_id="$2"
    local label="$3"
    local stem="$4"
    local entitlements="$work_dir/$stem-entitlements.plist"
    local application_identifier
    local sandbox_value
    local groups

    extract_entitlements "$signed_path" "$entitlements"
    sandbox_value="$(plist_value "$entitlements" com.apple.security.app-sandbox)"
    assert_equal "$sandbox_value" 'true' "$label app sandbox entitlement"
    if [ "$(plist_value "$entitlements" com.apple.security.get-task-allow 2> /dev/null || true)" = 'true' ]; then
        printf '%s must not contain get-task-allow.\n' "$label" >&2
        exit 1
    fi
    application_identifier="$(plist_value "$entitlements" com.apple.application-identifier)"
    assert_equal "$application_identifier" "$team_id.$expected_bundle_id" "$label signed application-identifier"
    groups="$(plist_value "$entitlements" com.apple.security.application-groups)"
    if ! grep -F -q "$RELEASE_APP_GROUP" <<< "$groups"; then
        printf '%s signed application groups do not contain %s.\n' "$label" "$RELEASE_APP_GROUP" >&2
        exit 1
    fi
}

assert_provisioning_profile() {
    local bundle_path="$1"
    local expected_bundle_id="$2"
    local label="$3"
    local stem="$4"
    local profile_path="$bundle_path/Contents/embedded.provisionprofile"
    local decoded_profile="$work_dir/$stem-profile.plist"
    local profile_team
    local application_identifier
    local groups

    if [ ! -s "$profile_path" ]; then
        printf '%s is missing embedded.provisionprofile.\n' "$label" >&2
        exit 1
    fi
    if ! security cms -D -i "$profile_path" > "$decoded_profile"; then
        printf '%s provisioning profile cannot be decoded.\n' "$label" >&2
        exit 1
    fi
    plutil -lint "$decoded_profile" > /dev/null
    profile_team="$(plist_value "$decoded_profile" TeamIdentifier:0)"
    application_identifier="$(plist_value "$decoded_profile" Entitlements:application-identifier)"
    assert_equal "$profile_team" "$team_id" "$label provisioning Team ID"
    assert_equal "$application_identifier" "$team_id.$expected_bundle_id" "$label provisioning application-identifier"
    groups="$(plist_value "$decoded_profile" Entitlements:com.apple.security.application-groups)"
    if ! grep -F -q "$RELEASE_APP_GROUP" <<< "$groups"; then
        printf '%s provisioning profile does not contain the required App Group.\n' "$label" >&2
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
    printf 'Privacy manifest is missing required reason %s for %s.\n' "$reason" "$category" >&2
    exit 1
}

assert_privacy_manifests() {
    local app_path="$1"
    local widget_path="$2"
    local app_manifest="$app_path/Contents/Resources/PrivacyInfo.xcprivacy"
    local widget_manifest="$widget_path/Contents/Resources/PrivacyInfo.xcprivacy"

    if [ ! -s "$app_manifest" ] || ! plutil -lint "$app_manifest" > /dev/null; then
        printf '%s\n' 'App payload is missing a valid PrivacyInfo.xcprivacy.' >&2
        exit 1
    fi
    if [ ! -s "$widget_manifest" ] || ! plutil -lint "$widget_manifest" > /dev/null; then
        printf '%s\n' 'Widget payload is missing a valid PrivacyInfo.xcprivacy.' >&2
        exit 1
    fi
    assert_privacy_reason "$app_manifest" NSPrivacyAccessedAPICategoryUserDefaults CA92.1
    assert_privacy_reason "$app_manifest" NSPrivacyAccessedAPICategoryDiskSpace 85F4.1
    assert_privacy_reason "$app_manifest" NSPrivacyAccessedAPICategoryFileTimestamp C617.1
}

if [ -n "$pkg_path" ]; then
    if ! package_signature="$(pkgutil --check-signature "$pkg_path" 2>&1)"; then
        printf '%s\n' 'Mac App Store package signature is invalid.' >&2
        exit 1
    fi
    if ! grep -F -q "$team_id" <<< "$package_signature"; then
        printf '%s\n' 'Mac App Store package signature Team ID does not match.' >&2
        exit 1
    fi
    if ! grep -F -q '3rd Party Mac Developer Installer:' <<< "$package_signature" &&
       ! grep -F -q 'Mac Installer Distribution:' <<< "$package_signature"; then
        printf '%s\n' 'Mac App Store package is not signed with an installer distribution identity.' >&2
        exit 1
    fi

    expanded_package="$work_dir/expanded"
    pkgutil --expand-full "$pkg_path" "$expanded_package"

    apps_file="$work_dir/apps.txt"
    find "$expanded_package" -type d -name '*.app' -print > "$apps_file"
    app_count="$(awk 'END {print NR + 0}' "$apps_file")"
    if [ "$app_count" -ne 1 ]; then
        printf 'Mac App Store package must contain exactly one app; found %s.\n' "$app_count" >&2
        exit 1
    fi
    app_path="$(sed -n '1p' "$apps_file")"
else
    app_path="$app_input"
fi
app_info="$app_path/Contents/Info.plist"
if [ ! -s "$app_info" ]; then
    printf '%s\n' 'Mac App Store package app is missing Info.plist.' >&2
    exit 1
fi
assert_equal "$(plist_value "$app_info" CFBundleIdentifier)" "$RELEASE_APP_BUNDLE_ID" 'App bundle identifier'
assert_equal "$(plist_value "$app_info" CFBundleShortVersionString)" "$expected_version" 'App version'
assert_equal "$(plist_value "$app_info" CFBundleVersion)" "$expected_build" 'App build'

extensions_file="$work_dir/extensions.txt"
find "$app_path/Contents/PlugIns" -maxdepth 1 -type d -name '*.appex' -print > "$extensions_file"
extension_count="$(awk 'END {print NR + 0}' "$extensions_file")"
if [ "$extension_count" -ne 1 ]; then
    printf 'Mac App Store package must contain exactly one extension; found %s.\n' "$extension_count" >&2
    exit 1
fi
widget_path="$(sed -n '1p' "$extensions_file")"
widget_info="$widget_path/Contents/Info.plist"
assert_equal "$(plist_value "$widget_info" CFBundleIdentifier)" "$RELEASE_WIDGET_BUNDLE_ID" 'Widget bundle identifier'
assert_equal "$(plist_value "$widget_info" CFBundleShortVersionString)" "$expected_version" 'Widget version'
assert_equal "$(plist_value "$widget_info" CFBundleVersion)" "$expected_build" 'Widget build'

app_executable="$(plist_value "$app_info" CFBundleExecutable)"
widget_executable="$(plist_value "$widget_info" CFBundleExecutable)"
assert_universal_binary "$app_path/Contents/MacOS/$app_executable" 'Mac App Store app'
assert_universal_binary "$widget_path/Contents/MacOS/$widget_executable" 'Mac App Store widget'
assert_mas_signature "$app_path" 'Mac App Store app'
assert_mas_signature "$widget_path" 'Mac App Store widget'
assert_signature_identifier "$app_path" "$RELEASE_APP_BUNDLE_ID" 'Mac App Store app'
assert_signature_identifier "$widget_path" "$RELEASE_WIDGET_BUNDLE_ID" 'Mac App Store widget'
assert_signed_entitlements "$app_path" "$RELEASE_APP_BUNDLE_ID" 'Mac App Store app' app
assert_signed_entitlements "$widget_path" "$RELEASE_WIDGET_BUNDLE_ID" 'Mac App Store widget' widget
assert_provisioning_profile "$app_path" "$RELEASE_APP_BUNDLE_ID" 'Mac App Store app' app
assert_provisioning_profile "$widget_path" "$RELEASE_WIDGET_BUNDLE_ID" 'Mac App Store widget' widget
assert_privacy_manifests "$app_path" "$widget_path"

if [ -n "$(find "$app_path" -type f -name '*.storekit' -print -quit)" ]; then
    printf '%s\n' 'Production payload must not contain a StoreKit test configuration.' >&2
    exit 1
fi

if [ -e "$app_path/Contents/Library/LaunchServices/$RELEASE_HELPER_EXECUTABLE_NAME" ] ||
   [ -d "$app_path/Contents/Library/LaunchDaemons" ]; then
    printf '%s\n' 'Mac App Store package contains a prohibited privileged component.' >&2
    exit 1
fi
if strings "$app_path/Contents/MacOS/$app_executable" | grep -F -q "$RELEASE_HELPER_SERVICE_ID"; then
    printf '%s\n' 'Mac App Store executable references the Direct-only helper service.' >&2
    exit 1
fi

if [ -n "$pkg_path" ]; then
    printf 'Mac App Store package validation passed: %s\n' "$pkg_path"
else
    printf 'Mac App Store archive app validation passed: %s\n' "$app_path"
fi
