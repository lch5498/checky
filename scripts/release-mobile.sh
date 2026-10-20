#!/usr/bin/env bash
# macOS Bash 3.2 compatible. No App Store review or Play production rollout.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MOBILE_DIR="$ROOT_DIR/apps/mobile"
STATE_DIR="$ROOT_DIR/.release-state"
PLATFORM="all"
MODE="release"
FORMAT="appbundle"
API_BASE_URL="${API_BASE_URL:-https://favis.vercel.app}"
KAKAO_NATIVE_APP_KEY="${KAKAO_NATIVE_APP_KEY:-471d534ffd886dcada787e331f059cb7}"
BUILD_NAME="${BUILD_NAME:-}"
BUILD_NUMBER="${BUILD_NUMBER:-}"
RUN_CLEAN=0
RUN_ANALYZE=1
RUN_TEST=1
BUILD_ONLY=0
UPLOAD_ONLY=0
AUTO_INCREMENT=1
DRY_RUN=0
IPA_PATH=""
AAB_PATH=""
EXPORT_OPTIONS=""
ANDROID_STATUS="completed"
LOCKED=0
BUILD_MARKER=""
IOS_RESULT="not requested"
ANDROID_RESULT="not requested"

usage() {
  cat <<'USAGE'
Usage: scripts/release-mobile.sh [options]

Default: build + upload both platforms. iOS uploads to App Store Connect only;
Android publishes to INTERNAL TESTING only. No production rollout or App Store review.

  --platform <ios|android|all>         Default: all
  --build-name <x.y.z>                Default: pubspec.yaml version name
  --build-number <integer>            Explicit number (must be unused on the stores)
  --no-increment                      Use pubspec number instead of auto-increment
  --clean                             Run flutter clean once
  --no-analyze                        Skip design check and flutter analyze
  --no-test                           Skip flutter test
  --build-only                        Build without upload (no store keys/fastlane needed)
  --upload-only                       Upload explicit --ipa/--aab; do not rebuild
  --ipa <file>                        IPA for --upload-only
  --aab <file>                        AAB for --upload-only
  --android-status <completed|draft>   Internal testing release status; default: completed
  --export-options-plist <file>        Optional iOS export options (signing)
  --mode <debug|profile|release>       Android build-only; default: release
  --format <apk|appbundle|aab>         Android build-only; default: appbundle
  --api-base-url <url>                Default: https://favis.vercel.app
  --kakao-native-app-key <key>         Native key (without kakao prefix)
  --dry-run                           Show plan; no build, upload, or state writes
  -h, --help                          Show help

Credentials (export in your shell; see docs/mobile-release.md):
  ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_FILE (.p8)
  GOOGLE_PLAY_JSON_KEY (service account JSON)

If --build-number is omitted, reserves max(pubspec number, local last number)+1.
pubspec.yaml is NOT edited. Store version codes are not queried; for another
machine/manual uploads, supply a number higher than all previous uploads.
USAGE
}

fail() { echo "Error: $*" >&2; exit 1; }
require_value() { [[ $# -ge 2 && -n "$2" && "$2" != --* ]] || fail "$1 requires a value"; }
need_command() { command -v "$1" >/dev/null 2>&1 || fail "Required command not found: $1"; }
absolute_file() {
  [[ -f "$1" && -s "$1" && -r "$1" ]] || fail "Missing, empty or unreadable file: $1"
  (cd "$(dirname "$1")" && printf '%s/%s\n' "$(pwd -P)" "$(basename "$1")")
}
valid_number() { [[ "$1" =~ ^[1-9][0-9]*$ && ${#1} -le 10 && "$1" -le 2100000000 ]]; }
fresh_artifact() {
  # macOS /bin/bash 3.2's -nt comparison can truncate sub-second timestamps.
  [[ -s "$1" && -n "$(find "$1" -newer "$BUILD_MARKER" -print)" ]]
}
run() {
  printf '==>'
  printf ' %q' "$@"
  printf '\n'
  if [[ "$DRY_RUN" -eq 0 ]]; then "$@"; fi
}
cleanup() {
  local status=$?
  [[ -z "$BUILD_MARKER" ]] || rm -f "$BUILD_MARKER"
  if [[ "$LOCKED" -eq 1 ]]; then rmdir "$STATE_DIR/lock"; fi
  if [[ "$DRY_RUN" -eq 0 ]]; then
    echo "==> iOS: $IOS_RESULT"
    echo "==> Android: $ANDROID_RESULT"
    if [[ "$status" -ne 0 ]]; then
      echo "Stopped. Already completed uploads are NOT rolled back. Retry only the failed platform with --upload-only and its explicit artifact." >&2
    fi
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --platform|--mode|--format|--build-name|--build-number|--api-base-url|--kakao-native-app-key|--ipa|--aab|--export-options-plist|--android-status)
      require_value "$@"
      case "$1" in
        --platform) PLATFORM="$2" ;;
        --mode) MODE="$2" ;;
        --format) FORMAT="$2" ;;
        --build-name) BUILD_NAME="$2" ;;
        --build-number) BUILD_NUMBER="$2" ;;
        --api-base-url) API_BASE_URL="$2" ;;
        --kakao-native-app-key) KAKAO_NATIVE_APP_KEY="$2" ;;
        --ipa) IPA_PATH="$2" ;;
        --aab) AAB_PATH="$2" ;;
        --export-options-plist) EXPORT_OPTIONS="$2" ;;
        --android-status) ANDROID_STATUS="$2" ;;
      esac
      shift 2 ;;
    --clean) RUN_CLEAN=1; shift ;;
    --no-analyze) RUN_ANALYZE=0; shift ;;
    --no-test) RUN_TEST=0; shift ;;
    --build-only) BUILD_ONLY=1; shift ;;
    --upload-only) UPLOAD_ONLY=1; shift ;;
    --no-increment) AUTO_INCREMENT=0; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) fail "Unknown option: $1 (see --help)" ;;
  esac
