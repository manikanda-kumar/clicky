#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<USAGE
Usage: create_dmg.sh --app-path /path/to/App.app --output-path /path/to/App.dmg [--volume-name NAME]
USAGE
}

APP_PATH=""
OUTPUT_PATH=""
VOLUME_NAME=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app-path)
      APP_PATH="$2"
      shift 2
      ;;
    --output-path)
      OUTPUT_PATH="$2"
      shift 2
      ;;
    --volume-name)
      VOLUME_NAME="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ -z "$APP_PATH" || -z "$OUTPUT_PATH" ]]; then
  echo "Missing required arguments." >&2
  usage
  exit 1
fi

if [[ ! -d "$APP_PATH" ]]; then
  echo "App not found: $APP_PATH" >&2
  exit 1
fi

if [[ -z "$VOLUME_NAME" ]]; then
  APP_BASENAME="$(basename "$APP_PATH" .app)"
  VOLUME_NAME="$APP_BASENAME"
fi

OUTPUT_DIR="$(cd "$(dirname "$OUTPUT_PATH")" && pwd)"
OUTPUT_BASENAME="$(basename "$OUTPUT_PATH")"
STAGING_DIR="$OUTPUT_DIR/.dmg-staging-${OUTPUT_BASENAME%.dmg}"

/bin/rm -rf "$STAGING_DIR"
/bin/mkdir -p "$STAGING_DIR"
/bin/rm -f "$OUTPUT_PATH"

/bin/cp -R "$APP_PATH" "$STAGING_DIR/"
/bin/ln -s /Applications "$STAGING_DIR/Applications"

hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$OUTPUT_PATH"

/bin/rm -rf "$STAGING_DIR"

echo "Created DMG: $OUTPUT_PATH"
