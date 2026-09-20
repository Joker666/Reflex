#!/bin/zsh

set -euo pipefail

script_directory=${0:A:h}
project_directory=${script_directory:h}
team_id=${DEVELOPMENT_TEAM_ID:-FA8NWUSJ95}
developer_id_identity=${DEVELOPER_ID_IDENTITY:-Developer ID Application}
notary_profile=${NOTARY_PROFILE:-}
api_key_path=${APPLE_API_KEY_PATH:-}
api_key_id=${APPLE_API_KEY_ID:-}
api_issuer_id=${APPLE_API_ISSUER_ID:-}
output_directory=${OUTPUT_DIRECTORY:-${project_directory}/dist}
temporary_directory=$(mktemp -d "${TMPDIR%/}/ReflexDistribution.XXXXXX")
archive_path="${temporary_directory}/Reflex.xcarchive"
unsigned_zip="${temporary_directory}/Reflex-notarization.zip"

cleanup() {
    rm -rf "${temporary_directory}"
}
trap cleanup EXIT

fail() {
    print -u2 "error: $1"
    exit 1
}

command -v xcodebuild >/dev/null || fail "Xcode command-line tools are not available."
command -v xcrun >/dev/null || fail "xcrun is not available."

if ! security find-identity -v -p codesigning | rg -Fq "\"${developer_id_identity}"; then
    fail "No '${developer_id_identity}' certificate with a private key is available. Create a Developer ID Application certificate in the Apple Developer account and install it in Keychain."
fi

notary_arguments=()
if [[ -n "${notary_profile}" ]]; then
    notary_arguments=(--keychain-profile "${notary_profile}")
elif [[ -n "${api_key_path}" && -n "${api_key_id}" && -n "${api_issuer_id}" ]]; then
    [[ -f "${api_key_path}" ]] || fail "APPLE_API_KEY_PATH does not point to a file."
    notary_arguments=(--key "${api_key_path}" --key-id "${api_key_id}" --issuer "${api_issuer_id}")
else
    fail "Set NOTARY_PROFILE, or set APPLE_API_KEY_PATH, APPLE_API_KEY_ID, and APPLE_API_ISSUER_ID."
fi

cd "${project_directory}"
xcodebuild \
    -project Reflex.xcodeproj \
    -scheme Reflex \
    -destination 'platform=macOS' \
    test \
    CODE_SIGNING_ALLOWED=NO \
    -quiet

xcodebuild \
    -project Reflex.xcodeproj \
    -scheme Reflex \
    -configuration Release \
    -destination 'generic/platform=macOS' \
    -archivePath "${archive_path}" \
    archive \
    DEVELOPMENT_TEAM="${team_id}" \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="${developer_id_identity}" \
    CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
    ENABLE_HARDENED_RUNTIME=YES \
    OTHER_CODE_SIGN_FLAGS=--timestamp \
    -quiet

app_path="${archive_path}/Products/Applications/Reflex.app"
[[ -d "${app_path}" ]] || fail "The archive did not contain Reflex.app."

codesign --verify --deep --strict --verbose=2 "${app_path}"
ditto -c -k --keepParent "${app_path}" "${unsigned_zip}"
xcrun notarytool submit "${unsigned_zip}" \
    "${notary_arguments[@]}" \
    --wait
xcrun stapler staple "${app_path}"
xcrun stapler validate "${app_path}"
spctl --assess --type execute --verbose=2 "${app_path}"

version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${app_path}/Contents/Info.plist")
build=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "${app_path}/Contents/Info.plist")
mkdir -p "${output_directory}"
output_zip="${output_directory}/Reflex-${version}-${build}.zip"
ditto -c -k --keepParent "${app_path}" "${output_zip}"
shasum -a 256 "${output_zip}" | tee "${output_zip}.sha256"
print "Created notarized distribution: ${output_zip}"
