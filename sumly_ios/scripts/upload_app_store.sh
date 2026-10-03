#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
IOS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG_FILE="${SUMLY_ASC_CONFIG:-$HOME/.config/sumly/appstore-connect.env}"
if [[ ! -f "$CONFIG_FILE" && -f "$IOS_DIR/.appstore-connect.env" ]]; then
  CONFIG_FILE="$IOS_DIR/.appstore-connect.env"
fi

if [[ -f "$CONFIG_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$CONFIG_FILE"
fi

: "${ASC_KEY_ID:?Missing ASC_KEY_ID. Put it in $CONFIG_FILE or export it in the shell.}"
: "${ASC_ISSUER_ID:?Missing ASC_ISSUER_ID. Put it in $CONFIG_FILE or export it in the shell.}"

ASC_KEY_PATH="${ASC_KEY_PATH:-$HOME/.private_keys/AuthKey_${ASC_KEY_ID}.p8}"

if [[ ! -f "$ASC_KEY_PATH" ]]; then
  echo "App Store Connect private key not found: $ASC_KEY_PATH" >&2
  exit 1
fi

if [[ ! -r "$ASC_KEY_PATH" ]]; then
  echo "App Store Connect private key is not readable: $ASC_KEY_PATH" >&2
  exit 1
fi

if [[ "${1:-}" == "--check-auth" ]]; then
  xcrun altool --list-apps \
    --api-key "$ASC_KEY_ID" \
    --api-issuer "$ASC_ISSUER_ID" \
    --p8-file-path "$ASC_KEY_PATH" >/dev/null
  echo "App Store Connect API Key authentication succeeded."
  exit 0
fi

upload_ipa() {
  echo "Uploading signed IPA with JWT-signed App Store Connect API requests..."
  export ASC_KEY_ID ASC_ISSUER_ID ASC_KEY_PATH
  local upload_args=("$1")
  if [[ "$#" == "3" ]]; then upload_args+=(--expected-version "$2" --expected-build "$3"); fi
  if [[ "${SUMLY_UPLOAD_DIRECT:-0}" == "1" ]]; then upload_args+=(--direct); fi
  python3 "$SCRIPT_DIR/upload_signed_ipa.py" "${upload_args[@]}"
}

if [[ "${1:-}" == "--ipa" ]]; then
  : "${2:?Usage: upload_app_store.sh --ipa /path/to/signed.ipa}"
  [[ -f "$2" ]] || { echo "Signed IPA does not exist: $2" >&2; exit 1; }
  upload_ipa "$2"
  exit 0
fi
if [[ -n "${1:-}" ]]; then
  echo "Usage: upload_app_store.sh [--check-auth | --ipa /path/to/signed.ipa]" >&2
  exit 2
fi

cd "$IOS_DIR"

xcodegen generate >/dev/null

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Sumly/Support/Info.plist)"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' Sumly/Support/Info.plist)"
ARCHIVE_PATH="build/Sumly-${VERSION}-b${BUILD}.xcarchive"
EXPORT_PATH="build/ipa-b${BUILD}"

mkdir -p build
if [[ -f "$EXPORT_PATH/Sumly.asc-upload-state.json" ]]; then
  [[ -f "$EXPORT_PATH/Sumly.ipa" ]] || { echo "Recovery state exists but its signed IPA is missing; preserve the state and inspect before rebuilding." >&2; exit 1; }
  echo "Resuming existing signed Sumly ${VERSION} (${BUILD})..."
  upload_ipa "$EXPORT_PATH/Sumly.ipa" "$VERSION" "$BUILD"
  exit 0
fi
rm -rf "$ARCHIVE_PATH" "$EXPORT_PATH"

echo "Archiving Sumly ${VERSION} (${BUILD})..."
xcodebuild   -project Sumly.xcodeproj   -scheme Sumly   -configuration Release   -destination 'generic/platform=iOS'   -archivePath "$ARCHIVE_PATH"   -allowProvisioningUpdates   -authenticationKeyPath "$ASC_KEY_PATH"   -authenticationKeyID "$ASC_KEY_ID"   -authenticationKeyIssuerID "$ASC_ISSUER_ID"   archive

echo "Exporting locally signed Sumly ${VERSION} (${BUILD})..."
xcodebuild -exportArchive -archivePath "$ARCHIVE_PATH" -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist "$SCRIPT_DIR/ExportOptions-upload.plist"

upload_ipa "$EXPORT_PATH/Sumly.ipa" "$VERSION" "$BUILD"
echo "Upload and processing completed for Sumly ${VERSION} (${BUILD})."