done

case "$PLATFORM" in ios|android|all) ;; *) fail "Invalid --platform: $PLATFORM" ;; esac
case "$MODE" in debug|profile|release) ;; *) fail "Invalid --mode: $MODE" ;; esac
case "$FORMAT" in apk|appbundle|aab) ;; *) fail "Invalid --format: $FORMAT" ;; esac
case "$ANDROID_STATUS" in completed|draft) ;; *) fail "Only internal completed/draft releases are supported" ;; esac
[[ "$FORMAT" != aab ]] || FORMAT=appbundle
[[ "$BUILD_ONLY" -eq 0 || "$UPLOAD_ONLY" -eq 0 ]] || fail "--build-only and --upload-only are mutually exclusive"
if [[ "$BUILD_ONLY" -eq 0 || "$PLATFORM" != android ]]; then
  [[ "$MODE" == release && "$FORMAT" == appbundle ]] || fail "--mode/--format overrides are only supported for Android --build-only"
fi
if [[ "$UPLOAD_ONLY" -eq 1 ]]; then
  [[ "$RUN_CLEAN" -eq 0 && -z "$BUILD_NAME$BUILD_NUMBER$EXPORT_OPTIONS" ]] || fail "--upload-only cannot clean, sign or change the artifact version"
  [[ "$PLATFORM" == android || -n "$IPA_PATH" ]] || fail "--upload-only requires --ipa for iOS"
  [[ "$PLATFORM" == ios || -n "$AAB_PATH" ]] || fail "--upload-only requires --aab for Android"
  [[ -z "$IPA_PATH" || "$PLATFORM" != android ]] || fail "--ipa requires ios/all"
  [[ -z "$AAB_PATH" || "$PLATFORM" != ios ]] || fail "--aab requires android/all"
