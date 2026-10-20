#!/usr/bin/env bash
# Backward-compatible build-only entry point; uploads require release-mobile.sh.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
for argument in "$@"; do
  case "$argument" in
    --platform|--upload-only|--ipa|--aab)
      echo "Use scripts/release-mobile.sh for platform selection and uploads." >&2
      exit 1 ;;
  esac
done
exec "$ROOT_DIR/scripts/release-mobile.sh" --platform android --build-only --no-increment --no-test "$@"
