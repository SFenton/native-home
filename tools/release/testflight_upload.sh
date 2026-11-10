#!/usr/bin/env bash
# Archives S+H (FentonHome, Release) and uploads the build to App Store Connect for TestFlight. This is the owner's manual local
# fallback: the release pipeline (.github/workflows/ios-release.yml) uploads every bumped version itself, through
# `ios_ipa_build.sh --upload`, from the same archive as the IPA artifact.
#
# Usage: tools/release/testflight_upload.sh [--tag ios/v<YYMM.DD.NN>] [--build N] [--source DIR] [--dry-run]
#          [--no-devcap] [--asc-key-path P --asc-key-id ID --asc-issuer-id ISSUER]
#   --tag    the version to stamp (default: the newest ios/v* tag; the tag only names the version, the code built is
#            the checkout, so HassGitSHA is this checkout's HEAD, not the tag's commit)
#   --build  CURRENT_PROJECT_VERSION (default: UTC time as YYYYMMDDHHMM; it must grow with every upload of a version)
#   --source the checkout to build (default: this one); CI passes a worktree of the tag. The tooling (this script,
#            devcap, the ExportOptions plist) always comes from the checkout the script lives in.
#   --no-devcap  run xcodebuild directly, with no tools/devcap.py hold (a runner that is not shared with other work)
#   --asc-*  App Store Connect API key: signs with cloud-managed certificates and profiles and uploads with the key, so
#            no Apple ID is needed (env ASC_KEY_PATH, ASC_KEY_ID, ASC_ISSUER_ID are the defaults; all three or none)
#   --dry-run  prints the commands instead of running them
# Output: build/testflight/ (FentonHome.xcarchive, export/ and the xcodebuild logs). The last lines say what was uploaded.
# Signing: automatic, team 3Q9X8JX23S; the Apple ID signed in to Xcode (or the API key) lets -allowProvisioningUpdates
# create the distribution certificate and profiles. Needs a password, 2FA or a Keychain prompt? It stops there: do that
# step yourself. Heavy steps run in a tools/devcap.py `build` hold. Never creates or pushes a tag (versions come from
# tools/release/versioning.py). Documentation: .agents/platforms/apple/testflight.md.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
TAG=""; BUILD="$(date -u +%Y%m%d%H%M)"; DRY=0; SRC=""; DEVCAP=1
KEY_PATH="${ASC_KEY_PATH:-}"; KEY_ID="${ASC_KEY_ID:-}"; KEY_ISSUER="${ASC_ISSUER_ID:-}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --tag) TAG="${2:?--tag needs a value}"; shift 2 ;;
    --build) BUILD="${2:?--build needs a value}"; shift 2 ;;
    --source) SRC="${2:?--source needs a value}"; shift 2 ;;
    --no-devcap) DEVCAP=0; shift ;;
    --asc-key-path) KEY_PATH="${2:?--asc-key-path needs a value}"; shift 2 ;;
    --asc-key-id) KEY_ID="${2:?--asc-key-id needs a value}"; shift 2 ;;
    --asc-issuer-id) KEY_ISSUER="${2:?--asc-issuer-id needs a value}"; shift 2 ;;
    --dry-run) DRY=1; shift ;;
    *) echo "usage: testflight_upload.sh [--tag ios/v…] [--build N] [--source DIR] [--no-devcap] [--asc-key-path P --asc-key-id ID --asc-issuer-id ISSUER] [--dry-run]" >&2; exit 2 ;;
  esac
done
[[ "$BUILD" =~ ^[1-9][0-9]*$ ]] || { echo "[testflight] --build must be a positive integer, got '$BUILD'" >&2; exit 2; }
SRC="${SRC:-$ROOT}"
[[ -d "$SRC/apple" ]] || { echo "[testflight] --source $SRC has no apple/ folder" >&2; exit 2; }
# The API key is all or nothing; its parts are never printed (the key file is read by xcodebuild only).
AUTH=()
if [[ -n "$KEY_PATH$KEY_ID$KEY_ISSUER" ]]; then
  [[ -n "$KEY_PATH" && -n "$KEY_ID" && -n "$KEY_ISSUER" ]] || { echo "[testflight] the API key needs a path, a key id and an issuer id" >&2; exit 2; }
  [[ $DRY == 1 || -f "$KEY_PATH" ]] || { echo "[testflight] API key file not found" >&2; exit 2; }
  AUTH=(-authenticationKeyPath "$KEY_PATH" -authenticationKeyID "$KEY_ID" -authenticationKeyIssuerID "$KEY_ISSUER")
