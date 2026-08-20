#!/bin/bash

set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

paths_file="$(mktemp "${TMPDIR:-/tmp}/coolcumber-tracked-paths.XXXXXX")"
matches_file="$(mktemp "${TMPDIR:-/tmp}/coolcumber-secret-matches.XXXXXX")"
app_password_candidates="$(mktemp "${TMPDIR:-/tmp}/coolcumber-app-password-candidates.XXXXXX")"

cleanup() {
    rm -f "$paths_file" "$matches_file" "$app_password_candidates"
}
trap cleanup EXIT

if ! command -v perl > /dev/null 2>&1; then
    printf '%s\n' 'Secret scan requires Perl on the macOS runner.' >&2
    exit 1
fi

git ls-files --cached -z > "$paths_file"

found_forbidden_path=0
while IFS= read -r -d '' tracked_path; do
    lower_path="$(printf '%s' "$tracked_path" | tr '[:upper:]' '[:lower:]')"

    case "$lower_path" in
        .env|.env.*|*/.env|*/.env.*)
            case "$lower_path" in
                .env.example|*/.env.example)
                    continue
                    ;;
            esac
            ;;
        *app-specific*password*|*app_specific_password*)
            ;;
        *.p8|*.p12|*.pfx|*.pem|*.key|*.cer|*.crt|*.certsigningrequest|*.mobileprovision|*.provisionprofile)
            ;;
        *.pkg|*.dmg|*.zip|*.tgz|*.tar.gz|*.xcarchive|*.xcarchive/*)
            ;;
        *)
            continue
            ;;
    esac

    printf 'Forbidden tracked credential or release artifact: %s\n' "$tracked_path" >&2
    found_forbidden_path=1
done < "$paths_file"

if [ "$found_forbidden_path" -ne 0 ]; then
    printf '%s\n' 'Secret scan failed: credentials, certificates, private keys, and release packages must stay outside Git.' >&2
    exit 1
fi

# Print filenames only. Secret values must never be echoed into CI logs.
content_pattern='-----BEGIN ([A-Z0-9 ]* )?PRIVATE KEY-----|gh[pousr]_[A-Za-z0-9]{36,}'
if git grep --cached -I -l -E -e "$content_pattern" -- . > "$matches_file"; then
    printf '%s\n' 'Potential secret material found in tracked files:' >&2
    sed 's/^/  - /' "$matches_file" >&2
    printf '%s\n' 'Secret scan failed. Remove the material from Git and rotate any credential that was exposed.' >&2
    exit 1
else
    grep_status=$?
    if [ "$grep_status" -ne 1 ]; then
        printf 'Secret scan could not inspect the Git index (git grep exit %s).\n' "$grep_status" >&2
        exit "$grep_status"
    fi
fi

# Apple's documentation commonly uses xxxx-xxxx-xxxx-xxxx as a harmless
# placeholder. Inspect candidate blobs without ever printing their contents and
# reject every other value with the same app-specific-password shape.
app_password_pattern='[a-z0-9]{4}(-[a-z0-9]{4}){3}'
if git grep --cached -I -l -E -e "$app_password_pattern" -- . > "$app_password_candidates"; then
    while IFS= read -r candidate_path; do
        if git show ":$candidate_path" | perl -0777 -e '
            my $content = do { local $/; <STDIN> };
            while ($content =~ /(?<![a-z0-9])([a-z0-9]{4}(?:-[a-z0-9]{4}){3})(?![a-z0-9])/g) {
                exit 0 if $1 ne "xxxx-xxxx-xxxx-xxxx";
            }
            exit 1;
        '; then
            printf 'Potential Apple app-specific password found in: %s\n' "$candidate_path" >&2
            printf '%s\n' 'Secret scan failed. Remove the material from Git and rotate the credential.' >&2
            exit 1
        else
            candidate_status=$?
            if [ "$candidate_status" -ne 1 ]; then
                printf 'Secret scan could not inspect indexed file: %s\n' "$candidate_path" >&2
                exit "$candidate_status"
            fi
        fi
    done < "$app_password_candidates"
else
    candidate_grep_status=$?
    if [ "$candidate_grep_status" -ne 1 ]; then
        printf 'Secret scan could not search for app-specific passwords (git grep exit %s).\n' "$candidate_grep_status" >&2
        exit "$candidate_grep_status"
    fi
fi

printf '%s\n' 'Secret scan passed: no prohibited tracked files or recognizable secret material.'
