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
dmg_staging_directory="${temporary_directory}/dmg"
notarization_dmg="${temporary_directory}/Reflex.dmg"

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

if ! security find-identity -v -p codesigning | grep -Fq "\"${developer_id_identity}"; then
    fail "No '${developer_id_identity}' certificate with a private key is available. Create a Developer ID Application certificate in the Apple Developer account and install it in Keychain."
fi

notary_arguments=()
if [[ -n "${notary_profile}" ]]; then
    notary_arguments=(--keychain-profile "${notary_profile}")
elif [[ -n "${api_key_path}" && -n "${api_key_id}" ]]; then
    [[ -f "${api_key_path}" ]] || fail "APPLE_API_KEY_PATH does not point to a file."
    notary_arguments=(--key "${api_key_path}" --key-id "${api_key_id}")
    if [[ -n "${api_issuer_id}" ]]; then
        notary_arguments+=(--issuer "${api_issuer_id}")
    fi
else
    fail "Set NOTARY_PROFILE, or set APPLE_API_KEY_PATH and APPLE_API_KEY_ID. A team API key also requires APPLE_API_ISSUER_ID."
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
mkdir -p "${dmg_staging_directory}"
ditto "${app_path}" "${dmg_staging_directory}/Reflex.app"
ln -s /Applications "${dmg_staging_directory}/Applications"
hdiutil create \
    -volname Reflex \
    -srcfolder "${dmg_staging_directory}" \
    -ov \
    -format UDZO \
    "${notarization_dmg}"
codesign --force --sign "${developer_id_identity}" --timestamp "${notarization_dmg}"
codesign --verify --verbose=2 "${notarization_dmg}"
xcrun notarytool submit "${notarization_dmg}" \
    "${notary_arguments[@]}" \
    --wait
xcrun stapler staple "${notarization_dmg}"
xcrun stapler validate "${notarization_dmg}"
spctl --assess --type open --context context:primary-signature --verbose=2 "${notarization_dmg}"
hdiutil verify "${notarization_dmg}"

version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${app_path}/Contents/Info.plist")
build=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "${app_path}/Contents/Info.plist")
mkdir -p "${output_directory}"
output_dmg="${output_directory}/Reflex-${version}-${build}.dmg"
ditto "${notarization_dmg}" "${output_dmg}"
xcrun stapler validate "${output_dmg}"
shasum -a 256 "${output_dmg}" | tee "${output_dmg}.sha256"
print "Created notarized distribution: ${output_dmg}"