fi
if [[ -z "$TAG" ]]; then
  TAG="$(git -C "$ROOT" tag -l 'ios/v*' --sort=-v:refname | head -n 1)"
  [[ -n "$TAG" ]] || { echo "[testflight] no ios/v* tag; fetch tags or pass --tag" >&2; exit 2; }
fi

OUT="$ROOT/build/testflight"; ARCHIVE="$OUT/FentonHome.xcarchive"
# A dry run never prints HASS_DEFAULT_SERVER's value (the repository is public, so is the job log): it shows ***.
redact() { if [[ -n "${HASS_DEFAULT_SERVER:-}" && "$1" == "HASS_DEFAULT_SERVER=$HASS_DEFAULT_SERVER" ]]; then echo "HASS_DEFAULT_SERVER=***"; else printf '%s' "$1"; fi; }
run() { if [[ $DRY == 1 ]]; then printf '+'; local arg; for arg in "$@"; do printf ' %q' "$(redact "$arg")"; done; printf '\n'; else "$@"; fi; }

# Version settings from the tag, with the checkout's own commit as HassGitSHA.
SETTINGS=()
if [[ $DRY == 1 ]]; then SETTINGS=("MARKETING_VERSION=${TAG#ios/v}" "CURRENT_PROJECT_VERSION=$BUILD" "HASS_GIT_SHA=<head>")
else
  while IFS= read -r line; do
    [[ -z "$line" || "$line" == HASS_GIT_SHA=* ]] || SETTINGS+=("$line")
  done < <(python3 "$ROOT/tools/release/versioning.py" --repo "$ROOT" build-settings --tag "$TAG" --build "$BUILD")
  [[ ${#SETTINGS[@]} -ge 2 ]] || { echo "[testflight] versioning.py returned no settings for $TAG" >&2; exit 1; }
  SETTINGS+=("HASS_GIT_SHA=$(git -C "$SRC" rev-parse HEAD)")
fi
# The sign-in Server field default is read from HASS_DEFAULT_SERVER, which a manual upload reads from the owner's shell; the
# hosted pipeline never sets it, so its artifact builds with a blank Server field. Empty leaves the field blank.
[[ -z "${HASS_DEFAULT_SERVER:-}" ]] || SETTINGS+=("HASS_DEFAULT_SERVER=$HASS_DEFAULT_SERVER")
shown=(); for line in "${SETTINGS[@]}"; do shown+=("$(redact "$line")"); done
echo "[testflight] ${shown[*]}"

[[ $DRY == 1 ]] || { rm -rf "$OUT"; mkdir -p "$OUT"; }
cd "$SRC/apple"
run xcodegen generate --quiet

# Heavy steps hold a devcap build slot unless --no-devcap (an unshared runner).
held() { local hold="$1" purpose="$2"; shift 2
  if [[ $DEVCAP == 1 ]]; then run python3 "$ROOT/tools/devcap.py" run --pool build --hold "$hold" --purpose "$purpose" -- "$@"
  else run "$@"; fi; }

held 3600 "testflight archive $TAG" \
  xcodebuild archive -project FentonHome.xcodeproj -scheme FentonHome -configuration Release \
    -destination 'generic/platform=iOS' -archivePath "$ARCHIVE" -derivedDataPath "$OUT/DerivedData" \
    -allowProvisioningUpdates ${AUTH[@]+"${AUTH[@]}"} "${SETTINGS[@]}"

# destination=upload sends the signed build straight to App Store Connect.
held 1800 "testflight upload $TAG" \
  xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$OUT/export" \
    -exportOptionsPlist "$ROOT/tools/release/ExportOptions-testflight.plist" -allowProvisioningUpdates \
    ${AUTH[@]+"${AUTH[@]}"}
[[ $DRY == 1 ]] || echo "[testflight] uploaded ${TAG#ios/v} (${BUILD}) to App Store Connect; it shows in TestFlight after processing"
