#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MOBILE_DIR="$ROOT_DIR/apps/mobile"

MODE="release"
FORMAT="appbundle"
API_BASE_URL="${API_BASE_URL:-https://favis.vercel.app}"
KAKAO_NATIVE_APP_KEY="${KAKAO_NATIVE_APP_KEY:-b337431d556984d924b2945179a29d9d}"
BUILD_NAME="${BUILD_NAME:-}"
BUILD_NUMBER="${BUILD_NUMBER:-}"
RUN_ANALYZE=1
RUN_CLEAN=0
KEY_PROPERTIES_FILE="$MOBILE_DIR/android/key.properties"

usage() {
  cat <<'USAGE'
Usage:
  scripts/build-android.sh [options]

Options:
  --mode <debug|profile|release>       Build mode. Default: release
  --format <apk|appbundle|aab>         Output format. Default: appbundle
  --api-base-url <url>                 API base URL.
  --kakao-native-app-key <key>         Kakao native app key.
  --build-name <version>               Flutter build-name, e.g. 1.0.0
  --build-number <number>              Flutter build-number/versionCode, e.g. 2
  --clean                              Run flutter clean before build.
  --no-analyze                         Skip flutter analyze.
  -h, --help                           Show this help.

Environment variables:
  API_BASE_URL
  KAKAO_NATIVE_APP_KEY
  BUILD_NAME
  BUILD_NUMBER

Examples:
  scripts/build-android.sh
  scripts/build-android.sh --format apk --mode debug
  scripts/build-android.sh --build-name 1.0.0 --build-number 2
USAGE
}

property_value() {
  local key="$1"
  if [[ ! -f "$KEY_PROPERTIES_FILE" ]]; then
    return 0
  fi

  grep -E "^${key}=" "$KEY_PROPERTIES_FILE" | tail -n 1 | cut -d '=' -f 2-
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode)
      MODE="${2:-}"
      shift 2
      ;;
    --format)
      FORMAT="${2:-}"
      shift 2
      ;;
    --api-base-url)
      API_BASE_URL="${2:-}"
      shift 2
      ;;
    --kakao-native-app-key)
      KAKAO_NATIVE_APP_KEY="${2:-}"
      shift 2
      ;;
    --build-name)
      BUILD_NAME="${2:-}"
      shift 2
      ;;
    --build-number)
      BUILD_NUMBER="${2:-}"
      shift 2
      ;;
    --clean)
      RUN_CLEAN=1
      shift
      ;;
    --no-analyze)
      RUN_ANALYZE=0
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

case "$MODE" in
  debug|profile|release) ;;
  *)
    echo "Invalid --mode: $MODE" >&2
    exit 1
    ;;
esac

case "$FORMAT" in
  apk) FLUTTER_TARGET="apk" ;;
  appbundle|aab) FLUTTER_TARGET="appbundle" ;;
  *)
    echo "Invalid --format: $FORMAT" >&2
    exit 1
    ;;
esac

if [[ -z "$API_BASE_URL" ]]; then
  echo "API_BASE_URL is required." >&2
  exit 1
fi

if [[ -z "$KAKAO_NATIVE_APP_KEY" ]]; then
  echo "KAKAO_NATIVE_APP_KEY is required." >&2
  exit 1
fi

if [[ "$MODE" == "release" ]]; then
  if [[ ! -f "$KEY_PROPERTIES_FILE" ]]; then
    cat >&2 <<EOF
Release signing is not configured.

Create:
  $KEY_PROPERTIES_FILE

You can start from:
  cp apps/mobile/android/key.properties.example apps/mobile/android/key.properties

Then create an upload keystore and fill storePassword, keyPassword, keyAlias, storeFile.
EOF
    exit 1
  fi

  for required_key in storePassword keyPassword keyAlias storeFile; do
    if [[ -z "$(property_value "$required_key")" ]]; then
      echo "Missing '$required_key' in $KEY_PROPERTIES_FILE" >&2
      exit 1
    fi
  done

  STORE_FILE="$(property_value storeFile)"
  if [[ "$STORE_FILE" = /* ]]; then
    STORE_FILE_PATH="$STORE_FILE"
  else
    STORE_FILE_PATH="$MOBILE_DIR/android/$STORE_FILE"
  fi

  if [[ ! -f "$STORE_FILE_PATH" ]]; then
    echo "Keystore file not found: $STORE_FILE_PATH" >&2
    exit 1
  fi
fi

BUILD_ARGS=(
  "$FLUTTER_TARGET"
  "--$MODE"
  "--dart-define=KAKAO_NATIVE_APP_KEY=$KAKAO_NATIVE_APP_KEY"
  "--dart-define=API_BASE_URL=$API_BASE_URL"
)

if [[ -n "$BUILD_NAME" ]]; then
  BUILD_ARGS+=("--build-name=$BUILD_NAME")
fi

if [[ -n "$BUILD_NUMBER" ]]; then
  BUILD_ARGS+=("--build-number=$BUILD_NUMBER")
fi

echo "==> Checky Android build"
echo "    mode: $MODE"
echo "    format: $FLUTTER_TARGET"
echo "    api: $API_BASE_URL"
echo "    kakao key: ${KAKAO_NATIVE_APP_KEY:0:6}..."

cd "$MOBILE_DIR"

if [[ "$RUN_CLEAN" -eq 1 ]]; then
  echo "==> flutter clean"
  flutter clean
fi

echo "==> flutter pub get"
flutter pub get

if [[ "$RUN_ANALYZE" -eq 1 ]]; then
  echo "==> flutter analyze"
  flutter analyze
fi

echo "==> flutter build ${BUILD_ARGS[*]}"
flutter build "${BUILD_ARGS[@]}"

if [[ "$FLUTTER_TARGET" == "appbundle" ]]; then
  echo "==> Output: $MOBILE_DIR/build/app/outputs/bundle/$MODE/app-$MODE.aab"
else
  echo "==> Output: $MOBILE_DIR/build/app/outputs/flutter-apk/app-$MODE.apk"
fi