else
  [[ -z "$IPA_PATH$AAB_PATH" ]] || fail "--ipa/--aab require --upload-only"
  [[ -n "$API_BASE_URL" && -n "$KAKAO_NATIVE_APP_KEY" ]] || fail "API URL and Kakao native key are required"
  KAKAO_NATIVE_APP_KEY="${KAKAO_NATIVE_APP_KEY#kakao}"
  [[ -n "$KAKAO_NATIVE_APP_KEY" ]] || fail "Empty Kakao native key"
  [[ "$API_BASE_URL" == https://* || "$BUILD_ONLY" -eq 1 ]] || fail "Uploads require an HTTPS API URL"
fi
if [[ -n "$EXPORT_OPTIONS" ]]; then
  [[ "$PLATFORM" != android ]] || fail "iOS export options require ios/all"
  EXPORT_OPTIONS="$(absolute_file "$EXPORT_OPTIONS")"
fi
if [[ -n "$IPA_PATH" ]]; then
  [[ "$IPA_PATH" == *.ipa ]] || fail "--ipa must be an .ipa file"
  IPA_PATH="$(absolute_file "$IPA_PATH")"
fi
if [[ -n "$AAB_PATH" ]]; then
  [[ "$AAB_PATH" == *.aab ]] || fail "--aab must be an .aab file"
  AAB_PATH="$(absolute_file "$AAB_PATH")"
fi

# Validate both platforms before a costly build or any store mutation.
if [[ "$DRY_RUN" -eq 0 ]]; then
  if [[ "$UPLOAD_ONLY" -eq 0 ]]; then
    need_command flutter
    if [[ "$PLATFORM" != android ]]; then
      [[ "$(uname -s)" == Darwin ]] || fail "iOS builds require macOS"
      need_command xcrun
    fi
    if [[ "$PLATFORM" != ios && "$MODE" == release ]]; then
      KEY_PROPERTIES_FILE="$MOBILE_DIR/android/key.properties"
      [[ -f "$KEY_PROPERTIES_FILE" ]] || fail "Missing Android signing file: $KEY_PROPERTIES_FILE"
      property_value() { sed -n "s/^$1=//p" "$KEY_PROPERTIES_FILE" | tail -n 1 | tr -d '\r'; }
      for key in storePassword keyPassword keyAlias storeFile; do
        [[ -n "$(property_value "$key")" ]] || fail "Missing $key in Android key.properties"
      done
      STORE_FILE="$(property_value storeFile)"
      [[ "$STORE_FILE" = /* ]] || STORE_FILE="$MOBILE_DIR/android/$STORE_FILE"
      [[ -f "$STORE_FILE" ]] || fail "Android upload keystore not found"
    fi
  fi
  if [[ "$BUILD_ONLY" -eq 0 ]]; then
    need_command fastlane
    if [[ "$PLATFORM" != android ]]; then
      [[ -n "${ASC_KEY_ID:-}" && -n "${ASC_ISSUER_ID:-}" && -n "${ASC_KEY_FILE:-}" ]] || fail "Set ASC_KEY_ID, ASC_ISSUER_ID and ASC_KEY_FILE (see docs/mobile-release.md)"
      ASC_KEY_FILE="$(absolute_file "$ASC_KEY_FILE")"
      export ASC_KEY_FILE
    fi
    if [[ "$PLATFORM" != ios ]]; then
      [[ -n "${GOOGLE_PLAY_JSON_KEY:-}" ]] || fail "Set GOOGLE_PLAY_JSON_KEY (see docs/mobile-release.md)"
      GOOGLE_PLAY_JSON_KEY="$(absolute_file "$GOOGLE_PLAY_JSON_KEY")"
      export GOOGLE_PLAY_JSON_KEY
    fi
  fi
fi

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
if [[ "$DRY_RUN" -eq 0 ]]; then
  mkdir -p "$STATE_DIR"
  mkdir "$STATE_DIR/lock" 2>/dev/null || fail "Another release is running (or stale .release-state/lock; see docs)"
  LOCKED=1
fi

if [[ "$UPLOAD_ONLY" -eq 0 ]]; then
  PUBSPEC_VERSION="$(awk '/^version:[[:space:]]/ {print $2; exit}' "$MOBILE_DIR/pubspec.yaml" | tr -d "\"'")"
  [[ "$PUBSPEC_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+\+[1-9][0-9]*$ ]] || fail "Expected pubspec version: x.y.z+integer"
  BUILD_NAME="${BUILD_NAME:-${PUBSPEC_VERSION%+*}}"
  [[ "$BUILD_NAME" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "--build-name must be x.y.z"
  if [[ -z "$BUILD_NUMBER" ]]; then
    BUILD_NUMBER="${PUBSPEC_VERSION##*+}"
    valid_number "$BUILD_NUMBER" || fail "Invalid pubspec build number"
    if [[ "$AUTO_INCREMENT" -eq 1 ]]; then
      LAST_NUMBER=0
      if [[ -f "$STATE_DIR/build-number" ]]; then
        LAST_NUMBER="$(<"$STATE_DIR/build-number")"
        valid_number "$LAST_NUMBER" || fail "Invalid local release state"
      fi
      [[ "$LAST_NUMBER" -le "$BUILD_NUMBER" ]] || BUILD_NUMBER="$LAST_NUMBER"
      BUILD_NUMBER=$((BUILD_NUMBER + 1))
    fi
  fi
  valid_number "$BUILD_NUMBER" || fail "--build-number must be 1..2100000000 (no leading zeros)"
  echo "==> Version: $BUILD_NAME ($BUILD_NUMBER); platform: $PLATFORM"
  if [[ "$DRY_RUN" -eq 0 ]]; then
    # Reserve before building, even on failure. Never reuse a partially uploaded number.
    LAST_NUMBER=0
    if [[ -f "$STATE_DIR/build-number" ]]; then
      LAST_NUMBER="$(<"$STATE_DIR/build-number")"
      valid_number "$LAST_NUMBER" || fail "Invalid local release state"
    fi
    if [[ "$BUILD_NUMBER" -gt "$LAST_NUMBER" ]]; then
      printf '%s\n' "$BUILD_NUMBER" > "$STATE_DIR/build-number.tmp"
      mv "$STATE_DIR/build-number.tmp" "$STATE_DIR/build-number"
    fi
  fi
  cd "$MOBILE_DIR"
  [[ "$RUN_CLEAN" -eq 0 ]] || run flutter clean
  run flutter pub get
  if [[ "$RUN_ANALYZE" -eq 1 ]]; then
    run dart tool/check_design.dart
    run flutter analyze
  fi
  [[ "$RUN_TEST" -eq 0 ]] || run flutter test
  if [[ "$DRY_RUN" -eq 0 ]]; then BUILD_MARKER="$(mktemp "${TMPDIR:-/tmp}/checky-release.XXXXXX")"; fi
  COMMON_ARGS=("--dart-define=API_BASE_URL=$API_BASE_URL" "--dart-define=KAKAO_NATIVE_APP_KEY=$KAKAO_NATIVE_APP_KEY" "--build-name=$BUILD_NAME" "--build-number=$BUILD_NUMBER")

  # Build both first: a failure on one platform must not upload the other yet.
  if [[ "$PLATFORM" != android ]]; then
    IOS_RESULT="build failed"
    IOS_ARGS=(ipa --release "${COMMON_ARGS[@]}")
    if [[ -n "$EXPORT_OPTIONS" ]]; then IOS_ARGS+=("--export-options-plist=$EXPORT_OPTIONS"); fi
    run flutter build "${IOS_ARGS[@]}"
    if [[ "$DRY_RUN" -eq 0 ]]; then
      shopt -s nullglob
      IPAS=("$MOBILE_DIR"/build/ios/ipa/*.ipa)
      [[ ${#IPAS[@]} -eq 1 ]] || fail "Expected exactly one newly built IPA in build/ios/ipa"
      IPA_PATH="${IPAS[0]}"
      fresh_artifact "$IPA_PATH" || fail "No fresh IPA produced; refusing to upload a stale build"
    fi
    IOS_RESULT="built"
  fi
  if [[ "$PLATFORM" != ios ]]; then
    ANDROID_RESULT="build failed"
    run flutter build "$FORMAT" "--$MODE" "${COMMON_ARGS[@]}"
    if [[ "$FORMAT" == apk ]]; then
      AAB_PATH="$MOBILE_DIR/build/app/outputs/flutter-apk/app-$MODE.apk"
    else
      AAB_PATH="$MOBILE_DIR/build/app/outputs/bundle/$MODE/app-$MODE.aab"
    fi
    if [[ "$DRY_RUN" -eq 0 ]]; then
      fresh_artifact "$AAB_PATH" || fail "No fresh Android artifact produced; refusing to upload a stale build"
    fi
    ANDROID_RESULT="built"
  fi
fi

[[ -z "$IPA_PATH" ]] || echo "==> IPA: $IPA_PATH"
[[ -z "$AAB_PATH" ]] || echo "==> Android artifact: $AAB_PATH"
if [[ "$BUILD_ONLY" -eq 1 ]]; then exit 0; fi

export FASTLANE_SKIP_UPDATE_CHECK=1 FASTLANE_OPT_OUT_USAGE=1 FASTLANE_HIDE_CHANGELOG=1
cd "$ROOT_DIR/scripts"
if [[ "$PLATFORM" != android ]]; then
  IOS_RESULT="upload not confirmed"
  export CHECKY_IPA_PATH="$IPA_PATH"
  run fastlane upload_ios
  IOS_RESULT="uploaded to App Store Connect (Apple processing pending; no review submitted)"
fi
if [[ "$PLATFORM" != ios ]]; then
  ANDROID_RESULT="upload not confirmed"
  export CHECKY_AAB_PATH="$AAB_PATH" CHECKY_ANDROID_STATUS="$ANDROID_STATUS"
  run fastlane upload_android
  ANDROID_RESULT="uploaded to Google Play internal testing ($ANDROID_STATUS)"
fi
